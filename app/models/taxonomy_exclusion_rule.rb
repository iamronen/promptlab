# frozen_string_literal: true

class TaxonomyExclusionRule < ApplicationRecord
  belongs_to :taxonomy
  belongs_to :excluding_taxonomy, class_name: "Taxonomy"
  belongs_to :project

  has_many :taxonomy_exclusion_rule_terms, dependent: :destroy
  has_many :excluding_terms, through: :taxonomy_exclusion_rule_terms, source: :taxonomy_term

  validates :excluding_taxonomy_id, uniqueness: { scope: :taxonomy_id }
  validate :taxonomy_must_be_process_tracking
  validate :excluding_taxonomy_must_differ
  validate :excluding_taxonomy_same_project
  validate :excluding_terms_belong_to_excluding_taxonomy

  before_validation :assign_project_from_taxonomy, on: :create

  def excluding_term_ids
    excluding_terms.pluck(:id)
  end

  private

  def assign_project_from_taxonomy
    self.project_id ||= taxonomy&.project_id
  end

  def taxonomy_must_be_process_tracking
    return if taxonomy&.process_tracking?

    errors.add(:taxonomy, "must have process tracking enabled")
  end

  def excluding_taxonomy_must_differ
    return if taxonomy_id.blank? || excluding_taxonomy_id.blank?
    return if taxonomy_id != excluding_taxonomy_id

    errors.add(:excluding_taxonomy, "must differ from the process taxonomy")
  end

  def excluding_taxonomy_same_project
    return if taxonomy.blank? || excluding_taxonomy.blank?
    return if taxonomy.project_id == excluding_taxonomy.project_id

    errors.add(:excluding_taxonomy, "must belong to the same project")
  end

  def must_have_at_least_one_excluding_term
    return if taxonomy_exclusion_rule_terms.any?

    errors.add(:base, "must include at least one excluding value")
  end

  def excluding_terms_belong_to_excluding_taxonomy
    return if excluding_taxonomy.blank?

    invalid =
      taxonomy_exclusion_rule_terms
        .includes(:taxonomy_term)
        .reject { |row| row.taxonomy_term&.taxonomy_id == excluding_taxonomy_id }
    return if invalid.empty?

    errors.add(:excluding_terms, "must belong to the excluding taxonomy")
  end
end
