# frozen_string_literal: true

require "test_helper"

class TaxonomyExclusionRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
    @stage =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    @perspective = @project.taxonomies.create!(name: "Perspective", cardinality: :one, position: 2)
    @vision = @perspective.taxonomy_terms.create!(label: "Vision", position: 1)
  end

  test "update syncs exclusion rules and returns taxonomy payload" do
    put exclusion_rules_project_taxonomy_path(@project, @stage),
        params: {
          exclusion_rules: [
            { excluding_taxonomy_id: @perspective.id, excluding_term_ids: [@vision.id] }
          ]
        },
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @stage.id, body["id"]
    assert_equal 1, body["exclusion_rules"].size
    assert_equal @perspective.id, body["exclusion_rules"].first["excluding_taxonomy_id"]
    assert_equal [@vision.id], body["exclusion_rules"].first["excluding_term_ids"]
  end

  test "update rejects non-process taxonomy" do
    standard = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 3)

    put exclusion_rules_project_taxonomy_path(@project, standard),
        params: { exclusion_rules: [] },
        as: :json

    assert_response :unprocessable_entity
  end

  test "index includes exclusion_rules for process taxonomies" do
    Taxonomies::SyncExclusionRules.call(
      taxonomy: @stage,
      rules: [{ excluding_taxonomy_id: @perspective.id, excluding_term_ids: [@vision.id] }]
    )

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    stage = JSON.parse(response.body)["taxonomies"].find { |t| t["id"] == @stage.id }
    assert_equal 1, stage["exclusion_rules"].size
  end
end
