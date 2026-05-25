# frozen_string_literal: true

module Taxonomies
  module AssignmentCleanup
    module_function

    def delete_assignments!(assignments, taxonomy:)
      rows = Array(assignments)
      return if rows.empty?

      if taxonomy.process_tracking?
        rows.each do |assignment|
          # History records only accept generative sequences; bundle rows are deleted without archiving.
          next if assignment.sequence&.bundle?

          archive_assignment!(assignment)
        end
      end

      TaxonomyAssignment.where(id: rows.map(&:id)).delete_all
    end

    def archive_assignment!(assignment)
      now = Time.current
      TaxonomyAssignmentHistory.create!(
        project_id: assignment.project_id,
        sequence_id: assignment.sequence_id,
        taxonomy_id: assignment.taxonomy_id,
        taxonomy_term_id: assignment.taxonomy_term_id,
        label_snapshot: assignment.label_snapshot,
        assigned_at: assignment.assigned_at,
        ended_at: now
      )
    end

    def bundle_assignments_for(taxonomy)
      TaxonomyAssignment
        .joins(:sequence)
        .where(taxonomy_id: taxonomy.id, sequences: { kind: Sequence.kinds[:bundle] })
        .to_a
    end

    def pipeline_sequence_assignments_for(taxonomy)
      pipeline_ids = pipeline_generative_sequence_ids_for(taxonomy.project)
      return [] if pipeline_ids.empty?

      TaxonomyAssignment.where(taxonomy_id: taxonomy.id, sequence_id: pipeline_ids).to_a
    end

    def pipeline_generative_sequence_ids_for(project)
      project.sequences.bundles.flat_map(&:pipeline_generative_sequence_ids).uniq
    end
  end
end
