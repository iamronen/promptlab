# frozen_string_literal: true

require "test_helper"

module Taxonomies
  class SyncExclusionRulesTest < ActiveSupport::TestCase
    setup do
      @project = Project.create!(name: "P", user: users(:alice))
      @stage =
        @project.taxonomies.create!(
          name: "Stage",
          cardinality: :one,
          process_tracking: true,
          applies_to_bundles: true,
          position: 1
        )
      @doing = @stage.taxonomy_terms.create!(label: "Doing", position: 1)
      @perspective =
        @project.taxonomies.create!(
          name: "Perspective",
          cardinality: :one,
          position: 2
        )
      @vision = @perspective.taxonomy_terms.create!(label: "Vision", position: 1)
      @production = @perspective.taxonomy_terms.create!(label: "Production", position: 2)

      @sequence =
        @project.sequences.create!(
          kind: :sequence,
          title: "Alpha",
          intent: "i",
          position: 1,
          steps_data: [{ "content" => "x" }],
          is_term: false
        )
    end

    test "sync creates rules and clears process assignments on triggered sequences" do
      TaxonomyAssignment.create!(
        project: @project,
        sequence: @sequence,
        taxonomy: @stage,
        taxonomy_term: @doing,
        label_snapshot: @doing.label,
        assigned_at: Time.current
      )
      TaxonomyAssignment.create!(
        project: @project,
        sequence: @sequence,
        taxonomy: @perspective,
        taxonomy_term: @vision,
        label_snapshot: @vision.label,
        assigned_at: Time.current
      )

      result =
        SyncExclusionRules.call(
          taxonomy: @stage,
          rules: [{ excluding_taxonomy_id: @perspective.id, excluding_term_ids: [@vision.id] }]
        )

      assert_equal :ok, result.status
      assert_equal 1, @stage.exclusion_rules.count
      assert_equal [@vision.id], @stage.exclusion_rules.first.excluding_term_ids
      assert_not TaxonomyAssignment.exists?(sequence: @sequence, taxonomy: @stage)
      assert TaxonomyAssignment.exists?(sequence: @sequence, taxonomy: @perspective)
    end

    test "sync rejects empty excluding terms" do
      result =
        SyncExclusionRules.call(
          taxonomy: @stage,
          rules: [{ excluding_taxonomy_id: @perspective.id, excluding_term_ids: [] }]
        )

      assert_equal :invalid, result.status
      assert result.errors.any? { |e| e.include?("at least one excluding value") }
    end

    test "sync replaces existing rules" do
      SyncExclusionRules.call(
        taxonomy: @stage,
        rules: [{ excluding_taxonomy_id: @perspective.id, excluding_term_ids: [@vision.id] }]
      )

      result =
        SyncExclusionRules.call(
          taxonomy: @stage,
          rules: [{ excluding_taxonomy_id: @perspective.id, excluding_term_ids: [@production.id] }]
        )

      assert_equal :ok, result.status
      assert_equal 1, @stage.exclusion_rules.count
      assert_equal [@production.id], @stage.exclusion_rules.first.excluding_term_ids
    end
  end
end
