# frozen_string_literal: true

class BackfillBundleTitlesFromFirstPipelineSequence < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Sequence.where(kind: "bundle").find_each do |bundle|
      ids = Array.wrap(bundle.read_attribute(:steps_data)).filter_map do |raw|
        next unless raw.is_a?(Hash)

        sid = raw.stringify_keys["sequence_id"]
        sid.present? ? sid.to_i : nil
      end
      next if ids.empty?

      first = Sequence.find_by(id: ids.first, project_id: bundle.project_id, kind: "sequence")
      next unless first

      bundle.update_column(:title, first.title.to_s)
    end
  end

  def down
  end
end
