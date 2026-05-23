# frozen_string_literal: true

class Sequence < ApplicationRecord
  DEFAULT_TITLE = "Untitled sequence"
  DEFAULT_INTENT = "Define one clear sentence for the sequence intent."

  BUNDLE_DEFAULT_TITLE = "Untitled bundle"
  BUNDLE_DEFAULT_INTENT = "Describe what this bundle does in one clear sentence."

  THREAD_DEFAULT_TITLE = "Genesis"
  THREAD_DEFAULT_INTENT = "Root strand order for bundles and sequences in this thread."
  ORPHANS_THREAD_TITLE = "Orphans"
  ORPHANS_THREAD_INTENT = "Secondary thread for sequences without a clear place in the Genesis lineage."
  STRAND_FORK_DEFAULT_TITLE = "Untitled strand"
  UNTITLED_THREAD_BRANCH_TITLE = "Untitled thread"

  belongs_to :project, inverse_of: :sequences
  belongs_to :created_by, class_name: "User", inverse_of: :created_sequences

  has_many :child_dependencies, class_name: "SequenceDependency", foreign_key: :parent_id, dependent: :destroy,
                                inverse_of: :parent
  has_many :parent_dependencies, class_name: "SequenceDependency", foreign_key: :child_id, dependent: :destroy,
                                   inverse_of: :child

  # thread_branch deps store the anchored generative sequence here (not parent_id / child_id).
  has_many :thread_branch_deps_as_anchor, class_name: "SequenceDependency",
                                            foreign_key: :anchor_sequence_id,
                                            dependent: :destroy,
                                            inverse_of: :anchor_sequence

  has_many :thread_nodes_as_parent_thread, class_name: "ThreadNode", foreign_key: :parent_thread_id,
                                            dependent: :destroy, inverse_of: :parent_thread
  has_many :thread_nodes_as_parent_bundle, class_name: "ThreadNode", foreign_key: :parent_bundle_id,
                                            dependent: :destroy, inverse_of: :parent_bundle
  has_many :thread_nodes_as_anchored_child_threads, class_name: "ThreadNode",
                                                      foreign_key: :parent_generative_sequence_id,
                                                      dependent: :destroy, inverse_of: :parent_generative_sequence
  has_one :thread_node_as_child, class_name: "ThreadNode", foreign_key: :child_thread_id, dependent: :destroy,
                                 inverse_of: :child_thread

  has_many :taxonomy_assignments, dependent: :destroy

  enum :kind, { sequence: "sequence", bundle: "bundle", thread: "thread" }, validate: true

  scope :generative_sequences, -> { where(kind: :sequence) }
  scope :bundles, -> { where(kind: :bundle) }
  scope :threads, -> { where(kind: :thread) }
  scope :genesis_threads, -> { threads.where(is_genesis: true) }
  scope :orphans_threads, -> { threads.where(is_orphans: true) }
  scope :terms, -> { generative_sequences.where(is_term: true) }
  scope :non_term_sequences, -> { generative_sequences.where(is_term: false) }
  scope :with_any_taxonomy_term_ids, lambda { |term_ids|
    term_ids = Array(term_ids).map(&:to_i).uniq
    next none if term_ids.empty?

    joins(:taxonomy_assignments).where(taxonomy_assignments: { taxonomy_term_id: term_ids }).distinct
  }

  StepRow = Struct.new(:position, :content, keyword_init: true)
  BundleStepRow = Struct.new(:position, :sequence_id, :title, keyword_init: true)
  ThreadStepRow = Struct.new(:position, :bundle_id, :sequence_id, :title, keyword_init: true)

  # Oldest-first thread chain toward Genesis for workspace panel header breadcrumbs (includes Genesis).
  ThreadWorkspaceBreadcrumb = Struct.new(:full_segments, :ellipsis, keyword_init: true) do
    def visible_segments
      ellipsis ? full_segments.last(3) : full_segments
    end

    def lineage_label_text
      full_segments.filter_map { |s| s&.title.to_s.presence }.join(", ")
    end
  end

  validates :title, :intent, :position, :created_by, presence: true
  validates :position, uniqueness: { scope: [:project_id, :kind] }
  validate :steps_data_must_be_array
  validate :bundle_steps_data_valid, if: -> { bundle? }
  validate :thread_steps_data_valid, if: -> { thread? }
  validate :genesis_flag_valid_for_kind
  validate :orphans_flag_valid_for_kind
  validate :genesis_orphans_mutex
  validate :root_thread_title_immutable, on: :update
  validate :child_thread_must_be_anchored, if: -> { thread? && !new_record? && !is_genesis? && !is_orphans? }

  before_validation :assign_created_by, on: :create
  before_validation :clear_term_flag_for_non_generative_kinds
  before_validation :normalize_steps_data
  before_validation :sync_bundle_title_from_first_pipeline, if: :bundle?

  before_destroy :prevent_root_thread_destroy
  # Prepend so we read parent_dependencies before has_many(dependent: :destroy) removes those rows.
  before_destroy :remove_self_from_bundle_pipeline_steps, prepend: true, if: :sequence?
  before_destroy :remove_self_from_thread_steps, prepend: true, if: -> { bundle? || sequence? }
  before_destroy :nullify_thread_nodes_parent_bundle, prepend: true, if: :bundle?

  after_save :sync_sequence_step_dependency_rows, if: :should_sync_sequence_step_rows?
  after_save :sync_thread_step_dependency_rows, if: :should_sync_thread_step_rows?
  after_save :sync_parent_bundle_titles_when_first_sequence_renamed, if: :should_sync_parent_bundle_titles_when_first_sequence_renamed?

  # Generative sequences referenced by this bundle pipeline, in order (excludes missing ids).
  def pipeline_generative_children_ordered
    ids = pipeline_generative_sequence_ids
    return [] if ids.empty?

    by_id = project.sequences.generative_sequences.where(id: ids).index_by(&:id)
    ids.filter_map { |sid| by_id[sid] }
  end

  def ordered_steps
    if bundle?
      ordered_bundle_steps
    elsif thread?
      ordered_thread_steps
    else
      Array.wrap(steps_data).map.with_index(1) do |raw, i|
        h = raw.is_a?(Hash) ? raw.stringify_keys : {}
        StepRow.new(position: i, content: h.fetch("content", "").to_s)
      end
    end
  end

  # Plain-text export for clipboard copy: title, intent, numbered steps.
  def copy_as_text
    lines = [ProjectPdfHtml.to_plain(title.to_s), "", ProjectPdfHtml.to_plain(intent.to_s), ""]
    ordered_steps.each_with_index do |step, i|
      plain = ProjectPdfHtml.to_plain(step.content.to_s).strip
      lines << "#{i + 1}. #{plain}" if plain.present?
    end
    "#{lines.join("\n").strip}\n"
  end

  def anchors_child_threads?
    thread_nodes_as_anchored_child_threads.exists?
  end

  def anchored_child_threads_ordered
    thread_nodes_as_anchored_child_threads
      .includes(:child_thread)
      .order(:child_order, :id)
      .filter_map(&:child_thread)
  end

  # Thread workspace panel header: lineage oldest→newest including Genesis when reached (never called for Genesis panel).
  # @return [ThreadWorkspaceBreadcrumb, nil]
  def thread_workspace_breadcrumb_payload
    return nil unless thread?
    return nil if is_genesis?

    ancestors = []
    cursor = self
    seen_parents = {}
    max_hops = 64

    max_hops.times do
      node = ThreadNode.find_by(child_thread_id: cursor.id)
      break unless node

      parent = node.parent_thread
      break unless parent
      break if seen_parents[parent.id]

      seen_parents[parent.id] = true
      ancestors.unshift(parent)
      break if parent.is_genesis?

      cursor = parent
    end

    full_segments = ancestors + [self]
    ellipsis = full_segments.size > 3

    ThreadWorkspaceBreadcrumb.new(full_segments: full_segments, ellipsis: ellipsis)
  end

  def prerequisite_bundle_ids
    child_dependencies.bundle_prerequisite.pluck(:child_id)
  end

  # Replaces prerequisite edges for this bundle. Call inside the same DB transaction as #save when needed.
  def sync_prerequisite_dependencies!(ids)
    return true unless bundle?

    ids = Array(ids).map(&:to_i).uniq - [id]
    valid_ids = project.sequences.bundles.where(id: ids).pluck(:id)
    if ids.size != valid_ids.size
      errors.add(:base, "Invalid prerequisite bundle")
      return false
    end

    child_dependencies.where(kind: :bundle_prerequisite).delete_all

    ids.each do |cid|
      if SequenceDependency.prerequisite_reachable?(cid, id)
        errors.add(:base, "Prerequisite bundles cannot form a cycle")
        return false
      end
    end

    ids.each do |cid|
      SequenceDependency.create!(parent_id: id, child_id: cid, kind: :bundle_prerequisite)
    end
    true
  end

  # Ordered generative sequence IDs in this bundle pipeline (from `steps_data`).
  def pipeline_generative_sequence_ids
    Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      sid = raw.stringify_keys["sequence_id"]
      sid.present? ? sid.to_i : nil
    end
  end

  # Bundle IDs in strand order (thread steps that reference bundles only).
  def thread_bundle_ids
    strand_step_pairs.filter_map { |k, id| id if k == :bundle }
  end

  # Ordered generative sequence IDs that appear directly on the thread (not inside a bundle).
  def thread_direct_generative_sequence_ids
    strand_step_pairs.filter_map { |k, id| id if k == :sequence }
  end

  # Flattened generative sequence ids along the thread: each bundle expands to its pipeline order.
  def flattened_generative_sequence_ids_on_strand
    return [] unless thread?

    ids = []
    strand_step_pairs.each do |kind, ref_id|
      if kind == :bundle
        b = project.sequences.bundles.find_by(id: ref_id)
        ids.concat(b.pipeline_generative_sequence_ids) if b
      elsif kind == :sequence
        ids << ref_id if ref_id.positive?
      end
    end
    ids
  end

  # Pairs of (:bundle | :sequence, id) in strand order.
  def strand_step_pairs
    return [] unless thread?

    Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      h = raw.stringify_keys
      if h["bundle_id"].present?
        [:bundle, h["bundle_id"].to_i]
      elsif h["sequence_id"].present?
        [:sequence, h["sequence_id"].to_i]
      end
    end
  end

  # If +sid+ appears inside a bundle on this thread's strand, returns that bundle's id; else nil.
  def bundle_containing_generative_sequence(sid)
    return nil unless thread?

    strand_step_pairs.each do |kind, ref_id|
      next unless kind == :bundle

      b = project.sequences.bundles.find_by(id: ref_id)
      return ref_id if b&.pipeline_generative_sequence_ids&.include?(sid)
    end
    nil
  end

  # Child threads reachable via ThreadNodes anchored on generative sequences in this strand
  # (used by the thread workspace index). Key: generative +sequence id+ on the strand; value: ordered, unique threads.
  def branch_child_threads_by_anchor_generative_sequence_id
    return {} unless thread?

    groups = {}
    seen = Hash.new { |h, k| h[k] = {} }

    thread_nodes_as_parent_thread.includes(:child_thread).order(:child_order, :id).each do |node|
      aid = node.parent_generative_sequence_id
      next if aid.blank?

      ct = node.child_thread
      next unless ct
      next if seen[aid][ct.id]

      seen[aid][ct.id] = true
      (groups[aid] ||= []) << ct
    end
    groups
  end

  # Threads listed under "Move to Thread": other open workspace panels first (order preserved),
  # then branch-linked child threads in strand-walk order. Deduped by thread id.
  def move_to_thread_menu_destinations(open_threads:)
    return [] unless thread?

    seen = {}
    out = []

    Array.wrap(open_threads).each do |t|
      next unless t.is_a?(Sequence) && t.thread?
      next if t.id == id || seen[t.id]

      seen[t.id] = true
      out << t
    end

    bmap = branch_child_threads_by_anchor_generative_sequence_id

    flattened_generative_sequence_ids_on_strand.each do |aid|
      (bmap[aid] || []).each do |ct|
        next if ct.id == id || seen[ct.id]

        seen[ct.id] = true
        out << ct
      end
    end

    strand_anchor_ids = flattened_generative_sequence_ids_on_strand
    orphan_anchors = bmap.keys - strand_anchor_ids
    orphan_anchors.sort.each do |aid|
      (bmap[aid] || []).each do |ct|
        next if ct.id == id || seen[ct.id]

        seen[ct.id] = true
        out << ct
      end
    end

    out
  end

  # Branched threads that can be re-anchored onto +anchor_sequence_id+ (optional +anchor_bundle_id+).
  # Same ordering/deduping as #move_to_thread_menu_destinations, but only threads that already have a
  # ThreadNode, excluding genesis/orphans and excluding no-op (already anchored at this anchor).
  def attach_branch_thread_menu_candidates(open_threads:, anchor_sequence_id:, anchor_bundle_id: nil)
    return [] unless thread?

    sid = anchor_sequence_id.to_i
    return [] if sid <= 0

    bid = anchor_bundle_id.to_i
    bid = nil unless bid.positive?

    move_to_thread_menu_destinations(open_threads: open_threads).filter_map do |t|
      next unless t.thread?
      next if t.id == id
      next if t.is_genesis? || t.is_orphans?

      node = t.thread_node_as_child
      next unless node

      next if node.parent_thread_id == id &&
              node.parent_generative_sequence_id == sid &&
              (node.parent_bundle_id || 0) == (bid || 0)

      t
    end
  end

  private

  def assign_created_by
    self.created_by ||= Current.user || project&.user
  end

  def sync_bundle_title_from_first_pipeline
    ids = pipeline_generative_sequence_ids
    if ids.empty?
      self.title = BUNDLE_DEFAULT_TITLE
      return
    end

    # Keep bundle title in lockstep with the first pipeline sequence only when the pipeline
    # membership or order changes. Title-only edits (e.g. thread editor autosave) should persist.
    return unless will_save_change_to_steps_data?

    first = project.sequences.generative_sequences.find_by(id: ids.first)
    self.title = first&.title.to_s.presence || BUNDLE_DEFAULT_TITLE
  end

  def genesis_flag_valid_for_kind
    return unless is_genesis && !thread?

    errors.add(:is_genesis, "may only be set on threads")
  end

  def orphans_flag_valid_for_kind
    return unless is_orphans && !thread?

    errors.add(:is_orphans, "may only be set on threads")
  end

  def genesis_orphans_mutex
    return unless is_genesis && is_orphans

    errors.add(:base, "cannot be both genesis and orphans thread")
  end

  def root_thread_title_immutable
    return unless thread? && (is_genesis? || is_orphans?)
    return unless will_save_change_to_title?

    errors.add(:title, "cannot be changed for this thread")
  end

  def prevent_root_thread_destroy
    return unless thread? && (is_genesis? || is_orphans?)
    return if Thread.current[:wiping_project_id_for_sequences].to_i == project_id.to_i

    errors.add(:base, "Cannot destroy root thread")
    throw :abort
  end

  def nullify_thread_nodes_parent_bundle
    ThreadNode.where(parent_bundle_id: id).update_all(parent_bundle_id: nil)
  end

  def child_thread_must_be_anchored
    return if is_genesis? || is_orphans?
    return unless thread?

    return if thread_node_as_child.present?
    return if parent_dependencies.where(kind: :thread_branch).exists?

    errors.add(:base, "non-root threads must be anchored to a parent thread strand")
  end

  def clear_term_flag_for_non_generative_kinds
    self.is_term = false if bundle? || thread?
  end

  def normalize_steps_data
    if bundle?
      normalize_steps_data_bundle
    elsif thread?
      normalize_steps_data_thread
    else
      normalize_steps_data_sequence
    end
  end

  def normalize_steps_data_sequence
    self.steps_data = Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      c = raw.stringify_keys.fetch("content", "").to_s.strip
      { "content" => c }
    end
  end

  def normalize_steps_data_bundle
    seen = {}
    self.steps_data = Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      sid = raw.stringify_keys["sequence_id"]
      next if sid.blank?

      id_val = sid.to_i
      next if id_val <= 0
      next if seen[id_val]

      seen[id_val] = true
      { "sequence_id" => id_val }
    end
  end

  # Interleaved bundle_id and sequence_id steps; at most one key per row.
  def normalize_steps_data_thread
    seen_bundle = {}
    seen_seq = {}
    self.steps_data = Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      h = raw.stringify_keys
      if h["bundle_id"].present?
        id_val = h["bundle_id"].to_i
        next if id_val <= 0
        next if seen_bundle[id_val]

        seen_bundle[id_val] = true
        { "bundle_id" => id_val }
      elsif h["sequence_id"].present?
        id_val = h["sequence_id"].to_i
        next if id_val <= 0
        next if seen_seq[id_val]

        seen_seq[id_val] = true
        { "sequence_id" => id_val }
      end
    end
  end

  def ordered_bundle_steps
    ids = pipeline_generative_sequence_ids
    titles_by_id = project.sequences.generative_sequences.where(id: ids).index_by(&:id)
    ids.each_with_index.map do |sid, i|
      row = titles_by_id[sid]
      BundleStepRow.new(
        position: i + 1,
        sequence_id: sid,
        title: row&.title.to_s
      )
    end
  end

  def ordered_thread_steps
    strand_step_pairs.each_with_index.map do |(kind, ref_id), i|
      title =
        if kind == :bundle
          project.sequences.bundles.find_by(id: ref_id)&.title.to_s
        else
          project.sequences.generative_sequences.find_by(id: ref_id)&.title.to_s
        end
      ThreadStepRow.new(
        position: i + 1,
        bundle_id: (kind == :bundle ? ref_id : nil),
        sequence_id: (kind == :sequence ? ref_id : nil),
        title: title
      )
    end
  end

  def bundle_steps_data_valid
    ids = pipeline_generative_sequence_ids
    return if ids.empty?

    valid = project.sequences.generative_sequences.where(id: ids).pluck(:id)
    invalid = ids - valid
    return if invalid.empty?

    errors.add(:steps_data, "references unknown or non-generative sequences")
  end

  def thread_steps_data_valid
    strand_step_pairs.each do |kind, ref_id|
      case kind
      when :bundle
        unless project.sequences.bundles.where(id: ref_id).exists?
          errors.add(:steps_data, "references unknown bundle")
          return
        end
      when :sequence
        unless project.sequences.generative_sequences.where(id: ref_id).exists?
          errors.add(:steps_data, "references unknown or non-generative sequence")
          return
        end
      end
    end
  end

  def remove_self_from_bundle_pipeline_steps
    parent_dependencies.sequence_step.includes(:parent).find_each do |dep|
      parent = dep.parent
      next unless parent&.bundle?

      filtered = Array.wrap(parent.steps_data).reject do |h|
        h.is_a?(Hash) && h.stringify_keys["sequence_id"].to_i == id
      end
      parent.update!(steps_data: filtered)
    end
  end

  def remove_self_from_thread_steps
    kinds = [SequenceDependency.kinds[:thread_step_bundle], SequenceDependency.kinds[:thread_step_sequence]]
    parent_dependencies.where(kind: kinds).includes(:parent).find_each do |dep|
      parent = dep.parent
      next unless parent&.thread?

      filtered = Array.wrap(parent.steps_data).reject do |h|
        next false unless h.is_a?(Hash)

        sh = h.stringify_keys
        if bundle?
          sh["bundle_id"].to_i == id
        elsif sequence?
          sh["sequence_id"].to_i == id
        else
          false
        end
      end
      parent.update!(steps_data: filtered)
    end
  end

  def should_sync_sequence_step_rows?
    bundle? && saved_change_to_steps_data?
  end

  def should_sync_parent_bundle_titles_when_first_sequence_renamed?
    sequence? && saved_change_to_title?
  end

  def sync_parent_bundle_titles_when_first_sequence_renamed
    parent_dependencies.where(kind: :sequence_step).includes(:parent).find_each do |dep|
      parent = dep.parent
      next unless parent&.bundle?

      ids = parent.pipeline_generative_sequence_ids
      next if ids.empty? || ids.first != id

      new_title = title.to_s
      parent.update_column(:title, new_title) if parent.title != new_title
    end
  end

  def sync_sequence_step_dependency_rows
    SequenceDependency.where(parent_id: id, kind: :sequence_step).delete_all

    pipeline_generative_sequence_ids.each_with_index do |child_id, index|
      SequenceDependency.create!(
        parent_id: id,
        child_id: child_id,
        kind: :sequence_step,
        position: index + 1
      )
    end
  end

  def should_sync_thread_step_rows?
    thread? && saved_change_to_steps_data?
  end

  def sync_thread_step_dependency_rows
    SequenceDependency.where(parent_id: id).where(kind: [:thread_step_bundle, :thread_step_sequence]).delete_all

    strand_step_pairs.each_with_index do |(kind, child_id), index|
      dep_kind = (kind == :bundle) ? :thread_step_bundle : :thread_step_sequence
      SequenceDependency.create!(
        parent_id: id,
        child_id: child_id,
        kind: dep_kind,
        position: index + 1
      )
    end
  end

  def steps_data_must_be_array
    errors.add(:steps_data, "must be an array") unless steps_data.nil? || steps_data.is_a?(Array)
  end
end
