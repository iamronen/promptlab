# frozen_string_literal: true

class TaxonomyAssignmentHistory < ApplicationRecord
  belongs_to :project
  belongs_to :sequence
  belongs_to :taxonomy
  belongs_to :taxonomy_term, optional: true

  validates :label_snapshot, presence: true
  validates :assigned_at, presence: true
  validates :ended_at, presence: true
  validate :taxonomy_matches_term_taxonomy
  validate :projects_aligned
  validate :sequence_assignable_to_taxonomies
  validate :ended_at_not_before_assigned_at

  scope :for_project, ->(project) { where(project_id: project.id) }
  scope :for_sequence_taxonomy, ->(sequence_id, taxonomy_id) {
    where(sequence_id: sequence_id, taxonomy_id: taxonomy_id).order(assigned_at: :desc)
  }

  private

  def taxonomy_matches_term_taxonomy
    return unless taxonomy && taxonomy_term

    return if taxonomy_term.taxonomy_id == taxonomy.id

    errors.add(:taxonomy_term_id, "does not belong to this taxonomy")
  end

  def projects_aligned
    return unless sequence && taxonomy && project_id.present?

    if taxonomy.project_id != project_id
      errors.add(:taxonomy_id, "must belong to the same project as the sequence")
    end

    return unless sequence.project_id.present?

    errors.add(:sequence_id, "must belong to the same project") if sequence.project_id != project_id
  end

  def sequence_assignable_to_taxonomies
    return unless sequence

    return if sequence.sequence?

    errors.add(:sequence_id, "must be a generative sequence")
  end

  def ended_at_not_before_assigned_at
    return unless assigned_at && ended_at

    return if ended_at >= assigned_at

    errors.add(:ended_at, "must be on or after assigned_at")
  end
end
