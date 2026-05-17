# frozen_string_literal: true

require "test_helper"

class ThreadNodeTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Forks")
    @genesis = @project.genesis_thread
    @g1 = @project.sequences.create!(
      kind: :sequence,
      title: "G1",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @t1 = @project.sequences.create!(
      kind: :bundle,
      title: "T1",
      intent: "a",
      position: 1,
      steps_data: [{ "sequence_id" => @g1.id }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])

    next_thread_pos = @project.sequences.threads.maximum(:position).to_i + 1
    @child_thread = @project.sequences.create!(
      kind: :thread,
      title: "Child strand",
      intent: "c",
      position: next_thread_pos,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
  end

  test "valid fork node" do
    node = ThreadNode.new(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: @g1,
      child_thread: @child_thread,
      child_order: 1
    )
    assert_predicate node, :valid?
    assert node.save
  end

  test "rejects genesis thread as child" do
    node = ThreadNode.new(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: @g1,
      child_thread: @project.genesis_thread,
      child_order: 1
    )
    assert_not node.valid?
    assert node.errors[:child_thread].any? { |m| m.include?("genesis") }
  end

  test "parent bundle must be on parent thread strand" do
    t_lonely = @project.sequences.create!(
      kind: :bundle,
      title: "Lonely",
      intent: "o",
      position: 99,
      steps_data: [{ "sequence_id" => @g1.id }],
      is_term: false
    )

    node = ThreadNode.new(
      parent_thread: @genesis,
      parent_bundle: t_lonely,
      parent_generative_sequence: @g1,
      child_thread: @child_thread,
      child_order: 1
    )
    assert_not node.valid?
    assert node.errors[:parent_bundle].any? { |m| m.include?("member") }
  end

  test "rejects cross-project threads" do
    other = Project.create!(name: "Other")
    foreign_child = other.sequences.create!(
      kind: :thread,
      title: "Foreign branch",
      intent: "f",
      position: other.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    node = ThreadNode.new(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: @g1,
      child_thread: foreign_child,
      child_order: 1
    )
    assert_not node.valid?
    assert node.errors[:child_thread].any? { |m| m.include?("same project") }
  end

  test "stale thread_branch dependency without thread node does not block a new fork" do
    orphan = @project.sequences.create!(
      kind: :thread,
      title: "Orphan branch row",
      intent: "o",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    SequenceDependency.create!(
      parent_id: @genesis.id,
      child_id: orphan.id,
      kind: :thread_branch,
      position: 1,
      anchor_sequence_id: @g1.id
    )

    real_child = @project.sequences.create!(
      kind: :thread,
      title: "Real child",
      intent: "r",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    assert_nothing_raised do
      ThreadNode.create!(
        parent_thread: @genesis,
        parent_bundle: @t1,
        parent_generative_sequence: @g1,
        child_thread: real_child,
        child_order: 1
      )
    end

    assert_not SequenceDependency.exists?(child_id: orphan.id, kind: :thread_branch)
    dep = SequenceDependency.find_by!(child_id: real_child.id, kind: :thread_branch)
    assert_equal 1, dep.position
    assert_equal @genesis.id, dep.parent_id
  end

  test "resync thread_branch deps never collides when positions have gaps or stale rows" do
    mk_thread = lambda do |title|
      pos = @project.sequences.threads.maximum(:position).to_i + 1
      @project.sequences.create!(
        kind: :thread,
        title: title,
        intent: "t",
        position: pos,
        steps_data: [],
        is_term: false,
        is_genesis: false,
        is_orphans: false
      )
    end
    c1 = mk_thread.call("C1")
    c2 = mk_thread.call("C2")
    c3 = mk_thread.call("C3")

    now = Time.current
    ThreadNode.insert_all!(
      [
        {
          parent_thread_id: @genesis.id,
          parent_bundle_id: @t1.id,
          parent_generative_sequence_id: @g1.id,
          child_thread_id: c1.id,
          child_order: 1,
          created_at: now,
          updated_at: now
        },
        {
          parent_thread_id: @genesis.id,
          parent_bundle_id: @t1.id,
          parent_generative_sequence_id: @g1.id,
          child_thread_id: c2.id,
          child_order: 2,
          created_at: now,
          updated_at: now
        },
        {
          parent_thread_id: @genesis.id,
          parent_bundle_id: @t1.id,
          parent_generative_sequence_id: @g1.id,
          child_thread_id: c3.id,
          child_order: 3,
          created_at: now,
          updated_at: now
        }
      ]
    )

    SequenceDependency.where(parent_id: @genesis.id, kind: :thread_branch).delete_all
    SequenceDependency.create!(
      parent_id: @genesis.id,
      child_id: c1.id,
      kind: :thread_branch,
      position: 1,
      anchor_sequence_id: @g1.id
    )
    SequenceDependency.create!(
      parent_id: @genesis.id,
      child_id: c3.id,
      kind: :thread_branch,
      position: 2,
      anchor_sequence_id: @g1.id
    )

    assert_nothing_raised do
      ThreadNode.resync_thread_branch_dependencies_for_parent!(@genesis.id)
    end

    deps = SequenceDependency.where(parent_id: @genesis.id, kind: :thread_branch).order(:position).pluck(:child_id)
    assert_equal [c1.id, c2.id, c3.id], deps
  end
end
