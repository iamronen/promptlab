# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :user
  belongs_to :default_process_taxonomy, class_name: "Taxonomy", optional: true

  # All Sequence rows (generative `sequence`, `bundle`, and weave `thread` strands).
  has_many :sequences, -> { order(:position) }, dependent: :destroy, inverse_of: :project
  has_many :taxonomies, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :project
  has_many :taxonomy_assignment_histories, dependent: :destroy

  validates :name, presence: true
  validates :public_id, presence: true, uniqueness: true
  validates :sharing_allowed, inclusion: { in: [true, false] }
  validate :default_process_taxonomy_belongs_to_project

  before_validation :assign_public_id, on: :create

  # Association `dependent: :destroy` registers `before_destroy` procs; without `prepend`,
  # they run before user `around_destroy` begins, so root threads abort first.
  around_destroy :with_sequence_teardown_thread_flag, prepend: true

  after_create :ensure_genesis_thread

  def self.generate_public_id
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless exists?(public_id: candidate)
    end
  end

  def self.find_by_public_id!(public_id)
    find_by!(public_id: public_id.to_s.strip)
  end

  def to_param
    public_id
  end

  def genesis_thread
    sequences.genesis_threads.first
  end

  def orphans_thread
    sequences.orphans_threads.first
  end

  def shared_threads
    sequences.merge(Sequence.with_share_enabled)
  end

  def share_defined_threads
    sequences.merge(Sequence.share_defined).order(:title, :id)
  end

  # Invoked after ProjectsController#create saves the project (not in after_create) so tests and
  # other callers of Project.create! can add their own first sequence without position clashes.
  def process_taxonomies_ordered
    taxonomies.where(process_tracking: true).order(:position, :id)
  end

  # Keeps default_process_taxonomy aligned with available process taxonomies:
  # cleared when none exist, forced when only one exists, and repaired when invalid.
  def reconcile_default_process_taxonomy!
    ordered_ids = process_taxonomies_ordered.pluck(:id)

    if ordered_ids.empty?
      update_column(:default_process_taxonomy_id, nil) if default_process_taxonomy_id.present?
      return
    end

    if ordered_ids.size == 1
      new_id = ordered_ids.first
      update_column(:default_process_taxonomy_id, new_id) if default_process_taxonomy_id != new_id
      return
    end

    current_id = default_process_taxonomy_id
    return if current_id && ordered_ids.include?(current_id)

    update_column(:default_process_taxonomy_id, ordered_ids.first)
  end

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

  def assign_public_id
    self.public_id = self.class.generate_public_id if public_id.blank?
  end

  def default_process_taxonomy_belongs_to_project
    return if default_process_taxonomy_id.blank?

    tax = default_process_taxonomy
    if tax.nil? || tax.project_id != id
      errors.add(:default_process_taxonomy, "must belong to this project")
    elsif !tax.process_tracking?
      errors.add(:default_process_taxonomy, "must track process over time")
    end
  end

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
