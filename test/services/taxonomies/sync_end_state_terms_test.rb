# frozen_string_literal: true

require "test_helper"

module Taxonomies
  class SyncEndStateTermsTest < ActiveSupport::TestCase
    setup do
      @project = Project.create!(name: "P", user: users(:alice))
      @stage =
        @project.taxonomies.create!(
          name: "Stage",
          cardinality: :one,
          process_tracking: true,
          position: 1
        )
      @doing = @stage.taxonomy_terms.create!(label: "Doing", position: 1)
      @done = @stage.taxonomy_terms.create!(label: "Done", position: 2)
    end

    test "sync marks end state terms" do
      result = SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@done.id])

      assert_equal :ok, result.status
      assert @done.reload.process_end_state?
      refute @doing.reload.process_end_state?
      assert_equal [@done.id], @stage.taxonomy_terms.where(process_end_state: true).pluck(:id)
    end

    test "sync replaces existing end state terms" do
      SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@done.id])

      result = SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@doing.id])

      assert_equal :ok, result.status
      assert @doing.reload.process_end_state?
      refute @done.reload.process_end_state?
    end

    test "sync accepts empty array and clears end states" do
      SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@done.id])

      result = SyncEndStateTerms.call(taxonomy: @stage, term_ids: [])

      assert_equal :ok, result.status
      assert_empty @stage.taxonomy_terms.where(process_end_state: true)
    end

    test "sync rejects unknown term ids" do
      other = @project.taxonomies.create!(name: "Other", cardinality: :one, position: 2)
      foreign = other.taxonomy_terms.create!(label: "Foreign", position: 1)

      result = SyncEndStateTerms.call(taxonomy: @stage, term_ids: [foreign.id])

      assert_equal :invalid, result.status
      assert result.errors.any? { |e| e.include?("unknown end state term ids") }
    end

    test "sync rejects non-process taxonomy" do
      standard = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 3)
      tag = standard.taxonomy_terms.create!(label: "Tag", position: 1)

      result = SyncEndStateTerms.call(taxonomy: standard, term_ids: [tag.id])

      assert_equal :invalid, result.status
      assert result.errors.any? { |e| e.include?("process tracking") }
    end
  end
end
