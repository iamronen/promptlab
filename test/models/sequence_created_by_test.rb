# frozen_string_literal: true

require "test_helper"

class SequenceCreatedByTest < ActiveSupport::TestCase
  setup do
    @alice = users(:alice)
    @bob = users(:bob)
    @project = Project.create!(name: "Created-by project", user: @alice)
  end

  teardown do
    Current.reset
  end

  test "assigns Current.user when set" do
    Current.user = @bob
    seq = @project.sequences.create!(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )
    assert_equal @bob, seq.created_by
  end

  test "falls back to project owner when Current.user is unset" do
    Current.user = nil
    seq = @project.sequences.create!(
      kind: :bundle,
      title: Sequence::BUNDLE_DEFAULT_TITLE,
      intent: Sequence::BUNDLE_DEFAULT_INTENT,
      position: 1,
      steps_data: [],
      is_term: false
    )
    assert_equal @alice, seq.created_by
  end

  test "bootstrap_initial_sequence_on_genesis! sets created_by to project owner" do
    Current.user = nil
    seq = @project.bootstrap_initial_sequence_on_genesis!
    assert_equal @alice, seq.created_by
  end
end
