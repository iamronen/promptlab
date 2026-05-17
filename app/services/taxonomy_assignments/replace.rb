# frozen_string_literal: true

module TaxonomyAssignments
  class Replace
    attr_reader :errors

    def self.call(sequence:, assignments:)
      new(sequence:, assignments:).call
    end

    def initialize(sequence:, assignments:)
      @sequence = sequence
      @assignments = normalize_assignments(assignments)
      @errors = []
    end

    def call
      @errors = []
      validate_sequence!
      validate_payload_shape!
      return false if @errors.any?

      begin
        ActiveRecord::Base.transaction do
          apply!
        end
      rescue ActiveRecord::RecordInvalid => e
        @errors.concat(e.record.errors.full_messages)
      end

      @errors.empty?
    end

    private

    def normalize_assignments(raw)
      Array(raw).map do |row|
        h =
          case row
          when ActionController::Parameters
            row.permit(:taxonomy_id, taxonomy_term_ids: []).to_h
          when Hash
            row.stringify_keys.slice("taxonomy_id", "taxonomy_term_ids")
          else
            {}
          end
        h["taxonomy_term_ids"] ||= []
        h
      end
    end

    def validate_sequence!
      return if @sequence&.sequence?

      @errors << "Sequence must be a generative sequence"
    end

    def validate_payload_shape!
      seen = {}
      @assignments.each do |row|
        taxonomy_id = row["taxonomy_id"].to_i
        if taxonomy_id <= 0
          @errors << "taxonomy_id must be present"
          next
        end

        if seen[taxonomy_id]
          @errors << "Duplicate taxonomy_id in payload"
        end
        seen[taxonomy_id] = true

        unless row["taxonomy_term_ids"].is_a?(Array)
          @errors << "taxonomy_term_ids must be an array"
        end
      end
    end

    def apply!
      project = @sequence.project

      TaxonomyAssignment.where(sequence_id: @sequence.id).delete_all

      @assignments.each do |row|
        taxonomy_id = row["taxonomy_id"].to_i
        term_ids = Array(row["taxonomy_term_ids"]).map(&:to_i).uniq
        next if term_ids.empty?

        taxonomy = project.taxonomies.find_by(id: taxonomy_id)
        unless taxonomy
          @errors << "Unknown taxonomy #{taxonomy_id}"
          raise ActiveRecord::Rollback
        end

        if taxonomy.one? && term_ids.size > 1
          @errors << "Taxonomy #{taxonomy_id} allows only one term"
          raise ActiveRecord::Rollback
        end

        terms = taxonomy.taxonomy_terms.where(id: term_ids).index_by(&:id)
        missing = term_ids - terms.keys
        if missing.any?
          @errors << "Unknown taxonomy term ids #{missing.join(', ')} for taxonomy #{taxonomy_id}"
          raise ActiveRecord::Rollback
        end

        term_ids.each do |tid|
          term = terms[tid]
          assignment = TaxonomyAssignment.new(
            sequence: @sequence,
            taxonomy: taxonomy,
            taxonomy_term: term,
            project_id: project.id
          )
          assignment.save!
        end
      end
    end
  end
end
