# frozen_string_literal: true

require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Alpha Project", user: users(:alice))
  end

  test "index renders application shell with projects tool" do
    get projects_path
    assert_response :success
    assert_select ".application-shell"
    assert_select ".tool-container--centered"
    assert_select ".tool-heading-title", text: "Projects"
    assert_select "a", text: "Open Workspace"
    assert_select ".sequence-nav-menu-trigger", count: 0
  end

  test "redirects to sign-in when not authenticated" do
    sign_out users(:alice)
    get projects_path
    assert_redirected_to new_user_session_path
  end

  test "returns not found when accessing another user's project" do
    other = Project.create!(name: "Bob project", user: users(:bob))
    get settings_project_path(other), headers: { "Turbo-Frame" => "project_settings_modal" }
    assert_response :not_found
  end

  test "settings returns modal partial inside turbo frame when Turbo-Frame header matches" do
    get settings_project_path(@project), headers: { "Turbo-Frame" => "project_settings_modal" }
    assert_response :success
    assert_select "turbo-frame#project_settings_modal"
    assert_select "h2", text: "Alpha Project"
    assert_match(/thread/i, response.body)
    assert_match(/sequences/i, response.body)
    assert_match(/Taxonomies/i, response.body)
    assert_match(/Default process taxonomy/i, response.body)
    assert_select "select[data-project-taxonomies-target='defaultProcessTaxonomySelect'][disabled]"
  end

  test "settings redirects to projects index without turbo frame" do
    get settings_project_path(@project)
    assert_redirected_to projects_path
  end

  test "new returns create modal partial inside turbo frame" do
    get new_project_path, headers: { "Turbo-Frame" => "project_create_modal" }
    assert_response :success
    assert_select "turbo-frame#project_create_modal"
    assert_select "h2", text: "New project"
  end

  test "new redirects to index without turbo frame" do
    get new_project_path
    assert_redirected_to projects_path
  end

  test "create redirects to workspace with genesis weave and focused sequence" do
    assert_difference("Project.count", 1) do
      post projects_path, params: { project: { name: "Fresh" } }
    end
    assert_response :see_other
    project = Project.order(:created_at).last
    assert_equal users(:alice), project.user
    genesis = project.genesis_thread
    seq = project.sequences.generative_sequences.order(:position).first
    assert_equal edit_project_sequence_path(project, seq), URI.parse(response.location).path
    assert_match(/weave_thread=#{genesis.id}/, response.location)
    assert_match(/focus_transformation_id=#{seq.id}/, response.location)
  end

  test "create renders modal partial with errors when turbo frame request and invalid" do
    assert_no_difference("Project.count") do
      post projects_path,
           headers: { "Turbo-Frame" => "project_create_modal" },
           params: { project: { name: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "turbo-frame#project_create_modal"
    assert_select "section.errors"
  end

  test "create redirects with alert when invalid without turbo frame" do
    assert_no_difference("Project.count") do
      post projects_path, params: { project: { name: "" } }
    end
    assert_redirected_to projects_path
    assert flash[:alert].present?
  end

  test "update redirects to projects index on success" do
    patch project_path(@project), params: { project: { name: "Renamed" } }
    assert_redirected_to projects_path
    assert_equal "Renamed", @project.reload.name
  end

  test "update renders modal partial with errors when turbo frame request and invalid" do
    patch project_path(@project),
          headers: { "Turbo-Frame" => "project_settings_modal" },
          params: { project: { name: "" } }
    assert_response :unprocessable_entity
    assert_select "turbo-frame#project_settings_modal"
    assert_select "section.errors"
    assert_equal "Alpha Project", @project.reload.name
  end

  test "update redirects with alert when invalid without turbo frame" do
    patch project_path(@project), params: { project: { name: "" } }
    assert_redirected_to projects_path
    assert_equal "Alpha Project", @project.reload.name
    assert flash[:alert].present?
  end

  test "destroy removes project and redirects" do
    assert_difference("Project.count", -1) do
      delete project_path(@project)
    end
    assert_redirected_to projects_path
  end

  test "update default process taxonomy via json" do
    first =
      @project.taxonomies.create!(
        name: "First",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )
    second =
      @project.taxonomies.create!(
        name: "Second",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 2
      )
    @project.update!(default_process_taxonomy: first)

    patch project_path(@project),
          params: { project: { default_process_taxonomy_id: second.id } },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal second.id, body["default_process_taxonomy_id"]
    assert_equal second.id, @project.reload.default_process_taxonomy_id
  end

  test "update rejects non-process taxonomy as default via json" do
    taxonomy = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 1)

    patch project_path(@project),
          params: { project: { default_process_taxonomy_id: taxonomy.id } },
          as: :json

    assert_response :unprocessable_entity
    assert_nil @project.reload.default_process_taxonomy_id
  end

  test "destroy removes project with taxonomy terms and sequence assignments" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    sequence =
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
      sequence_id: sequence.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: true
    )

    assert_difference("Project.count", -1) do
      assert_difference(["Taxonomy.count", "TaxonomyTerm.count", "TaxonomyAssignment.count"], -1) do
        delete project_path(@project)
      end
    end
    assert_redirected_to projects_path
  end
end
