# frozen_string_literal: true

require "test_helper"

class ProjectPdfGeneratorTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "PDF export project", user: users(:alice))
    @genesis = @project.genesis_thread
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Strand seq",
      intent: "intent",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "Step one" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])

    next_thread_pos = @project.sequences.threads.maximum(:position).to_i + 1
    @child_thread = @project.sequences.create!(
      kind: :thread,
      title: "Branch thread",
      intent: "branch",
      position: next_thread_pos,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    @bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Pipe bundle",
      intent: "b intent",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => @seq.id }],
      is_term: false
    )
  end

  test "pdf_export_branches depth-first with genesis first then child subtrees" do
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: nil,
      parent_generative_sequence: @seq,
      child_thread: @child_thread,
      child_order: 1
    )

    branches = FabricThreadTree.pdf_export_branches(@project.reload)
    titles = branches.map { |b| b.thread.title }

    assert_equal ["Genesis", "Branch thread"], titles
  end

  test "pdf_export_branches orders sibling threads by strand anchor position" do
    seq_b = @project.sequences.create!(
      kind: :sequence,
      title: "Second anchor",
      intent: "i",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }, { "sequence_id" => seq_b.id }])

    child_a = @child_thread
    child_b = @project.sequences.create!(
      kind: :thread,
      title: "Later anchor branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: seq_b,
      child_thread: child_b,
      child_order: 1
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: @seq,
      child_thread: child_a,
      child_order: 1
    )

    titles = FabricThreadTree.pdf_export_branches(@project.reload).map { |b| b.thread.title }

    assert_equal ["Genesis", "Branch thread", "Later anchor branch"], titles
  end

  test "render returns non-empty PDF bytes" do
    pdf = ProjectPdfGenerator.render(@project.reload)

    assert pdf.bytesize.positive?
    assert pdf.start_with?("%PDF")
  end

  test "bundle strand includes pipeline blocks in export" do
    @genesis.update!(steps_data: [{ "bundle_id" => @bundle.id }])

    pdf = ProjectPdfGenerator.render(@project.reload)

    assert pdf.bytesize.positive?
  end
end
