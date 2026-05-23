# frozen_string_literal: true

require "test_helper"

class TaxonomiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
  end

  test "index returns taxonomies as json" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        single_select_ui: "dropdown",
        position: 1
      )
    taxonomy.taxonomy_terms.create!(label: "Open", position: 1)

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 1, data.size
    assert_equal "Status", data.first["name"]
    assert_equal "one", data.first["cardinality"]
    assert_equal "dropdown", data.first["single_select_ui"]
    assert_equal 1, data.first["terms"].size
    assert_equal 0, data.first["terms"].first["applied_sequence_count"]
  end

  test "index includes applied_sequence_count on terms" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :many, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    seq1 =
      @project.sequences.create!(
        kind: :sequence,
        title: "S1",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    seq2 =
      @project.sequences.create!(
        kind: :sequence,
        title: "S2",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq1.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: false
    )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq2.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: false
    )

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    term_json = data.find { |t| t["id"] == taxonomy.id }["terms"].find { |x| x["id"] == term.id }
    assert_equal 2, term_json["applied_sequence_count"]
  end

  test "create taxonomy returns created json" do
    assert_difference -> { @project.taxonomies.count }, +1 do
      post project_taxonomies_path(@project),
           params: {
             taxonomy: { name: "  Lane  ", cardinality: "many", position: 2 }
           },
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Lane", body["name"]
    assert_equal "many", body["cardinality"]
    assert_nil body["single_select_ui"]
  end

  test "create rejects many cardinality with single_select_ui" do
    assert_no_difference -> { @project.taxonomies.count } do
      post project_taxonomies_path(@project),
           params: {
             taxonomy: { name: "Bad", cardinality: "many", single_select_ui: "dropdown" }
           },
           as: :json
    end

    assert_response :unprocessable_entity
  end

  test "update taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "A", cardinality: :one, single_select_ui: "dropdown", position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { name: "B", single_select_ui: "button_group" } },
          as: :json

    assert_response :success
    taxonomy.reload
    assert_equal "B", taxonomy.name
    assert_equal "button_group", taxonomy.single_select_ui
  end

  test "destroy taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "A", cardinality: :one, position: 1)

    assert_difference -> { @project.taxonomies.count }, -1 do
      delete project_taxonomy_path(@project, taxonomy), as: :json
    end

    assert_response :no_content
  end

  test "index returns taxonomies ordered by position" do
    t3 = @project.taxonomies.create!(name: "Third", cardinality: :many, position: 3)
    t1 = @project.taxonomies.create!(name: "First", cardinality: :many, position: 1)
    t2 = @project.taxonomies.create!(name: "Second", cardinality: :many, position: 2)

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    ids = JSON.parse(response.body).map { |row| row["id"] }
    assert_equal [t1.id, t2.id, t3.id], ids
  end

  test "reorder taxonomies" do
    t1 = @project.taxonomies.create!(name: "A", cardinality: :many, position: 1)
    t2 = @project.taxonomies.create!(name: "B", cardinality: :many, position: 2)
    t3 = @project.taxonomies.create!(name: "C", cardinality: :many, position: 3)

    put reorder_project_taxonomies_path(@project),
        params: { ordered_taxonomy_ids: [t3.id, t1.id, t2.id] },
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    positions = body.to_h { |row| [row["id"], row["position"]] }
    assert_equal 1, positions[t3.id]
    assert_equal 2, positions[t1.id]
    assert_equal 3, positions[t2.id]
  end
end
