# frozen_string_literal: true

require "test_helper"

class ProcessBoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Process board project", user: users(:alice))
    @seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "Alpha",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    @taxonomy =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    @todo = @taxonomy.taxonomy_terms.create!(label: "Todo", position: 1)
    @project.update!(default_process_taxonomy: @taxonomy)
  end

  test "show requires authentication" do
    sign_out :user
    get project_process_board_path(@project), headers: { "Turbo-Frame" => "process_board" }
    assert_redirected_to new_user_session_path
  end

  test "show renders turbo frame with kanban columns" do
    get project_process_board_path(@project), headers: { "Turbo-Frame" => "process_board" }
    assert_response :success
    assert_select "turbo-frame#process_board"
    assert_select ".workspace-process-board"
    assert_select ".workspace-process-column", count: 2
    assert_select ".tool-part-header", text: /Todo/
    assert_select ".tool-part-header", text: /Unassigned/
    assert_select ".workspace-process-task-card[aria-label*='Alpha']"
  end

  test "show moves card into assigned column after taxonomy update" do
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: @taxonomy,
      taxonomy_term: @todo,
      label_snapshot: @todo.label,
      assigned_at: Time.current
    )

    get project_process_board_path(@project), headers: { "Turbo-Frame" => "process_board" }
    assert_response :success
    assert_select ".tool-part-header", text: /Todo/ do |headers|
      column = headers.first.ancestors(".workspace-process-column").first
      assert column.at_css(".workspace-process-task-card[aria-label*='Alpha']")
    end
    assert_select ".tool-part-header", text: /Unassigned/, count: 0
  end
end
