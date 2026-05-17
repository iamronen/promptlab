# frozen_string_literal: true

# View model for Fabric workspace mode: recursive thread hierarchy only.
# Child order follows strand anchor positions (ThreadNode + flattened strand) but
# intermediate sequence/bundle anchors are not shown as tree nodes.
class FabricThreadTree
  ThreadBranch = Struct.new(:thread, :child_branches, keyword_init: true)

  class << self
    def root_branches(project)
      new(project).root_branches
    end
  end

  def initialize(project)
    @project = project
  end

  def root_branches
    root_threads_for(@project).filter_map { |t| build_thread_branch(t, []) }
  end

  def build_thread_branch(thread, ancestor_ids)
    return nil unless thread&.thread?

    return nil if ancestor_ids.include?(thread.id)

    next_ancestors = ancestor_ids + [thread.id]
    nodes = ThreadNode.where(parent_thread_id: thread.id)
      .includes(:child_thread)
      .to_a
    return ThreadBranch.new(thread: thread, child_branches: []) if nodes.empty?

    ordered = nodes.sort_by do |n|
      idx = anchor_strand_index(thread, n.parent_generative_sequence_id)
      [idx.nil? ? 10_000 : idx, n.child_order, n.id]
    end

    seen = {}
    child_branches = []
    ordered.each do |n|
      ct = n.child_thread
      next unless ct
      next if seen[ct.id]

      seen[ct.id] = true
      branch = build_thread_branch(ct, next_ancestors)
      child_branches << branch if branch
    end

    ThreadBranch.new(thread: thread, child_branches: child_branches)
  end

  private

  def root_threads_for(project)
    thread_scope = project.sequences.threads
    return thread_scope.none unless thread_scope.exists?

    inbound = ThreadNode.where(child_thread_id: thread_scope.select(:id)).distinct.pluck(:child_thread_id)
    roots = thread_scope.where.not(id: inbound).order(:position)
    return roots if roots.exists?

    thread_scope.order(:position)
  end

  def anchor_strand_index(thread, generative_sequence_id)
    return nil unless generative_sequence_id

    flat = thread.flattened_generative_sequence_ids_on_strand
    flat.index(generative_sequence_id)
  end
end
