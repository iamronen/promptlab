# frozen_string_literal: true

# View model for Made workspace mode: vertical timeline of artifacts in process end-states.
class MadeTimeline
  include ProcessWorkspaceArtifacts

  Entry = Struct.new(:sequence, :term, :assigned_at, keyword_init: true)
  DateGroup = Struct.new(:date, :entries, keyword_init: true)

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

  def end_state_terms_configured?
    return false unless ready?

    taxonomy.taxonomy_terms.any?(&:process_end_state?)
  end

  def show_end_state_labels?
    return false unless ready?

    taxonomy.taxonomy_terms.count(&:process_end_state?) > 1
  end

  def entries
    return [] unless ready?

    assignments_by_sequence_id = load_assignments_by_sequence_id
    list = []

    applicable_artifacts.each do |sequence|
      assignment = assignments_by_sequence_id[sequence.id]
      next unless end_state_assignment?(assignment)

      list << Entry.new(
        sequence: sequence,
        term: assignment.taxonomy_term,
        assigned_at: assignment.assigned_at
      )
    end

    list.sort_by(&:assigned_at)
  end

  def date_groups
    entries
      .group_by { |entry| entry.assigned_at.in_time_zone.to_date }
      .sort_by { |date, _| date }
      .map do |date, group_entries|
        DateGroup.new(date: date, entries: group_entries.sort_by(&:assigned_at))
      end
  end
end
