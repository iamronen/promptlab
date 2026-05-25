# frozen_string_literal: true

require "test_helper"

class TaxonomiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
    @project = Project.create!(name: "P", user: users(:alice))
  end

  test "index returns taxonomies as json" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        single_select_ui: "dropdown",
        position: 1
      )
    taxonomy.taxonomy_terms.create!(label: "Open", position: 1)

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    taxonomies = data.fetch("taxonomies")
    assert_equal 1, taxonomies.size
    assert_equal "Status", taxonomies.first["name"]
    assert_equal "one", taxonomies.first["cardinality"]
    assert_equal "dropdown", taxonomies.first["single_select_ui"]
    assert_equal 1, taxonomies.first["terms"].size
    assert_equal 0, taxonomies.first["terms"].first["applied_sequence_count"]
    assert_nil data["default_process_taxonomy_id"]
  end

  test "index includes applied_sequence_count on terms" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :many, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    seq1 =
      @project.sequences.create!(
        kind: :sequence,
        title: "S1",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    seq2 =
      @project.sequences.create!(
        kind: :sequence,
        title: "S2",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq1.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: false
    )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: seq2.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: false
    )

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    taxonomies = data.fetch("taxonomies")
    term_json = taxonomies.find { |t| t["id"] == taxonomy.id }["terms"].find { |x| x["id"] == term.id }
    assert_equal 2, term_json["applied_sequence_count"]
  end

  test "create taxonomy returns created json" do
    assert_difference -> { @project.taxonomies.count }, +1 do
      post project_taxonomies_path(@project),
           params: {
             taxonomy: { name: "  Lane  ", cardinality: "many", position: 2 }
           },
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Lane", body["name"]
    assert_equal "many", body["cardinality"]
    assert_nil body["single_select_ui"]
    assert_equal false, body["process_tracking"]
    assert_equal true, body["applies_to_sequences"]
    assert_equal false, body["applies_to_bundles"]
    assert_equal false, body["applies_to_bundle_pipeline_sequences"]
  end

  test "create rejects many cardinality with single_select_ui" do
    assert_no_difference -> { @project.taxonomies.count } do
      post project_taxonomies_path(@project),
           params: {
             taxonomy: { name: "Bad", cardinality: "many", single_select_ui: "dropdown" }
           },
           as: :json
    end

    assert_response :unprocessable_entity
  end

  test "update enables process tracking on single cardinality taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, single_select_ui: "dropdown", position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { process_tracking: true } },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["process_tracking"]
    assert taxonomy.reload.process_tracking?
  end

  test "update clears process tracking on many cardinality taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { process_tracking: true } },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["process_tracking"]
    refute taxonomy.reload.process_tracking?
  end

  test "changing cardinality to many clears process tracking" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { cardinality: "many", single_select_ui: nil, process_tracking: false } },
          as: :json

    assert_response :success
    taxonomy.reload
    assert taxonomy.many?
    refute taxonomy.process_tracking?
  end

  test "update taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "A", cardinality: :one, single_select_ui: "dropdown", position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { name: "B", single_select_ui: "button_group" } },
          as: :json

    assert_response :success
    taxonomy.reload
    assert_equal "B", taxonomy.name
    assert_equal "button_group", taxonomy.single_select_ui
  end

  test "destroy taxonomy" do
    taxonomy = @project.taxonomies.create!(name: "A", cardinality: :one, position: 1)

    assert_difference -> { @project.taxonomies.count }, -1 do
      delete project_taxonomy_path(@project, taxonomy), as: :json
    end

    assert_response :no_content
  end

  test "index returns taxonomies ordered by position" do
    t3 = @project.taxonomies.create!(name: "Third", cardinality: :many, position: 3)
    t1 = @project.taxonomies.create!(name: "First", cardinality: :many, position: 1)
    t2 = @project.taxonomies.create!(name: "Second", cardinality: :many, position: 2)

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    ids = JSON.parse(response.body).fetch("taxonomies").map { |row| row["id"] }
    assert_equal [t1.id, t2.id, t3.id], ids
  end

  test "reorder taxonomies" do
    t1 = @project.taxonomies.create!(name: "A", cardinality: :many, position: 1)
    t2 = @project.taxonomies.create!(name: "B", cardinality: :many, position: 2)
    t3 = @project.taxonomies.create!(name: "C", cardinality: :many, position: 3)

    put reorder_project_taxonomies_path(@project),
        params: { ordered_taxonomy_ids: [t3.id, t1.id, t2.id] },
        as: :json

    assert_response :success
    body = JSON.parse(response.body)
    positions = body.fetch("taxonomies").to_h { |row| [row["id"], row["position"]] }
    assert_equal 1, positions[t3.id]
    assert_equal 2, positions[t1.id]
    assert_equal 3, positions[t2.id]
  end

  test "enabling first process taxonomy sets project default" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, single_select_ui: "dropdown", position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { process_tracking: true } },
          as: :json

    assert_response :success
    assert_equal taxonomy.id, @project.reload.default_process_taxonomy_id
  end

  test "disabling default process taxonomy reassigns to next process taxonomy in sequence" do
    first =
      @project.taxonomies.create!(
        name: "First",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )
    second =
      @project.taxonomies.create!(
        name: "Second",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 2
      )
    @project.update!(default_process_taxonomy: first)

    patch project_taxonomy_path(@project, first),
          params: { taxonomy: { process_tracking: false } },
          as: :json

    assert_response :success
    assert_equal second.id, @project.reload.default_process_taxonomy_id
  end

  test "index returns default_process_taxonomy_id" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal taxonomy.id, data["default_process_taxonomy_id"]
  end

  test "update disabling bundles returns conflict when bundle assignments exist" do
    taxonomy = @project.taxonomies.create!(name: "Lane", cardinality: :one, position: 1, applies_to_bundles: true)
    term = taxonomy.taxonomy_terms.create!(label: "A", position: 1)
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: bundle.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: true
    )

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { applies_to_bundles: false } },
          as: :json

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal true, body["confirmation_required"]
    assert taxonomy.reload.applies_to_bundles?
  end

  test "update disabling bundles with confirm_deletions removes bundle assignments" do
    taxonomy = @project.taxonomies.create!(name: "Lane", cardinality: :one, position: 1, applies_to_bundles: true)
    term = taxonomy.taxonomy_terms.create!(label: "A", position: 1)
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: bundle.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: true
    )

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { applies_to_bundles: false }, confirm_deletions: true },
          as: :json

    assert_response :success
    assert_not taxonomy.reload.applies_to_bundles?
    assert_empty TaxonomyAssignment.where(sequence_id: bundle.id, taxonomy_id: taxonomy.id)
  end

  test "update disabling bundles accepts confirm_deletions query param" do
    taxonomy = @project.taxonomies.create!(name: "Lane", cardinality: :one, position: 1, applies_to_bundles: true)
    term = taxonomy.taxonomy_terms.create!(label: "A", position: 1)
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: bundle.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: true
    )

    patch "#{project_taxonomy_path(@project, taxonomy)}?confirm_deletions=1",
          params: { taxonomy: { applies_to_bundles: false } },
          as: :json

    assert_response :success
    assert_not taxonomy.reload.applies_to_bundles?
  end

  test "update disabling bundles accepts X-Confirm-Deletions header" do
    taxonomy = @project.taxonomies.create!(name: "Lane", cardinality: :one, position: 1, applies_to_bundles: true)
    term = taxonomy.taxonomy_terms.create!(label: "A", position: 1)
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: bundle.id,
      taxonomy_id: taxonomy.id,
      taxonomy_term_id: term.id,
      label_snapshot: term.label,
      single_value_taxonomy_copy: true
    )

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { applies_to_bundles: false, applies_to_bundle_pipeline_sequences: false } },
          headers: { "X-Confirm-Deletions" => "1" },
          as: :json

    assert_response :success
    assert_not taxonomy.reload.applies_to_bundles?
  end

  test "index includes default value settings" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    taxonomy.update!(default_value_enabled: true, default_taxonomy_term: term)

    get project_taxonomies_path(@project), as: :json

    assert_response :success
    data = JSON.parse(response.body)
    tax = data.fetch("taxonomies").first
    assert_equal true, tax["default_value_enabled"]
    assert_equal term.id, tax["default_taxonomy_term_id"]
    assert_kind_of Integer, tax["unassigned_applicable_count"]
  end

  test "update enables default value with selected term" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)

    patch project_taxonomy_path(@project, taxonomy),
          params: { taxonomy: { default_value_enabled: true, default_taxonomy_term_id: term.id } },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["default_value_enabled"]
    assert_equal term.id, body["default_taxonomy_term_id"]
  end

  test "apply_default_value assigns unassigned applicable sequences" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    term = taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    taxonomy.update!(default_value_enabled: true, default_taxonomy_term: term)
    seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )

    post apply_default_value_project_taxonomy_path(@project, taxonomy), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["applied_count"]
    assert TaxonomyAssignment.exists?(sequence_id: seq.id, taxonomy_term_id: term.id)
  end

  test "apply_default_value skips sequences excluded by exclusion rules" do
    stage =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    open_term = stage.taxonomy_terms.create!(label: "Open", position: 1)
    stage.update!(default_value_enabled: true, default_taxonomy_term: open_term)

    perspective = @project.taxonomies.create!(name: "Perspective", cardinality: :one, position: 2)
    vision = perspective.taxonomy_terms.create!(label: "Vision", position: 1)

    Taxonomies::SyncExclusionRules.call(
      taxonomy: stage,
      rules: [{ excluding_taxonomy_id: perspective.id, excluding_term_ids: [vision.id] }]
    )

    seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: seq,
      taxonomy: perspective,
      taxonomy_term: vision,
      label_snapshot: vision.label,
      assigned_at: Time.current
    )

    post apply_default_value_project_taxonomy_path(@project, stage), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["applied_count"]
    assert_not TaxonomyAssignment.exists?(sequence_id: seq.id, taxonomy_id: stage.id)
  end

  test "apply_default_value rejects when default is not configured" do
    taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    taxonomy.taxonomy_terms.create!(label: "Open", position: 1)

    post apply_default_value_project_taxonomy_path(@project, taxonomy), as: :json

    assert_response :unprocessable_entity
  end
end
