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

ActiveRecord::Schema[8.1].define(version: 2026_05_09_143000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sequence_dependencies", force: :cascade do |t|
    t.bigint "anchor_sequence_id"
    t.bigint "child_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.bigint "parent_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["child_id"], name: "index_sequence_dependencies_on_child_id"
    t.index ["child_id"], name: "index_sequence_dependencies_unique_thread_branch_child", unique: true, where: "((kind)::text = 'thread_branch'::text)"
    t.index ["child_id"], name: "index_sequence_dependencies_unique_thread_step_bundle_child", unique: true, where: "((kind)::text = 'thread_step_bundle'::text)"
    t.index ["child_id"], name: "index_sequence_dependencies_unique_thread_step_sequence_child", unique: true, where: "((kind)::text = 'thread_step_sequence'::text)"
    t.index ["parent_id", "child_id"], name: "index_sequence_dependencies_unique_bundle_prerequisite_pair", unique: true, where: "((kind)::text = 'bundle_prerequisite'::text)"
    t.index ["parent_id", "kind"], name: "index_sequence_dependencies_on_parent_id_and_kind"
    t.index ["parent_id", "position"], name: "index_sequence_dependencies_unique_sequence_step_position", unique: true, where: "((kind)::text = 'sequence_step'::text)"
    t.index ["parent_id", "position"], name: "index_sequence_dependencies_unique_thread_branch_position", unique: true, where: "((kind)::text = 'thread_branch'::text)"
    t.index ["parent_id", "position"], name: "index_sequence_dependencies_unique_thread_step_bundle_position", unique: true, where: "((kind)::text = 'thread_step_bundle'::text)"
    t.index ["parent_id", "position"], name: "index_sequence_dependencies_unique_thread_step_sequence_positio", unique: true, where: "((kind)::text = 'thread_step_sequence'::text)"
  end

  create_table "sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "intent", null: false
    t.boolean "is_genesis", default: false, null: false
    t.boolean "is_orphans", default: false, null: false
    t.boolean "is_term", default: false, null: false
    t.string "kind", default: "sequence", null: false
    t.integer "position", null: false
    t.bigint "project_id", null: false
    t.jsonb "steps_data", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind", "position"], name: "index_sequences_on_project_id_kind_and_position", unique: true
    t.index ["project_id"], name: "index_sequences_on_project_id"
    t.index ["project_id"], name: "index_sequences_unique_genesis_thread_per_project", unique: true, where: "(((kind)::text = 'thread'::text) AND (is_genesis IS TRUE))"
    t.index ["project_id"], name: "index_sequences_unique_orphans_thread_per_project", unique: true, where: "(((kind)::text = 'thread'::text) AND (is_orphans IS TRUE))"
  end

  create_table "thread_nodes", force: :cascade do |t|
    t.integer "child_order", null: false
    t.bigint "child_thread_id", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_bundle_id"
    t.bigint "parent_generative_sequence_id"
    t.bigint "parent_thread_id", null: false
    t.datetime "updated_at", null: false
    t.index ["child_thread_id"], name: "index_thread_nodes_on_child_thread_id_unique", unique: true
    t.index ["parent_thread_id", "parent_generative_sequence_id", "child_order"], name: "index_thread_nodes_on_parent_anchor_child_order", unique: true
  end

  add_foreign_key "sequence_dependencies", "sequences", column: "anchor_sequence_id"
  add_foreign_key "sequence_dependencies", "sequences", column: "child_id"
  add_foreign_key "sequence_dependencies", "sequences", column: "parent_id"
  add_foreign_key "sequences", "projects"
  add_foreign_key "thread_nodes", "sequences", column: "child_thread_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_bundle_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_generative_sequence_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_thread_id"
end
