# frozen_string_literal: true

class SequenceShareInclusion < ApplicationRecord
  belongs_to :root_sequence, class_name: "Sequence", inverse_of: :share_inclusions
  belongs_to :included_sequence, class_name: "Sequence", inverse_of: :share_inclusions_as_included

  validates :included_sequence_id, uniqueness: { scope: :root_sequence_id }
  validate :root_must_be_share_defined_thread
  validate :included_must_be_thread_in_same_project
  validate :included_must_not_be_root
  validate :included_must_be_descendant_of_root

  def self.descendant_of_root?(included, root)
    return false unless included&.thread? && root&.thread?
    return false unless included.project_id == root.project_id

    FabricThreadTree.descendant_thread_ids_for(root).include?(included.id)
  end

  private

  def root_must_be_share_defined_thread
    return if root_sequence&.share_defined? && root_sequence.thread?

    errors.add(:root_sequence, "must be a thread with a defined share")
  end

  def included_must_be_thread_in_same_project
    return if included_sequence&.thread? && root_sequence &&
              included_sequence.project_id == root_sequence.project_id

    errors.add(:included_sequence, "must be a thread in the same project as the share root")
  end

  def included_must_not_be_root
    return if included_sequence_id.blank? || root_sequence_id.blank?
    return if included_sequence_id != root_sequence_id

    errors.add(:included_sequence, "cannot be the share root (root is always included implicitly)")
  end

  def included_must_be_descendant_of_root
    return if errors[:included_sequence].any? || errors[:root_sequence].any?
    return if self.class.descendant_of_root?(included_sequence, root_sequence)

    errors.add(:included_sequence, "must be a descendant of the share root in the thread tree")
  end
end
