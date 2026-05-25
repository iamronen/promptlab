# frozen_string_literal: true

require "test_helper"

class BundlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
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
    @bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Gen",
      intent: "ti",
      position: 1,
      steps_data: [{ "sequence_id" => @gen.id }],
      is_term: false
    )
  end

  test "bundle edit wires application shell font size controller and scale target" do
    get edit_project_bundle_path(@project, @bundle)
    assert_response :success
    assert_select ".application-shell"
    assert_select ".tool-container--full"
    assert_select ".workspace-shell"
    assert_select ".workspace-fabric"
    assert_select '*[data-controller~="workspace-font-size"]'
    assert_select '*[data-workspace-font-size-target="scaleRoot"]'
  end

  test "create_pipeline_sequence creates a generative sequence and returns JSON" do
    assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
      post create_pipeline_sequence_project_bundle_path(@project, @bundle, format: :json),
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

  test "update trims trailing whitespace from bundle title and intent" do
    patch project_bundle_path(@project, @bundle), params: {
      sequence: {
        title: "Renamed bundle  ",
        intent: "Updated intent  ",
        prerequisite_bundle_ids: [""],
        steps_attributes: {
          "0" => { sequence_id: @gen.id, position: 1, _destroy: "false" }
        }
      }
    }

    assert_redirected_to edit_project_bundle_path(@project, @bundle)
    @bundle.reload
    assert_equal "Renamed bundle", @bundle.title
    assert_equal "Updated intent", @bundle.intent
  end

  test "update trims trailing whitespace from nested generative sequence steps" do
    patch project_bundle_path(@project, @bundle), params: {
      sequence: {
        title: @bundle.title,
        intent: @bundle.intent,
        prerequisite_bundle_ids: [""],
        steps_attributes: {
          "0" => { sequence_id: @gen.id, position: 1, _destroy: "false" }
        }
      },
      nested_sequences: {
        @gen.id.to_s => {
          title: @gen.title,
          intent: @gen.intent,
          steps_attributes: {
            "0" => { content: "<p>updated   </p><p></p>", position: 1, _destroy: "false" }
          }
        }
      }
    }

    assert_redirected_to edit_project_bundle_path(@project, @bundle)
    assert_equal [{ "content" => "<p>updated</p>" }], @gen.reload.steps_data
  end

  test "update trims trailing whitespace from sequence title and intent" do
    patch project_sequence_path(@project, @gen), params: {
      sequence: {
        title: "Renamed sequence  ",
        intent: "Updated intent  ",
        steps_attributes: {
          "0" => { content: "<p>a</p>", position: 1, _destroy: "false" }
        }
      }
    }

    assert_redirected_to edit_project_sequence_path(@project, @gen)
    @gen.reload
    assert_equal "Renamed sequence", @gen.title
    assert_equal "Updated intent", @gen.intent
  end

  test "update saves nested generative sequence steps" do
    patch project_bundle_path(@project, @bundle), params: {
      sequence: {
        title: @bundle.title,
        intent: @bundle.intent,
        prerequisite_bundle_ids: [""],
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

    assert_redirected_to edit_project_bundle_path(@project, @bundle)
    @gen.reload
    assert_equal [{ "content" => "<p>updated</p>" }], @gen.steps_data
    assert_equal "Gen renamed", @gen.title
    assert_equal "Gen renamed", @bundle.reload.title
    assert_equal "Updated intent", @gen.intent
  end

  test "autosave JSON returns bundle_title when only bundle title changes" do
    patch project_bundle_path(@project, @bundle), params: {
      autosave: "1",
      sequence: {
        title: "Renamed bundle",
        intent: @bundle.intent,
        prerequisite_bundle_ids: [""],
        steps_attributes: {
          "0" => { sequence_id: @gen.id, position: 1, _destroy: "false" }
        }
      }
    }, headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" }

    assert_response :ok
    data = JSON.parse(response.body)
    assert_equal "Renamed bundle", data["bundle_title"]
    assert_equal "Renamed bundle", @bundle.reload.title
    assert_equal "Gen", @gen.reload.title
  end

  test "thread embed bundle edit resolves strand step index from partner thread when weave_thread is child" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "bundle_id" => @bundle.id }])

    child = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => @gen.id }],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: genesis,
      parent_bundle: @bundle,
      parent_generative_sequence: @gen,
      child_thread: child,
      child_order: 1
    )

    get edit_project_bundle_path(
      @project,
      @bundle,
      modal: true,
      weave_thread: child.id,
      thread_partner: genesis.id
    ), headers: { "Turbo-Frame" => "thread_editor_bundle_#{@bundle.id}" }

    assert_response :success
    assert_includes response.body, 'aria-label="Step 1.1"'
  end

  test "rejects nested updates for sequence not in pipeline" do
    patch project_bundle_path(@project, @bundle), params: {
      sequence: {
        title: @bundle.title,
        intent: @bundle.intent,
        prerequisite_bundle_ids: [""],
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
