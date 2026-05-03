# frozen_string_literal: true

class Sequence < ApplicationRecord
  DEFAULT_TITLE = "Untitled sequence"
  DEFAULT_INTENT = "Define one clear sentence for the sequence intent."

  TRANSFORMATION_DEFAULT_TITLE = "Untitled transformation"
  TRANSFORMATION_DEFAULT_INTENT = "Describe what this transformation does in one clear sentence."

  belongs_to :project, inverse_of: :sequences

  has_many :child_dependencies, class_name: "SequenceDependency", foreign_key: :parent_id, dependent: :destroy,
                                inverse_of: :parent
  has_many :parent_dependencies, class_name: "SequenceDependency", foreign_key: :child_id, dependent: :destroy,
                                   inverse_of: :child

  enum :kind, { sequence: "sequence", transformation: "transformation" }, validate: true

  scope :generative_sequences, -> { where(kind: :sequence) }
  scope :transformations, -> { where(kind: :transformation) }
  scope :terms, -> { generative_sequences.where(is_term: true) }
  scope :non_term_sequences, -> { generative_sequences.where(is_term: false) }

  StepRow = Struct.new(:position, :content, keyword_init: true)
  TransformationStepRow = Struct.new(:position, :sequence_id, :title, keyword_init: true)

  validates :title, :intent, :position, presence: true
  validates :position, uniqueness: { scope: [:project_id, :kind] }
  validate :steps_data_must_be_array
  validate :transformation_steps_data_valid, if: -> { transformation? }

  before_validation :clear_term_flag_for_transformations
  before_validation :normalize_steps_data

  before_destroy :remove_self_from_transformation_pipeline_steps, if: :sequence?

  after_save :sync_sequence_step_dependency_rows, if: :should_sync_sequence_step_rows?

  # Generative sequences referenced by this transformation’s pipeline, in order (excludes missing ids).
  def pipeline_generative_children_ordered
    ids = transformation_step_sequence_ids
    return [] if ids.empty?

    by_id = project.sequences.generative_sequences.where(id: ids).index_by(&:id)
    ids.filter_map { |sid| by_id[sid] }
  end

  def ordered_steps
    if transformation?
      ordered_transformation_steps
    else
      Array.wrap(steps_data).map.with_index(1) do |raw, i|
        h = raw.is_a?(Hash) ? raw.stringify_keys : {}
        StepRow.new(position: i, content: h.fetch("content", "").to_s)
      end
    end
  end

  def prerequisite_transformation_ids
    child_dependencies.transformation_prerequisite.pluck(:child_id)
  end

  # Replaces prerequisite edges for this transformation. Call inside the same DB transaction as #save when needed.
  def sync_prerequisite_dependencies!(ids)
    return true unless transformation?

    ids = Array(ids).map(&:to_i).uniq - [id]
    valid_ids = project.sequences.transformations.where(id: ids).pluck(:id)
    if ids.size != valid_ids.size
      errors.add(:base, "Invalid prerequisite transformation")
      return false
    end

    child_dependencies.where(kind: :transformation_prerequisite).delete_all

    ids.each do |cid|
      if SequenceDependency.prerequisite_reachable?(cid, id)
        errors.add(:base, "Prerequisite transformations cannot form a cycle")
        return false
      end
    end

    ids.each do |cid|
      SequenceDependency.create!(parent_id: id, child_id: cid, kind: :transformation_prerequisite)
    end
    true
  end

  # Ordered generative sequence IDs referenced by this transformation's pipeline (from `steps_data`).
  def transformation_step_sequence_ids
    Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      sid = raw.stringify_keys["sequence_id"]
      sid.present? ? sid.to_i : nil
    end
  end

  private

  def clear_term_flag_for_transformations
    self.is_term = false if transformation?
  end

  def normalize_steps_data
    if transformation?
      normalize_steps_data_transformation
    else
      normalize_steps_data_sequence
    end
  end

  def normalize_steps_data_sequence
    self.steps_data = Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      c = raw.stringify_keys.fetch("content", "").to_s.strip
      { "content" => c }
    end
  end

  def normalize_steps_data_transformation
    seen = {}
    self.steps_data = Array.wrap(steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      sid = raw.stringify_keys["sequence_id"]
      next if sid.blank?

      id_val = sid.to_i
      next if id_val <= 0
      next if seen[id_val]

      seen[id_val] = true
      { "sequence_id" => id_val }
    end
  end

  def ordered_transformation_steps
    ids = transformation_step_sequence_ids
    titles_by_id = project.sequences.generative_sequences.where(id: ids).index_by(&:id)
    ids.each_with_index.map do |sid, i|
      row = titles_by_id[sid]
      TransformationStepRow.new(
        position: i + 1,
        sequence_id: sid,
        title: row&.title.to_s
      )
    end
  end

  def transformation_steps_data_valid
    ids = transformation_step_sequence_ids
    return if ids.empty?

    valid = project.sequences.generative_sequences.where(id: ids).pluck(:id)
    invalid = ids - valid
    return if invalid.empty?

    errors.add(:steps_data, "references unknown or non-generative sequences")
  end

  def remove_self_from_transformation_pipeline_steps
    parent_dependencies.sequence_step.includes(:parent).find_each do |dep|
      parent = dep.parent
      next unless parent&.transformation?

      filtered = Array.wrap(parent.steps_data).reject do |h|
        h.is_a?(Hash) && h.stringify_keys["sequence_id"].to_i == id
      end
      parent.update!(steps_data: filtered)
    end
  end

  def should_sync_sequence_step_rows?
    transformation? && saved_change_to_steps_data?
  end

  def sync_sequence_step_dependency_rows
    SequenceDependency.where(parent_id: id, kind: :sequence_step).delete_all

    transformation_step_sequence_ids.each_with_index do |child_id, index|
      SequenceDependency.create!(
        parent_id: id,
        child_id: child_id,
        kind: :sequence_step,
        position: index + 1
      )
    end
  end

  def steps_data_must_be_array
    errors.add(:steps_data, "must be an array") unless steps_data.nil? || steps_data.is_a?(Array)
  end
end
