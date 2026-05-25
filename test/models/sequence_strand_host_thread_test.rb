# frozen_string_literal: true

require "test_helper"

class SequenceStrandHostThreadTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Host thread project", user: users(:alice))
    @genesis = @project.genesis_thread
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "On strand",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])
  end

  test "strand_host_thread returns parent thread for sequence on strand" do
    assert_equal @genesis, @seq.reload.strand_host_thread
  end

  test "strand_host_thread returns parent thread for bundle on strand" do
    pipeline_seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "Pipe",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "y" }],
        is_term: false
      )
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "Bundle",
        intent: "i",
        position: 3,
        steps_data: [{ "sequence_id" => pipeline_seq.id }],
        is_term: false
      )
    @genesis.update!(steps_data: [{ "bundle_id" => bundle.id }])

    assert_equal @genesis, bundle.reload.strand_host_thread
  end

  test "strand_host_thread is nil when not on a strand" do
    loose =
      @project.sequences.create!(
        kind: :sequence,
        title: "Loose",
        intent: "i",
        position: 9,
        steps_data: [{ "content" => "z" }],
        is_term: false
      )

    assert_nil loose.strand_host_thread
  end
end
