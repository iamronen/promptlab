# frozen_string_literal: true

require "test_helper"

class SequenceThreadDependenciesTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "WeaveProject")
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

  test "move_to_thread_menu_destinations is empty for non-thread sequences" do
    assert_empty @t1.move_to_thread_menu_destinations(open_threads: [])
  end

  test "move_to_thread_menu_destinations orders open threads first then branch children by strand walk" do
    g1 = @project.sequences.create!(
      kind: :sequence,
      title: "G1",
      intent: "a",
      position: 3,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "b",
      position: 4,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g1.id }, { "sequence_id" => g2.id }])

    open_b = @project.sequences.create!(
      kind: :thread,
      title: "Open B",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    open_a = @project.sequences.create!(
      kind: :thread,
      title: "Open A",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
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

    dest = @genesis.move_to_thread_menu_destinations(open_threads: [open_b, open_a])
    assert_equal [open_b.id, open_a.id, branch_a.id, branch_b.id], dest.map(&:id)

    # Swap strand order: branch children follow g2 before g1
    @genesis.update!(steps_data: [{ "sequence_id" => g2.id }, { "sequence_id" => g1.id }])
    dest_reordered = @genesis.reload.move_to_thread_menu_destinations(open_threads: [])
    assert_equal [branch_b.id, branch_a.id], dest_reordered.map(&:id)
  end

  test "move_to_thread_menu_destinations excludes self and dedupes open versus branch" do
    g = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "g",
      position: 3,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => g.id }])

    other = @project.sequences.create!(
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
      parent_generative_sequence: g,
      child_thread: other,
      child_order: 1
    )

    assert_equal [other.id], @genesis.reload.move_to_thread_menu_destinations(open_threads: [@genesis]).map(&:id)
    assert_equal [other.id], @genesis.move_to_thread_menu_destinations(open_threads: [other, other]).map(&:id)
    assert_equal [other.id], @genesis.move_to_thread_menu_destinations(open_threads: [other]).map(&:id)
  end

  test "attach_branch_thread_menu_candidates is empty for non-thread" do
    assert_empty @t1.attach_branch_thread_menu_candidates(open_threads: [], anchor_sequence_id: 1)
  end

  test "attach_branch_thread_menu_candidates lists only branched threads and respects anchor no-op" do
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

    open_b = @project.sequences.create!(
      kind: :thread,
      title: "Open B",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    open_a = @project.sequences.create!(
      kind: :thread,
      title: "Open A",
      intent: "t",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
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
    cand_g1 = genesis.attach_branch_thread_menu_candidates(
      open_threads: [open_b, open_a],
      anchor_sequence_id: g1.id
    )
    assert_equal [branch_b.id], cand_g1.map(&:id),
                 "open threads without ThreadNode excluded; branch_a already on g1"

    cand_g2 = genesis.attach_branch_thread_menu_candidates(
      open_threads: [],
      anchor_sequence_id: g2.id
    )
    assert_equal [branch_a.id], cand_g2.map(&:id)
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
      open_threads: [child],
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
      open_threads: [],
      anchor_sequence_id: g.id,
      anchor_bundle_id: @t1.id
    )
    assert_equal [other.id], cand.map(&:id)
  end
end
