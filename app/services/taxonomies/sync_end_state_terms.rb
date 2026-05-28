# frozen_string_literal: true

module Taxonomies
  class SyncEndStateTerms
    Result = Struct.new(:status, :taxonomy, :errors, keyword_init: true)

    def self.call(taxonomy:, term_ids:)
      new(taxonomy: taxonomy, term_ids: term_ids).call
    end

    def initialize(taxonomy:, term_ids:)
      @taxonomy = taxonomy
      @term_ids = Array(term_ids).map(&:to_i).uniq
      @errors = []
    end

    def call
      unless @taxonomy.process_tracking?
        return Result.new(status: :invalid, errors: ["End state values require process tracking"])
      end

      validate_term_ids!
      return Result.new(status: :invalid, errors: @errors) if @errors.any?

      Taxonomy.transaction do
        @taxonomy.taxonomy_terms.update_all(process_end_state: false)
        @taxonomy.taxonomy_terms.where(id: @term_ids).update_all(process_end_state: true) if @term_ids.any?
      end

      Result.new(status: :ok, taxonomy: @taxonomy.reload)
    end

    private

    def validate_term_ids!
      return if @term_ids.empty?

      found = @taxonomy.taxonomy_terms.where(id: @term_ids).pluck(:id)
      missing = @term_ids - found
      return if missing.empty?

      @errors << "unknown end state term ids #{missing.join(', ')}"
    end
  end
end
