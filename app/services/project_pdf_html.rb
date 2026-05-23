# frozen_string_literal: true

require "nokogiri"

# Converts a small subset of HTML to Prawn output: strips tags, maps <b>/<strong> to bold runs.
module ProjectPdfHtml
  module_function

  # Plain text for layout estimates and simple lines (no markup).
  def to_plain(html)
    to_prawn_formatted(html).map { |s| s[:text] }.join
  end

  # [{ text: String, styles: [:bold] }, ...] for pdf.formatted_text
  def to_prawn_formatted(html)
    source = html.to_s
    return [{ text: "" }] if source.blank?

    fragment = Nokogiri::HTML.fragment(source)
    segments = walk_fragment_children(fragment, bold: false)
    segments = merge_adjacent_segments(segments)
    return [{ text: "" }] if segments.empty?

    segments
  end

  def walk_fragment_children(node, bold:)
    node.children.flat_map { |child| walk_node(child, bold: bold) }
  end

  def walk_node(node, bold:)
    case node
    when Nokogiri::XML::Text
      text = node.text
      return [] if text.empty?

      seg = { text: text, styles: bold ? [:bold] : [] }
      [seg]
    when Nokogiri::XML::Element
      case node.name.downcase
      when "script", "style"
        []
      when "br"
        [{ text: "\n", styles: [] }]
      when "b", "strong"
        walk_fragment_children(node, bold: true)
      when "p", "div", "li", "h1", "h2", "h3", "h4"
        inner = walk_fragment_children(node, bold: bold)
        inner << { text: "\n", styles: [] } if inner.any?
        inner
      else
        walk_fragment_children(node, bold: bold)
      end
    else
      []
    end
  end

  def merge_adjacent_segments(segments)
    out = []
    segments.each do |seg|
      styles = Array(seg[:styles]).uniq.sort
      if out.last && style_key(out.last[:styles]) == style_key(styles)
        out.last[:text] += seg[:text]
      else
        out << { text: seg[:text], styles: styles }
      end
    end
    out
  end

  def style_key(styles)
    Array(styles).uniq.sort
  end
end
