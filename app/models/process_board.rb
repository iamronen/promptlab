# frozen_string_literal: true

# View model for Making workspace mode: kanban columns from the project's default process taxonomy.
class ProcessBoard
  include ProcessWorkspaceArtifacts
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
      next if end_state_assignment?(assignment)

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
      taxonomy.taxonomy_terms.reject(&:process_end_state?).map do |term|
        Column.new(
          term: term,
          label: term.label,
          cards: sort_cards(cards_by_term_id[term.id])
        )
      end

    unassigned_column.cards.any? ? [unassigned_column] + term_columns : term_columns
  end

  private

  def sort_cards(cards)
    cards.sort_by { |card| [card.sequence.position, card.sequence.id] }
  end
end
