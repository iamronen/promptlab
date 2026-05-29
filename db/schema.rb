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

ActiveRecord::Schema[8.1].define(version: 2026_05_29_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_process_taxonomy_id"
    t.text "description"
    t.string "name", null: false
    t.string "public_id", limit: 24, null: false
    t.boolean "sharing_allowed", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["default_process_taxonomy_id"], name: "index_projects_on_default_process_taxonomy_id"
    t.index ["public_id"], name: "index_projects_on_public_id", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
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

  create_table "sequence_share_inclusions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "included_sequence_id", null: false
    t.bigint "root_sequence_id", null: false
    t.datetime "updated_at", null: false
    t.index ["included_sequence_id"], name: "index_sequence_share_inclusions_on_included_sequence_id"
    t.index ["root_sequence_id", "included_sequence_id"], name: "index_sequence_share_inclusions_on_root_and_included", unique: true
    t.index ["root_sequence_id"], name: "index_sequence_share_inclusions_on_root_sequence_id"
  end

  create_table "sequences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.text "intent", null: false
    t.boolean "is_genesis", default: false, null: false
    t.boolean "is_orphans", default: false, null: false
    t.boolean "is_term", default: false, null: false
    t.string "kind", default: "sequence", null: false
    t.integer "position", null: false
    t.bigint "project_id", null: false
    t.string "public_id", limit: 24, null: false
    t.string "share_public_name"
    t.string "share_scope", default: "everything", null: false
    t.string "share_state", default: "none", null: false
    t.boolean "share_tease", default: false, null: false
    t.jsonb "steps_data", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_sequences_on_created_by_id"
    t.index ["project_id", "kind", "position"], name: "index_sequences_on_project_id_kind_and_position", unique: true
    t.index ["project_id"], name: "index_sequences_on_project_id"
    t.index ["project_id"], name: "index_sequences_unique_genesis_thread_per_project", unique: true, where: "(((kind)::text = 'thread'::text) AND (is_genesis IS TRUE))"
    t.index ["project_id"], name: "index_sequences_unique_orphans_thread_per_project", unique: true, where: "(((kind)::text = 'thread'::text) AND (is_orphans IS TRUE))"
    t.index ["public_id"], name: "index_sequences_on_public_id", unique: true
    t.index ["share_state"], name: "index_sequences_on_share_state_enabled", where: "((share_state)::text = 'enabled'::text)"
  end

  create_table "taxonomies", force: :cascade do |t|
    t.boolean "applies_to_bundle_pipeline_sequences", default: false, null: false
    t.boolean "applies_to_bundles", default: false, null: false
    t.boolean "applies_to_sequences", default: true, null: false
    t.string "cardinality", null: false
    t.datetime "created_at", null: false
    t.bigint "default_taxonomy_term_id"
    t.boolean "default_value_enabled", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.boolean "process_tracking", default: false, null: false
    t.bigint "project_id", null: false
    t.string "single_select_ui"
    t.datetime "updated_at", null: false
    t.index "project_id, lower((name)::text)", name: "index_taxonomies_on_project_id_lower_name", unique: true
    t.index ["default_taxonomy_term_id"], name: "index_taxonomies_on_default_taxonomy_term_id"
    t.index ["project_id"], name: "index_taxonomies_on_project_id"
  end

  create_table "taxonomy_assignment_histories", force: :cascade do |t|
    t.datetime "assigned_at", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at", null: false
    t.string "label_snapshot", null: false
    t.bigint "project_id", null: false
    t.bigint "sequence_id", null: false
    t.bigint "taxonomy_id", null: false
    t.bigint "taxonomy_term_id"
    t.datetime "updated_at", null: false
    t.index ["project_id", "taxonomy_id"], name: "index_taxonomy_assignment_histories_on_project_taxonomy"
    t.index ["project_id"], name: "index_taxonomy_assignment_histories_on_project_id"
    t.index ["sequence_id", "taxonomy_id", "assigned_at"], name: "index_taxonomy_assignment_histories_on_seq_tax_assigned"
    t.index ["sequence_id"], name: "index_taxonomy_assignment_histories_on_sequence_id"
    t.index ["taxonomy_id"], name: "index_taxonomy_assignment_histories_on_taxonomy_id"
    t.index ["taxonomy_term_id"], name: "index_taxonomy_assignment_histories_on_taxonomy_term_id"
  end

  create_table "taxonomy_assignments", force: :cascade do |t|
    t.datetime "assigned_at", null: false
    t.datetime "created_at", null: false
    t.string "label_snapshot", null: false
    t.bigint "project_id", null: false
    t.bigint "sequence_id", null: false
    t.boolean "single_value_taxonomy_copy", null: false
    t.bigint "taxonomy_id", null: false
    t.bigint "taxonomy_term_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "taxonomy_id"], name: "index_taxonomy_assignments_on_project_id_and_taxonomy_id"
    t.index ["project_id"], name: "index_taxonomy_assignments_on_project_id"
    t.index ["sequence_id", "taxonomy_id"], name: "index_taxonomy_assignments_unique_single_taxonomy", unique: true, where: "(single_value_taxonomy_copy = true)"
    t.index ["sequence_id", "taxonomy_term_id"], name: "index_taxonomy_assignments_unique_sequence_term", unique: true
    t.index ["sequence_id"], name: "index_taxonomy_assignments_on_sequence_id"
    t.index ["taxonomy_id", "taxonomy_term_id"], name: "index_taxonomy_assignments_on_taxonomy_id_and_taxonomy_term_id"
    t.index ["taxonomy_id"], name: "index_taxonomy_assignments_on_taxonomy_id"
    t.index ["taxonomy_term_id"], name: "index_taxonomy_assignments_on_taxonomy_term_id"
  end

  create_table "taxonomy_exclusion_rule_terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "taxonomy_exclusion_rule_id", null: false
    t.bigint "taxonomy_term_id", null: false
    t.datetime "updated_at", null: false
    t.index ["taxonomy_exclusion_rule_id", "taxonomy_term_id"], name: "index_taxonomy_exclusion_rule_terms_on_rule_and_term", unique: true
    t.index ["taxonomy_exclusion_rule_id"], name: "idx_on_taxonomy_exclusion_rule_id_e5b1d7c588"
    t.index ["taxonomy_term_id"], name: "index_taxonomy_exclusion_rule_terms_on_taxonomy_term_id"
  end

  create_table "taxonomy_exclusion_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "excluding_taxonomy_id", null: false
    t.bigint "project_id", null: false
    t.bigint "taxonomy_id", null: false
    t.datetime "updated_at", null: false
    t.index ["excluding_taxonomy_id"], name: "index_taxonomy_exclusion_rules_on_excluding_taxonomy_id"
    t.index ["project_id"], name: "index_taxonomy_exclusion_rules_on_project_id"
    t.index ["taxonomy_id", "excluding_taxonomy_id"], name: "index_taxonomy_exclusion_rules_on_taxonomy_and_excluding", unique: true
    t.index ["taxonomy_id"], name: "index_taxonomy_exclusion_rules_on_taxonomy_id"
  end

  create_table "taxonomy_terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.integer "position", null: false
    t.boolean "process_end_state", default: false, null: false
    t.bigint "taxonomy_id", null: false
    t.datetime "updated_at", null: false
    t.index ["taxonomy_id", "position"], name: "index_taxonomy_terms_on_taxonomy_id_and_position", unique: true
    t.index ["taxonomy_id"], name: "index_taxonomy_terms_on_taxonomy_id"
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

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "public_id", limit: 24, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "projects", "taxonomies", column: "default_process_taxonomy_id", on_delete: :nullify
  add_foreign_key "projects", "users"
  add_foreign_key "sequence_dependencies", "sequences", column: "anchor_sequence_id"
  add_foreign_key "sequence_dependencies", "sequences", column: "child_id"
  add_foreign_key "sequence_dependencies", "sequences", column: "parent_id"
  add_foreign_key "sequence_share_inclusions", "sequences", column: "included_sequence_id", on_delete: :cascade
  add_foreign_key "sequence_share_inclusions", "sequences", column: "root_sequence_id", on_delete: :cascade
  add_foreign_key "sequences", "projects"
  add_foreign_key "sequences", "users", column: "created_by_id"
  add_foreign_key "taxonomies", "projects"
  add_foreign_key "taxonomies", "taxonomy_terms", column: "default_taxonomy_term_id", on_delete: :nullify
  add_foreign_key "taxonomy_assignment_histories", "projects"
  add_foreign_key "taxonomy_assignment_histories", "sequences"
  add_foreign_key "taxonomy_assignment_histories", "taxonomies"
  add_foreign_key "taxonomy_assignment_histories", "taxonomy_terms", on_delete: :nullify
  add_foreign_key "taxonomy_assignments", "projects"
  add_foreign_key "taxonomy_assignments", "sequences"
  add_foreign_key "taxonomy_assignments", "taxonomies"
  add_foreign_key "taxonomy_assignments", "taxonomy_terms", on_delete: :restrict
  add_foreign_key "taxonomy_exclusion_rule_terms", "taxonomy_exclusion_rules", on_delete: :cascade
  add_foreign_key "taxonomy_exclusion_rule_terms", "taxonomy_terms", on_delete: :cascade
  add_foreign_key "taxonomy_exclusion_rules", "projects", on_delete: :cascade
  add_foreign_key "taxonomy_exclusion_rules", "taxonomies", column: "excluding_taxonomy_id", on_delete: :cascade
  add_foreign_key "taxonomy_exclusion_rules", "taxonomies", on_delete: :cascade
  add_foreign_key "taxonomy_terms", "taxonomies"
  add_foreign_key "thread_nodes", "sequences", column: "child_thread_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_bundle_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_generative_sequence_id"
  add_foreign_key "thread_nodes", "sequences", column: "parent_thread_id"
end
