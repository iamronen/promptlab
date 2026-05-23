# frozen_string_literal: true

require "test_helper"

class SequencesWorkspaceModesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Mode project", user: users(:alice))
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Alpha",
      intent: "intent",
      position: 1,
      steps_data: [ { "content" => "x" } ],
      is_term: false
    )
  end

  test "legacy browsing workspace_mode on sequence edit redirects to sequencing URL" do
    get edit_project_sequence_path(@project, @seq, workspace_mode: "browsing")
    assert_response :redirect
    assert_redirected_to edit_project_sequence_path(@project, @seq)
    follow_redirect!
    assert_response :success
    assert_select ".workspace--two-pane"
    assert_select ".workspace-browse-nav-panel", count: 0
    assert_select ".workspace-work-inner"
  end

  test "sequencing mode renders thread work area without fabric sidebar" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace--two-pane"
    assert_select ".workspace-weave-panel", count: 0
    assert_select ".workspace-work-inner"
    assert_select ".workspace-browse-nav-panel", count: 0
  end

  test "fabric mode renders single-pane thread tree without assistant or editors" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

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
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    get edit_project_sequence_path(@project, @seq, workspace_mode: "fabric")
    assert_response :success
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".fabric-thread-tree.fabric-thread-tree--explorer"
    assert_select "a.fabric-thread-menu-open[href*='weave_thread=#{genesis.id}']", text: "Open"
    assert_select "a.fabric-thread-menu-open[href*='weave_thread=#{child.id}']", text: "Open"
    assert_select ".fabric-thread-tree[data-controller='weave-panel']", count: 0
    assert_select "#workspace-panel-assistant", count: 0
    assert_select ".workspace-work-inner", count: 0
    assert_select ".workspace-browse-nav-panel", count: 0
    assert_select ".workspace-weave-panel", count: 0
  end

  test "bundle sequencing keeps weave sidebar; bundle fabric is single pane" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Fabric bundle",
      intent: "fb",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false
    )
    get edit_project_bundle_path(@project, bundle)
    assert_response :success
    assert_select ".workspace-weave-panel"

    get edit_project_bundle_path(@project, bundle, workspace_mode: "fabric")
    assert_response :success
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".workspace-weave-panel", count: 0
    assert_select "#workspace-panel-assistant", count: 0
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
    assert_select ".workspace-thread-panel-browse-controls button.workspace-thread-panel-win-btn", count: 2
    assert_select ".workspace-thread-panel-window-controls button.workspace-thread-panel-win-btn", count: 2
  end

  test "workspace strand row renders thread-branch band with chip and link indicators when anchored" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

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
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    assert_response :success
    assert_select ".thread-branch-strand-bridge-band", count: 1
    assert_select ".thread-branch-strand-bridge-band .sequence-thread-indicator", count: 1
    assert_select ".thread-branch-strand-bridge-band .thread-link-container", text: "Branch strand"
    assert_select ".thread-branch-strand-bridge-band .sequence-has-threads-indicator--strand-rail", count: 1
    assert_select ".workspace-thread-editor-step-rail.prompt-thread-editor-step-rail .thread-branch-strand-rail-marker",
                  count: 0
    assert_select %[turbo-frame#thread_editor_sequence_#{@seq.id}[src*='strand_thread_chip_parent']]
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

  test "thread embed sequence frame shows thread-branch indicator when anchored child threads exist" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

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
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    frame_id = "thread_editor_sequence_#{@seq.id}"
    get edit_project_sequence_path(@project, @seq),
        headers: { "Turbo-Frame" => frame_id }

    assert_response :success
    assert_select "span.sequence-has-threads-indicator[aria-label=?]",
                  "This sequence branches to thread: Branch strand."
    assert_select ".sequence-thread-indicator", count: 1
    assert_select ".thread-link-container", text: "Branch strand"
    assert_select "div[data-sequence-editor-steps-end-anchor]"
  end

  test "thread embed sequence frame shows one thread indicator per anchored child thread" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    child_one = @project.sequences.create!(
      kind: :thread,
      title: "Alpha branch",
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )
    child_two = @project.sequences.create!(
      kind: :thread,
      title: "Beta branch",
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
      child_thread_id: child_one.id,
      child_order: 1
    )
    ThreadNode.create!(
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child_two.id,
      child_order: 2
    )

    frame_id = "thread_editor_sequence_#{@seq.id}"
    get edit_project_sequence_path(@project, @seq),
        headers: { "Turbo-Frame" => frame_id }

    assert_response :success
    assert_select ".sequence-thread-indicator", count: 2
    assert_select ".thread-link-container", text: "Alpha branch"
    assert_select ".thread-link-container", text: "Beta branch"
    assert_select "span.sequence-has-threads-indicator[aria-label=?]",
                  "This sequence branches to threads: Alpha branch, Beta branch."
  end

  test "thread embed sequence frame hides footer chip when strand_thread_chip_parent param set" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

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
      parent_thread_id: genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    frame_id = "thread_editor_sequence_#{@seq.id}"
    get edit_project_sequence_path(@project, @seq, strand_thread_chip_parent: "1"),
        headers: { "Turbo-Frame" => frame_id }

    assert_response :success
    assert_select ".thread-editor-thread-branch-indicator-tail", count: 0
    assert_select ".sequence-has-threads-indicator", count: 0
    assert_select ".sequence-thread-indicator", count: 0
    assert_select "div[data-sequence-editor-steps-end-anchor]"
  end

  test "thread embed sequence frame omits thread-branch indicator without anchored child threads" do
    frame_id = "thread_editor_sequence_#{@seq.id}"
    get edit_project_sequence_path(@project, @seq),
        headers: { "Turbo-Frame" => frame_id }
    assert_response :success
    assert_select ".sequence-has-threads-indicator", count: 0
    assert_select "div[data-sequence-editor-steps-end-anchor]", count: 0
  end

  test "bundle edit strips legacy browsing workspace_mode" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "t",
      position: 2,
      steps_data: [],
      is_term: false
    )
    get edit_project_bundle_path(@project, bundle, workspace_mode: "browsing")
    assert_redirected_to edit_project_bundle_path(@project, bundle)

    follow_redirect!
    assert_response :success
    assert_select ".workspace-weave-panel"
    assert_select ".workspace-browse-nav-panel", count: 0
  end

  test "invalid thread_partner query is ignored for split layout" do
    genesis = @project.genesis_thread
    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id, thread_partner: 999_999_999)
    assert_response :success
    assert_select ".workspace-thread-panel-layout--split", count: 0
  end

  test "valid thread_partner shows two workspace thread panels" do
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
    assert_select '*[data-controller~="thread-workspace"]'
    assert_select "[data-thread-panel-id='#{genesis.id}']"
    assert_select "[data-thread-panel-id='#{child.id}']"
    assert_select "*[data-controller~='workspace-thread-panel']", count: 2
    assert_select ".workspace-thread-panel-editor-stack", count: 2
    assert_select "button[data-action*='thread-workspace#closePanel'][data-thread-workspace-thread-id-param='#{genesis.id}']", count: 1
    assert_select "button[data-action*='thread-workspace#closePanel'][data-thread-workspace-thread-id-param='#{child.id}']", count: 1
    assert_select "[data-action*='workspace-thread-panel-title#toggleMoveSubmenu'][data-submenu-id='strip-move']", count: 2
    assert_select(
      "button[data-action*='thread-workspace#movePanelLeft'][data-thread-workspace-thread-id-param='#{genesis.id}']",
      count: 1
    )
    assert_select(
      "button[data-action*='thread-workspace#movePanelRight'][data-thread-workspace-thread-id-param='#{genesis.id}']",
      count: 1
    )
  end

  test "open_threads param orders multiple workspace thread panels" do
    genesis = @project.genesis_thread

    branch_seq = @project.sequences.create!(
      kind: :sequence,
      title: "Other step",
      intent: "o",
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "o" }],
      is_term: false
    )

    other = @project.sequences.create!(
      kind: :thread,
      title: "Other strand",
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => branch_seq.id }],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )

    get edit_project_sequence_path(
      @project,
      @seq,
      weave_thread: other.id,
      open_threads: "#{genesis.id},#{other.id}"
    )
    assert_response :success
    assert_select "*[data-controller~='thread-workspace']"
    assert_select "[data-thread-panel-id='#{genesis.id}']"
    assert_select "[data-thread-panel-id='#{other.id}']"

    strip_panel_ids =
      css_select("#workspace-thread-workspace-strip [data-thread-panel-id]").map do |node|
        node["data-thread-panel-id"].to_i
      end
    assert_equal [genesis.id, other.id], strip_panel_ids
  end

  test "genesis workspace panel omits lineage breadcrumb nav" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select "[data-thread-panel-id='#{genesis.id}'] .workspace-thread-panel-title-breadcrumb", count: 0
  end

  test "non-genesis workspace panel renders lineage breadcrumb with thread-workspace ancestor actions" do
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
      title: "Branch strand",
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

    assert_select "[data-thread-panel-id='#{genesis.id}'] .workspace-thread-panel-title-breadcrumb", count: 0

    assert_select "[data-thread-panel-id='#{child.id}'] nav.workspace-thread-panel-title-breadcrumb", count: 1
    assert_select "[data-thread-panel-id='#{child.id}'] .workspace-thread-panel-title-breadcrumb-ellipsis", count: 0

    assert_select(
      "[data-thread-panel-id='#{child.id}'] button[data-action*='thread-workspace#focusOrOpenAncestorFromBreadcrumb']" \
      "[data-thread-workspace-ancestor-id-param='#{genesis.id}'][data-thread-workspace-panel-owner-id-param='#{child.id}']",
      text: genesis.title,
      count: 1
    )

    assert_select "[data-thread-panel-id='#{child.id}'] span[data-workspace-thread-panel-title-target=currentTitle]",
                  text: child.title,
                  count: 1
  end

  test "deep thread lineage breadcrumb shows ellipsis and ancestor crumb buttons" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    mid = workspace_test_make_branch_thread!("Mid", genesis, @seq)
    mid_anchor = @project.sequences.generative_sequences.find(mid.strand_step_pairs.first.last)
    between = workspace_test_make_branch_thread!("Between", mid, mid_anchor)
    between_anchor = @project.sequences.generative_sequences.find(between.strand_step_pairs.first.last)
    leaf = workspace_test_make_branch_thread!("Leaf", between, between_anchor)

    get edit_project_sequence_path(
      @project,
      @seq,
      weave_thread: leaf.id,
      open_threads: "#{genesis.id},#{mid.id},#{between.id},#{leaf.id}"
    )
    assert_response :success

    assert_select "[data-thread-panel-id='#{leaf.id}'] .workspace-thread-panel-title-breadcrumb-ellipsis", count: 1
    assert_select "[data-thread-panel-id='#{leaf.id}'] button[data-action*='thread-workspace#focusOrOpenAncestorFromBreadcrumb']",
                  count: 2
    assert_select "[data-thread-panel-id='#{leaf.id}'] span[data-workspace-thread-panel-title-target=currentTitle]",
                  text: leaf.title,
                  count: 1
  end

  test "open project redirects to sequence editor without workspace_shell" do
    get open_project_path(@project)
    assert_redirected_to edit_project_sequence_path(@project, @seq)
    refute_match(/workspace_shell/, @response.redirect_url)
  end

  test "open project ignores stale workspace_shell query param" do
    get open_project_path(@project, workspace_shell: "v2")
    assert_redirected_to edit_project_sequence_path(@project, @seq)
    refute_match(/workspace_shell/, @response.redirect_url)
  end

  test "sequence edit uses unified workspace shell" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace-shell"
    assert_select '*[data-controller~="workspace-font-size"]'
    assert_select '*[data-workspace-font-size-target="scaleRoot"]'
    assert_select "button[aria-label='Smaller workspace text']"
    assert_select "button[aria-label='Default workspace text size']"
    assert_select "button[aria-label='Larger workspace text']"
  end

  test "bundle edit legacy browsing redirect drops workspace_mode from URL" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "t",
      position: 2,
      steps_data: [],
      is_term: false
    )
    get edit_project_bundle_path(@project, bundle, workspace_mode: "browsing")
    target = URI.parse(@response.redirect_url)
    q = Rack::Utils.parse_query(target.query)
    assert q["workspace_mode"].blank?
  end

  # Regression: flex: 0 1 auto on the maximized editor pane prevents the pane from filling the column
  # height, so .workspace-thread-panel-editor-stack never gets a bounded height and loses its scrollbar (v1).
  test "thread panel editor column stylesheet keeps flex growth for inner vertical scroll" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_includes css, "Thread editor column — scroll contract",
                    "keep the scroll-contract comment next to the maximized editor-pane flex rules (Tailwind components layer)"

    pane_block = css[/
      \.workspace-thread-panel-root--maximized \s+
      \.workspace-thread-panel-editor-pane \s*
      \{[^}]*\} /mx]
    assert pane_block, "expected .workspace-thread-panel-root--maximized .workspace-thread-panel-editor-pane block"
    assert_match(/flex:\s*1\s+1\s+auto/, pane_block)
    assert_match(/min-height:\s*0/, pane_block)
  end

  def workspace_test_make_branch_thread!(title, parent_thread, anchor_sequence)
    th = @project.sequences.create!(
      kind: :thread,
      title: title,
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )
    ThreadNode.create!(
      parent_thread_id: parent_thread.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: anchor_sequence.id,
      child_thread_id: th.id,
      child_order: 1
    )
    inner = @project.sequences.create!(
      kind: :sequence,
      title: "#{title} seq",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "c" }],
      is_term: false
    )
    th.update!(steps_data: [{ "sequence_id" => inner.id }])
    th.reload
  end
end
