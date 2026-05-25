# frozen_string_literal: true

module Taxonomies
  class ClearExcludedProcessAssignments
    def self.call(process_taxonomy:)
      new(process_taxonomy: process_taxonomy).call
    end

    def initialize(process_taxonomy:)
      @process_taxonomy = process_taxonomy
    end

    def call
      excluded_ids = Exclusion.excluded_sequence_ids_for(@process_taxonomy.project, process_taxonomy: @process_taxonomy)
      return 0 if excluded_ids.empty?

      assignments =
        TaxonomyAssignment
          .where(taxonomy_id: @process_taxonomy.id, sequence_id: excluded_ids)
          .includes(:sequence, :taxonomy)
          .to_a

      return 0 if assignments.empty?

      AssignmentCleanup.delete_assignments!(assignments, taxonomy: @process_taxonomy)
      assignments.size
    end
  end
end
