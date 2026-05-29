# frozen_string_literal: true

module PublicShareReaderPayload
  extend ActiveSupport::Concern
  include ActionView::Helpers::SanitizeHelper

  READER_STEP_ALLOWED_TAGS = %w[p br strong b em i u ol ul li a span].freeze
  READER_STEP_ALLOWED_ATTRIBUTES = %w[href class].freeze

  private

  def reader_payload(share_root, initial_thread:)
    {
      share_title: share_root.share_public_title,
      share_root_public_id: share_root.public_id,
      show_top_nav: share_root.share_has_included_descendant_threads?,
      initial_thread_public_id: initial_thread.public_id,
      threads: build_reader_threads_map(share_root)
    }
  end

  def build_reader_threads_map(share_root)
    thread_ids = [share_root.id] + readable_descendant_ids(share_root)
    threads_by_id = share_root.project.sequences.threads.where(id: thread_ids).index_by(&:id)

    thread_ids.filter_map do |tid|
      thread = threads_by_id[tid]
      next unless thread

      [thread.public_id, serialize_reader_thread(share_root, thread)]
    end.to_h
  end

  def readable_descendant_ids(share_root)
    if share_root.share_scope_everything?
      FabricThreadTree.descendant_thread_ids_for(share_root)
    else
      share_root.included_descendant_threads.pluck(:id)
    end
  end

  def serialize_reader_thread(share_root, thread)
    {
      public_id: thread.public_id,
      title: thread.title,
      breadcrumb: share_reader_breadcrumb_segments(share_root, thread),
      strand_children: serialize_strand_children(thread),
      child_threads: share_root.share_reader_child_threads_for(thread)
    }
  end

  def share_reader_breadcrumb_segments(share_root, current_thread)
    if current_thread.id == share_root.id
      return [{ public_id: share_root.public_id, label: "Start", current: true }]
    end

    path_ids = FabricThreadTree.thread_path_from_root(share_root, current_thread)
    threads_by_id = share_root.project.sequences.threads.where(id: path_ids).index_by(&:id)

    segments = [{ public_id: share_root.public_id, label: "Start", current: false }]
    path_ids.each do |tid|
      thread = threads_by_id[tid]
      next unless thread

      segments << {
        public_id: thread.public_id,
        label: thread.title,
        current: tid == current_thread.id
      }
    end
    segments
  end

  def serialize_strand_children(thread)
    thread.ordered_steps.filter_map do |row|
      if row.bundle_id.present?
        serialize_strand_bundle(thread, row)
      else
        serialize_strand_sequence(thread, row)
      end
    end
  end

  def serialize_strand_sequence(thread, row)
    sequence = thread.project.sequences.generative_sequences.find_by(id: row.sequence_id)
    return unless sequence

    {
      position: row.position,
      kind: "sequence",
      title: row.title.presence || sequence.title,
      steps: sequence.ordered_steps.map do |step|
        { position: step.position, content: sanitize_reader_step_content(step.content) }
      end
    }
  end

  def serialize_strand_bundle(thread, row)
    bundle = thread.project.sequences.bundles.find_by(id: row.bundle_id)
    return unless bundle

    {
      position: row.position,
      kind: "bundle",
      title: row.title.presence || bundle.title,
      sequences: bundle.pipeline_generative_children_ordered.each_with_index.filter_map do |child, idx|
        {
          position: idx + 1,
          title: child.title,
          steps: child.ordered_steps.map do |step|
            { position: step.position, content: sanitize_reader_step_content(step.content) }
          end
        }
      end
    }
  end

  def sanitize_reader_step_content(html)
    normalized = Loofah.fragment(html.to_s)
    normalized.css("b").each { |node| node.name = "strong" }
    normalized.css("i").each { |node| node.name = "em" }
    normalized.css("div").each { |node| node.name = "p" }

    sanitize(
      normalized.to_s,
      tags: READER_STEP_ALLOWED_TAGS,
      attributes: READER_STEP_ALLOWED_ATTRIBUTES
    )
  end
end
