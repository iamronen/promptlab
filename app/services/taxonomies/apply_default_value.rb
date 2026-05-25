# frozen_string_literal: true

module Taxonomies
  class ApplyDefaultValue
    Result = Struct.new(:status, :applied_count, :errors, keyword_init: true)

    def self.call(taxonomy)
      new(taxonomy).call
    end

    def initialize(taxonomy)
      @taxonomy = taxonomy
    end

    def call
      unless @taxonomy.default_value_configured?
        return Result.new(status: :invalid, errors: ["Default value is not configured"])
      end

      term = @taxonomy.default_taxonomy_term
      unless term
        return Result.new(status: :invalid, errors: ["Default value is not configured"])
      end

      applied_count = 0
      TaxonomyAssignment.transaction do
        unassigned_applicable_sequences.each do |sequence|
          TaxonomyAssignment.create!(
            project_id: sequence.project_id,
            sequence: sequence,
            taxonomy: @taxonomy,
            taxonomy_term: term,
            assigned_at: Time.current
          )
          applied_count += 1
        end
      end

      Result.new(status: :ok, applied_count: applied_count)
    end

    def self.unassigned_applicable_sequences_for(taxonomy)
      new(taxonomy).send(:unassigned_applicable_sequences)
    end

    private

    def unassigned_applicable_sequences
      project = @taxonomy.project
      assigned_sequence_ids =
        TaxonomyAssignment
          .where(taxonomy_id: @taxonomy.id)
          .distinct
          .pluck(:sequence_id)
          .to_set

      project.sequences.where(kind: %i[sequence bundle]).filter_map do |sequence|
        next if assigned_sequence_ids.include?(sequence.id)
        next unless applicable?(sequence)

        sequence
      end
    end

    def applicable?(sequence)
      if sequence.bundle?
        @taxonomy.applicable_to_bundle?
      else
        @taxonomy.applicable_to_sequence?(sequence)
      end
    end
  end
end
