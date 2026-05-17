# frozen_string_literal: true

class Project < ApplicationRecord
  # All Sequence rows (generative `sequence`, `bundle`, and weave `thread` strands).
  has_many :sequences, -> { order(:position) }, dependent: :destroy, inverse_of: :project
  has_many :taxonomies, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :project

  validates :name, presence: true

  # Association `dependent: :destroy` registers `before_destroy` procs; without `prepend`,
  # they run before user `around_destroy` begins, so root threads abort first.
  around_destroy :with_sequence_teardown_thread_flag, prepend: true

  after_create :ensure_genesis_thread

  def genesis_thread
    sequences.genesis_threads.first
  end

  def orphans_thread
    sequences.orphans_threads.first
  end

  # Invoked after ProjectsController#create saves the project (not in after_create) so tests and
  # other callers of Project.create! can add their own first sequence without position clashes.
  def bootstrap_initial_sequence_on_genesis!
    g = genesis_thread
    raise ActiveRecord::RecordNotFound, "Missing genesis thread" unless g

    seq = nil
    transaction do
      scope = sequences.generative_sequences
      position = scope.maximum(:position).to_i + 1
      seq = sequences.create!(
        kind: :sequence,
        title: Sequence::DEFAULT_TITLE,
        intent: Sequence::DEFAULT_INTENT,
        position: position,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
      pairs = g.strand_step_pairs + [[:sequence, seq.id]]
      g.steps_data = pairs.map do |k, sid|
        k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid }
      end
      g.save!
    end
    seq
  end

  private

  def with_sequence_teardown_thread_flag
    prev = Thread.current[:wiping_project_id_for_sequences]
    Thread.current[:wiping_project_id_for_sequences] = id
    yield
  ensure
    Thread.current[:wiping_project_id_for_sequences] = prev
  end

  def ensure_genesis_thread
    return if sequences.where(kind: :thread, is_genesis: true).exists?

    next_pos = sequences.where(kind: :thread).maximum(:position).to_i + 1
    sequences.create!(
      kind: :thread,
      title: Sequence::THREAD_DEFAULT_TITLE,
      intent: Sequence::THREAD_DEFAULT_INTENT,
      position: next_pos,
      steps_data: [],
      is_term: false,
      is_genesis: true,
      is_orphans: false
    )
  end
end
