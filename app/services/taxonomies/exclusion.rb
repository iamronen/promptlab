# frozen_string_literal: true

module Taxonomies
  module Exclusion
    module_function

    def trigger_term_ids_for(process_taxonomy)
      TaxonomyExclusionRuleTerm
        .joins(:taxonomy_exclusion_rule)
        .where(taxonomy_exclusion_rules: { taxonomy_id: process_taxonomy.id })
        .distinct
        .pluck(:taxonomy_term_id)
    end

    def excluded?(sequence, process_taxonomy:)
      term_ids_by_taxonomy = assignment_term_ids_by_taxonomy_for(sequence)
      excluded_with_term_ids_by_taxonomy?(process_taxonomy:, term_ids_by_taxonomy:)
    end

    def excluded_with_term_ids_by_taxonomy?(process_taxonomy:, term_ids_by_taxonomy:)
      rules = process_taxonomy.exclusion_rules.includes(:taxonomy_exclusion_rule_terms)
      return false if rules.empty?

      rules.any? { |rule| rule_triggered?(rule, term_ids_by_taxonomy) }
    end

    def excluded_sequence_ids_for(project, process_taxonomy:)
      term_ids = trigger_term_ids_for(process_taxonomy)
      return [] if term_ids.empty?

      TaxonomyAssignment
        .where(project_id: project.id, taxonomy_term_id: term_ids)
        .distinct
        .pluck(:sequence_id)
    end

    def assignment_term_ids_by_taxonomy_for(sequence)
      TaxonomyAssignment
        .where(sequence_id: sequence.id)
        .group_by(&:taxonomy_id)
        .transform_values { |rows| rows.map(&:taxonomy_term_id) }
    end

    def rule_triggered?(rule, term_ids_by_taxonomy)
      assigned = term_ids_by_taxonomy[rule.excluding_taxonomy_id] || []
      excluding_ids = rule.taxonomy_exclusion_rule_terms.map(&:taxonomy_term_id)
      assigned.any? { |term_id| excluding_ids.include?(term_id) }
    end
  end
end
