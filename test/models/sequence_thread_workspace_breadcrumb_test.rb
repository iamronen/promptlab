# frozen_string_literal: true

require "test_helper"

class SequenceThreadWorkspaceBreadcrumbTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Bcumb project", user: users(:alice))
    @genesis = @project.genesis_thread
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Step",
      intent: "i",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])
  end

  test "payload is nil for genesis thread" do
    assert_nil @genesis.thread_workspace_breadcrumb_payload
  end

  test "payload is nil for non-thread sequences" do
    assert_nil @seq.thread_workspace_breadcrumb_payload
  end

  test "direct child of genesis has genesis and self in chain without ellipsis" do
    child = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: @project.sequences.maximum(:position).to_i + 1,
      steps_data: [],
      is_genesis: false,
      is_orphans: false,
      is_term: false
    )
    ThreadNode.create!(
      parent_thread_id: @genesis.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: @seq.id,
      child_thread_id: child.id,
      child_order: 1
    )

    pl = child.thread_workspace_breadcrumb_payload
    assert_equal [@genesis.id, child.id], pl.full_segments.map(&:id)
    refute pl.ellipsis
    assert_equal pl.full_segments, pl.visible_segments
  end

  test "four segments yields ellipsis and visible last three titles" do
    mid = thread_branch!("Mid")
    between = thread_branch!("Between", parent: mid, anchor: anchor_seq_for(mid))
    leaf = thread_branch!("Leaf", parent: between, anchor: anchor_seq_for(between))

    pl = leaf.thread_workspace_breadcrumb_payload
    assert_equal [@genesis.id, mid.id, between.id, leaf.id], pl.full_segments.map(&:id)
    assert pl.ellipsis
    assert_equal [mid.id, between.id, leaf.id], pl.visible_segments.map(&:id)
    assert_includes pl.lineage_label_text, @genesis.title
    assert_includes pl.lineage_label_text, leaf.title
  end

  private

  def anchor_seq_for(thread)
    sid = thread.strand_step_pairs.first&.last
    assert sid&.positive?, "thread needs strand sequence"

    @project.sequences.generative_sequences.find(sid)
  end

  def thread_branch!(title, parent: @genesis, anchor: @seq)
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
      parent_thread_id: parent.id,
      parent_bundle_id: nil,
      parent_generative_sequence_id: anchor.id,
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
    th
  end
end
