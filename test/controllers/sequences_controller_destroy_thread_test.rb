# frozen_string_literal: true

require "test_helper"

class SequencesControllerDestroyThreadTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Delete thread project", user: users(:alice))
    @genesis = @project.genesis_thread
    @seq = @project.sequences.create!(
      kind: :sequence,
      title: "Lane",
      intent: "i",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => @seq.id }])
  end

  test "destroy fork thread removes thread and rewires weave query" do
    child = fork_thread_under_anchor(@seq.id)

    open_threads = "#{@genesis.id},#{child.id}"
    rt = "#{edit_project_sequence_path(@project, @seq)}?#{{
      weave_thread: child.id.to_s,
      open_threads: open_threads
    }.to_query}"

    assert_difference -> { @project.sequences.threads.count }, -1 do
      delete project_sequence_path(@project, child),
             params: {
               redirect_to: rt,
               weave_thread: child.id,
               open_threads: open_threads
             }
    end

    assert_redirected_to %r{\Ahttp://www.example.com#{Regexp.escape(edit_project_sequence_path(@project, @seq))}}
    uri = URI.parse(@response.redirect_url)
    q = Rack::Utils.parse_nested_query(uri.query.to_s)

    expected_open = ([@genesis.id].map(&:to_s))
    assert_equal expected_open.sort, q["open_threads"].to_s.split(",").map(&:strip).sort
    assert_equal @genesis.id.to_s, q["weave_thread"].to_s
    assert q["workspace_mode"].blank?, "fabric mode omitted when strips remain"

    assert_not @project.sequences.threads.where(id: child.id).exists?
  end

  test "destroy last open thread redirects to fabric and clears weave keys" do
    child = fork_thread_under_anchor(@seq.id)
    ot = "#{child.id}"

    rt = "#{edit_project_sequence_path(@project, @seq)}?#{{
      weave_thread: child.id.to_s,
      open_threads: ot
    }.to_query}"

    assert_difference -> { @project.sequences.threads.where.not(id: @genesis.id).count }, -1 do
      delete project_sequence_path(@project, child),
             params: {
               redirect_to: rt,
               weave_thread: child.id,
               open_threads: ot
             }
    end

    uri = URI.parse(@response.redirect_url)
    q = Rack::Utils.parse_nested_query(uri.query.to_s)

    assert_equal "fabric", q["workspace_mode"].to_s
    assert q["open_threads"].blank?, "open_threads cleared"
    assert q["weave_thread"].blank?, "weave_thread cleared"
    assert q["thread_partner"].blank?

    assert_not @project.sequences.threads.where(id: child.id).exists?
  end

  test "cannot destroy genesis thread" do
    rt = edit_project_sequence_path(@project, @seq, weave_thread: @genesis.id)
    genesis_id = @genesis.id

    assert_no_difference -> { Sequence.count } do
      delete project_sequence_path(@project, @genesis.id), params: { redirect_to: rt }
    end

    assert_response :redirect
    assert @project.sequences.threads.where(id: genesis_id).exists?
    assert flash[:notice].blank?, "no success flash"
    assert flash[:alert].present?, "expect alert"
    assert_includes flash[:alert].to_s.downcase, "destroy"
  end

  private

  def fork_thread_under_anchor(generative_anchor_id)
    child = nil
    assert_difference -> { @project.sequences.threads.where(is_genesis: false, is_orphans: false).count }, +1 do
      assert_difference -> { ThreadNode.where(parent_thread_id: @genesis.id).count }, +1 do
        post thread_fork_strand_project_sequence_path(@project, @genesis),
             params: {
               parent_generative_sequence_id: generative_anchor_id,
               redirect_to: edit_project_sequence_path(@project, @seq, weave_thread: @genesis.id),
               thread_title: "Test branch"
             }
      end
      assert_response :redirect
      child =
        Sequence.threads.where.not(is_genesis: true).where.not(is_orphans: true).order(:id).last
    end
    child&.reload
    assert_equal 1, child.strand_step_pairs.size
    assert_equal :sequence, child.strand_step_pairs.first.first
    child
  end
end
