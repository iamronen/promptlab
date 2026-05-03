# frozen_string_literal: true

class SequenceDependency < ApplicationRecord
  belongs_to :parent, class_name: "Sequence", inverse_of: :child_dependencies
  belongs_to :child, class_name: "Sequence", inverse_of: :parent_dependencies

  enum :kind, {
    sequence_step: "sequence_step",
    transformation_prerequisite: "transformation_prerequisite"
  }, validate: true

  validates :position, presence: true, if: -> { sequence_step? }
  validates :position, absence: true, if: -> { transformation_prerequisite? }
  validate :sequence_step_endpoints, if: -> { sequence_step? }
  validate :prerequisite_endpoints, if: -> { transformation_prerequisite? }
  validate :same_project_as_parent
  validate :prerequisite_acyclic, if: -> { transformation_prerequisite? && new_record? }

  # Follow edges "parent depends on child" (rows where kind is transformation_prerequisite).
  # True when start_parent_id can reach target_parent_id via outgoing prerequisite edges.
  def self.prerequisite_reachable?(start_parent_id, target_parent_id, visited = nil)
    return true if start_parent_id == target_parent_id

    visited ||= {}
    return false if visited[start_parent_id]

    visited[start_parent_id] = true
    where(parent_id: start_parent_id, kind: :transformation_prerequisite).pluck(:child_id).each do |next_id|
      return true if prerequisite_reachable?(next_id, target_parent_id, visited)
    end
    false
  end

  private

  def sequence_step_endpoints
    errors.add(:parent, "must be a transformation") unless parent&.transformation?
    errors.add(:child, "must be a generative sequence") unless child&.sequence?
  end

  def prerequisite_endpoints
    errors.add(:parent, "must be a transformation") unless parent&.transformation?
    errors.add(:child, "must be a transformation") unless child&.transformation?
    errors.add(:child, "cannot equal parent") if parent_id == child_id
  end

  def same_project_as_parent
    return unless parent && child

    errors.add(:child, "must belong to the same project") if child.project_id != parent.project_id
  end

  def prerequisite_acyclic
    return unless parent_id && child_id

    errors.add(:base, "Prerequisite would create a cycle") if self.class.prerequisite_reachable?(child_id, parent_id)
  end
end
