# frozen_string_literal: true

module Taxonomies
  class BackfillBundleAssignments
    def self.call(taxonomy)
      new(taxonomy).call
    end

    def initialize(taxonomy)
      @taxonomy = taxonomy
    end

    def call
      return unless @taxonomy.applies_to_bundles?

      @taxonomy.project.sequences.bundles.find_each do |bundle|
        backfill_bundle!(bundle)
      end
    end

    private

    def backfill_bundle!(bundle)
      first_id = bundle.pipeline_generative_sequence_ids.first
      return unless first_id

      source_assignments =
        TaxonomyAssignment.where(sequence_id: first_id, taxonomy_id: @taxonomy.id).to_a
      return if source_assignments.empty?

      existing_term_ids =
        TaxonomyAssignment
          .where(sequence_id: bundle.id, taxonomy_id: @taxonomy.id)
          .pluck(:taxonomy_term_id)
          .to_set

      source_assignments.each do |src|
        next if existing_term_ids.include?(src.taxonomy_term_id)

        TaxonomyAssignment.create!(
          project_id: bundle.project_id,
          sequence: bundle,
          taxonomy: @taxonomy,
          taxonomy_term: src.taxonomy_term,
          label_snapshot: src.label_snapshot,
          single_value_taxonomy_copy: src.single_value_taxonomy_copy,
          assigned_at: src.assigned_at
        )
      end
    end
  end
end
