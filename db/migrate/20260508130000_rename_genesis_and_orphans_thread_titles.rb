# frozen_string_literal: true

class RenameGenesisAndOrphansThreadTitles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE sequences
      SET title = 'Genesis'
      WHERE kind = 'thread' AND is_genesis IS TRUE
        AND title IN ('Genesis thread', 'Genesis Thread');
    SQL
    execute <<~SQL.squish
      UPDATE sequences
      SET title = 'Orphans'
      WHERE kind = 'thread' AND is_orphans IS TRUE
        AND title IN ('Orphans thread', 'Orphans Thread');
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE sequences
      SET title = 'Genesis thread'
      WHERE kind = 'thread' AND is_genesis IS TRUE AND title = 'Genesis';
    SQL
    execute <<~SQL.squish
      UPDATE sequences
      SET title = 'Orphans thread'
      WHERE kind = 'thread' AND is_orphans IS TRUE AND title = 'Orphans';
    SQL
  end
end
