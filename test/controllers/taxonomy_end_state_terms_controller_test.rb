# frozen_string_literal: true

require "test_helper"

class TaxonomyEndStateTermsControllerTest < ActionDispatch::IntegrationTest
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
    @doing = @stage.taxonomy_terms.create!(label: "Doing", position: 1)
    @done = @stage.taxonomy_terms.create!(label: "Done", position: 2)
  end

  test "update syncs end state terms and returns taxonomy payload" do
    put end_state_terms_project_taxonomy_path(@project, @stage),
        params: { end_state_term_ids: [@done.id] },
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @stage.id, body["id"]
    assert_equal [@done.id], body["end_state_term_ids"]
    assert @done.reload.process_end_state?
  end

  test "update rejects non-process taxonomy" do
    standard = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 3)

    put end_state_terms_project_taxonomy_path(@project, standard),
        params: { end_state_term_ids: [] },
        as: :json

    assert_response :unprocessable_entity
  end

  test "index includes end_state_term_ids for process taxonomies" do
    Taxonomies::SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@done.id])

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    stage = JSON.parse(response.body)["taxonomies"].find { |t| t["id"] == @stage.id }
    assert_equal [@done.id], stage["end_state_term_ids"]
  end
end
