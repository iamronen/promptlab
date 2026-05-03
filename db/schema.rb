# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_04_122201) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sequence_dependencies", force: :cascade do |t|
    t.bigint "child_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.bigint "parent_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["child_id"], name: "index_sequence_dependencies_on_child_id"
    t.index ["parent_id", "child_id"], name: "index_sequence_dependencies_unique_prerequisite_pair", unique: true, where: "((kind)::text = 'transformation_prerequisite'::text)"
    t.index ["parent_id", "kind"], name: "index_sequence_dependencies_on_parent_id_and_kind"
    t.index ["parent_id", "position"], name: "index_sequence_dependencies_unique_sequence_step_position", unique: true, where: "((kind)::text = 'sequence_step'::text)"
  end

  create_table "sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "intent", null: false
    t.boolean "is_term", default: false, null: false
    t.string "kind", default: "sequence", null: false
    t.integer "position", null: false
    t.bigint "project_id", null: false
    t.jsonb "steps_data", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind", "position"], name: "index_sequences_on_project_id_kind_and_position", unique: true
    t.index ["project_id"], name: "index_sequences_on_project_id"
  end

  add_foreign_key "sequence_dependencies", "sequences", column: "child_id"
  add_foreign_key "sequence_dependencies", "sequences", column: "parent_id"
  add_foreign_key "sequences", "projects"
end
