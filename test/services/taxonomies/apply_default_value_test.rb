# frozen_string_literal: true

require "test_helper"

module Taxonomies
  class ApplyDefaultValueTest < ActiveSupport::TestCase
    setup do
      @project = Project.create!(name: "P", user: users(:alice))
      @taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
      @term = @taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
      @taxonomy.update!(default_value_enabled: true, default_taxonomy_term: @term)
    end

    test "returns invalid when default value is not configured" do
      @taxonomy.update!(default_value_enabled: false)

      result = ApplyDefaultValue.call(@taxonomy)

      assert_equal :invalid, result.status
      assert_includes result.errors, "Default value is not configured"
    end

    test "applies default to unassigned standalone sequences" do
      seq =
        @project.sequences.create!(
          kind: :sequence,
          title: "S",
          intent: "i",
          position: 1,
          steps_data: [{ "content" => "" }],
          is_term: false
        )

      result = ApplyDefaultValue.call(@taxonomy)

      assert_equal :ok, result.status
      assert_equal 1, result.applied_count
      assignment = TaxonomyAssignment.find_by(sequence_id: seq.id, taxonomy_id: @taxonomy.id)
      assert_equal @term.id, assignment.taxonomy_term_id
    end

    test "skips sequences that already have a value" do
      assigned =
        @project.sequences.create!(
          kind: :sequence,
          title: "Assigned",
          intent: "i",
          position: 1,
          steps_data: [{ "content" => "" }],
          is_term: false
        )
      unassigned =
        @project.sequences.create!(
          kind: :sequence,
          title: "Unassigned",
          intent: "i",
          position: 2,
          steps_data: [{ "content" => "" }],
          is_term: false
        )
      other_term = @taxonomy.taxonomy_terms.create!(label: "Done", position: 2)
      TaxonomyAssignment.create!(
        project_id: @project.id,
        sequence: assigned,
        taxonomy: @taxonomy,
        taxonomy_term: other_term,
        label_snapshot: other_term.label,
        single_value_taxonomy_copy: true
      )

      result = ApplyDefaultValue.call(@taxonomy)

      assert_equal 1, result.applied_count
      assert TaxonomyAssignment.exists?(sequence_id: unassigned.id, taxonomy_term_id: @term.id)
      assert TaxonomyAssignment.exists?(sequence_id: assigned.id, taxonomy_term_id: other_term.id)
    end

    test "applies to bundles when taxonomy applies to bundles" do
      gen =
        @project.sequences.create!(
          kind: :sequence,
          title: "Gen",
          intent: "i",
          position: 1,
          steps_data: [{ "content" => "" }],
          is_term: false
        )
      bundle =
        @project.sequences.create!(
          kind: :bundle,
          title: "Bundle",
          intent: "bi",
          position: 1,
          steps_data: [{ "sequence_id" => gen.id }],
          is_term: false
        )
      @taxonomy.update!(applies_to_bundles: true, applies_to_bundle_pipeline_sequences: false)

      result = ApplyDefaultValue.call(@taxonomy)

      assert_equal 1, result.applied_count
      assert TaxonomyAssignment.exists?(sequence_id: bundle.id, taxonomy_term_id: @term.id)
      assert_not TaxonomyAssignment.exists?(sequence_id: gen.id, taxonomy_id: @taxonomy.id)
    end

    test "applies to pipeline sequences when enabled" do
      gen =
        @project.sequences.create!(
          kind: :sequence,
          title: "Gen",
          intent: "i",
          position: 1,
          steps_data: [{ "content" => "" }],
          is_term: false
        )
      bundle =
        @project.sequences.create!(
          kind: :bundle,
          title: "Bundle",
          intent: "bi",
          position: 1,
          steps_data: [{ "sequence_id" => gen.id }],
          is_term: false
        )
      bundle
      gen.reload
      @taxonomy.update!(applies_to_bundles: true, applies_to_bundle_pipeline_sequences: true)

      result = ApplyDefaultValue.call(@taxonomy)

      assert_equal 2, result.applied_count
      assert TaxonomyAssignment.exists?(sequence_id: bundle.id, taxonomy_term_id: @term.id)
      assert TaxonomyAssignment.exists?(sequence_id: gen.id, taxonomy_term_id: @term.id)
    end
  end
end
