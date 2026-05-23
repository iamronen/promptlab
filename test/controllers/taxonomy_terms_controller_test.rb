# frozen_string_literal: true

require "test_helper"

class TaxonomyTermsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :many, position: 1)
    @t1 = @taxonomy.taxonomy_terms.create!(label: "A", position: 1)
    @t2 = @taxonomy.taxonomy_terms.create!(label: "B", position: 2)
  end

  test "create term" do
    assert_difference -> { @taxonomy.taxonomy_terms.count }, +1 do
      post project_taxonomy_taxonomy_terms_path(@project, @taxonomy),
           params: { taxonomy_term: { label: " New " } },
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "New", body["label"]
    assert_equal @taxonomy.id, body["taxonomy_id"]
  end

  test "update term label refreshes assignments snapshot via callback" do
    seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @t1.id,
      label_snapshot: @t1.label,
      single_value_taxonomy_copy: false
    )

    patch project_taxonomy_taxonomy_term_path(@project, @taxonomy, @t1),
          params: { taxonomy_term: { label: "Renamed" } },
          as: :json

    assert_response :success
    assert_equal "Renamed", TaxonomyAssignment.find_by(sequence_id: seq.id).label_snapshot
  end

  test "reorder terms" do
    put reorder_project_taxonomy_taxonomy_terms_path(@project, @taxonomy),
        params: { ordered_term_ids: [@t2.id, @t1.id] },
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    positions = body["terms"].to_h { |t| [t["id"], t["position"]] }
    assert_equal 1, positions[@t2.id]
    assert_equal 2, positions[@t1.id]
  end

  test "destroy term deletes assignments for that term" do
    seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @t1.id,
      label_snapshot: @t1.label,
      single_value_taxonomy_copy: false
    )

    assert_difference -> { TaxonomyTerm.count }, -1 do
      delete project_taxonomy_taxonomy_term_path(@project, @taxonomy, @t1), as: :json
    end

    assert_response :no_content
    refute TaxonomyAssignment.exists?(taxonomy_term_id: @t1.id)
  end
end
