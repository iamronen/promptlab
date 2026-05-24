# frozen_string_literal: true

require "test_helper"

class SequenceCopyAsTextTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Copy text project", user: users(:alice))
  end

  test "copy_as_text includes title intent and numbered plain steps" do
    seq = @project.sequences.create!(
      kind: :sequence,
      title: "My sequence",
      intent: "Do the thing",
      position: 1,
      steps_data: [
        { "content" => "First step" },
        { "content" => "<p>Second <strong>step</strong></p>" },
        { "content" => "" }
      ],
      is_term: false
    )

    text = seq.copy_as_text

    assert_equal <<~TEXT, text
      My sequence

      Do the thing

      1. First step
      2. Second step
    TEXT
  end

  test "copy_as_text strips html from title and intent when present" do
    seq = @project.sequences.create!(
      kind: :sequence,
      title: "<b>Bold title</b>",
      intent: "<p>Rich intent</p>",
      position: 1,
      steps_data: [{ "content" => "Only step" }],
      is_term: false
    )

    text = seq.copy_as_text

    assert_includes text, "Bold title"
    assert_includes text, "Rich intent"
    assert_includes text, "1. Only step"
    assert_not_includes text, "<b>"
    assert_not_includes text, "<p>"
  end

  test "copy_as_text for bundle includes title and each pipeline sequence" do
    child_a = @project.sequences.create!(
      kind: :sequence,
      title: "First seq",
      intent: "Intent A",
      position: 1,
      steps_data: [{ "content" => "Step A1" }],
      is_term: false
    )
    child_b = @project.sequences.create!(
      kind: :sequence,
      title: "Second seq",
      intent: "Intent B",
      position: 2,
      steps_data: [{ "content" => "Step B1" }, { "content" => "Step B2" }],
      is_term: false
    )
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "My bundle",
      intent: "Bundle intent",
      position: 3,
      steps_data: [{ "sequence_id" => child_a.id }, { "sequence_id" => child_b.id }],
      is_term: false
    )
    bundle.update!(title: "My bundle")

    text = bundle.copy_as_text

    assert_equal <<~TEXT, text
      My bundle

      First seq

      Intent A

      1. Step A1

      Second seq

      Intent B

      1. Step B1
      2. Step B2
    TEXT
  end

  test "copy_as_text omits default title and intent placeholders" do
    seq = @project.sequences.create!(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: 1,
      steps_data: [{ "content" => "Only step" }],
      is_term: false
    )

    text = seq.copy_as_text

    assert_equal "1. Only step\n", text
  end

  test "copy_as_text for bundle skips empty pipeline sequences" do
    empty_child = @project.sequences.create!(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: 1,
      steps_data: [],
      is_term: false
    )
    filled_child = @project.sequences.create!(
      kind: :sequence,
      title: "Filled seq",
      intent: Sequence::DEFAULT_INTENT,
      position: 2,
      steps_data: [{ "content" => "Step one" }],
      is_term: false
    )
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "My bundle",
      intent: Sequence::BUNDLE_DEFAULT_INTENT,
      position: 3,
      steps_data: [{ "sequence_id" => empty_child.id }, { "sequence_id" => filled_child.id }],
      is_term: false
    )
    bundle.update!(title: "My bundle")

    text = bundle.copy_as_text

    assert_equal <<~TEXT, text
      My bundle

      Filled seq

      1. Step one
    TEXT
  end
end
