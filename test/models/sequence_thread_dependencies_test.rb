# frozen_string_literal: true

require "test_helper"

class SequenceThreadDependenciesTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "WeaveProject", user: users(:alice))
    @genesis = @project.genesis_thread
    @t1 = @project.sequences.create!(
      kind: :bundle,
      title: "T1",
      intent: "a",
      position: 1,
      steps_data: [],
      is_term: false
    )
    @t2 = @project.sequences.create!(
      kind: :bundle,
      title: "T2",
      intent: "b",
      position: 2,
      steps_data: [],
      is_term: false
    )
  end

  test "sync thread_step_bundle rows after thread steps_data update" do
    @genesis.update!(steps_data: [ { "bundle_id" => @t1.id } ])
    deps = SequenceDependency.where(parent_id: @genesis.id, kind: :thread_step_bundle)
    assert_equal 1, deps.count
    assert_equal @t1.id, deps.first.child_id
    assert_equal 1, deps.first.position
  end

  test "destroy bundle removes strand reference from thread" do
    @genesis.update!(steps_data: [ { "bundle_id" => @t1.id }, { "bundle_id" => @t2.id } ])
    assert_equal 2, SequenceDependency.where(parent_id: @genesis.id, kind: :thread_step_bundle).count

    @t1.destroy!

    @genesis.reload
    expected_ids = [ @t2.id ]
    assert_equal expected_ids, @genesis.thread_bundle_ids
    assert_empty SequenceDependency.where(kind: :thread_step_bundle, child_id: @t1.id)
  end

  test "normalizes thread steps_data dedupes bundle ids" do
    @genesis.assign_attributes(
      steps_data: [
        { "bundle_id" => @t1.id },
        { "bundle_id" => @t1.id }
      ]
    )
    @genesis.valid?
    assert_equal 1, @genesis.steps_data.size
  end

  test "unique thread_step_bundle child prevents duplicate thread membership at database" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "G",
      intent: "g",
      position: 1,
      steps_data: [ { "content" => "x" } ],
      is_term: false
    )
    @t1.update!(steps_data: [ { "sequence_id" => g.id } ])
    @genesis.update!(steps_data: [ { "bundle_id" => @t1.id } ])

    other = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread_id: @genesis.id,
      parent_bundle_id: @t1.id,
      parent_generative_sequence_id: g.id,
      child_thread_id: other.id,
      child_order: 1
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      other.update!(steps_data: [ { "bundle_id" => @t1.id } ])
    end
  end

  test "reject is_genesis on non-thread sequence" do
    row = Sequence.new(
      project: @project,
      kind: :bundle,
      title: Sequence::BUNDLE_DEFAULT_TITLE,
      intent: Sequence::BUNDLE_DEFAULT_INTENT,
      position: 9,
      steps_data: [],
      is_term: false,
      is_genesis: true
    )
    assert_not row.valid?
    assert row.errors[:is_genesis].any?
  end

  test "branch_child_threads_by_anchor_generative_sequence_id groups nodes by anchor sequence" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "g",
      position: 3,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => g.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])

    child = @project.sequences.create!(
      kind: :thread,
      title: "Fork A",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: g,
      child_thread: child,
      child_order: 1
    )

    map = @genesis.reload.branch_child_threads_by_anchor_generative_sequence_id
    assert_equal [child.id], map[g.id].map(&:id)

    assert_equal({}, @t1.reload.branch_child_threads_by_anchor_generative_sequence_id)
  end

  test "move_to_thread_menu_destination_groups is empty for non-thread sequences" do
    groups = @t1.move_to_thread_menu_destination_groups
    assert_empty groups.parents
    assert_empty groups.parallels
    assert_empty groups.cousins
    refute @t1.move_to_thread_menu_destinations_any?
  end

  test "move_to_thread_menu_destination_groups is empty for genesis" do
    groups = @genesis.move_to_thread_menu_destination_groups
    assert_empty groups.parents
    assert_empty groups.parallels
    assert_empty groups.cousins
    refute @genesis.move_to_thread_menu_destinations_any?
  end

  test "move_to_thread_menu_destination_groups lists parents parallels and cousins" do
    g_root = @project.sequences.create!(
      kind: :sequence,
      title: "Root anchor",
      intent: "a",
      position: 3,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    g_parent = @project.sequences.create!(
      kind: :sequence,
      title: "Parent anchor",
      intent: "b",
      position: 4,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    g_parallel1 = @project.sequences.create!(
      kind: :sequence,
      title: "Parallel1 anchor",
      intent: "c",
      position: 5,
      steps_data: [{ "content" => "z" }],
      is_term: false
    )
    g_cousin1 = @project.sequences.create!(
      kind: :sequence,
      title: "Cousin1 anchor",
      intent: "d",
      position: 6,
      steps_data: [{ "content" => "w" }],
      is_term: false
    )
    g_cousin2 = @project.sequences.create!(
      kind: :sequence,
      title: "Cousin2 anchor",
      intent: "e",
      position: 7,
      steps_data: [{ "content" => "v" }],
      is_term: false
    )

    @genesis.update!(steps_data: [{ "sequence_id" => g_root.id }])

    parent_a = thread_branch!("Parent A", parent: @genesis, anchor: g_root)
    parent_a.update!(steps_data: [
      { "sequence_id" => g_parent.id },
      { "sequence_id" => g_parallel1.id }
    ])

    current = thread_branch!("Current", parent: parent_a, anchor: g_parent)
    parallel1 = thread_branch!("Parallel 1", parent: parent_a, anchor: g_parallel1)
    parallel1.update!(steps_data: [
      { "sequence_id" => g_cousin1.id },
      { "sequence_id" => g_cousin2.id }
    ])
    cousin1 = thread_branch!("Cousin 1", parent: parallel1, anchor: g_cousin1)
    cousin2 = thread_branch!("Cousin 2", parent: parallel1, anchor: g_cousin2)

    groups = current.reload.move_to_thread_menu_destination_groups
    assert_equal [@genesis.id, parent_a.id], groups.parents.map(&:id)
    assert_equal [parallel1.id], groups.parallels.map(&:id)
    assert_equal [cousin1.id, cousin2.id], groups.cousins.map(&:id)
    assert current.move_to_thread_menu_destinations_any?

    groups.parents.each { |t| refute_equal current.id, t.id }
    groups.parallels.each { |t| refute_equal current.id, t.id }
    groups.cousins.each { |t| refute_equal current.id, t.id }
  end

  test "move_to_thread_menu_destinations legacy helper still accepts open_threads" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "g",
      position: 3,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g.id }])

    other = thread_branch!("Fork", parent: @genesis, anchor: g)

    assert_equal [other.id], @genesis.reload.move_to_thread_menu_destinations(open_threads: [other]).map(&:id)
  end

  test "attach_branch_thread_menu_candidates is empty for non-thread" do
    assert_empty @t1.attach_branch_thread_menu_candidates(anchor_sequence_id: 1)
  end

  test "attach_branch_thread_menu_candidates lists direct child threads and respects anchor no-op" do
    g1 = @project.sequences.create!(
      kind: :sequence,
      title: "G1",
      intent: "a",
      position: 5,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "b",
      position: 6,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g1.id }, { "sequence_id" => g2.id }])

    branch_a = @project.sequences.create!(
      kind: :thread,
      title: "Branch A",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    branch_b = @project.sequences.create!(
      kind: :thread,
      title: "Branch B",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: g1,
      child_thread: branch_a,
      child_order: 1
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: g2,
      child_thread: branch_b,
      child_order: 1
    )

    genesis = @genesis.reload
    cand_g1 = genesis.attach_branch_thread_menu_candidates(anchor_sequence_id: g1.id)
    assert_equal [branch_b.id], cand_g1.map(&:id), "branch_a already on g1"

    cand_g2 = genesis.attach_branch_thread_menu_candidates(anchor_sequence_id: g2.id)
    assert_equal [branch_a.id], cand_g2.map(&:id)
  end

  test "attach_branch_thread_menu_candidates on genesis lists forked child threads" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "g",
      position: 8,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g.id }])
    child = thread_branch!("Fork", parent: @genesis, anchor: g)

    cand = @genesis.reload.attach_branch_thread_menu_candidates(anchor_sequence_id: g.id)
    assert_empty cand, "already anchored at g"

    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "b",
      position: 9,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g.id }, { "sequence_id" => g2.id }])
    other = thread_branch!("Other", parent: @genesis, anchor: g2)

    cand = @genesis.reload.attach_branch_thread_menu_candidates(anchor_sequence_id: g.id)
    assert_equal [other.id], cand.map(&:id)
  end

  test "attach_branch_thread_menu_candidates dedupes and matches bundle anchor no-op" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "g",
      position: 7,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => g.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])

    child = @project.sequences.create!(
      kind: :thread,
      title: "Fork",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: g,
      child_thread: child,
      child_order: 1
    )

    genesis = @genesis.reload
    assert_empty genesis.attach_branch_thread_menu_candidates(
      anchor_sequence_id: g.id,
      anchor_bundle_id: @t1.id
    )

    other = @project.sequences.create!(
      kind: :thread,
      title: "Other",
      intent: "o",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: g,
      child_thread: other,
      child_order: 2
    )
    # other is a direct strand anchor on genesis — not in bundle context; child is bundle-anchored.
    cand = genesis.attach_branch_thread_menu_candidates(
      anchor_sequence_id: g.id,
      anchor_bundle_id: @t1.id
    )
    assert_equal [other.id], cand.map(&:id)
  end

  private

  def thread_branch!(title, parent:, anchor:)
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
      parent_thread: parent,
      parent_generative_sequence: anchor,
      child_thread: th,
      child_order: 1
    )
    th
  end
end
