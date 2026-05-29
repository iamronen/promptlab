# frozen_string_literal: true

require "test_helper"

class SequenceSharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "Share API project", user: users(:alice))
    @genesis = @project.genesis_thread
    @genesis.activate_share!(share_public_name: "Public Genesis")
  end

  test "show returns share payload with descendants and inclusions" do
    child = create_child_thread(parent: @genesis, title: "Branch")
    @genesis.replace_share_inclusions!([child])

    get project_sequence_share_path(@project, @genesis), as: :json
    assert_response :success

    body = JSON.parse(response.body)
    share = body["share"]
    assert_equal @genesis.public_id, share["public_id"]
    assert_equal "Public Genesis", share["share_public_name"]
    assert_equal "enabled", share["share_state"]
    assert_includes share["included_thread_public_ids"], child.public_id
    assert share["descendant_threads"].any? { |row| row["public_id"] == child.public_id }
  end

  test "update save changes public name and inclusions" do
    child = create_child_thread(parent: @genesis, title: "Branch")

    patch project_sequence_share_path(@project, @genesis),
          params: {
            share: {
              operation: "save",
              share_public_name: "Renamed Share",
              share_scope: "selected",
              share_enabled: true,
              included_thread_public_ids: [child.public_id]
            }
          },
          as: :json

    assert_response :success
    @genesis.reload
    assert_equal "Renamed Share", @genesis.share_public_name
    assert_equal [child.id], @genesis.included_descendant_threads.pluck(:id)
  end

  test "update disable and enable share" do
    patch project_sequence_share_path(@project, @genesis),
          params: { share: { operation: "disable" } },
          as: :json
    assert_response :success
    assert @genesis.reload.share_state_disabled?

    patch project_sequence_share_path(@project, @genesis),
          params: { share: { operation: "enable" } },
          as: :json
    assert_response :success
    assert @genesis.reload.share_state_enabled?
  end

  test "update enable blocked when project disallows sharing" do
    @genesis.disable_share!
    @project.update!(sharing_allowed: false)

    patch project_sequence_share_path(@project, @genesis),
          params: { share: { operation: "enable" } },
          as: :json

    assert_response :unprocessable_entity
    assert @genesis.reload.share_state_disabled?
  end

  test "destroy deletes share configuration" do
    assert_difference -> { @project.share_defined_threads.count }, -1 do
      delete project_sequence_share_path(@project, @genesis), as: :json
    end

    assert_response :success
    @genesis.reload
    assert @genesis.share_state_unset?
    assert_nil @genesis.share_public_name
  end

  test "destroy responds with turbo stream replacing shares list" do
    delete project_sequence_share_path(@project, @genesis),
           headers: { Accept: "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_includes response.media_type, "text/vnd.turbo-stream.html"
    assert_match(/project_shares_list_content/, response.body)
    assert_match(/No shares yet/, response.body)
  end

  test "returns not found for another users project" do
    other = Project.create!(name: "Other", user: users(:bob))
    other_genesis = other.genesis_thread
    other_genesis.activate_share!

    get project_sequence_share_path(other, other_genesis), as: :json
    assert_response :not_found
  end

  test "show returns draft payload for unset share" do
    @genesis.delete_share!

    get project_sequence_share_path(@project, @genesis), as: :json
    assert_response :success

    body = JSON.parse(response.body)
    share = body["share"]
    assert_equal @genesis.public_id, share["public_id"]
    assert_not share["share_defined"]
    assert_equal "everything", share["share_scope"]
    assert share["thread_tree"].present?
  end

  test "create share as disabled draft" do
    @genesis.delete_share!
    child = create_child_thread(parent: @genesis, title: "Branch")

    patch project_sequence_share_path(@project, @genesis),
          params: {
            share: {
              operation: "save",
              share_public_name: "Draft Share",
              share_scope: "selected",
              share_tease: true,
              share_enabled: false,
              included_thread_public_ids: [child.public_id]
            }
          },
          as: :json

    assert_response :success
    @genesis.reload
    assert @genesis.share_defined?
    assert @genesis.share_state_disabled?
    assert_equal "Draft Share", @genesis.share_public_name
    assert @genesis.share_scope_selected?
    assert @genesis.share_tease?
    assert_equal [child.id], @genesis.included_descendant_threads.pluck(:id)
  end

  test "save everything scope clears inclusions" do
    child = create_child_thread(parent: @genesis, title: "Branch")
    @genesis.update_share_config!(
      share_public_name: "Public Genesis",
      share_scope: :selected,
      share_tease: false,
      included_threads: [child],
      enabled: true
    )

    patch project_sequence_share_path(@project, @genesis),
          params: {
            share: {
              operation: "save",
              share_scope: "everything",
              share_enabled: true
            }
          },
          as: :json

    assert_response :success
    @genesis.reload
    assert @genesis.share_scope_everything?
    assert_empty @genesis.share_inclusions
  end

  test "rejects selected inclusion without parent chain" do
    child = create_child_thread(parent: @genesis, title: "Branch")
    grandchild = create_child_thread(parent: child, title: "Grandchild")
    @genesis.delete_share!

    patch project_sequence_share_path(@project, @genesis),
          params: {
            share: {
              operation: "save",
              share_scope: "selected",
              share_enabled: false,
              included_thread_public_ids: [grandchild.public_id]
            }
          },
          as: :json

    assert_response :unprocessable_entity
  end

  private

  def create_child_thread(parent:, title: "Branch")
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor #{title}",
      intent: "g",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    parent.update!(steps_data: [{ "sequence_id" => anchor.id }])

    child_strand_seq = @project.sequences.create!(
      kind: :sequence,
      title: "Strand #{title}",
      intent: "s",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "y" }],
      is_term: false
    )

    child = @project.sequences.create!(
      kind: :thread,
      title: title,
      intent: "branch",
      position: @project.sequences.threads.maximum(:position).to_i + 1,
      steps_data: [{ "sequence_id" => child_strand_seq.id }],
      is_term: false,
      is_genesis: false,
      is_orphans: false
    )

    ThreadNode.create!(
      parent_thread_id: parent.id,
      parent_generative_sequence_id: anchor.id,
      child_thread_id: child.id,
      child_order: 1
    )

    child
  end
end
