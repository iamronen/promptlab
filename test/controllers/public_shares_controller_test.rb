# frozen_string_literal: true

require "test_helper"

class PublicSharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    Current.user = @user
    @project = Project.create!(name: "Public share project", user: @user)
    @genesis = @project.genesis_thread
  end

  test "show renders reader without authentication for enabled share" do
    @genesis.activate_share!(share_public_name: "Public Genesis")

    get public_share_path(@genesis.public_id)
    assert_response :success
    assert_select "h1.public-share-reader-title", text: "Public Genesis"
    assert_select "[data-controller='public-share-reader']"
    assert_select ".public-share-reader-attribution", text: "Powered by Sequential"
    assert_select ".application-shell", count: 0
    assert_no_match(/preview coming soon/i, response.body)
  end

  test "show hides top nav when share has no included descendants" do
    @genesis.activate_share!(share_public_name: "Solo", share_scope: :selected)

    get public_share_path(@genesis.public_id)
    assert_response :success
    assert_equal false, reader_payload_from_response["show_top_nav"]
  end

  test "show shows top nav when share includes descendants" do
    child = create_child_thread(parent: @genesis, title: "Branch A")
    @genesis.activate_share!(share_public_name: "With branches", included_threads: [child])

    get public_share_path(@genesis.public_id)
    assert_response :success
    payload = reader_payload_from_response
    assert_equal true, payload["show_top_nav"]
    assert_equal "Start", payload.dig("threads", @genesis.public_id, "breadcrumb", 0, "label")
  end

  test "show embeds strand content in reader payload" do
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor seq",
      intent: "g",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "Step one" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => anchor.id }])
    @genesis.activate_share!(share_public_name: "Content share")

    get public_share_path(@genesis.public_id)
    assert_response :success
    assert_match(/strand_children/, response.body)
    assert_match(/Step one/, response.body)
  end

  test "show preserves step emphasis in reader payload" do
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor seq",
      intent: "g",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "<p>Plain <b>bold</b> and <i>italic</i></p>" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => anchor.id }])
    @genesis.activate_share!(share_public_name: "Emphasis share")

    get public_share_path(@genesis.public_id)
    assert_response :success
    content = reader_payload_from_response.dig("threads", @genesis.public_id, "strand_children", 0, "steps", 0, "content")
    assert_includes content, "<strong>bold</strong>"
    assert_includes content, "<em>italic</em>"
  end

  test "show preserves step emphasis for child threads in reader payload" do
    anchor = @project.sequences.create!(
      kind: :sequence,
      title: "Anchor seq",
      intent: "g",
      position: @project.sequences.generative_sequences.maximum(:position).to_i + 1,
      steps_data: [{ "content" => "anchor" }],
      is_term: false
    )
    @genesis.update!(steps_data: [{ "sequence_id" => anchor.id }])

    child = create_child_thread(parent: @genesis, title: "Child branch")
    child_strand_seq = @project.sequences.generative_sequences.find(child.ordered_steps.first.sequence_id)
    child_strand_seq.update!(steps_data: [{ "content" => "<div>Child <b>bold</b> and <i>italic</i></div>" }])

    @genesis.activate_share!(share_public_name: "Child emphasis share", share_scope: :everything)

    get public_share_path(@genesis.public_id)
    assert_response :success
    child_content = reader_payload_from_response.dig("threads", child.public_id, "strand_children", 0, "steps", 0, "content")
    assert_includes child_content, "<strong>bold</strong>"
    assert_includes child_content, "<em>italic</em>"
  end

  test "show lists teased child threads as not readable in payload" do
    child = create_child_thread(parent: @genesis, title: "Hidden branch")
    @genesis.activate_share!(share_public_name: "Tease share", share_scope: :selected, share_tease: true)

    get public_share_path(@genesis.public_id)
    assert_response :success
    assert_match(/Hidden branch/, response.body)
    child_entry = reader_payload_from_response.dig("threads", @genesis.public_id, "child_threads", 0)
    assert_equal false, child_entry["readable"]
  end

  test "show deep links to readable child thread" do
    child = create_child_thread(parent: @genesis, title: "Readable child")
    @genesis.activate_share!(included_threads: [child])

    get public_share_path(@genesis.public_id, t: child.public_id)
    assert_response :success
    assert_equal child.public_id, reader_payload_from_response["initial_thread_public_id"]
  end

  test "show returns not found for deep link to non-readable thread" do
    child = create_child_thread(parent: @genesis, title: "Hidden")
    @genesis.activate_share!(share_scope: :selected, share_tease: true)

    get public_share_path(@genesis.public_id, t: child.public_id)
    assert_response :not_found
  end

  test "show returns not found for disabled share" do
    @genesis.activate_share!
    @genesis.disable_share!

    get public_share_path(@genesis.public_id)
    assert_response :not_found
  end

  test "show returns not found for unknown public id" do
    get public_share_path("missing-share-id")
    assert_response :not_found
  end

  private

  def reader_payload_from_response
    script = Nokogiri::HTML(response.body).at("[data-public-share-reader-target='payloadSource']")
    assert script, "expected reader payload script tag"
    JSON.parse(CGI.unescapeHTML(script.text))
  end

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
