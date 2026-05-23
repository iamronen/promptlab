# frozen_string_literal: true

require "prawn"

# Renders project weave threads as a PDF: thread index (depth-first from Genesis, then Orphans)
# followed by thread details (one thread per page, sequence blocks kept together when possible).
class ProjectPdfGenerator
  BASE_PT = 11.0
  FONT_SCALE = 0.8
  BREADCRUMB_SEP = " › "
  STEP_MARKER_GAP = 5

  def self.render(project)
    new(project).render
  end

  def initialize(project)
    @project = project
    @branches = FabricThreadTree.pdf_export_branches(@project)
  end

  def render
    pdf = Prawn::Document.new(page_size: "LETTER", margin: [72, 72, 72, 72])

    if @branches.empty?
      pdf.text "No threads to export for “#{ProjectPdfHtml.to_plain(@project.name)}”.", size: sz(1.0)
    else
      pdf.text "Index", size: sz(1.5), style: :bold
      pdf.move_down 10
      @branches.each_with_index do |branch, i|
        render_index_section(pdf, branch, thread_num: i + 1)
      end

      pdf.start_new_page
      first_details = true
      @branches.each_with_index do |branch, i|
        pdf.start_new_page unless first_details
        first_details = false
        render_thread_details(pdf, branch, thread_num: i + 1)
      end
    end

    pdf.render
  end

  private

  def sz(multiplier)
    (BASE_PT * multiplier * FONT_SCALE).round(2)
  end

  def draw_formatted(pdf, html, size:, leading: 2, default_bold: false)
    frags = ProjectPdfHtml.to_prawn_formatted(html)
    formatted = frags.map do |f|
      styles = Array(f[:styles]).dup
      styles << :bold if default_bold
      styles.uniq!
      h = { text: f[:text], size: size }
      h[:styles] = styles if styles.any?
      h
    end
    pdf.formatted_text formatted, leading: leading
  end

  def draw_index_thread_heading(pdf, thread_num, thread)
    draw_numbered_heading(pdf, thread_num, thread.title, prefix: nil, size_mult: 1.2)
  end

  def draw_details_thread_heading(pdf, thread_num, thread)
    draw_numbered_heading(pdf, thread_num, thread.title, prefix: "Thread: ", size_mult: 1.5)
  end

  def draw_numbered_heading(pdf, number, html, prefix:, size_mult:)
    size = sz(size_mult)
    frags = [{ text: "#{number}. ", size: size, styles: [:bold] }]
    frags << { text: prefix, size: size, styles: [:bold] } if prefix.present?
    ProjectPdfHtml.to_prawn_formatted(html).each do |f|
      styles = ((f[:styles] || []) + [:bold]).uniq
      frags << { text: f[:text], size: size, styles: styles }
    end
    pdf.formatted_text frags
  end

  def draw_numbered_index_body_line(pdf, label, html, suffix: "", size_mult: 1.0, title_bold: false)
    size = sz(size_mult)
    frags = [{ text: label, size: size }]
    frags.first[:styles] = [:bold] if title_bold
    ProjectPdfHtml.to_prawn_formatted(html).each do |f|
      styles = Array(f[:styles]).dup
      styles << :bold if title_bold
      styles.uniq!
      h = { text: f[:text], size: size }
      h[:styles] = styles if styles.any?
      frags << h
    end
    frags << { text: suffix, size: size } if suffix.present?
    pdf.formatted_text frags
  end

  def render_index_section(pdf, branch, thread_num:)
    thread = branch.thread

    draw_index_thread_heading(pdf, thread_num, thread)

    unless thread.is_genesis?
      crumb = ancestor_breadcrumb_plain(thread)
      if crumb.present?
        pdf.move_down 4
        pdf.text "Child of: #{crumb}", size: sz(0.8)
      end
    end

    pdf.move_down 8
    pdf.font_size(sz(1.0)) do
      pdf.indent(18) do
        render_strand_index_numbered(pdf, thread)
      end
    end

    pdf.move_down 12
  end

  # Strand items in index/details order with labels matching the index (1., 1.1., …).
  def strand_numbered_items(thread)
    items = []
    n = 0
    thread.strand_step_pairs.each do |kind, ref_id|
      case kind
      when :bundle
        bundle = @project.sequences.bundles.find_by(id: ref_id)
        next unless bundle

        n += 1
        bundle_label = "#{n}."
        items << { type: :bundle, label: bundle_label, bundle: bundle }
        sub = 0
        bundle.pipeline_generative_children_ordered.each do |seq|
          sub += 1
          items << { type: :sequence, label: "#{n}.#{sub}.", sequence: seq, bundle: bundle }
        end
      when :sequence
        seq = @project.sequences.generative_sequences.find_by(id: ref_id)
        next unless seq

        n += 1
        items << { type: :sequence, label: "#{n}.", sequence: seq, bundle: nil, bundle_label: nil }
      end
    end
    items
  end

  def render_strand_index_numbered(pdf, thread)
    strand_numbered_items(thread).each do |item|
      case item[:type]
      when :bundle
        draw_numbered_index_body_line(pdf, "#{item[:label]} ", item[:bundle].title.to_s, suffix: " (bundle)")
      when :sequence
        if item[:bundle]
          pdf.indent(12) do
            draw_numbered_index_body_line(pdf, "#{item[:label]} ", item[:sequence].title.to_s)
          end
        else
          draw_numbered_index_body_line(pdf, "#{item[:label]} ", item[:sequence].title.to_s)
        end
      end
    end
  end

  def render_thread_details(pdf, branch, thread_num:)
    thread = branch.thread

    draw_details_thread_heading(pdf, thread_num, thread)
    pdf.move_down 6

    unless thread.is_genesis?
      trail = details_breadcrumb_line(thread)
      if trail.present?
        pdf.text trail, size: sz(1.0)
        pdf.move_down 12
      else
        pdf.move_down 8
      end
    else
      pdf.move_down 8
    end

    items = strand_numbered_items(thread)
    if items.empty?
      pdf.text "No sequences on this thread.", size: sz(1.0)
      return
    end

    items.each do |item|
      case item[:type]
      when :bundle
        pdf.move_down 4 if pdf.cursor < pdf.bounds.top - 20
        draw_numbered_index_body_line(pdf, "#{item[:label]} ", item[:bundle].title.to_s, suffix: " (bundle)")
        pdf.move_down 8
      when :sequence
        render_sequence_block(
          pdf,
          item[:sequence],
          number_label: item[:label],
          bundle: item[:bundle]
        )
      end
    end
  end

  def render_sequence_block(pdf, sequence, number_label:, bundle: nil)
    needed = estimate_sequence_block_height(pdf, sequence, number_label: number_label, bundle: bundle)
    pdf.start_new_page if pdf.cursor < needed + 48

    draw_numbered_index_body_line(pdf, number_label, sequence.title.to_s, size_mult: 1.2, title_bold: true)
    if bundle
      pdf.move_down 2
      pdf.text "Bundle: #{ProjectPdfHtml.to_plain(bundle.title)}", size: sz(1.0)
    end
    pdf.move_down 6
    draw_formatted(pdf, sequence.intent, size: sz(1.0), default_bold: false)
    pdf.move_down 6

    sequence.ordered_steps.each_with_index do |step, i|
      draw_ol_step(pdf, i + 1, step.content)
    end
    pdf.move_down 14
  end

  def draw_ol_step(pdf, index, html)
    size = sz(1.0)
    marker = "#{index}."
    marker_w = pdf.width_of("#{marker} ", size: size)
    content_left = marker_w + STEP_MARKER_GAP

    y_start = pdf.cursor
    pdf.indent(content_left) do
      draw_formatted(pdf, html, size: size, leading: 2)
    end
    y_end = pdf.cursor
    block_h = [y_start - y_end, pdf.height_of("#{marker} ", size: size)].max

    pdf.text_box "#{marker} ",
      at: [pdf.bounds.left, y_start],
      width: marker_w,
      height: block_h,
      size: size,
      valign: :top,
      overflow: :shrink_to_fit

    pdf.move_down 4
  end

  def estimate_sequence_block_height(pdf, sequence, number_label:, bundle:)
    w = pdf.bounds.width
    title_plain = "#{number_label} #{ProjectPdfHtml.to_plain(sequence.title)}"
    block_h = pdf.height_of(title_plain, width: w, size: sz(1.2), style: :bold)
    if bundle
      block_h += 2 + pdf.height_of("Bundle: …", width: w, size: sz(1.0))
    end
    block_h += 6
    block_h += height_of_formatted_plain(pdf, sequence.intent, w, sz(1.0), default_bold: false)
    block_h += 6

    content_w = w - pdf.width_of("99. ", size: sz(1.0)) - STEP_MARKER_GAP
    sequence.ordered_steps.each_with_index do |step, _i|
      plain = ProjectPdfHtml.to_plain(step.content)
      block_h += pdf.height_of(plain, width: content_w, size: sz(1.0), leading: 2) + 4
    end

    block_h + 14
  end

  def height_of_formatted_plain(pdf, html, width, size, default_bold:)
    plain = ProjectPdfHtml.to_plain(html)
    pdf.height_of(plain, width: width, size: size, style: default_bold ? :bold : :normal)
  end

  def ancestor_breadcrumb_plain(thread)
    return "" if thread.is_genesis?

    payload = thread.thread_workspace_breadcrumb_payload
    return "" unless payload

    segs = payload.full_segments[0...-1]
    segs.filter_map { |s| ProjectPdfHtml.to_plain(s&.title).presence }.join(BREADCRUMB_SEP)
  end

  def details_breadcrumb_line(thread)
    return "" if thread.is_genesis?

    trail = breadcrumb_trail_plain_including_self(thread)
    return "" if trail.blank?

    "Child of: #{trail}"
  end

  def breadcrumb_trail_plain_including_self(thread)
    payload = thread.thread_workspace_breadcrumb_payload
    if payload
      payload.full_segments.filter_map { |s| ProjectPdfHtml.to_plain(s&.title).presence }.join(BREADCRUMB_SEP)
    else
      ProjectPdfHtml.to_plain(thread.title)
    end
  end
end
