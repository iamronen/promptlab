# frozen_string_literal: true

require "test_helper"

class TaxonomiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = Project.create!(name: "P")
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
end
