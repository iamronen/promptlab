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

  test "legacy browsing workspace_mode on sequence edit redirects to fabric URL" do
    get edit_project_sequence_path(@project, @seq, workspace_mode: "browsing")
    assert_response :redirect
    assert_redirected_to edit_project_sequence_path(@project, @seq)
    follow_redirect!
    assert_response :success
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".workspace-browse-nav-panel", count: 0
    assert_select ".workspace-weave-panel", count: 0
  end

  test "default edit renders fabric layout" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".workspace-weave-panel", count: 0
    assert_select "#workspace-panel-assistant", count: 0
    assert_select ".workspace-browse-nav-panel", count: 0
  end

  test "fabric mode renders split hierarchy and empty thread panel without assistant" do
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

    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".workspace-fabric-layout"
    assert_select ".workspace-fabric-hierarchy"
    assert_select ".workspace-fabric-hierarchy-resize-handle"
    assert_select ".workspace-fabric-layout[data-controller~='fabric-hierarchy-resize']"
    assert_select ".workspace-fabric-layout[data-controller~='fabric-assistant-resize']"
    assert_select ".workspace-fabric-thread-panel"
    assert_select "#workspace-fabric-panel-assistant"
    assert_select ".workspace-fabric-assistant-resize-handle"
    assert_select ".workspace-fabric-assistant-placeholder", text: "Interactive LLM chat will appear here."
    assert_select ".workspace-fabric-thread-panel-empty"
    assert_select ".fabric-thread-tree.fabric-thread-tree--explorer"
    assert_select "details.fabric-tree-node-thread[open]", count: 1
    assert_select "details.fabric-tree-node-thread:not([open])", count: 0
    assert_select "button.fabric-tree-thread-select[data-action*='weave-panel#select']", minimum: 2
    assert_select "a.fabric-thread-menu-open[href*='weave_thread=#{genesis.id}']", text: "Open"
    assert_select "a.fabric-thread-menu-open[href*='weave_thread=#{child.id}']", text: "Open"
    assert_select ".fabric-thread-tree[data-controller='weave-panel']", count: 1
    assert_select "*[data-controller~='thread-workspace'][data-thread-workspace-fabric-mode-value='true']"
    assert_select "[data-thread-panel-id]", count: 0
    assert_select "#workspace-panel-assistant", count: 0
    assert_select ".workspace-weave-panel", count: 0
  end

  test "fabric mode with weave_thread renders thread panel index and editor" do
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
    assert_select "[data-thread-panel-id='#{genesis.id}']", count: 1
    assert_select ".workspace-thread-panel-index-pane"
    assert_select ".workspace-thread-panel-editor-pane"
    assert_select "button.fabric-tree-thread-select.is-selected[data-thread-id='#{genesis.id}']", count: 1
    assert_select ".workspace-fabric-thread-panel-empty", count: 0
  end

  test "bundle edit renders fabric layout" do
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
    assert_select ".workspace--one-pane"
    assert_select ".workspace-fabric"
    assert_select ".workspace-fabric-layout"
    assert_select ".workspace-fabric-hierarchy"
    assert_select ".workspace-fabric-thread-panel"
    assert_select "#workspace-fabric-panel-assistant"
    assert_select ".workspace-weave-panel", count: 0
    assert_select "#workspace-panel-assistant", count: 0
  end

  test "thread panel exposes layout and browse controls when strand has steps" do
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
    assert_select ".workspace-thread-panel-toolbar"
    assert_select ".workspace-thread-panel-header .workspace-thread-panel-browse-controls", count: 0
    assert_select ".workspace-thread-panel-header .workspace-thread-panel-window-controls", count: 0
    assert_select ".workspace-thread-panel-toolbar .workspace-thread-panel-browse-controls button.workspace-thread-panel-win-btn", count: 2
    assert_select ".workspace-thread-panel-toolbar .workspace-thread-panel-window-controls button.workspace-thread-panel-win-btn", count: 3
    assert_select ".workspace-thread-panel-toolbar button[title='Index only']", count: 1
    assert_select ".workspace-thread-panel-toolbar button[title='Index and editor']", count: 1
    assert_select ".workspace-thread-panel-toolbar button[title='Editor only']", count: 1
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
    assert_select "button[data-action='thread-strand-panel#copyBundleAsText']", text: "Copy as text"
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
    assert_select ".step-order-rail--thread-handle.prompt-thread-bundle-order-rail"
    assert_select ".thread-embed-sequence-step-drag-handle[data-action*='openThreadEmbedStepMenu']"
    assert_select ".nested-sequence-editor .step-order-rail--thread-handle.prompt-thread-step-handle-rail"
    assert_select "button[data-action='sequence-editor#copyPipelineChildAsText']", text: "Copy as text"
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
    assert_select ".workspace-fabric"
    assert_select ".workspace-browse-nav-panel", count: 0
    assert_select ".workspace-weave-panel", count: 0
  end

  test "genesis workspace panel omits lineage breadcrumb nav" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    get edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
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

    get edit_project_sequence_path(@project, @seq, weave_thread: child.id)
    assert_response :success

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

  test "deep thread lineage breadcrumb shows full trail up to five segments" do
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
      weave_thread: leaf.id
    )
    assert_response :success

    assert_select "[data-thread-panel-id='#{leaf.id}'] .workspace-thread-panel-title-breadcrumb-ellipsis", count: 0
    assert_select "[data-thread-panel-id='#{leaf.id}'] button[data-action*='thread-workspace#focusOrOpenAncestorFromBreadcrumb']",
                  count: 3
    assert_select "[data-thread-panel-id='#{leaf.id}'] span[data-workspace-thread-panel-title-target=currentTitle]",
                  text: leaf.title,
                  count: 1
  end

  test "very deep thread lineage breadcrumb shows ellipsis after five segments" do
    genesis = @project.genesis_thread
    genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    mid = workspace_test_make_branch_thread!("Mid", genesis, @seq)
    mid_anchor = @project.sequences.generative_sequences.find(mid.strand_step_pairs.first.last)
    between = workspace_test_make_branch_thread!("Between", mid, mid_anchor)
    between_anchor = @project.sequences.generative_sequences.find(between.strand_step_pairs.first.last)
    deeper = workspace_test_make_branch_thread!("Deeper", between, between_anchor)
    deeper_anchor = @project.sequences.generative_sequences.find(deeper.strand_step_pairs.first.last)
    deeper2 = workspace_test_make_branch_thread!("Deeper2", deeper, deeper_anchor)
    deeper2_anchor = @project.sequences.generative_sequences.find(deeper2.strand_step_pairs.first.last)
    leaf = workspace_test_make_branch_thread!("Leaf", deeper2, deeper2_anchor)

    get edit_project_sequence_path(
      @project,
      @seq,
      weave_thread: leaf.id
    )
    assert_response :success

    assert_select "[data-thread-panel-id='#{leaf.id}'] .workspace-thread-panel-title-breadcrumb-ellipsis", count: 1
    assert_select "[data-thread-panel-id='#{leaf.id}'] button[data-action*='thread-workspace#focusOrOpenAncestorFromBreadcrumb']",
                  count: 4
    assert_select "[data-thread-panel-id='#{leaf.id}'] span[data-workspace-thread-panel-title-target=currentTitle]",
                  text: leaf.title,
                  count: 1
  end

  test "open project redirects to sequence editor with genesis weave thread" do
    genesis = @project.genesis_thread
    get open_project_path(@project)
    assert_redirected_to edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    refute_match(/workspace_shell/, @response.redirect_url)
  end

  test "open project ignores stale workspace_shell query param" do
    genesis = @project.genesis_thread
    get open_project_path(@project, workspace_shell: "v2")
    assert_redirected_to edit_project_sequence_path(@project, @seq, weave_thread: genesis.id)
    refute_match(/workspace_shell/, @response.redirect_url)
  end

  test "sequence edit uses unified application shell and project tool" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".application-shell"
    assert_select ".tool-container--full"
    assert_select ".workspace-shell"
    assert_select '*[data-controller~="workspace-font-size"]'
    assert_select '*[data-workspace-font-size-target="scaleRoot"]'
    assert_select "button[aria-label='Smaller workspace text']"
    assert_select "button[aria-label='Default workspace text size']"
    assert_select "button[aria-label='Larger workspace text']"
    assert_select ".tool-heading-title", text: /Project: Mode project/
    assert_select "[role='group'][aria-label='Project tool mode']"
    assert_select "[role='group'][aria-label='Project tool mode'] a", text: "Fabric"
    assert_select "[role='group'][aria-label='Project tool mode'] a", text: "Sequencing", count: 0
  end

  test "settings workspace mode renders project settings panel in tool body" do
    get edit_project_sequence_path(@project, @seq, workspace_mode: "settings")
    assert_response :success
    assert_select ".workspace-settings-panel"
    assert_select ".project-settings-panel-body"
    assert_select "h2", text: "Mode project"
    assert_select "[role='group'][aria-label='Project tool mode'] a[aria-current='page'][aria-label='Project settings']"
  end

  test "process workspace mode renders kanban board with mode toggle" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )
    todo = taxonomy.taxonomy_terms.create!(label: "Todo", position: 1)
    taxonomy.taxonomy_terms.create!(label: "Done", position: 2)

    get edit_project_sequence_path(@project, @seq, workspace_mode: "process")
    assert_response :success
    assert_select ".workspace-process-board"
    assert_select "turbo-frame#process_board"
    assert_select "[data-controller='process-card-modal']"
    assert_select "dialog.process-card-modal-dialog"
    assert_select "turbo-frame#process_card_modal"
    assert_select ".workspace-shell--process"
    assert_select "[role='group'][aria-label='Project tool mode'] a", text: "Fabric"
    assert_select "[role='group'][aria-label='Project tool mode'] a", text: "Process"
    assert_select "[role='group'][aria-label='Project tool mode'] a[aria-current='page']", text: "Process"
    assert_select "[role='group'][aria-label='Editor mode']", count: 0
    assert_select ".workspace-process-column", count: 3
    assert_select ".tool-part-header", text: /Todo/
    assert_select ".tool-part-header", text: /Done/
    assert_select ".tool-part-header", text: /Unassigned/
    assert_select ".workspace-process-task-card", text: /Alpha/
    assert_select "button.workspace-process-task-card[data-process-card-modal-url]"
    assert_select "a.workspace-process-task-card", count: 0

    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: taxonomy,
      taxonomy_term: todo,
      label_snapshot: todo.label,
      assigned_at: Time.current
    )

    get edit_project_sequence_path(@project, @seq, workspace_mode: "process")
    assert_response :success
    assert_select ".tool-part-header", text: /Todo/ do |headers|
      column = headers.first.ancestors(".workspace-process-column").first
      assert column.at_css(".workspace-process-task-card[aria-label*='Alpha']")
    end
    assert_select ".workspace-process-column", count: 2
    assert_select ".tool-part-header", text: /Unassigned/, count: 0
  end

  test "process mode shows bundle card when taxonomy applies to bundles" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        applies_to_bundles: true,
        position: 1
      )
    doing = taxonomy.taxonomy_terms.create!(label: "Doing", position: 1)
    pipeline_seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "Ship bundle",
        intent: "t",
        position: 2,
        steps_data: [{ "content" => "x" }],
        is_term: false
      )
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "Ship bundle",
        intent: "t",
        position: 1,
        steps_data: [{ "sequence_id" => pipeline_seq.id }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: bundle,
      taxonomy: taxonomy,
      taxonomy_term: doing,
      label_snapshot: doing.label,
      assigned_at: Time.current
    )

    get edit_project_bundle_path(@project, bundle, workspace_mode: "process")
    assert_response :success
    assert_select ".workspace-process-board"
    assert_select "button.workspace-process-task-card[data-process-card-modal-url*='#{bundle.id}']", text: /Ship bundle/
    assert_select "a.workspace-process-task-card", count: 0
    assert_select ".tool-part-header", text: /Doing/ do |headers|
      column = headers.first.ancestors(".workspace-process-column").first
      assert column.at_css("button.workspace-process-task-card[data-process-card-modal-url*='#{bundle.id}']")
    end
  end

  test "process mode without taxonomy shows empty state" do
    get edit_project_sequence_path(@project, @seq, workspace_mode: "process")
    assert_response :success
    assert_select ".workspace-process-empty"
    assert_select ".workspace-process-board", count: 0
    assert_select "a.prompt-btn-primary", text: "Open project settings"
  end

  test "default edit still renders fabric not process" do
    get edit_project_sequence_path(@project, @seq)
    assert_response :success
    assert_select ".workspace-fabric"
    assert_select ".workspace-process-board", count: 0
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
