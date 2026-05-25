# frozen_string_literal: true

module Taxonomies
  class SyncExclusionRules
    Result = Struct.new(:status, :taxonomy, :errors, keyword_init: true)

    def self.call(taxonomy:, rules:)
      new(taxonomy: taxonomy, rules: rules).call
    end

    def initialize(taxonomy:, rules:)
      @taxonomy = taxonomy
      @rules = normalize_rules(rules)
      @errors = []
    end

    def call
      unless @taxonomy.process_tracking?
        return Result.new(status: :invalid, errors: ["Exclusion rules require process tracking"])
      end

      validate_rules!
      return Result.new(status: :invalid, errors: @errors) if @errors.any?

      Taxonomy.transaction do
        @taxonomy.exclusion_rules.destroy_all
        @rules.each { |row| create_rule!(row) }
      end

      ClearExcludedProcessAssignments.call(process_taxonomy: @taxonomy.reload)

      Result.new(status: :ok, taxonomy: @taxonomy.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(status: :invalid, errors: e.record.errors.full_messages)
    end

    private

    def normalize_rules(raw)
      Array(raw).map do |row|
        h =
          case row
          when ActionController::Parameters
            row.permit(:excluding_taxonomy_id, excluding_term_ids: []).to_h
          when Hash
            row.stringify_keys.slice("excluding_taxonomy_id", "excluding_term_ids")
          else
            {}
          end
        h["excluding_term_ids"] = Array(h["excluding_term_ids"]).map(&:to_i).uniq
        h
      end
    end

    def validate_rules!
      seen_excluding_taxonomy_ids = {}
      project = @taxonomy.project

      @rules.each do |row|
        excluding_taxonomy_id = row["excluding_taxonomy_id"].to_i
        term_ids = row["excluding_term_ids"]

        if excluding_taxonomy_id <= 0
          @errors << "excluding_taxonomy_id must be present"
          next
        end

        if excluding_taxonomy_id == @taxonomy.id
          @errors << "excluding taxonomy must differ from the process taxonomy"
        end

        if seen_excluding_taxonomy_ids[excluding_taxonomy_id]
          @errors << "duplicate excluding taxonomy in exclusion rules"
        end
        seen_excluding_taxonomy_ids[excluding_taxonomy_id] = true

        if term_ids.empty?
          @errors << "each exclusion rule must include at least one excluding value"
          next
        end

        excluding_taxonomy = project.taxonomies.find_by(id: excluding_taxonomy_id)
        unless excluding_taxonomy
          @errors << "unknown excluding taxonomy #{excluding_taxonomy_id}"
          next
        end

        found = excluding_taxonomy.taxonomy_terms.where(id: term_ids).pluck(:id)
        missing = term_ids - found
        if missing.any?
          @errors << "unknown excluding term ids #{missing.join(', ')} for taxonomy #{excluding_taxonomy_id}"
        end
      end
    end

    def create_rule!(row)
      excluding_taxonomy_id = row["excluding_taxonomy_id"].to_i
      term_ids = row["excluding_term_ids"]

      rule =
        @taxonomy.exclusion_rules.create!(
          excluding_taxonomy_id: excluding_taxonomy_id,
          project_id: @taxonomy.project_id
        )

      term_ids.each do |term_id|
        rule.taxonomy_exclusion_rule_terms.create!(taxonomy_term_id: term_id)
      end
    end
  end
end
