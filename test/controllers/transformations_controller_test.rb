# frozen_string_literal: true

require "test_helper"

class TransformationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = Project.create!(name: "P")
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "<p>a</p>" }],
      is_term: false
    )
    @gen2 = @project.sequences.create!(
      kind: :sequence,
      title: "Gen2",
      intent: "i2",
      position: 2,
      steps_data: [{ "content" => "<p>b</p>" }],
      is_term: false
    )
    @trans = @project.sequences.create!(
      kind: :transformation,
      title: "T",
      intent: "ti",
      position: 1,
      steps_data: [{ "sequence_id" => @gen.id }],
      is_term: false
    )
  end

  test "create_pipeline_sequence creates a generative sequence and returns JSON" do
    assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
      post create_pipeline_sequence_project_transformation_path(@project, @trans, format: :json),
           headers: { "Accept" => "application/json" }
    end
    assert_response :created
    data = JSON.parse(response.body)
    assert data["id"]
    assert data["title"].present?

    seq = Sequence.find(data["id"])
    assert_predicate seq, :sequence?
    refute seq.is_term?
  end

  test "update saves nested generative sequence steps" do
    patch project_transformation_path(@project, @trans), params: {
      sequence: {
        title: @trans.title,
        intent: @trans.intent,
        prerequisite_transformation_ids: [""],
        steps_attributes: {
          "0" => { sequence_id: @gen.id, position: 1, _destroy: "false" }
        }
      },
      nested_sequences: {
        @gen.id.to_s => {
          title: "Gen renamed",
          intent: "Updated intent",
          steps_attributes: {
            "0" => { content: "<p>updated</p>", position: 1, _destroy: "false" }
          }
        }
      }
    }

    assert_redirected_to edit_project_transformation_path(@project, @trans)
    @gen.reload
    assert_equal [{ "content" => "<p>updated</p>" }], @gen.steps_data
    assert_equal "Gen renamed", @gen.title
    assert_equal "Updated intent", @gen.intent
  end

  test "rejects nested updates for sequence not in pipeline" do
    patch project_transformation_path(@project, @trans), params: {
      sequence: {
        title: @trans.title,
        intent: @trans.intent,
        prerequisite_transformation_ids: [""],
        steps_attributes: {
          "0" => { sequence_id: @gen.id, position: 1, _destroy: "false" }
        }
      },
      nested_sequences: {
        @gen2.id.to_s => {
          steps_attributes: {
            "0" => { content: "<p>x</p>", position: 1, _destroy: "false" }
          }
        }
      }
    }

    assert_response :unprocessable_entity
    assert_equal [{ "content" => "<p>b</p>" }], @gen2.reload.steps_data
  end
end
