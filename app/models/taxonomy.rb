# frozen_string_literal: true

class Taxonomy < ApplicationRecord
  belongs_to :project
  # Listed before `taxonomy_terms` so teardown removes taxonomy-level assignment rows before terms.
  has_many :taxonomy_assignments, dependent: :destroy
  has_many :taxonomy_terms, -> { order(:position) }, dependent: :destroy, inverse_of: :taxonomy

  enum :cardinality, { one: "one", many: "many" }, validate: true

  SINGLE_SELECT_UI_VALUES = %w[dropdown button_group].freeze

  validates :name, presence: true
  validates :single_select_ui, inclusion: { in: SINGLE_SELECT_UI_VALUES }, allow_nil: true
  validate :single_select_ui_matches_cardinality

  before_validation :normalize_name
  before_validation :assign_default_position, on: :create

  private

  def assign_default_position
    return unless project
    return if position.present? && position.positive?

    self.position = project.taxonomies.maximum(:position).to_i + 1
  end

  def normalize_name
    self.name = name.to_s.strip
  end

  def single_select_ui_matches_cardinality
    if many?
      errors.add(:single_select_ui, "must be blank when cardinality is many") if single_select_ui.present?
    end
  end
end
