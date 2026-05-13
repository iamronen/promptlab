# frozen_string_literal: true

class Project < ApplicationRecord
  # All Sequence rows (generative `sequence`, `bundle`, and weave `thread` strands).
  has_many :sequences, -> { order(:position) }, dependent: :destroy, inverse_of: :project

  validates :name, presence: true

  after_create :ensure_root_threads

  def genesis_thread
    sequences.genesis_threads.first
  end

  def orphans_thread
    sequences.orphans_threads.first
  end

  private

  def ensure_root_threads
    ensure_genesis_thread
    ensure_orphans_thread
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

  def ensure_orphans_thread
    return if sequences.where(kind: :thread, is_orphans: true).exists?

    next_pos = sequences.where(kind: :thread).maximum(:position).to_i + 1
    sequences.create!(
      kind: :thread,
      title: Sequence::ORPHANS_THREAD_TITLE,
      intent: Sequence::ORPHANS_THREAD_INTENT,
      position: next_pos,
      steps_data: [],
      is_term: false,
      is_genesis: false,
      is_orphans: true
    )
  end
end
