# frozen_string_literal: true

require "test_helper"

class SequencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Sequences project", user: users(:alice))
    @sequence = @project.sequences.create!(
      kind: :sequence,
      title: "Multi-step",
      intent: "Test intent",
      position: 1,
      steps_data: [{ "content" => "A" }, { "content" => "B" }, { "content" => "C" }],
      is_term: false
    )
  end

  test "autosave title-only preserves existing multi-step steps_data" do
    patch project_sequence_path(@project, @sequence),
          params: { autosave: "1", sequence: { title: "New title" } },
          as: :json

    assert_response :success
    @sequence.reload
    assert_equal "New title", @sequence.title
    assert_equal 3, @sequence.steps_data.size
    assert_equal %w[A B C], @sequence.steps_data.map { |s| s["content"] }
  end

  test "autosave with partial steps_attributes and no save_steps preserves existing steps" do
    patch project_sequence_path(@project, @sequence),
          params: {
            autosave: "1",
            sequence: {
              title: "New title",
              steps_attributes: {
                "0" => { position: "1", _destroy: "false", content: "only one" }
              }
            }
          },
          as: :json

    assert_response :success
    @sequence.reload
    assert_equal "New title", @sequence.title
    assert_equal 3, @sequence.steps_data.size
    assert_equal %w[A B C], @sequence.steps_data.map { |s| s["content"] }
  end

  test "autosave with save_steps updates step content" do
    patch project_sequence_path(@project, @sequence),
          params: {
            autosave: "1",
            save_steps: "1",
            sequence: {
              title: "Multi-step",
              intent: "Test intent",
              steps_attributes: {
                "0" => { position: "1", _destroy: "false", content: "Alpha" },
                "1" => { position: "2", _destroy: "false", content: "Beta" },
                "2" => { position: "3", _destroy: "false", content: "Gamma" }
              }
            }
          },
          as: :json

    assert_response :success
    @sequence.reload
    assert_equal %w[Alpha Beta Gamma], @sequence.steps_data.map { |s| s["content"] }
  end
end
