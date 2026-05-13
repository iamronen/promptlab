# frozen_string_literal: true

require "test_helper"

class ProjectGenesisThreadTest < ActiveSupport::TestCase
  test "creates genesis and orphans root threads on project create" do
    project = Project.create!(name: "With weave")
    assert_equal 1, project.sequences.genesis_threads.count
    assert_equal 1, project.sequences.orphans_threads.count
    genesis = project.genesis_thread
    assert_predicate genesis, :thread?
    assert genesis.is_genesis
    assert_equal [], genesis.steps_data
    assert_equal Sequence::THREAD_DEFAULT_TITLE, genesis.title

    orphans = project.orphans_thread
    assert orphans.is_orphans?
    assert_equal Sequence::ORPHANS_THREAD_TITLE, orphans.title
  end

  test "genesis_thread finder returns genesis sequence" do
    project = Project.create!(name: "G")
    g = project.genesis_thread
    assert_kind_of Sequence, g
    assert_predicate g, :thread?
    assert g.is_genesis
  end
end
