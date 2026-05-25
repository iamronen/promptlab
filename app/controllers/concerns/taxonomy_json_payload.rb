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
      process_tracking: taxonomy.process_tracking?,
      applies_to_sequences: taxonomy.applies_to_sequences?,
      applies_to_bundles: taxonomy.applies_to_bundles?,
      applies_to_bundle_pipeline_sequences: taxonomy.applies_to_bundle_pipeline_sequences?,
      bundle_assignment_count: bundle_assignment_count_for(taxonomy),
      bundle_pipeline_sequence_assignment_count: bundle_pipeline_sequence_assignment_count_for(taxonomy),
      default_value_enabled: taxonomy.default_value_enabled?,
      default_taxonomy_term_id: taxonomy.default_taxonomy_term_id,
      unassigned_applicable_count: unassigned_applicable_count_for(taxonomy),
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

  def bundle_assignment_count_for(taxonomy)
    Taxonomies::AssignmentCleanup.bundle_assignments_for(taxonomy).size
  end

  def bundle_pipeline_sequence_assignment_count_for(taxonomy)
    Taxonomies::AssignmentCleanup.pipeline_sequence_assignments_for(taxonomy).size
  end

  def unassigned_applicable_count_for(taxonomy)
    Taxonomies::ApplyDefaultValue.unassigned_applicable_sequences_for(taxonomy).size
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
    process_taxonomy_ids =
      assignments.filter_map { |a| a.taxonomy_id if a.taxonomy.process_tracking? }.uniq
    histories_by_taxonomy = histories_by_taxonomy_for(sequence, process_taxonomy_ids)

    {
      assignments: assignments.map { |assignment|
        assignment_payload(assignment, histories: histories_by_taxonomy[assignment.taxonomy_id])
      }
    }
  end

  def histories_by_taxonomy_for(sequence, taxonomy_ids)
    return {} if taxonomy_ids.empty?

    rows =
      TaxonomyAssignmentHistory
        .where(sequence_id: sequence.id, taxonomy_id: taxonomy_ids)
        .order(assigned_at: :desc)
        .to_a
    rows.group_by(&:taxonomy_id)
  end

  def assignment_payload(assignment, histories: nil)
    payload = {
      id: assignment.id,
      taxonomy_id: assignment.taxonomy_id,
      taxonomy_term_id: assignment.taxonomy_term_id,
      label_snapshot: assignment.label_snapshot,
      assigned_at: assignment.assigned_at.iso8601
    }

    if assignment.taxonomy.process_tracking?
      payload[:histories] = Array(histories).map { |history| history_payload(history) }
    end

    payload
  end

  def history_payload(history)
    {
      id: history.id,
      taxonomy_term_id: history.taxonomy_term_id,
      label_snapshot: history.label_snapshot,
      assigned_at: history.assigned_at.iso8601,
      ended_at: history.ended_at.iso8601
    }
  end
end
