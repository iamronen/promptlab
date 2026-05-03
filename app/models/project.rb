class Project < ApplicationRecord
  # All Sequence rows (`sequence` generative pipelines and `transformation` workflows).
  # Workspace sidebar lists both via Sequence scopes (`generative_sequences`, `transformations`).
  has_many :sequences, -> { order(:position) }, dependent: :destroy, inverse_of: :project

  validates :name, presence: true
end
