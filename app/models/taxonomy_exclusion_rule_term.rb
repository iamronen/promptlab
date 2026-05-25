# frozen_string_literal: true

class TaxonomyExclusionRuleTerm < ApplicationRecord
  belongs_to :taxonomy_exclusion_rule
  belongs_to :taxonomy_term

  validates :taxonomy_term_id, uniqueness: { scope: :taxonomy_exclusion_rule_id }
  validate :term_belongs_to_excluding_taxonomy

  private

  def term_belongs_to_excluding_taxonomy
    return if taxonomy_term.blank? || taxonomy_exclusion_rule.blank?

    excluding_taxonomy_id = taxonomy_exclusion_rule.excluding_taxonomy_id
    return if taxonomy_term.taxonomy_id == excluding_taxonomy_id

    errors.add(:taxonomy_term, "must belong to the excluding taxonomy")
  end
end
