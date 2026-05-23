# frozen_string_literal: true

require "test_helper"

class ThreadStrandMutationsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Weave project", user: users(:alice))
    @genesis = @project.genesis_thread
    @g = @project.sequences.create!(
      kind: :sequence,
      title: "G",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @t1 = @project.sequences.create!(
      kind: :bundle,
      title: "A",
      intent: "a",
      position: 1,
      steps_data: [{ "sequence_id" => @g.id }],
      is_term: false
    )
    @t2 = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "b",
      position: 2,
      steps_data: [{ "sequence_id" => @g.id }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [{ "bundle_id" => @t1.id }, { "bundle_id" => @t2.id }]
    )
  end

  test "thread_update_steps autosave returns no content" do
    patch thread_update_steps_project_sequence_path(@project, @genesis),
          params: {
            autosave: "1",
            strand_step_tokens: ["b:#{@t2.id}", "b:#{@t1.id}"]
          }
    assert_response :no_content
    assert_equal [@t2.id, @t1.id], @genesis.reload.thread_bundle_ids
  end

  test "thread_update_steps reorders strand bundles" do
    dest = "/projects/#{@project.id}/open"
    patch thread_update_steps_project_sequence_path(@project, @genesis),
          params: { bundle_ids: [@t2.id, @t1.id], redirect_to: dest }
    assert_redirected_to %r{\Ahttp://www.example.com#{Regexp.escape(dest)}}
    assert_equal [@t2.id, @t1.id], @genesis.reload.thread_bundle_ids
  end

  test "thread_insert_bundle appends a new bundle" do
    dest = "/projects/#{@project.id}/open"
    assert_difference -> { @project.sequences.bundles.count }, +1 do
      post thread_insert_bundle_project_sequence_path(@project, @genesis),
           params: { insert: "end", redirect_to: dest }
    end
    assert_redirected_to %r{focus_bundle_id=\d+}
    bundle = Sequence.bundles.order(:id).last
    assert_equal @genesis.reload.thread_bundle_ids.last, bundle.id
  end

  test "thread_insert_sequence appends to strand end" do
    dest = "/projects/#{@project.id}/open"
    assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
      post thread_insert_sequence_project_sequence_path(@project, @genesis),
           params: { insert: "end", redirect_to: dest }
    end
    assert_redirected_to %r{focus_transformation_id=\d+}
    pairs = @genesis.reload.strand_step_pairs
    assert_equal :sequence, pairs.last[0]
  end

  test "thread_insert_sequence inserts before a bundle step" do
    dest = "/projects/#{@project.id}/open"
    assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
      post thread_insert_sequence_project_sequence_path(@project, @genesis),
           params: {
             insert: "before",
             relative_kind: "bundle",
             relative_to_id: @t1.id,
             redirect_to: dest
           }
    end
    assert_redirected_to %r{focus_transformation_id=\d+}
    pairs = @genesis.reload.strand_step_pairs
    assert_equal :sequence, pairs[0][0]
    assert_equal @t1.id, pairs[1][1]
  end

  test "thread_duplicate_strand_child_sequence duplicates sequence step and inserts after source on strand" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "solo" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [
        { "bundle_id" => @t1.id },
        { "sequence_id" => solo.id }
      ]
    )

    assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
      post thread_duplicate_strand_child_sequence_project_sequence_path(@project, @genesis),
           params: { source_sequence_id: solo.id, redirect_to: dest }
    end
    assert_response :redirect
    pairs = @genesis.reload.strand_step_pairs
    seq_ids = pairs.filter_map { |k, id| id if k == :sequence }
    assert_equal 2, seq_ids.size
    assert_equal solo.id, seq_ids[0]
    assert_operator seq_ids[1], :!=, solo.id
    copy = @project.sequences.generative_sequences.find(seq_ids[1])
    assert_match(/\(copy\)/i, copy.title.to_s)
  end

  test "thread_fork_strand creates child thread and thread node" do
    dest = "/projects/#{@project.id}/open"
    assert_difference -> { @project.sequences.threads.count }, +1 do
      assert_difference -> { @project.sequences.generative_sequences.count }, +1 do
        post thread_fork_strand_project_sequence_path(@project, @genesis),
             params: { parent_generative_sequence_id: @g.id, redirect_to: dest, thread_title: "My branch" }
      end
    end
    assert_response :redirect
    child = @project.sequences.threads.where(is_genesis: false, is_orphans: false).order(:id).last
    assert child
    assert_equal "My branch", child.title
    assert_equal @genesis.id, ThreadNode.find_by(child_thread: child).parent_thread_id
    seq_ids = child.steps_data.filter_map { |s| s["sequence_id"] }
    assert_equal 1, seq_ids.size
    new_seq = @project.sequences.generative_sequences.find(seq_ids.first)
    assert_equal Sequence::DEFAULT_TITLE, new_seq.title
    loc = response.headers["Location"]
    assert_match(/weave_thread=#{child.id}/, loc)
    assert_match(/open_threads=.*#{@genesis.id}.*#{child.id}|open_threads=.*#{child.id}.*#{@genesis.id}/, loc)
    assert_match(/focus_transformation_id=#{new_seq.id}/, loc)
    assert_no_match(/editor_mode=/, loc)
    assert_no_match(/thread_partner=/, loc)
  end

  test "thread_fork_strand rejects blank thread title" do
    dest = "/projects/#{@project.id}/open"
    assert_no_difference -> { @project.sequences.threads.count } do
      post thread_fork_strand_project_sequence_path(@project, @genesis),
           params: { parent_generative_sequence_id: @g.id, redirect_to: dest, thread_title: "   " }
    end
    assert_redirected_to dest
    assert_equal "Thread name is required.", flash[:alert]
  end

  test "thread_fork_strand twice from same generative sequence works" do
    dest = "/projects/#{@project.id}/open"
    post thread_fork_strand_project_sequence_path(@project, @genesis),
         params: { parent_generative_sequence_id: @g.id, redirect_to: dest, thread_title: "Branch one" }
    assert_response :redirect

    post thread_fork_strand_project_sequence_path(@project, @genesis),
         params: { parent_generative_sequence_id: @g.id, redirect_to: dest, thread_title: "Branch two" }
    assert_response :redirect

    nodes = ThreadNode.where(parent_thread_id: @genesis.id, parent_generative_sequence_id: @g.id).order(:child_order)
    assert_equal 2, nodes.size
    assert_equal [1, 2], nodes.pluck(:child_order)
    deps = SequenceDependency.where(parent_id: @genesis.id, kind: :thread_branch).order(:position)
    assert_equal 2, deps.size
    assert_equal [1, 2], deps.pluck(:position)
  end

  test "thread_unbundle_pipeline_sequence places first pipeline sequence before bundle on strand" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    g3 = @project.sequences.create!(
      kind: :sequence,
      title: "G3",
      intent: "g3",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "z" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }, { "sequence_id" => g3.id }])

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: @t1.id, sequence_id: @g.id, redirect_to: dest }

    assert_response :redirect
    pairs = @genesis.reload.strand_step_pairs
    assert_equal [:sequence, @g.id], pairs[0]
    assert_equal [:bundle, @t1.id], pairs[1]
    assert_equal [g2.id, g3.id], @t1.reload.pipeline_generative_sequence_ids
  end

  test "thread_unbundle_pipeline_sequence places non-first pipeline sequence after bundle on strand" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    g3 = @project.sequences.create!(
      kind: :sequence,
      title: "G3",
      intent: "g3",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "z" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }, { "sequence_id" => g3.id }])

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: @t1.id, sequence_id: g2.id, redirect_to: dest }

    assert_response :redirect
    pairs = @genesis.reload.strand_step_pairs
    assert_equal [:bundle, @t1.id], pairs[0]
    assert_equal [:sequence, g2.id], pairs[1]
    assert_equal [@g.id, g3.id], @t1.reload.pipeline_generative_sequence_ids
  end

  test "thread_unbundle_pipeline_sequence dissolves bundle when one sequence remains" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }])
    bundle_id = @t1.id
    @genesis.update!(steps_data: [{ "bundle_id" => bundle_id }])

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: bundle_id, sequence_id: @g.id, redirect_to: dest }

    assert_response :redirect
    assert_nil @project.sequences.bundles.find_by(id: bundle_id)
    pairs = @genesis.reload.strand_step_pairs
    assert_equal [[:sequence, @g.id], [:sequence, g2.id]], pairs
  end

  test "thread_unbundle_pipeline_sequence removes lone bundle when unbundling only child" do
    dest = "/projects/#{@project.id}/open"
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])
    bundle_id = @t1.id

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: bundle_id, sequence_id: @g.id, redirect_to: dest }

    assert_response :redirect
    assert_nil @project.sequences.bundles.find_by(id: bundle_id)
    assert_equal [[:sequence, @g.id]], @genesis.reload.strand_step_pairs
  end

  test "thread_unbundle_pipeline_sequence nullifies parent_bundle_id on thread nodes when bundle destroyed" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])

    next_thread_pos = @project.sequences.threads.maximum(:position).to_i + 1
    child_thread = @project.sequences.create!(
      kind: :thread,
      title: "Fork",
      intent: "f",
      position: next_thread_pos,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    node = ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: @t1,
      parent_generative_sequence: @g,
      child_thread: child_thread,
      child_order: 1
    )
    bundle_id = @t1.id

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: bundle_id, sequence_id: @g.id, redirect_to: dest }

    assert_response :redirect
    assert_nil @project.sequences.bundles.find_by(id: bundle_id)
    assert_nil node.reload.parent_bundle_id
    assert_equal child_thread.id, @project.sequences.threads.find(child_thread.id).id
  end

  test "thread_unbundle_pipeline_sequence autosave returns no content" do
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    g3 = @project.sequences.create!(
      kind: :sequence,
      title: "G3",
      intent: "g3",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "z" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }, { "sequence_id" => g3.id }])

    post thread_unbundle_pipeline_sequence_project_sequence_path(@project, @genesis),
         params: { bundle_id: @t1.id, sequence_id: @g.id, autosave: "1" }

    assert_response :no_content
  end

  test "thread_merge_adjacent_strand_steps merges two sequences into a new bundle" do
    dest = "/projects/#{@project.id}/open"
    h1 = @project.sequences.create!(
      kind: :sequence,
      title: "H1",
      intent: "h1",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    h2 = @project.sequences.create!(
      kind: :sequence,
      title: "H2",
      intent: "h2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => h1.id }, { "sequence_id" => h2.id }])

    assert_difference -> { @project.sequences.bundles.count }, +1 do
      post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
           params: {
             strand_step_token: "s:#{h2.id}",
             merge_direction: "previous",
             redirect_to: dest
           }
    end
    assert_response :redirect
    pairs = @genesis.reload.strand_step_pairs
    assert_equal 1, pairs.size
    assert_equal :bundle, pairs[0][0]
    bundle = @project.sequences.bundles.find(pairs[0][1])
    assert_equal [h1.id, h2.id], bundle.pipeline_generative_sequence_ids
  end

  test "thread_merge_adjacent_strand_steps merge next joins sequences in thread order" do
    dest = "/projects/#{@project.id}/open"
    h1 = @project.sequences.create!(
      kind: :sequence,
      title: "H1",
      intent: "h1",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    h2 = @project.sequences.create!(
      kind: :sequence,
      title: "H2",
      intent: "h2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => h1.id }, { "sequence_id" => h2.id }])

    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "s:#{h1.id}",
           merge_direction: "next",
           redirect_to: dest
         }
    assert_response :redirect
    pairs = @genesis.reload.strand_step_pairs
    assert_equal 1, pairs.size
    bundle = @project.sequences.bundles.find(pairs[0][1])
    assert_equal [h1.id, h2.id], bundle.pipeline_generative_sequence_ids
  end

  test "thread_merge_adjacent_strand_steps prepends loose sequence to bundle below" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "solo" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => solo.id }, { "bundle_id" => @t1.id }])

    assert_no_difference -> { @project.sequences.bundles.count } do
      post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
           params: {
             strand_step_token: "s:#{solo.id}",
             merge_direction: "next",
             redirect_to: dest
           }
    end
    assert_response :redirect
    assert_equal [[:bundle, @t1.id]], @genesis.reload.strand_step_pairs
    assert_equal [solo.id, @g.id], @t1.reload.pipeline_generative_sequence_ids
  end

  test "thread_merge_adjacent_strand_steps appends loose sequence after bundle" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "solo" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }, { "sequence_id" => solo.id }])

    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "b:#{@t1.id}",
           merge_direction: "next",
           redirect_to: dest
         }
    assert_response :redirect
    assert_equal [[:bundle, @t1.id]], @genesis.reload.strand_step_pairs
    assert_equal [@g.id, solo.id], @t1.reload.pipeline_generative_sequence_ids
  end

  test "thread_merge_adjacent_strand_steps merges two bundles into one" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t2.update!(steps_data: [{ "sequence_id" => g2.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }, { "bundle_id" => @t2.id }])
    absorbed_id = @t2.id

    assert_difference -> { @project.sequences.bundles.count }, -1 do
      post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
           params: {
             strand_step_token: "b:#{@t2.id}",
             merge_direction: "previous",
             redirect_to: dest
           }
    end
    assert_response :redirect
    assert_nil @project.sequences.bundles.find_by(id: absorbed_id)
    assert_equal [[:bundle, @t1.id]], @genesis.reload.strand_step_pairs
    assert_equal [@g.id, g2.id], @t1.reload.pipeline_generative_sequence_ids
  end

  test "thread_merge_adjacent_strand_steps reparents thread nodes from absorbed bundle" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t2.update!(steps_data: [{ "sequence_id" => g2.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }, { "bundle_id" => @t2.id }])

    next_thread_pos = @project.sequences.threads.maximum(:position).to_i + 1
    child_thread = @project.sequences.create!(
      kind: :thread,
      title: "Fork2",
      intent: "f",
      position: next_thread_pos,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    node = ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: @t2,
      parent_generative_sequence: g2,
      child_thread: child_thread,
      child_order: 1
    )

    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "b:#{@t2.id}",
           merge_direction: "previous",
           redirect_to: dest
         }
    assert_response :redirect
    assert_equal @t1.id, node.reload.parent_bundle_id
  end

  test "thread_merge_adjacent_strand_steps rejects merge previous on first row" do
    dest = "/projects/#{@project.id}/open"
    @genesis.update!(steps_data: [{ "sequence_id" => @g.id }, { "bundle_id" => @t1.id }])
    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "s:#{@g.id}",
           merge_direction: "previous",
           redirect_to: dest
         }
    assert_response :redirect
    assert_equal [[:sequence, @g.id], [:bundle, @t1.id]], @genesis.reload.strand_step_pairs
  end

  test "thread_merge_adjacent_strand_steps rejects merge next on last row" do
    dest = "/projects/#{@project.id}/open"
    @genesis.update!(steps_data: [{ "sequence_id" => @g.id }, { "bundle_id" => @t1.id }])
    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "b:#{@t1.id}",
           merge_direction: "next",
           redirect_to: dest
         }
    assert_response :redirect
    assert_equal [[:sequence, @g.id], [:bundle, @t1.id]], @genesis.reload.strand_step_pairs
  end

  test "thread_merge_adjacent_strand_steps autosave returns no content" do
    h1 = @project.sequences.create!(
      kind: :sequence,
      title: "H1",
      intent: "h1",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    h2 = @project.sequences.create!(
      kind: :sequence,
      title: "H2",
      intent: "h2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => h1.id }, { "sequence_id" => h2.id }])

    post thread_merge_adjacent_strand_steps_project_sequence_path(@project, @genesis),
         params: {
           strand_step_token: "s:#{h2.id}",
           merge_direction: "previous",
           autosave: "1"
         }
    assert_response :no_content
    assert_equal 1, @genesis.reload.strand_step_pairs.size
    assert_equal :bundle, @genesis.strand_step_pairs.first[0]
  end

  test "thread_dissolve_strand_bundle expands bundle to sequences at strand position" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }])
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Before",
      intent: "b",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "b" }],
      is_term: false
    )
    after = @project.sequences.create!(
      kind: :sequence,
      title: "After",
      intent: "a",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [
        { "sequence_id" => solo.id },
        { "bundle_id" => @t1.id },
        { "sequence_id" => after.id }
      ]
    )
    bundle_id = @t1.id

    assert_difference -> { @project.sequences.bundles.count }, -1 do
      post thread_dissolve_strand_bundle_project_sequence_path(@project, @genesis),
           params: { bundle_id: bundle_id, redirect_to: dest }
    end
    assert_response :redirect
    assert_nil @project.sequences.bundles.find_by(id: bundle_id)
    pairs = @genesis.reload.strand_step_pairs
    assert_equal(
      [
        [:sequence, solo.id],
        [:sequence, @g.id],
        [:sequence, g2.id],
        [:sequence, after.id]
      ],
      pairs
    )
  end

  test "thread_dissolve_strand_bundle removes empty bundle step from strand" do
    dest = "/projects/#{@project.id}/open"
    @t1.update!(steps_data: [])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])
    bundle_id = @t1.id

    assert_difference -> { @project.sequences.bundles.count }, -1 do
      post thread_dissolve_strand_bundle_project_sequence_path(@project, @genesis),
           params: { bundle_id: bundle_id, redirect_to: dest }
    end
    assert_response :redirect
    assert_empty @genesis.reload.strand_step_pairs
  end

  test "thread_dissolve_strand_bundle rejects bundle not on strand" do
    dest = "/projects/#{@project.id}/open"
    lone = @project.sequences.create!(
      kind: :bundle,
      title: "Lonely",
      intent: "l",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false
    )

    post thread_dissolve_strand_bundle_project_sequence_path(@project, @genesis),
         params: { bundle_id: lone.id, redirect_to: dest }
    assert_response :redirect
    assert lone.reload
    assert_includes @genesis.reload.strand_step_pairs, [:bundle, @t1.id]
  end

  test "thread_dissolve_strand_bundle autosave returns no content" do
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "g2",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @t1.update!(steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }])
    @genesis.update!(steps_data: [{ "bundle_id" => @t1.id }])

    post thread_dissolve_strand_bundle_project_sequence_path(@project, @genesis),
         params: { bundle_id: @t1.id, autosave: "1" }
    assert_response :no_content
    assert_nil @project.sequences.bundles.find_by(id: @t1.id)
    pairs = @genesis.reload.strand_step_pairs
    assert_equal 2, pairs.size
    assert_equal [:sequence, @g.id], pairs[0]
    assert_equal [:sequence, g2.id], pairs[1]
  end

  test "sequences update autosave renames a branch thread title" do
    dest = "/projects/#{@project.id}/open"
    assert_difference -> { @project.sequences.threads.count }, +1 do
      post thread_fork_strand_project_sequence_path(@project, @genesis),
           params: { parent_generative_sequence_id: @g.id, redirect_to: dest, thread_title: "Fork for rename test" }
    end
    child = @project.sequences.threads.where(is_genesis: false, is_orphans: false).order(:id).last

    patch project_sequence_path(@project, child),
          params: { autosave: "1", sequence: { title: "Renamed strand" } },
          headers: { "Accept" => "application/json" }

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "Renamed strand", body["title"]
    assert_equal "Renamed strand", child.reload.title
  end

  test "sequences update rejects genesis thread title change via autosave" do
    patch project_sequence_path(@project, @genesis),
          params: { autosave: "1", sequence: { title: "Renamed genesis" } },
          headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert_predicate @genesis.reload.title, :present?
    assert_not_equal "Renamed genesis", @genesis.title
  end

  test "sequences update does not accept bundles through sequences route" do
    patch project_sequence_path(@project, @t1),
          params: { autosave: "1", sequence: { title: "Hack" } },
          headers: { "Accept" => "application/json" }

    assert_response :not_found
  end

  test "thread_move_sequence_to_thread moves direct strand sequence to end of target" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: 99,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [
        { "sequence_id" => solo.id },
        { "bundle_id" => @t1.id },
        { "bundle_id" => @t2.id }
      ]
    )
    other = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: @g.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_sequence_to_thread_project_sequence_path(@project, @genesis),
         params: {
           sequence_id: solo.id,
           target_thread_id: other.id,
           redirect_to: dest,
           weave_thread: @genesis.id,
           open_threads: "#{@genesis.id},#{other.id}"
         }

    assert_response :redirect
    assert_match(/weave_thread=#{other.id}/, @response.redirect_url)
    assert_match(/focus_transformation_id=#{solo.id}/, @response.redirect_url)
    refute_includes @genesis.reload.strand_step_pairs, [:sequence, solo.id]
    assert_equal [:sequence, solo.id], other.reload.strand_step_pairs.last
  end

  test "thread_move_sequence_to_thread moves sequence from bundle to target strand" do
    dest = "/projects/#{@project.id}/open"
    g_only = @project.sequences.create!(
      kind: :sequence,
      title: "OnlyInBundle",
      intent: "x",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "z" }],
      is_term: false
    )
    bundle_only = @project.sequences.create!(
      kind: :bundle,
      title: "SingleSeqBundle",
      intent: "b",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => g_only.id }],
      is_term: false
    )
    anchor_only = @project.sequences.create!(
      kind: :sequence,
      title: "AnchorForBranch",
      intent: "x",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => bundle_only.id }, { "sequence_id" => anchor_only.id }])

    other = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: anchor_only.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_sequence_to_thread_project_sequence_path(@project, @genesis),
         params: {
           sequence_id: g_only.id,
           target_thread_id: other.id,
           from_bundle_id: bundle_only.id,
           redirect_to: dest,
           weave_thread: @genesis.id
         }

    assert_response :redirect
    assert_nil flash[:alert], flash.to_hash.inspect
    assert_equal "Sequence moved to thread.", flash[:notice]
    assert_equal [[:sequence, anchor_only.id]], @genesis.reload.strand_step_pairs
    assert_equal [:sequence, g_only.id], other.reload.strand_step_pairs.last
  end

  test "thread_move_sequence_to_thread rejects moving to same thread" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: 99,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => solo.id }])

    post thread_move_sequence_to_thread_project_sequence_path(@project, @genesis),
         params: {
           sequence_id: solo.id,
           target_thread_id: @genesis.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_match(/example\.com#{Regexp.escape(dest)}/, @response.redirect_url)
    assert_includes flash[:alert].to_s.downcase, "invalid"
  end

  test "thread_move_sequence_to_thread rejects moving into thread branched from that sequence" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Solo",
      intent: "s",
      position: 99,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => solo.id }])

    other = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: solo.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_sequence_to_thread_project_sequence_path(@project, @genesis),
         params: {
           sequence_id: solo.id,
           target_thread_id: other.id,
           redirect_to: dest,
           weave_thread: @genesis.id
         }

    assert_response :redirect
    assert_match(/example\.com#{Regexp.escape(dest)}/, @response.redirect_url)
    assert_includes flash[:alert].to_s, "branched from that sequence"
    assert_equal [[:sequence, solo.id]], @genesis.reload.strand_step_pairs
    assert_empty other.reload.strand_step_pairs
  end

  test "thread_move_bundle_to_thread appends bundle to end of target strand" do
    dest = "/projects/#{@project.id}/open"
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor",
      intent: "a",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [
        { "bundle_id" => @t1.id },
        { "bundle_id" => @t2.id },
        { "sequence_id" => anchor.id }
      ]
    )
    other = @project.sequences.create!(
      kind: :thread,
      title: "Dest",
      intent: "d",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: anchor.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_bundle_to_thread_project_sequence_path(@project, @genesis),
         params: {
           bundle_id: @t1.id,
           target_thread_id: other.id,
           redirect_to: dest,
           weave_thread: @genesis.id
         }

    assert_response :redirect
    assert_equal "Bundle moved to thread.", flash[:notice]
    assert_equal [[:bundle, @t2.id], [:sequence, anchor.id]], @genesis.reload.strand_step_pairs
    assert_equal [[:bundle, @t1.id]], other.reload.strand_step_pairs
    assert_match(/focus_bundle_id=#{@t1.id}/, @response.redirect_url)
    assert_match(/weave_thread=#{other.id}/, @response.redirect_url)
  end

  test "thread_move_bundle_to_thread rejects moving to same thread" do
    dest = "/projects/#{@project.id}/open"
    post thread_move_bundle_to_thread_project_sequence_path(@project, @genesis),
         params: {
           bundle_id: @t1.id,
           target_thread_id: @genesis.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_includes flash[:alert].to_s.downcase, "invalid"
    assert_equal [[:bundle, @t1.id], [:bundle, @t2.id]], @genesis.reload.strand_step_pairs
  end

  test "thread_move_bundle_to_thread rejects moving into thread branched from pipeline sequence" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Pipe",
      intent: "p",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    bundle_only = @project.sequences.create!(
      kind: :bundle,
      title: "Pipeline bundle",
      intent: "b",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => solo.id }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => bundle_only.id }])

    other = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: solo.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_bundle_to_thread_project_sequence_path(@project, @genesis),
         params: {
           bundle_id: bundle_only.id,
           target_thread_id: other.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_includes flash[:alert].to_s, "branched from a sequence in that bundle"
    assert_equal [[:bundle, bundle_only.id]], @genesis.reload.strand_step_pairs
    assert_empty other.reload.strand_step_pairs
  end

  test "thread_move_bundle_to_thread rejects when target strand already includes a pipeline sequence" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "Dup",
      intent: "d",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    strand_anchor = @project.sequences.create!(
      kind: :sequence,
      title: "StrandAnchor",
      intent: "x",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    bundle_moving = @project.sequences.create!(
      kind: :bundle,
      title: "WillMove",
      intent: "b",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => solo.id }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => bundle_moving.id }, { "sequence_id" => strand_anchor.id }])

    other = @project.sequences.create!(
      kind: :thread,
      title: "HasSolo",
      intent: "o",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => solo.id }],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence_id: strand_anchor.id,
      child_thread: other,
      child_order: 1
    )

    post thread_move_bundle_to_thread_project_sequence_path(@project, @genesis),
         params: {
           bundle_id: bundle_moving.id,
           target_thread_id: other.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_includes flash[:alert].to_s, "already on the target strand"
    assert_equal [[:bundle, bundle_moving.id], [:sequence, strand_anchor.id]], @genesis.reload.strand_step_pairs
    assert_equal [[:sequence, solo.id]], other.reload.strand_step_pairs
  end

  test "thread_attach_branch_thread reanchors within same parent thread" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "x",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }]
    )
    branch = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: @g,
      child_thread: branch,
      child_order: 1
    )

    post thread_attach_branch_thread_project_sequence_path(@project, @genesis),
         params: {
           child_thread_id: branch.id,
           anchor_sequence_id: g2.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_equal "Thread branch attached.", flash[:notice]
    node = ThreadNode.find_by(child_thread_id: branch.id)
    assert_equal @genesis.id, node.parent_thread_id
    assert_equal g2.id, node.parent_generative_sequence_id
    assert_nil node.parent_bundle_id
  end

  test "thread_attach_branch_thread moves branch to another parent thread and resyncs deps" do
    dest = "/projects/#{@project.id}/open"
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "G2",
      intent: "x",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )
    @genesis.update!(
      steps_data: [{ "sequence_id" => @g.id }, { "sequence_id" => g2.id }]
    )
    branch_a = @project.sequences.create!(
      kind: :thread,
      title: "Branch A",
      intent: "a",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    branch_b = @project.sequences.create!(
      kind: :thread,
      title: "Branch B",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: @g,
      child_thread: branch_a,
      child_order: 1
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: g2,
      child_thread: branch_b,
      child_order: 1
    )
    h = @project.sequences.create!(
      kind: :sequence,
      title: "H",
      intent: "h",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "h" }],
      is_term: false
    )
    branch_b.update!(steps_data: [{ "sequence_id" => h.id }])

    post thread_attach_branch_thread_project_sequence_path(@project, branch_b),
         params: {
           child_thread_id: branch_a.id,
           anchor_sequence_id: h.id,
           redirect_to: dest,
           open_threads: "#{@genesis.id},#{branch_a.id},#{branch_b.id}"
         }

    assert_response :redirect
    node = ThreadNode.find_by(child_thread_id: branch_a.id)
    assert_equal branch_b.id, node.parent_thread_id
    assert_equal h.id, node.parent_generative_sequence_id

    genesis_branch_ids =
      SequenceDependency.where(parent_id: @genesis.id, kind: :thread_branch).order(:position).pluck(:child_id)
    assert_equal [branch_b.id], genesis_branch_ids

    b_branch_ids =
      SequenceDependency.where(parent_id: branch_b.id, kind: :thread_branch).pluck(:child_id)
    assert_equal [branch_a.id], b_branch_ids
  end

  test "thread_attach_branch_thread updates bundle anchor" do
    dest = "/projects/#{@project.id}/open"
    g1 = @project.sequences.create!(
      kind: :sequence,
      title: "GP1",
      intent: "p",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "p" }],
      is_term: false
    )
    g2 = @project.sequences.create!(
      kind: :sequence,
      title: "GP2",
      intent: "q",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "q" }],
      is_term: false
    )
    b1 = @project.sequences.create!(
      kind: :bundle,
      title: "Pipe1",
      intent: "b",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => g1.id }],
      is_term: false
    )
    b2 = @project.sequences.create!(
      kind: :bundle,
      title: "Pipe2",
      intent: "b",
      position: @project.sequences.bundles.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => g2.id }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "bundle_id" => b1.id }, { "bundle_id" => b2.id }])

    branch = @project.sequences.create!(
      kind: :thread,
      title: "FromPipe1",
      intent: "x",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_bundle: b1,
      parent_generative_sequence: g1,
      child_thread: branch,
      child_order: 1
    )

    post thread_attach_branch_thread_project_sequence_path(@project, @genesis),
         params: {
           child_thread_id: branch.id,
           anchor_sequence_id: g2.id,
           anchor_bundle_id: b2.id,
           redirect_to: dest
         }

    assert_response :redirect
    node = ThreadNode.find_by(child_thread_id: branch.id)
    assert_equal b2.id, node.parent_bundle_id
    assert_equal g2.id, node.parent_generative_sequence_id
  end

  test "thread_attach_branch_thread rejects no-op and invalid anchor" do
    dest = "/projects/#{@project.id}/open"
    solo = @project.sequences.create!(
      kind: :sequence,
      title: "SoloAnchor",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "s" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => solo.id }])
    branch = @project.sequences.create!(
      kind: :thread,
      title: "Branch",
      intent: "b",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: solo,
      child_thread: branch,
      child_order: 1
    )

    post thread_attach_branch_thread_project_sequence_path(@project, @genesis),
         params: {
           child_thread_id: branch.id,
           anchor_sequence_id: solo.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_includes flash[:alert].to_s.downcase, "already"

    orphan = @project.sequences.create!(
      kind: :sequence,
      title: "Orphan",
      intent: "o",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "o" }],
      is_term: false
    )
    post thread_attach_branch_thread_project_sequence_path(@project, @genesis),
         params: {
           child_thread_id: branch.id,
           anchor_sequence_id: orphan.id,
           redirect_to: dest
         }
    assert_response :redirect
    assert_includes flash[:alert].to_s.downcase, "anchor"
  end

  test "thread_attach_branch_thread rejects cycle when child is ancestor of target parent" do
    dest = "/projects/#{@project.id}/open"
    inner = @project.sequences.create!(
      kind: :sequence,
      title: "Inner",
      intent: "i",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "i" }],
      is_term: false
    )
    h = @project.sequences.create!(
      kind: :sequence,
      title: "Hstep",
      intent: "h",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "h" }],
      is_term: false
    )
    k = @project.sequences.create!(
      kind: :sequence,
      title: "Kstep",
      intent: "k",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "k" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => inner.id }])

    mid = @project.sequences.create!(
      kind: :thread,
      title: "Mid",
      intent: "m",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    leaf = @project.sequences.create!(
      kind: :thread,
      title: "Leaf",
      intent: "l",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )
    ThreadNode.create!(
      parent_thread: @genesis,
      parent_generative_sequence: inner,
      child_thread: mid,
      child_order: 1
    )
    mid.update!(steps_data: [{ "sequence_id" => h.id }])
    ThreadNode.create!(
      parent_thread: mid,
      parent_generative_sequence: h,
      child_thread: leaf,
      child_order: 1
    )
    leaf.update!(steps_data: [{ "sequence_id" => k.id }])

    post thread_attach_branch_thread_project_sequence_path(@project, leaf),
         params: {
           child_thread_id: mid.id,
           anchor_sequence_id: k.id,
           redirect_to: dest
         }

    assert_response :redirect
    assert_includes flash[:alert].to_s.downcase, "cycle"
    assert_equal @genesis.id, ThreadNode.find_by(child_thread_id: mid.id).parent_thread_id
  end

end
