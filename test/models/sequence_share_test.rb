# frozen_string_literal: true

require "test_helper"

class SequenceShareTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    Current.user = @user
    @project = Project.create!(name: "Share project", user: @user)
    @genesis = @project.genesis_thread
  end

  test "new thread defaults share_state to none" do
    @genesis.reload
    assert @genesis.share_state_unset?
    assert_not @genesis.share_defined?
  end

  test "non-thread cannot be enabled" do
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "b",
      position: 1,
      steps_data: [],
      is_term: false
    )

    bundle.share_state = :enabled
    assert_not bundle.valid?
    assert_includes bundle.errors[:share_state], "may only be set on threads"
    assert bundle.share_state_unset?
  end

  test "enabled blocked when project disallows sharing" do
    @project.update!(sharing_allowed: false)

    @genesis.share_state = :enabled
    assert_not @genesis.valid?
    assert_includes @genesis.errors[:share_state], "cannot be enabled while project disallows sharing"
  end

  test "share_public_title falls back to thread title" do
    @genesis.update!(share_state: :enabled, share_public_name: nil)

    assert_equal @genesis.title, @genesis.share_public_title
  end

  test "activate_share sets public name from title when omitted" do
    @genesis.activate_share!

    @genesis.reload
    assert @genesis.share_state_enabled?
    assert_equal @genesis.title, @genesis.share_public_name
  end

  test "disable_share retains name and inclusions" do
    child = create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!(share_public_name: "Public Genesis", included_threads: [child])
    @genesis.disable_share!

    @genesis.reload
    assert @genesis.share_state_disabled?
    assert_equal "Public Genesis", @genesis.share_public_name
    assert_equal [child.id], @genesis.included_descendant_threads.pluck(:id)
  end

  test "delete_share clears config and inclusions" do
    child = create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!(included_threads: [child])
    @genesis.delete_share!

    @genesis.reload
    assert @genesis.share_state_unset?
    assert_nil @genesis.share_public_name
    assert_empty @genesis.share_inclusions
  end

  test "replace_share_inclusions no-op when share not defined" do
    child = create_child_thread(parent: @genesis, title: "Child")

    assert_no_difference -> { SequenceShareInclusion.count } do
      @genesis.replace_share_inclusions!([child])
    end
  end

  test "replace_share_inclusions syncs descendant set when share defined" do
    child_a = create_child_thread(parent: @genesis, title: "A")
    child_b = create_child_thread(parent: @genesis, title: "B")
    @genesis.activate_share!(included_threads: [child_a], share_scope: :selected)
    @genesis.replace_share_inclusions!([child_b])

    assert_equal [child_b.id], @genesis.included_descendant_threads.pluck(:id)
    assert @genesis.includes_descendant_thread?(child_b)
    assert_not @genesis.includes_descendant_thread?(child_a)
  end

  test "parent chain validation rejects orphan grandchild inclusion" do
    child = create_child_thread(parent: @genesis, title: "Child")
    grandchild = create_child_thread(parent: child, title: "Grandchild")
    @genesis.activate_share!(share_scope: :selected)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @genesis.replace_share_inclusions!([grandchild])
    end
    assert_includes error.record.errors[:base], "included threads must include every ancestor on the path from the share root"
  end

  test "project shared_threads scope lists enabled thread shares only" do
    @genesis.activate_share!
    other = create_child_thread(parent: @genesis, title: "Other")
    other.activate_share!
    other.disable_share!

    ids = @project.shared_threads.pluck(:id)
    assert_equal [@genesis.id], ids
  end

  test "share_has_included_descendant_threads false for root-only selected share" do
    @genesis.activate_share!(share_scope: :selected)

    assert_not @genesis.share_has_included_descendant_threads?
  end

  test "share_has_included_descendant_threads true for everything scope with children" do
    create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!(share_scope: :everything)

    assert @genesis.share_has_included_descendant_threads?
  end

  test "share_has_included_descendant_threads true when descendant explicitly included" do
    child = create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!(share_scope: :selected, included_threads: [child])

    assert @genesis.share_has_included_descendant_threads?
  end

  test "share_has_included_descendant_threads false when tease only without inclusions" do
    create_child_thread(parent: @genesis, title: "Child")
    @genesis.activate_share!(share_scope: :selected, share_tease: true)

    assert_not @genesis.share_has_included_descendant_threads?
  end

  test "share_reader_child_threads_for respects scope and tease" do
    child_hidden = create_child_thread(parent: @genesis, title: "Hidden")
    @genesis.activate_share!(share_scope: :selected, share_tease: true)

    entries = @genesis.share_reader_child_threads_for(@genesis)

    assert_equal 1, entries.size
    assert_equal "Hidden", entries.first[:title]
    assert_equal false, entries.first[:readable]
  end

  test "share_reader_child_threads_for lists all children when scope is everything" do
    child = create_child_thread(parent: @genesis, title: "All visible")
    @genesis.activate_share!(share_scope: :everything)

    entries = @genesis.share_reader_child_threads_for(@genesis)

    assert_equal 1, entries.size
    assert entries.all? { |e| e[:readable] }
    assert_equal child.public_id, entries.first[:public_id]
  end

  test "share_reader_thread_readable allows root and included descendants only" do
    child = create_child_thread(parent: @genesis, title: "Child")
    other = create_child_thread(parent: @genesis, title: "Other")
    @genesis.activate_share!(share_scope: :selected, included_threads: [child])

    assert @genesis.share_reader_thread_readable?(@genesis)
    assert @genesis.share_reader_thread_readable?(child)
    assert_not @genesis.share_reader_thread_readable?(other)
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
