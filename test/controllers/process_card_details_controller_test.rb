# frozen_string_literal: true

require "test_helper"

class ProcessCardDetailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Process card project", user: users(:alice))
    @genesis = @project.genesis_thread
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Alpha",
      intent: "Ship the feature",
      position: 1,
      steps_data: [{ "content" => "step one" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])
  end

  test "show requires authentication" do
    sign_out :user
    get project_process_card_path(@project, @seq), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_redirected_to new_user_session_path
  end

  test "show rejects thread records" do
    get project_process_card_path(@project, @genesis), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_response :not_found
  end

  test "show sequence card renders header intent metadata and open in thread link" do
    get project_process_card_path(@project, @seq), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_response :success
    assert_select "turbo-frame#process_card_modal"
    assert_select "#process-card-modal-heading", text: "Alpha"
    assert_select ".process-card-modal-breadcrumb", count: 0
    assert_select ".process-card-modal-intent", text: /Ship the feature/
    assert_select ".sequence-meta-taxonomies-host"
    assert_select "a", text: "Open in Thread" do |links|
      href = links.first["href"]
      assert_includes href, "weave_thread=#{@genesis.id}"
      assert_includes href, "focus_transformation_id=#{@seq.id}"
      refute_includes href, "workspace_mode=process"
    end
    assert_select ".sequence-title-input", count: 0
    assert_select "h3.process-card-modal-sequence-block-title", count: 0
  end

  test "show sequence card breadcrumb links to fabric for branched thread host" do
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "i",
      position: 2,
      steps_data: [{ "content" => "anchor" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => anchor.id }])

    child = @project.sequences.create!(
      kind: :thread,
      title: "Branch strand",
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )
    ThreadNode.create!(
      parent_thread_id: @genesis.id,
      parent_generative_sequence_id: anchor.id,
      child_thread_id: child.id,
      child_order: 1
    )
    branch_seq = @project.sequences.create!(
      kind: :sequence,
      title: "Branch step",
      intent: "Branch intent",
      position: 3,
      steps_data: [{ "content" => "branch" }],
      is_term: false
    )
    child.update!(steps_data: [{ "sequence_id" => branch_seq.id }])

    get project_process_card_path(@project, branch_seq), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_response :success
    assert_select ".process-card-modal-breadcrumb"
    assert_select ".process-card-modal-breadcrumb a.workspace-thread-panel-title-breadcrumb-ancestor", text: @genesis.title
    assert_select "a", text: "Open in Thread" do |links|
      assert_includes links.first["href"], "weave_thread=#{child.id}"
    end
  end

  test "show bundle card renders bundle metadata and per-sequence blocks" do
    pipeline_seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "Child seq",
        intent: "Child intent",
        position: 2,
        steps_data: [{ "content" => "child step" }],
        is_term: false
      )
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "Ship bundle",
        intent: "Bundle intent",
        position: 3,
        steps_data: [{ "sequence_id" => pipeline_seq.id }],
        is_term: false
      )
    @genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    get project_process_card_path(@project, bundle), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_response :success
    assert_select "#process-card-modal-heading", text: "Child seq"
    assert_select ".bundle-pipeline-bundle-title-input", count: 0
    assert_select ".process-card-modal-sequence-block", count: 1
    assert_select "h3.process-card-modal-sequence-block-title", text: "Child seq"
    assert_select ".process-card-modal-intent--child", text: /Child intent/
    assert_select "a", text: "Open in Thread" do |links|
      href = links.first["href"]
      assert_includes href, "weave_thread=#{@genesis.id}"
      assert_includes href, "focus_bundle_id=#{bundle.id}"
    end
  end

  test "show hides open in thread when artifact has no host thread" do
    loose =
      @project.sequences.create!(
        kind: :sequence,
        title: "Loose",
        intent: "Loose intent",
        position: 9,
        steps_data: [{ "content" => "z" }],
        is_term: false
      )

    get project_process_card_path(@project, loose), headers: { "Turbo-Frame" => "process_card_modal" }
    assert_response :success
    assert_select "a", text: "Open in Thread", count: 0
    assert_select ".process-card-modal-breadcrumb", count: 0
  end
end
