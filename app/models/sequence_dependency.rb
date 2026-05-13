# frozen_string_literal: true

class SequenceDependency < ApplicationRecord
  belongs_to :parent, class_name: "Sequence", inverse_of: :child_dependencies
  belongs_to :child, class_name: "Sequence", inverse_of: :parent_dependencies
  belongs_to :anchor_sequence, class_name: "Sequence", foreign_key: :anchor_sequence_id, optional: true

  enum :kind, {
    sequence_step: "sequence_step",
    bundle_prerequisite: "bundle_prerequisite",
    thread_step_bundle: "thread_step_bundle",
    thread_step_sequence: "thread_step_sequence",
    thread_branch: "thread_branch"
  }, validate: true

  validates :position, presence: true, if: -> {
    sequence_step? || thread_step_bundle? || thread_step_sequence? || thread_branch?
  }
  validates :position, absence: true, if: -> { bundle_prerequisite? }
  validates :anchor_sequence_id, presence: true, if: -> { thread_branch? }
  validate :sequence_step_endpoints, if: -> { sequence_step? }
  validate :prerequisite_endpoints, if: -> { bundle_prerequisite? }
  validate :thread_step_bundle_endpoints, if: -> { thread_step_bundle? }
  validate :thread_step_sequence_endpoints, if: -> { thread_step_sequence? }
  validate :thread_branch_endpoints, if: -> { thread_branch? }
  validate :same_project_as_parent
  validate :prerequisite_acyclic, if: -> { bundle_prerequisite? && new_record? }

  # Follow outgoing prerequisite edges: parent "depends on" child bundles.
  def self.prerequisite_reachable?(start_parent_id, target_parent_id, visited = nil)
    return true if start_parent_id == target_parent_id

    visited ||= {}
    return false if visited[start_parent_id]

    visited[start_parent_id] = true
    where(parent_id: start_parent_id, kind: :bundle_prerequisite).pluck(:child_id).each do |next_id|
      return true if prerequisite_reachable?(next_id, target_parent_id, visited)
    end
    false
  end

  private

  def sequence_step_endpoints
    errors.add(:parent, "must be a bundle") unless parent&.bundle?
    errors.add(:child, "must be a generative sequence") unless child&.sequence?
  end

  def prerequisite_endpoints
    errors.add(:parent, "must be a bundle") unless parent&.bundle?
    errors.add(:child, "must be a bundle") unless child&.bundle?
    errors.add(:child, "cannot equal parent") if parent_id == child_id
  end

  def thread_step_bundle_endpoints
    errors.add(:parent, "must be a thread") unless parent&.thread?
    errors.add(:child, "must be a bundle") unless child&.bundle?
  end

  def thread_step_sequence_endpoints
    errors.add(:parent, "must be a thread") unless parent&.thread?
    errors.add(:child, "must be a generative sequence") unless child&.sequence?
  end

  def thread_branch_endpoints
    errors.add(:parent, "must be a thread") unless parent&.thread?
    errors.add(:child, "must be a thread") unless child&.thread?
    unless anchor_sequence&.sequence?
      errors.add(:anchor_sequence, "must be a generative sequence")
    end
  end

  def same_project_as_parent
    return unless parent && child

    errors.add(:child, "must belong to the same project") if child.project_id != parent.project_id
    return unless thread_branch? && anchor_sequence_id

    errors.add(:anchor_sequence, "must belong to the same project") if anchor_sequence && anchor_sequence.project_id != parent.project_id
  end

  def prerequisite_acyclic
    return unless parent_id && child_id

    errors.add(:base, "Prerequisite would create a cycle") if self.class.prerequisite_reachable?(child_id, parent_id)
  end
end
