# frozen_string_literal: true

require "test_helper"

class ProjectDefaultProcessTaxonomyTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
  end

  test "reconcile clears default when no process taxonomies exist" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )
    @project.update!(default_process_taxonomy: taxonomy)

    taxonomy.update!(process_tracking: false)

    assert_nil @project.reload.default_process_taxonomy_id
  end

  test "reconcile sets sole process taxonomy as default" do
    taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        position: 1
      )

    assert_equal taxonomy.id, @project.reload.default_process_taxonomy_id
  end

  test "reconcile picks first process taxonomy in sequence when default becomes invalid" do
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

    first.update!(process_tracking: false)

    assert_equal second.id, @project.reload.default_process_taxonomy_id
  end

  test "reconcile preserves explicit default among multiple process taxonomies" do
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
    @project.update!(default_process_taxonomy: second)

    first.update!(name: "Renamed")

    assert_equal second.id, @project.reload.default_process_taxonomy_id
  end

  test "reconcile reassigns when default process taxonomy is deleted" do
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

    first.destroy!

    assert_equal second.id, @project.reload.default_process_taxonomy_id
  end

  test "rejects default taxonomy that does not track process" do
    taxonomy = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 1)

    @project.default_process_taxonomy = taxonomy

    refute @project.valid?
    assert_includes @project.errors[:default_process_taxonomy], "must track process over time"
  end
end
