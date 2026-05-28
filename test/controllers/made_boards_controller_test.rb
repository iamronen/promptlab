# frozen_string_literal: true

require "test_helper"

class MadeBoardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Made board project", user: users(:alice))
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
    @doing = @taxonomy.taxonomy_terms.create!(label: "Doing", position: 1)
    @done = @taxonomy.taxonomy_terms.create!(label: "Done", position: 2, process_end_state: true)
    @project.update!(default_process_taxonomy: @taxonomy)
  end

  test "show requires authentication" do
    sign_out :user
    get project_made_board_path(@project), headers: { "Turbo-Frame" => "made_board" }
    assert_redirected_to new_user_session_path
  end

  test "show renders empty state when no end-state assignments" do
    get project_made_board_path(@project), headers: { "Turbo-Frame" => "made_board" }
    assert_response :success
    assert_select "turbo-frame#made_board"
    assert_select ".workspace-made-empty"
  end

  test "show renders timeline entries for end-state assignments" do
    assigned_at = Time.zone.parse("2026-03-15 14:30")
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: assigned_at
    )

    get project_made_board_path(@project), headers: { "Turbo-Frame" => "made_board" }
    assert_response :success
    assert_select ".workspace-made-timeline"
    assert_select ".workspace-made-timeline-date-group", count: 1
    assert_select "time[datetime='#{assigned_at.to_date.iso8601}']"
    assert_select ".workspace-made-timeline-date", count: 1
    assert_select ".workspace-made-timeline-term", count: 0
    assert_select ".workspace-made-task-card-end-state-pill", count: 0
    assert_select ".workspace-process-task-card[aria-label*='Alpha']"
    assert_select ".workspace-process-task-card[aria-label*='Done']", count: 0
  end

  test "show renders end-state pill when taxonomy has multiple end-state values" do
    shipped = @taxonomy.taxonomy_terms.create!(label: "Shipped", position: 3, process_end_state: true)
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: @taxonomy,
      taxonomy_term: shipped,
      label_snapshot: shipped.label,
      assigned_at: Time.zone.parse("2026-03-15 14:30")
    )

    get project_made_board_path(@project), headers: { "Turbo-Frame" => "made_board" }
    assert_response :success
    assert_select ".workspace-made-task-card-end-state-pill", text: "Shipped"
    assert_select ".workspace-process-task-card[aria-label*='Shipped']"
  end

  test "show excludes in-progress assignments" do
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: @taxonomy,
      taxonomy_term: @doing,
      label_snapshot: @doing.label,
      assigned_at: Time.current
    )

    get project_made_board_path(@project), headers: { "Turbo-Frame" => "made_board" }
    assert_response :success
    assert_select ".workspace-made-timeline", count: 0
    assert_select ".workspace-made-empty"
  end
end
