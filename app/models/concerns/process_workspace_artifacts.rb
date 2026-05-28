# frozen_string_literal: true

# Shared artifact eligibility for Making (ProcessBoard) and Made (MadeTimeline) workspaces.
module ProcessWorkspaceArtifacts
  extend ActiveSupport::Concern

  private

  def applicable_artifacts
    excluded_ids = excluded_sequence_ids.to_set
    sequences = @project.sequences.generative_sequences.where(is_term: false).to_a
    bundles = @project.sequences.bundles.to_a
    (sequences + bundles)
      .select { |artifact| applicable?(artifact) }
      .reject { |artifact| excluded_ids.include?(artifact.id) }
  end

  def excluded_sequence_ids
    return [] unless ready?

    Taxonomies::Exclusion.excluded_sequence_ids_for(@project, process_taxonomy: taxonomy)
  end

  def applicable?(artifact)
    return taxonomy.applicable_to_bundle? if artifact.bundle?

    taxonomy.applicable_to_sequence?(artifact)
  end

  def load_assignments_by_sequence_id
    TaxonomyAssignment
      .where(project_id: @project.id, taxonomy_id: taxonomy.id)
      .includes(:sequence, :taxonomy_term)
      .index_by(&:sequence_id)
  end

  def end_state_assignment?(assignment)
    assignment&.taxonomy_term&.process_end_state?
  end
end
