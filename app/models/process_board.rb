# frozen_string_literal: true

# View model for Process workspace mode: kanban columns from the project's default process taxonomy.
class ProcessBoard
  TaskCard = Struct.new(:sequence, keyword_init: true)
  Column = Struct.new(:term, :label, :cards, keyword_init: true)

  UNASSIGNED_LABEL = "Unassigned"

  def initialize(project)
    @project = project
  end

  def ready?
    taxonomy.present?
  end

  def taxonomy
    @taxonomy ||= @project.default_process_taxonomy
  end

  def taxonomy_name
    taxonomy&.name.to_s
  end

  def columns
    return [] unless ready?

    assignments_by_sequence_id = load_assignments_by_sequence_id
    cards_by_term_id = Hash.new { |h, k| h[k] = [] }

    applicable_artifacts.each do |sequence|
      assignment = assignments_by_sequence_id[sequence.id]
      term_id = assignment&.taxonomy_term_id
      cards_by_term_id[term_id] << TaskCard.new(sequence: sequence)
    end

    unassigned_column =
      Column.new(
        term: nil,
        label: UNASSIGNED_LABEL,
        cards: sort_cards(cards_by_term_id[nil])
      )

    term_columns =
      taxonomy.taxonomy_terms.map do |term|
        Column.new(
          term: term,
          label: term.label,
          cards: sort_cards(cards_by_term_id[term.id])
        )
      end

    unassigned_column.cards.any? ? [unassigned_column] + term_columns : term_columns
  end

  private

  def applicable_artifacts
    excluded_ids = excluded_sequence_ids.to_set
    sequences = @project.sequences.generative_sequences.where(is_term: false).to_a
    bundles = @project.sequences.bundles.to_a
    (sequences + bundles)
      .select { |artifact| applicable?(artifact) }
      .reject { |artifact| excluded_ids.include?(artifact.id) }
  end

  def excluded_sequence_ids
    return [] unless ready?

    Taxonomies::Exclusion.excluded_sequence_ids_for(@project, process_taxonomy: taxonomy)
  end

  def applicable?(artifact)
    return taxonomy.applicable_to_bundle? if artifact.bundle?

    taxonomy.applicable_to_sequence?(artifact)
  end

  def load_assignments_by_sequence_id
    TaxonomyAssignment
      .where(project_id: @project.id, taxonomy_id: taxonomy.id)
      .includes(:sequence, :taxonomy_term)
      .index_by(&:sequence_id)
  end

  def sort_cards(cards)
    cards.sort_by { |card| [card.sequence.position, card.sequence.id] }
  end
end
