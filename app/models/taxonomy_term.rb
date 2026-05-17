# frozen_string_literal: true

class TaxonomyTerm < ApplicationRecord
  belongs_to :taxonomy, inverse_of: :taxonomy_terms
  has_many :taxonomy_assignments, dependent: :delete_all

  validates :label, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }

  before_validation :normalize_label
  before_validation :assign_default_position, on: :create
  after_update :sync_assignment_label_snapshots, if: :saved_change_to_label?

  private

  def assign_default_position
    return unless taxonomy
    return if position.present? && position.positive?

    self.position = taxonomy.taxonomy_terms.maximum(:position).to_i + 1
  end

  def normalize_label
    self.label = label.to_s.strip
  end

  def sync_assignment_label_snapshots
    TaxonomyAssignment.where(taxonomy_term_id: id).update_all(label_snapshot: label)
  end
end
