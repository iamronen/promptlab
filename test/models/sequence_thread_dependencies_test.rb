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
end
