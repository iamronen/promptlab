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
end
