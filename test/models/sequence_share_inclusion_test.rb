# frozen_string_literal: true

require "test_helper"

class SequenceShareInclusionTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    Current.user = @user
    @project = Project.create!(name: "Inclusion project", user: @user)
    @genesis = @project.genesis_thread
    @child = create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!
  end

  test "valid inclusion for descendant thread" do
    inclusion = @genesis.share_inclusions.build(included_sequence: @child)

    assert inclusion.valid?
    assert inclusion.save
  end

  test "rejects non-descendant thread in same project" do
    sibling = create_child_thread(parent: @genesis, title: "Sibling")

    @child.activate_share!
    inclusion = @child.share_inclusions.build(included_sequence: sibling)

    assert_not inclusion.valid?
    assert_includes inclusion.errors[:included_sequence], "must be a descendant of the share root in the thread tree"
    assert_not SequenceShareInclusion.descendant_of_root?(sibling, @child)
  end

  test "rejects self inclusion" do
    inclusion = @genesis.share_inclusions.build(included_sequence: @genesis)

    assert_not inclusion.valid?
    assert_includes inclusion.errors[:included_sequence], "cannot be the share root (root is always included implicitly)"
  end

  test "rejects inclusion when root share is none" do
    @genesis.delete_share!

    inclusion = SequenceShareInclusion.new(root_sequence: @genesis, included_sequence: @child)
    assert_not inclusion.valid?
    assert_includes inclusion.errors[:root_sequence], "must be a thread with a defined share"
  end

  test "rejects generative sequence as included" do
    seq = @project.sequences.create!(
      kind: :sequence,
      title: "S",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )

    inclusion = @genesis.share_inclusions.build(included_sequence: seq)
    assert_not inclusion.valid?
    assert_includes inclusion.errors[:included_sequence], "must be a thread in the same project as the share root"
  end

  test "overlapping ShareA and ShareB inclusion sets coexist" do
    grandchild = create_child_thread(parent: @child, title: "Grandchild")

    @genesis.replace_share_inclusions!([@child])
    @child.activate_share!(included_threads: [grandchild])

    assert_equal [@child.id], @genesis.included_descendant_threads.pluck(:id)
    assert_equal [grandchild.id], @child.included_descendant_threads.pluck(:id)
    assert_equal 2, SequenceShareInclusion.count
  end

  test "destroying included thread removes inclusion row" do
    @genesis.replace_share_inclusions!([@child])
    assert_equal 1, SequenceShareInclusion.count

    @child.destroy!

    assert_empty SequenceShareInclusion.where(included_sequence_id: @child.id)
  end

  test "destroying share root cascades inclusions" do
    share_root = create_child_thread(parent: @genesis, title: "Share root")
    grandchild = create_child_thread(parent: share_root, title: "Grandchild")
    share_root.activate_share!(included_threads: [grandchild])

    assert_difference -> { SequenceShareInclusion.count }, -1 do
      share_root.destroy!
    end
    assert_empty SequenceShareInclusion.where(root_sequence_id: share_root.id)
  end

  private

  def create_child_thread(parent:, title: "Branch")
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor #{title}",
      intent: "g",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    parent.update!(steps_data: [{ "sequence_id" => anchor.id }])

    child_strand_seq = @project.sequences.create!(
      kind: :sequence,
      title: "Strand #{title}",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )

    child = @project.sequences.create!(
      kind: :thread,
      title: title,
      intent: "branch",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => child_strand_seq.id }],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread_id: parent.id,
      parent_generative_sequence_id: anchor.id,
      child_thread_id: child.id,
      child_order: 1
    )

    child
  end
end
