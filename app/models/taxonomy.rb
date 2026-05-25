# frozen_string_literal: true

class Taxonomy < ApplicationRecord
  belongs_to :project
  belongs_to :default_taxonomy_term, class_name: "TaxonomyTerm", optional: true
  # Listed before `taxonomy_terms` so teardown removes taxonomy-level assignment rows before terms.
  has_many :taxonomy_assignments, dependent: :destroy
  has_many :taxonomy_assignment_histories, dependent: :destroy
  has_many :taxonomy_terms, -> { order(:position) }, dependent: :destroy, inverse_of: :taxonomy
  has_many :exclusion_rules,
           class_name: "TaxonomyExclusionRule",
           dependent: :destroy,
           inverse_of: :taxonomy
  has_many :excluding_taxonomy_rules,
           class_name: "TaxonomyExclusionRule",
           foreign_key: :excluding_taxonomy_id,
           dependent: :destroy,
           inverse_of: :excluding_taxonomy

  enum :cardinality, { one: "one", many: "many" }, validate: true

  SINGLE_SELECT_UI_VALUES = %w[dropdown button_group].freeze

  validates :name, presence: true
  validates :single_select_ui, inclusion: { in: SINGLE_SELECT_UI_VALUES }, allow_nil: true
  validate :single_select_ui_matches_cardinality
  validate :process_tracking_matches_cardinality
  validate :bundle_pipeline_sequences_requires_bundles
  validate :default_taxonomy_term_belongs_to_taxonomy

  before_validation :normalize_name
  before_validation :assign_default_position, on: :create
  before_validation :clear_default_taxonomy_term_when_disabled
  before_validation :clear_process_tracking_for_many
  before_validation :clear_bundle_pipeline_sequences_for_process_tracking
  before_validation :clear_bundle_pipeline_sequences_without_bundles

  def applicable_to_sequence?(sequence)
    return false unless applies_to_sequences?
    return true unless sequence.in_bundle_pipeline?
    return true unless applies_to_bundles?

    applies_to_bundle_pipeline_sequences?
  end

  def applicable_to_bundle?
    applies_to_bundles?
  end

  def disable_default_value!
    update!(default_value_enabled: false, default_taxonomy_term: nil)
  end

  def default_value_configured?
    default_value_enabled? && default_taxonomy_term_id.present?
  end

  after_save :destroy_exclusion_rules_unless_process_tracking, if: :saved_change_to_process_tracking?
  after_commit :reconcile_project_default_process_taxonomy

  private

  def clear_default_taxonomy_term_when_disabled
    self.default_taxonomy_term = nil unless default_value_enabled?
  end

  def default_taxonomy_term_belongs_to_taxonomy
    return if default_taxonomy_term_id.blank?

    unless taxonomy_terms.exists?(id: default_taxonomy_term_id)
      errors.add(:default_taxonomy_term, "must be a value in this taxonomy")
    end
  end

  def destroy_exclusion_rules_unless_process_tracking
    exclusion_rules.destroy_all unless process_tracking?
  end

  def reconcile_project_default_process_taxonomy
    project&.reconcile_default_process_taxonomy!
  end

  def assign_default_position
    return unless project
    return if position.present? && position.positive?

    self.position = project.taxonomies.maximum(:position).to_i + 1
  end

  def normalize_name
    self.name = name.to_s.strip
  end

  def clear_process_tracking_for_many
    self.process_tracking = false if many?
  end

  def single_select_ui_matches_cardinality
    if many?
      errors.add(:single_select_ui, "must be blank when cardinality is many") if single_select_ui.present?
    end
  end

  def process_tracking_matches_cardinality
    return unless process_tracking?

    return if one?

    errors.add(:process_tracking, "is only allowed when cardinality is one")
  end

  def bundle_pipeline_sequences_requires_bundles
    return unless applies_to_bundle_pipeline_sequences?
    return if applies_to_bundles?

    errors.add(:applies_to_bundle_pipeline_sequences, "requires applies to bundles")
  end

  def clear_bundle_pipeline_sequences_for_process_tracking
    self.applies_to_bundle_pipeline_sequences = false if process_tracking?
  end

  def clear_bundle_pipeline_sequences_without_bundles
    self.applies_to_bundle_pipeline_sequences = false unless applies_to_bundles?
  end
end
