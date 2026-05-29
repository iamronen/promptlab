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

    # Depth-first pre-order: parent thread first, then each child subtree in strand-anchor order
    # (child_branches are already ordered by anchor sequence on the parent strand).
    def depth_first_branches(branch)
      return [] unless branch

      [branch] + branch.child_branches.flat_map { |b| depth_first_branches(b) }
    end

    # Genesis fabric (depth-first from Genesis), then Orphans fabric, for PDF index + details.
    def pdf_export_branches(project)
      tree = new(project)
      out = []
      genesis = project.genesis_thread
      if genesis
        gen_branch = tree.build_thread_branch(genesis, [])
        out.concat(depth_first_branches(gen_branch)) if gen_branch
      end

      orphans = project.orphans_thread
      if orphans
        orphans_branch = tree.build_thread_branch(orphans, [])
        out.concat(depth_first_branches(orphans_branch)) if orphans_branch
      end

      out
    end

    # Thread ids of all descendants under root (excludes root), depth-first order.
    def descendant_thread_ids_for(root)
      new(root.project).descendant_thread_ids_for(root)
    end

    def build_thread_branch(root, ancestor_ids = [])
      new(root.project).build_thread_branch(root, ancestor_ids)
    end

    # Direct parent thread id of child, or nil.
    def parent_thread_id_of(child)
      return nil unless child&.thread?

      ThreadNode.find_by(child_thread_id: child.id)&.parent_thread_id
    end

    # Thread ids from root's child down to descendant (includes descendant, excludes root).
    def thread_path_from_root(root, descendant)
      new(root.project).thread_path_from_root(root, descendant)
    end
  end

  def descendant_thread_ids_for(root)
    branch = build_thread_branch(root, [])
    return [] unless branch

    self.class.depth_first_branches(branch).drop(1).map { |b| b.thread.id }
  end

  def parent_thread_id_of(child)
    self.class.parent_thread_id_of(child)
  end

  def thread_path_from_root(root, descendant)
    return [] unless descendant&.thread? && root&.thread?
    return [] if descendant.id == root.id
    return [] unless descendant_thread_ids_for(root).include?(descendant.id)

    path = []
    current = descendant
    while current && current.id != root.id
      path.unshift(current.id)
      parent_id = parent_thread_id_of(current)
      break unless parent_id

      current = @project.sequences.threads.find_by(id: parent_id)
    end
    path
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
