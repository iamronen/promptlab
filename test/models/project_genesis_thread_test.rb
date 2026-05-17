# frozen_string_literal: true

require "test_helper"

class ProjectGenesisThreadTest < ActiveSupport::TestCase
  test "creates genesis root thread on project create without orphans" do
    project = Project.create!(name: "With weave")
    assert_equal 1, project.sequences.genesis_threads.count
    assert_equal 0, project.sequences.orphans_threads.count
    genesis = project.genesis_thread
    assert_predicate genesis, :thread?
    assert genesis.is_genesis
    assert_equal [], genesis.steps_data
    assert_equal Sequence::THREAD_DEFAULT_TITLE, genesis.title

    assert_nil project.orphans_thread
  end

  test "genesis_thread finder returns genesis sequence" do
    project = Project.create!(name: "G")
    g = project.genesis_thread
    assert_kind_of Sequence, g
    assert_predicate g, :thread?
    assert g.is_genesis
  end

  test "bootstrap_initial_sequence_on_genesis! adds sequence to genesis strand" do
    project = Project.create!(name: "Bootstrap")
    assert_equal [], project.genesis_thread.steps_data

    seq = project.bootstrap_initial_sequence_on_genesis!
    assert_predicate seq, :sequence?
    assert_equal [[:sequence, seq.id]], project.genesis_thread.reload.strand_step_pairs
  end
end
