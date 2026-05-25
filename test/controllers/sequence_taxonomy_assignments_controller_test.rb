# frozen_string_literal: true

require "test_helper"

class SequenceTaxonomyAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
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
    assert body["assignments"].first["assigned_at"].present?
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

  test "update omits unstated taxonomy rows so they clear assignments" do
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy_one.id,
      taxonomy_term_id: @p1.id,
      label_snapshot: @p1.label,
      single_value_taxonomy_copy: true
    )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy_many.id,
      taxonomy_term_id: @m1.id,
      label_snapshot: @m1.label,
      single_value_taxonomy_copy: false
    )

    put project_sequence_taxonomy_assignments_path(@project, @sequence),
        params: {
          assignments: [{ taxonomy_id: @taxonomy_many.id, taxonomy_term_ids: [@m2.id] }]
        },
        as: :json

    assert_response :success
    rows = TaxonomyAssignment.where(sequence_id: @sequence.id)
    assert_equal 1, rows.count
    assert_equal @taxonomy_many.id, rows.first.taxonomy_id
    assert_equal @m2.id, rows.first.taxonomy_term_id
  end

  test "bundle assignments work when taxonomy applies to bundles" do
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    @taxonomy_one.update!(applies_to_bundles: true)

    put project_sequence_taxonomy_assignments_path(@project, bundle),
        params: {
          assignments: [
            { taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p1.id] }
          ]
        },
        as: :json

    assert_response :success
    assert_equal 1, TaxonomyAssignment.where(sequence_id: bundle.id).count
  end

  test "bundle assignments reject taxonomy that does not apply to bundles" do
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )

    put project_sequence_taxonomy_assignments_path(@project, bundle),
        params: {
          assignments: [
            { taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p1.id] }
          ]
        },
        as: :json

    assert_response :unprocessable_entity
  end

  test "thread sequences are not assignable" do
    get project_sequence_taxonomy_assignments_path(@project, 0), as: :json

    assert_response :not_found
  end

  test "show includes histories for process taxonomies" do
    @taxonomy_one.update!(process_tracking: true)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy_one.id,
      taxonomy_term_id: @p1.id,
      label_snapshot: @p1.label,
      single_value_taxonomy_copy: true,
      assigned_at: 2.hours.ago
    )

    TaxonomyAssignmentHistory.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy_one.id,
      taxonomy_term_id: @p2.id,
      label_snapshot: @p2.label,
      assigned_at: 4.hours.ago,
      ended_at: 2.hours.ago
    )

    get project_sequence_taxonomy_assignments_path(@project, @sequence), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    row = body["assignments"].find { |a| a["taxonomy_id"] == @taxonomy_one.id }
    assert row["assigned_at"].present?
    assert_equal 1, row["histories"].size
    assert_equal @p2.label, row["histories"].first["label_snapshot"]
    assert row["histories"].first["assigned_at"].present?
    assert row["histories"].first["ended_at"].present?
  end

  test "update on process taxonomy archives previous value" do
    @taxonomy_one.update!(process_tracking: true)

    put project_sequence_taxonomy_assignments_path(@project, @sequence),
        params: {
          assignments: [{ taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p1.id] }]
        },
        as: :json

    assert_response :success

    put project_sequence_taxonomy_assignments_path(@project, @sequence),
        params: {
          assignments: [{ taxonomy_id: @taxonomy_one.id, taxonomy_term_ids: [@p2.id] }]
        },
        as: :json

    assert_response :success
    assert_equal 1, TaxonomyAssignmentHistory.where(sequence_id: @sequence.id, taxonomy_id: @taxonomy_one.id).count

    body = JSON.parse(response.body)
    row = body["assignments"].find { |a| a["taxonomy_id"] == @taxonomy_one.id }
    assert_equal @p2.id, row["taxonomy_term_id"]
    assert_equal 1, row["histories"].size
    assert_equal @p1.label, row["histories"].first["label_snapshot"]
  end
end
