# frozen_string_literal: true

require "test_helper"

class SequencesWorkspaceModesTest < ActionDispatch::IntegrationTest
  setup do
    @project = Project.create!(name: "Mode project")
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Alpha",
      intent: "intent",
      position: 1,
      steps_data: [ { "content" => "x" } ],
      is_term: false
    )
  end

  test "browse mode renders browse navigator and sequence editor" do
    get edit_project_sequence_path(@project, @seq, workspace_mode: "browsing")
    assert_response :success
    assert_select ".workspace-browse-nav-panel"
    assert_select "main.sequence-editor"
    assert_select ".workspace-work-inner", count: 0
  end

  test "sequencing mode renders thread work area without fabric sidebar" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace--two-pane"
    assert_select ".workspace-weave-panel", count: 0
    assert_select ".workspace-work-inner"
    assert_select ".workspace-browse-nav-panel", count: 0
  end

  test "thread panel exposes minimize and maximize controls when strand has steps" do
    genesis = @project.genesis_thread
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "C",
      intent: "c",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => @seq.id }],
      is_term: false
    )
    genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    assert_response :success
    assert_select "button.workspace-thread-panel-win-btn", count: 2
  end

  test "thread panel embeds lazy turbo frames in editor stack" do
    genesis = @project.genesis_thread
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Strand bundle",
      intent: "i",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => @seq.id }],
      is_term: false
    )
    genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    assert_response :success
    assert_select ".workspace-thread-panel-editor-stack turbo-frame#thread_editor_bundle_#{bundle.id}"
  end

  test "thread index lists bundle pipeline sequences with bundle-pipeline-index" do
    genesis = @project.genesis_thread
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Strand bundle",
      intent: "i",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => @seq.id }],
      is_term: false
    )
    genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    assert_response :success
    assert_select ".workspace-thread-bundle-pipeline-index[data-controller*='bundle-pipeline-index']"
    assert_select "li.workspace-thread-bundle-pipeline-item[data-pipeline-sequence-id='#{@seq.id}']"
  end

  test "inline thread bundle frame returns matching turbo frame id" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "i",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false
    )
    frame_id = "thread_editor_bundle_#{bundle.id}"
    get edit_project_bundle_path(@project, bundle),
        headers: { "Turbo-Frame" => frame_id }
    assert_response :success
    assert_select %[turbo-frame##{frame_id}]
  end

  test "thread embed bundle editor shows strand-prefixed pipeline step badge on bundle strand rail" do
    genesis = @project.genesis_thread
    seq_a = @seq
    seq_b = @project.sequences.create!(
      kind: :sequence,
      title: "Mid",
      intent: "i",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "m" }],
      is_term: false
    )
    pipe_child = @project.sequences.create!(
      kind: :sequence,
      title: "In bundle",
      intent: "ib",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "c" }],
      is_term: false
    )
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Strand bundle",
      intent: "bi",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => pipe_child.id }],
      is_term: false
    )
    genesis.update!(
      steps_data: [
        { "sequence_id" => seq_a.id },
        { "sequence_id" => seq_b.id },
        { "bundle_id" => bundle.id }
      ]
    )

    frame_id = "thread_editor_bundle_#{bundle.id}"
    get edit_project_bundle_path(@project, bundle, weave_thread: genesis.id),
        headers: { "Turbo-Frame" => frame_id }

    assert_response :success
    assert_select ".workspace-thread-editor-step-badge.bundle-pipeline-thread-child-strand-badge", text: "3.1"
    assert_select "span.bundle-thread-child-sequence-index", count: 0
  end

  test "inline thread sequence frame returns matching turbo frame id" do
    frame_id = "thread_editor_sequence_#{@seq.id}"
    get edit_project_sequence_path(@project, @seq),
        headers: { "Turbo-Frame" => frame_id }
    assert_response :success
    assert_select %[turbo-frame##{frame_id}]
  end

  test "bundle edit with browsing redirects to first generative sequence" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "t",
      position: 2,
      steps_data: [],
      is_term: false
    )
    get edit_project_bundle_path(@project, bundle, workspace_mode: "browsing")
    assert_redirected_to edit_project_sequence_path(@project, @seq, sidebar: "sequences", workspace_mode: "browsing")

    follow_redirect!
    assert_select ".workspace-browse-nav-panel"
  end

  test "invalid thread_partner query is ignored for split layout" do
    genesis = @project.genesis_thread
    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id, thread_partner: 999_999_999)
    assert_response :success
    assert_select ".workspace-thread-panel-layout--split", count: 0
  end

  test "valid thread_partner shows split thread panels" do
    genesis = @project.genesis_thread
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Strand bundle",
      intent: "i",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [ { "sequence_id" => @seq.id } ],
      is_term: false
    )
    genesis.update!(steps_data: [ { "bundle_id" => bundle.id } ])

    child = @project.sequences.create!(
      kind: :thread,
      title: Sequence::UNTITLED_THREAD_BRANCH_TITLE,
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )
    ThreadNode.create!(
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    branch_seq = @project.sequences.create!(
      kind: :sequence,
      title: "Branch step",
      intent: "br",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    child.update!(steps_data: [{ "sequence_id" => branch_seq.id }])

    get edit_project_sequence_path(@project, @seq, weave_thread: child.id, thread_partner: genesis.id)
    assert_response :success
    assert_select ".workspace-thread-panel-layout--split", count: 1
    assert_select "#workspace-thread-panel-heading-partner"
    assert_select "#workspace-thread-panel-heading-main"
    assert_select "*[data-controller~='workspace-thread-panel']", count: 2
    assert_select ".workspace-thread-panel-editor-stack", count: 2
  end

  test "open project preserves workspace_shell on redirect" do
    get open_project_path(@project, workspace_shell: "v2")
    assert_redirected_to edit_project_sequence_path(@project, @seq, workspace_shell: "v2")
  end

  test "open project ignores invalid workspace_shell" do
    get open_project_path(@project, workspace_shell: "nope")
    assert_redirected_to edit_project_sequence_path(@project, @seq)
    refute_match(/workspace_shell/, @response.redirect_url)
  end

  test "sequence edit with workspace_shell v1 succeeds" do
    get edit_project_sequence_path(@project, @seq, workspace_shell: "v1")
    assert_response :success
    assert_select ".workspace-shell"
    assert_select ".workspace-shell--v2", count: 0
    assert_select '*[data-workspace-font-size-target="scaleRoot"]', count: 0
  end

  test "sequence edit with workspace_shell v2 succeeds" do
    get edit_project_sequence_path(@project, @seq, workspace_shell: "v2")
    assert_response :success
    assert_select ".workspace-shell"
    assert_select ".workspace-shell--v2"
    assert_select '*[data-controller~="workspace-font-size"]'
    assert_select '*[data-workspace-font-size-target="scaleRoot"]'
    assert_select "button[aria-label='Smaller workspace text']"
    assert_select "button[aria-label='Default workspace text size']"
    assert_select "button[aria-label='Larger workspace text']"
  end

  test "bundle edit browsing redirect preserves workspace_shell" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "t",
      position: 2,
      steps_data: [],
      is_term: false
    )
    get edit_project_bundle_path(@project, bundle, workspace_mode: "browsing", workspace_shell: "v2")
    assert_redirected_to edit_project_sequence_path(
      @project,
      @seq,
      sidebar: "sequences",
      workspace_mode: "browsing",
      workspace_shell: "v2"
    )
  end
end
