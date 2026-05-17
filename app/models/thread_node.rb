# frozen_string_literal: true

# Fork between weave strands: parent thread, optional parent bundle (when fork is inside a bundle),
# anchor generative sequence on the strand, and child thread with sibling order among same anchor.
class ThreadNode < ApplicationRecord
  belongs_to :parent_thread, class_name: "Sequence", inverse_of: :thread_nodes_as_parent_thread
  belongs_to :parent_bundle, class_name: "Sequence", foreign_key: :parent_bundle_id, optional: true,
                           inverse_of: :thread_nodes_as_parent_bundle
  belongs_to :parent_generative_sequence, class_name: "Sequence", foreign_key: :parent_generative_sequence_id,
                                          inverse_of: :thread_nodes_as_anchored_child_threads
  belongs_to :child_thread, class_name: "Sequence", inverse_of: :thread_node_as_child

  validates :child_order, presence: true, numericality: { only_integer: true }
  validates :parent_generative_sequence_id, presence: true

  validate :validate_parent_thread
  validate :validate_parent_bundle_context
  validate :validate_child_thread_branch
  validate :validate_same_project_scope
  validate :validate_anchor_on_parent_strand

  before_destroy :remember_parent_thread_for_branch_resync, prepend: true
  after_save :sync_thread_branch_dependencies_full
  after_destroy :resync_thread_branches_after_destroy

  class << self
    # Rewrites thread_branch SequenceDependencies for +parent_thread_id+ from current ThreadNodes:
    # deletes all branch edges for the parent, then inserts contiguous positions 1..n ordered by strand
    # anchor then child_order (avoids unique (parent_id, position) violations from incremental updates).
    def resync_thread_branch_dependencies_for_parent!(parent_thread_id)
      return if parent_thread_id.blank?

      parent = Sequence.find_by(id: parent_thread_id)
      return unless parent&.thread?

      ordered = ordered_thread_nodes_for_parent(parent_thread_id)

      # Wipe then recreate rows: incremental find/save hits (parent_id, position) unique index
      # violations when positions are reassigned while another child row still occupies the target slot
      # (e.g. missing intermediate dep, or stale ordering).
      SequenceDependency.where(parent_id: parent_thread_id, kind: :thread_branch).delete_all

      ordered.each_with_index do |node, i|
        SequenceDependency.create!(
          parent_id: parent_thread_id,
          child_id: node.child_thread_id,
          kind: :thread_branch,
          position: i + 1,
          anchor_sequence_id: node.parent_generative_sequence_id
        )
      end
    end

    def ordered_thread_nodes_for_parent(parent_thread_id)
      nodes = ThreadNode.where(parent_thread_id: parent_thread_id).includes(:parent_thread).order(:id).to_a
      flat_idx = lambda do |node|
        t = node.parent_thread
        return 1_000_000 unless t && node.parent_generative_sequence_id

        ids = t.flattened_generative_sequence_ids_on_strand
        idx = ids.index(node.parent_generative_sequence_id)
        idx || 1_000_000
      end
      nodes.sort_by { |n| [flat_idx.call(n), n.child_order, n.id] }
    end
  end

  private

  def sync_thread_branch_dependencies_full
    if saved_change_to_parent_thread_id?
      prev = saved_change_to_parent_thread_id[0]
      self.class.resync_thread_branch_dependencies_for_parent!(prev) if prev.present?
    end
    self.class.resync_thread_branch_dependencies_for_parent!(parent_thread_id)
  end

  def remember_parent_thread_for_branch_resync
    @__branch_parent_thread_id_for_resync = parent_thread_id
  end

  def resync_thread_branches_after_destroy
    pid = @__branch_parent_thread_id_for_resync
    self.class.resync_thread_branch_dependencies_for_parent!(pid) if pid
  end

  def validate_parent_thread
    return unless parent_thread

    errors.add(:parent_thread, "must be a thread") unless parent_thread.thread?
  end

  def validate_parent_bundle_context
    return unless parent_thread && parent_generative_sequence_id

    if parent_bundle_id.present?
      unless parent_bundle&.bundle?
        errors.add(:parent_bundle, "must be a bundle")
        return
      end

      ids = parent_thread.thread_bundle_ids
      unless ids.include?(parent_bundle_id)
        errors.add(:parent_bundle, "must be a member of the parent thread")
      end

      unless parent_bundle.pipeline_generative_sequence_ids.include?(parent_generative_sequence_id)
        errors.add(:parent_generative_sequence, "must be a member of the parent bundle pipeline")
      end
    end
  end

  def validate_anchor_on_parent_strand
    return unless parent_thread && parent_generative_sequence_id

    ids = parent_thread.flattened_generative_sequence_ids_on_strand
    return if ids.include?(parent_generative_sequence_id)

    errors.add(:parent_generative_sequence, "must appear on the parent thread strand")
  end

  def validate_child_thread_branch
    return unless child_thread

    unless child_thread.thread?
      errors.add(:child_thread, "must be a thread")
      return
    end

    errors.add(:child_thread, "cannot be the genesis thread") if child_thread.is_genesis?
    errors.add(:child_thread, "cannot be the orphans thread") if child_thread.is_orphans?
  end

  def validate_same_project_scope
    return unless parent_thread && child_thread

    pid = parent_thread.project_id
    if parent_bundle_id.present? && parent_bundle && parent_bundle.project_id != pid
      errors.add(:parent_bundle, "must belong to the same project as the parent thread")
    end

    if parent_generative_sequence && parent_generative_sequence.project_id != pid
      errors.add(:parent_generative_sequence, "must belong to the same project as the parent thread")
    end

    return unless child_thread.project_id != pid

    errors.add(:child_thread, "must belong to the same project as the parent thread")
  end
end
