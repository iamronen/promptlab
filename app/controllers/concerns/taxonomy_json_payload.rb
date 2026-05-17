# frozen_string_literal: true

module TaxonomyJsonPayload
  extend ActiveSupport::Concern

  private

  def taxonomy_payload(taxonomy)
    terms = taxonomy.taxonomy_terms.sort_by(&:position)
    counts = term_applied_sequence_counts(terms.map(&:id))
    {
      id: taxonomy.id,
      name: taxonomy.name,
      cardinality: taxonomy.cardinality,
      single_select_ui: taxonomy.single_select_ui,
      position: taxonomy.position,
      terms: terms.map { |term| term_payload(term, counts: counts) }
    }
  end

  # Distinct sequences (including bundles: `Sequence` kind bundle) using this term.
  def term_applied_sequence_counts(term_ids)
    term_ids = Array(term_ids).map(&:to_i).uniq
    return {} if term_ids.empty?

    TaxonomyAssignment
      .where(taxonomy_term_id: term_ids)
      .group(:taxonomy_term_id)
      .count(Arel.sql("DISTINCT sequence_id"))
  end

  def term_payload(term, counts: nil)
    applied =
      if counts
        counts[term.id].to_i
      else
        term_applied_sequence_counts([term.id])[term.id].to_i
      end
    {
      id: term.id,
      taxonomy_id: term.taxonomy_id,
      label: term.label,
      position: term.position,
      applied_sequence_count: applied
    }
  end

  def assignments_payload(sequence)
    assignments =
      sequence.taxonomy_assignments.includes(:taxonomy, :taxonomy_term).order(:taxonomy_id, :id)
    {
      assignments: assignments.map { |assignment| assignment_payload(assignment) }
    }
  end

  def assignment_payload(assignment)
    {
      id: assignment.id,
      taxonomy_id: assignment.taxonomy_id,
      taxonomy_term_id: assignment.taxonomy_term_id,
      label_snapshot: assignment.label_snapshot
    }
  end
end
