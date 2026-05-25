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
          apply_exclusion_strips!
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
      return if @sequence&.sequence? || @sequence&.bundle?

      @errors << "Sequence must be a generative sequence or bundle"
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

    def apply_exclusion_strips!
      project = @sequence.project
      process_taxonomies = project.taxonomies.where(process_tracking: true).includes(:exclusion_rules)
      term_ids_by_taxonomy = merged_term_ids_by_taxonomy_for_exclusion

      @assignments.each do |row|
        taxonomy_id = row["taxonomy_id"].to_i
        taxonomy = process_taxonomies.find { |t| t.id == taxonomy_id }
        next unless taxonomy
        next unless Taxonomies::Exclusion.excluded_with_term_ids_by_taxonomy?(
          process_taxonomy: taxonomy,
          term_ids_by_taxonomy: term_ids_by_taxonomy
        )

        row["taxonomy_term_ids"] = []
      end
    end

    def merged_term_ids_by_taxonomy_for_exclusion
      existing_by_taxonomy =
        TaxonomyAssignment.where(sequence_id: @sequence.id).group_by(&:taxonomy_id)
      payload_taxonomy_ids = @assignments.map { |row| row["taxonomy_id"].to_i }.to_set
      merged = {}

      @assignments.each do |row|
        merged[row["taxonomy_id"].to_i] = Array(row["taxonomy_term_ids"]).map(&:to_i).uniq
      end

      existing_by_taxonomy.each_key do |taxonomy_id|
        next if payload_taxonomy_ids.include?(taxonomy_id)

        merged[taxonomy_id] = existing_by_taxonomy[taxonomy_id].map(&:taxonomy_term_id)
      end

      merged
    end

    def apply!
      project = @sequence.project
      payload_taxonomy_ids = @assignments.map { |row| row["taxonomy_id"].to_i }.to_set
      existing_by_taxonomy =
        TaxonomyAssignment.where(sequence_id: @sequence.id).includes(:taxonomy, :taxonomy_term).group_by(&:taxonomy_id)

      clear_omitted_taxonomies!(project, existing_by_taxonomy, payload_taxonomy_ids)

      @assignments.each do |row|
        taxonomy_id = row["taxonomy_id"].to_i
        term_ids = Array(row["taxonomy_term_ids"]).map(&:to_i).uniq

        taxonomy = project.taxonomies.find_by(id: taxonomy_id)
        unless taxonomy
          @errors << "Unknown taxonomy #{taxonomy_id}"
          raise ActiveRecord::Rollback
        end

        unless taxonomy_applicable?(taxonomy)
          @errors << "Taxonomy #{taxonomy_id} does not apply to this #{@sequence.bundle? ? 'bundle' : 'sequence'}"
          raise ActiveRecord::Rollback
        end

        if term_ids.empty?
          clear_taxonomy!(taxonomy, existing_by_taxonomy[taxonomy_id])
          next
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

        if taxonomy.process_tracking?
          apply_process_taxonomy!(taxonomy, terms, existing_by_taxonomy[taxonomy_id])
        else
          apply_standard_taxonomy!(taxonomy, term_ids, terms, existing_by_taxonomy[taxonomy_id])
        end
      end
    end

    def clear_omitted_taxonomies!(project, existing_by_taxonomy, payload_taxonomy_ids)
      existing_by_taxonomy.each_key do |taxonomy_id|
        next if payload_taxonomy_ids.include?(taxonomy_id)

        taxonomy = project.taxonomies.find_by(id: taxonomy_id)
        next unless taxonomy

        clear_taxonomy!(taxonomy, existing_by_taxonomy[taxonomy_id])
      end
    end

    def clear_taxonomy!(taxonomy, existing_rows)
      rows = Array(existing_rows)
      return if rows.empty?

      if taxonomy.process_tracking?
        rows.each { |assignment| archive_assignment!(assignment) }
      end

      TaxonomyAssignment.where(id: rows.map(&:id)).delete_all
    end

    def apply_standard_taxonomy!(taxonomy, term_ids, terms, existing_rows)
      TaxonomyAssignment.where(id: Array(existing_rows).map(&:id)).delete_all

      term_ids.each do |tid|
        term = terms[tid]
        assignment = TaxonomyAssignment.new(
          sequence: @sequence,
          taxonomy: taxonomy,
          taxonomy_term: term,
          project_id: @sequence.project_id,
          assigned_at: Time.current
        )
        assignment.save!
      end
    end

    def apply_process_taxonomy!(taxonomy, terms, existing_rows)
      term_id = terms.keys.first
      term = terms[term_id]
      current = Array(existing_rows).first

      if current.nil?
        assignment = TaxonomyAssignment.new(
          sequence: @sequence,
          taxonomy: taxonomy,
          taxonomy_term: term,
          project_id: @sequence.project_id,
          assigned_at: Time.current
        )
        assignment.save!
        return
      end

      return if current.taxonomy_term_id == term_id

      archive_assignment!(current)
      current.taxonomy_term = term
      current.assigned_at = Time.current
      current.save!
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

    def taxonomy_applicable?(taxonomy)
      if @sequence.bundle?
        taxonomy.applicable_to_bundle?
      else
        taxonomy.applicable_to_sequence?(@sequence)
      end
    end
  end
end
