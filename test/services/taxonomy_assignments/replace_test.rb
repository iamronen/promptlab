# frozen_string_literal: true

require "test_helper"

class TaxonomyAssignmentsReplaceTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "T", cardinality: :one, position: 1)
    @term = @taxonomy.taxonomy_terms.create!(label: "Only", position: 1)
    @sequence =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
  end

  test "replace clears omitted taxonomies" do
    other = @project.taxonomies.create!(name: "Other", cardinality: :many, position: 2)
    other_term = other.taxonomy_terms.create!(label: "X", position: 1)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: other.id,
      taxonomy_term_id: other_term.id,
      label_snapshot: other_term.label,
      single_value_taxonomy_copy: false
    )

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }]
      )

    assert replacer.call
    assert_predicate replacer.errors, :empty?
    assert_equal 1, TaxonomyAssignment.where(sequence_id: @sequence.id).count
    assert TaxonomyAssignment.exists?(taxonomy_id: @taxonomy.id, sequence_id: @sequence.id)
    refute TaxonomyAssignment.exists?(taxonomy_id: other.id, sequence_id: @sequence.id)
  end

  test "duplicate taxonomy payload is rejected" do
    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [
          { "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] },
          { "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }
        ]
      )

    refute replacer.call
    assert_includes replacer.errors.join, "Duplicate taxonomy_id"
  end
end
