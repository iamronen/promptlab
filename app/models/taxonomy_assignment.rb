# frozen_string_literal: true

class TaxonomyAssignment < ApplicationRecord
  belongs_to :project
  belongs_to :sequence
  belongs_to :taxonomy
  belongs_to :taxonomy_term

  validates :label_snapshot, presence: true
  validates :assigned_at, presence: true
  validate :taxonomy_matches_term_taxonomy
  validate :projects_aligned
  validate :sequence_assignable_to_taxonomies

  before_validation :sync_denormalized_fields

  scope :for_project, ->(project) { where(project_id: project.id) }

  private

  def sync_denormalized_fields
    return unless taxonomy && taxonomy_term && sequence

    self.project_id = sequence.project_id if sequence.project_id.present?
    self.label_snapshot = taxonomy_term.label.to_s if taxonomy_term.label.present?
    self.single_value_taxonomy_copy = taxonomy.one?
    self.assigned_at ||= Time.current
  end

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

    return if sequence.sequence? || sequence.bundle?

    errors.add(:sequence_id, "must be a generative sequence or bundle")
  end
end
