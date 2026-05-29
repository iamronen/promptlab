# frozen_string_literal: true

module ShareJsonPayload
  extend ActiveSupport::Concern

  private

  def share_payload(thread)
    branch = FabricThreadTree.build_thread_branch(thread, [])
    included_ids = thread.included_descendant_threads.pluck(:public_id)

    {
      public_id: thread.public_id,
      thread_title: thread.title,
      share_public_name: thread.share_public_name,
      share_public_title: thread.share_public_title,
      share_state: thread.share_state,
      share_defined: thread.share_defined?,
      share_enabled: thread.share_state_enabled?,
      share_state_disabled: thread.share_state_disabled?,
      share_scope: thread.share_scope,
      share_tease: thread.share_tease,
      included_thread_public_ids: included_ids,
      descendant_threads: flat_descendant_threads(thread),
      breadcrumb: breadcrumb_payload_for(thread),
      thread_tree: serialize_thread_branch(branch)
    }
  end

  def flat_descendant_threads(thread)
    descendant_ids = FabricThreadTree.descendant_thread_ids_for(thread)
    descendants_by_id = @project.sequences.threads.where(id: descendant_ids).index_by(&:id)
    descendant_ids.filter_map do |id|
      t = descendants_by_id[id]
      next unless t

      { public_id: t.public_id, title: t.title }
    end
  end

  def breadcrumb_payload_for(thread)
    payload = thread.thread_workspace_breadcrumb_payload
    return { ellipsis: false, segments: [{ public_id: thread.public_id, title: thread.title, current: true }] } unless payload

    segments = payload.visible_segments.map do |seg|
      {
        public_id: seg.public_id,
        title: seg.title,
        current: seg.id == thread.id
      }
    end
    { ellipsis: payload.ellipsis, segments: segments }
  end

  def serialize_thread_branch(branch)
    return nil unless branch

    {
      public_id: branch.thread.public_id,
      title: branch.thread.title,
      children: branch.child_branches.filter_map { |child| serialize_thread_branch(child) }
    }
  end
end
