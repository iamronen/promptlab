# frozen_string_literal: true

require "test_helper"

class SequenceBundleDependenciesTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @bundle = @project.sequences.create!(
      kind: :bundle,
      title: Sequence::BUNDLE_DEFAULT_TITLE,
      intent: "ti",
      position: 1,
      steps_data: [],
      is_term: false
    )
  end

  test "in_bundle_pipeline is true for generative sequence in bundle pipeline" do
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    @gen.reload

    assert @gen.in_bundle_pipeline?
  end

  test "sync sequence_step rows after bundle steps_data update" do
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    deps = SequenceDependency.where(parent_id: @bundle.id, kind: :sequence_step)
    assert_equal 1, deps.count
    assert_equal @gen.id, deps.first.child_id
    assert_equal 1, deps.first.position
    assert_equal "Gen", @bundle.reload.title
  end

  test "destroy generative sequence removes pipeline reference from bundle" do
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    assert_equal 1, SequenceDependency.where(parent_id: @bundle.id, kind: :sequence_step).count

    @gen.destroy!

    @bundle.reload
    assert_equal [], @bundle.steps_data
    assert_equal Sequence::BUNDLE_DEFAULT_TITLE, @bundle.title
    assert_empty SequenceDependency.where(parent_id: @bundle.id, kind: :sequence_step)
  end

  test "normalizes bundle steps_data dedupes sequence ids" do
    @bundle.assign_attributes(
      steps_data: [
        { "sequence_id" => @gen.id },
        { "sequence_id" => @gen.id }
      ]
    )
    @bundle.valid?
    assert_equal 1, @bundle.steps_data.size
    assert_equal "Gen", @bundle.title
  end

  test "sync_prerequisite_dependencies replaces edges" do
    t2 = @project.sequences.create!(
      kind: :bundle,
      title: "T2",
      intent: "i2",
      position: 2,
      steps_data: [],
      is_term: false
    )
    assert @bundle.sync_prerequisite_dependencies!([t2.id])
    assert_equal [t2.id], @bundle.prerequisite_bundle_ids.sort
  end

  test "bundle title follows first pipeline sequence when reordered" do
    gen2 = @project.sequences.create!(
      kind: :sequence,
      title: "Second",
      intent: "i2",
      position: 2,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }, { "sequence_id" => gen2.id }])
    assert_equal "Gen", @bundle.reload.title

    @bundle.update!(steps_data: [{ "sequence_id" => gen2.id }, { "sequence_id" => @gen.id }])
    assert_equal "Second", @bundle.reload.title
  end

  test "renaming first sequence in pipeline updates bundle title" do
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    assert_equal "Gen", @bundle.reload.title

    @gen.update!(title: "Renamed root")
    assert_equal "Renamed root", @bundle.reload.title
  end

  test "bundle title can be edited without changing steps_data" do
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    assert_equal "Gen", @bundle.reload.title

    assert @bundle.update!(title: "Display name only")
    assert_equal "Display name only", @bundle.reload.title
    assert_equal "Gen", @gen.reload.title
  end

  test "sync_prerequisite_dependencies rejects cycle" do
    t2 = @project.sequences.create!(
      kind: :bundle,
      title: "T2",
      intent: "i2",
      position: 2,
      steps_data: [],
      is_term: false
    )
    assert t2.sync_prerequisite_dependencies!([@bundle.id])

    assert_not @bundle.sync_prerequisite_dependencies!([t2.id])
    assert @bundle.errors[:base].any? { |m| m.include?("cycle") }
  end
end
