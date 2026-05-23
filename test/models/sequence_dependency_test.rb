# frozen_string_literal: true

require "test_helper"

class SequenceDependencyTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Proj", user: users(:alice))
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    @t1 = @project.sequences.create!(
      kind: :bundle,
      title: "T1",
      intent: "t1",
      position: 1,
      steps_data: [],
      is_term: false
    )
    @t2 = @project.sequences.create!(
      kind: :bundle,
      title: "T2",
      intent: "t2",
      position: 2,
      steps_data: [],
      is_term: false
    )
  end

  test "sequence_step requires bundle parent and generative child" do
    dep = SequenceDependency.new(parent: @gen, child: @gen, kind: :sequence_step, position: 1)
    assert_not dep.valid?

    dep = SequenceDependency.new(parent: @t1, child: @gen, kind: :sequence_step, position: 1)
    assert dep.valid?
  end

  test "bundle_prerequisite requires both bundles" do
    dep = SequenceDependency.new(parent: @t1, child: @gen, kind: :bundle_prerequisite)
    assert_not dep.valid?

    dep = SequenceDependency.new(parent: @t1, child: @t2, kind: :bundle_prerequisite)
    assert dep.valid?
  end

  test "bundle_prerequisite rejects cycle on create" do
    SequenceDependency.create!(parent: @t2, child: @t1, kind: :bundle_prerequisite)

    dep = SequenceDependency.new(parent: @t1, child: @t2, kind: :bundle_prerequisite)
    assert_not dep.valid?
    assert dep.errors[:base].any? { |m| m.include?("cycle") }
  end

  test "thread_step_bundle requires thread parent and bundle child" do
    project = Project.create!(name: "Weave", user: users(:alice))
    genesis = project.genesis_thread
    tf = project.sequences.create!(
      kind: :bundle,
      title: "Tf",
      intent: "i",
      position: 1,
      steps_data: [],
      is_term: false
    )
    gen = project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )

    dep = SequenceDependency.new(parent: gen, child: genesis, kind: :thread_step_bundle, position: 1)
    assert_not dep.valid?

    dep = SequenceDependency.new(parent: genesis, child: tf, kind: :thread_step_bundle, position: 1)
    assert dep.valid?
  end

  test "destroying generative sequence removes thread_branch deps that reference anchor_sequence_id" do
    project = Project.create!(name: "AnchorDel", user: users(:alice))
    genesis = project.genesis_thread
    g_anchor = project.sequences.create!(
      kind: :sequence,
      title: "Hook",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    bundle = project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "b",
      position: 1,
      steps_data: [{ "sequence_id" => g_anchor.id }],
      is_term: false
    )
    genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    child_thread = project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "c",
      position: project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    SequenceDependency.create!(
      parent_id: genesis.id,
      child_id: child_thread.id,
      kind: :thread_branch,
      position: 1,
      anchor_sequence_id: g_anchor.id
    )

    assert_difference -> { SequenceDependency.where(anchor_sequence_id: g_anchor.id).count }, -1 do
      g_anchor.destroy!
    end
  end
end
