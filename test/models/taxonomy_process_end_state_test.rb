# frozen_string_literal: true

require "test_helper"

class TaxonomyProcessEndStateTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @stage =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    @done = @stage.taxonomy_terms.create!(label: "Done", position: 1)
  end

  test "term rejects process_end_state when taxonomy is not process tracking" do
    standard = @project.taxonomies.create!(name: "Tags", cardinality: :one, position: 2)
    term = standard.taxonomy_terms.create!(label: "Tag", position: 1)

    term.process_end_state = true

    refute term.valid?
    assert term.errors[:process_end_state].any?
  end

  test "disabling process tracking clears end state flags" do
    Taxonomies::SyncEndStateTerms.call(taxonomy: @stage, term_ids: [@done.id])
    assert @done.reload.process_end_state?

    @stage.update!(process_tracking: false)

    refute @done.reload.process_end_state?
  end
end
