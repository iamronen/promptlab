# frozen_string_literal: true

require "test_helper"

class Taxonomies::BackfillBundleAssignmentsTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "Lane", cardinality: :one, position: 1, applies_to_bundles: true)
    @term = @taxonomy.taxonomy_terms.create!(label: "Alpha", position: 1)
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )
    @bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Bundle",
      intent: "bi",
      position: 1,
      steps_data: [{ "sequence_id" => @gen.id }],
      is_term: false
    )
    @assigned_at = 3.days.ago.change(usec: 0)
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @gen.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true,
      assigned_at: @assigned_at
    )
  end

  test "copies first pipeline sequence assignment to bundle with assigned_at" do
    Taxonomies::BackfillBundleAssignments.call(@taxonomy)

    row = TaxonomyAssignment.find_by!(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
    assert_equal @term.id, row.taxonomy_term_id
    assert_equal @assigned_at, row.assigned_at
  end

  test "skips bundle when first pipeline sequence has no assignment" do
    TaxonomyAssignment.where(sequence_id: @gen.id).delete_all

    Taxonomies::BackfillBundleAssignments.call(@taxonomy)

    assert_nil TaxonomyAssignment.find_by(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
  end
end
