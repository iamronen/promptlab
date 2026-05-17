# frozen_string_literal: true

require "test_helper"

class SequenceTaxonomyAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = Project.create!(name: "P")
    @taxonomy_one = @project.taxonomies.create!(name: "Priority", cardinality: :one, position: 1)
    @taxonomy_many = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 2)
    @p1 = @taxonomy_one.taxonomy_terms.create!(label: "High", position: 1)
    @p2 = @taxonomy_one.taxonomy_terms.create!(label: "Low", position: 2)
    @m1 = @taxonomy_many.taxonomy_terms.create!(label: "A", position: 1)
    @m2 = @taxonomy_many.taxonomy_terms.create!(label: "B", position: 2)

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

  test "show returns assignments json" do
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy_one.id,
      taxonomy_term_id: @p1.id,
      label_snapshot: @p1.label,
      single_value_taxonomy_copy: true
    )

    get project_sequence_taxonomy_assignments_path(@project, @sequence), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["assignments"].size
    assert_equal @taxonomy_one.id, body["assignments"].first["taxonomy_id"]
    assert_equal @p1.id, body["assignments"].first["taxonomy_term_id"]
  end

  test "update replaces assignments" do
    put project_sequence_taxonomy_assignments_path(@project, @sequence),
        params: {
          assignments: [
            { taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p2.id] },
            { taxonomy_id: @taxonomy_many.id, taxonomy_term_ids: [@m1.id, @m2.id] }
          ]
        },
        as: :json

    assert_response :success
    rows = TaxonomyAssignment.where(sequence_id: @sequence.id).order(:taxonomy_id, :id)
    assert_equal 3, rows.count
    assert_equal [@p2.id], rows.where(taxonomy_id: @taxonomy_one.id).pluck(:taxonomy_term_id)
    assert_equal [@m1.id, @m2.id].sort, rows.where(taxonomy_id: @taxonomy_many.id).pluck(:taxonomy_term_id).sort
  end

  test "update rejects multiple terms for single cardinality taxonomy" do
    put project_sequence_taxonomy_assignments_path(@project, @sequence),
        params: {
          assignments: [
            { taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p1.id, @p2.id] }
          ]
        },
        as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert body["errors"].join.include?("allows only one term")
  end

  test "generative sequence scope rejects bundles" do
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )

    get project_sequence_taxonomy_assignments_path(@project, bundle), as: :json

    assert_response :not_found
  end
end
