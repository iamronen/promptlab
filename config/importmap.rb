# Pin npm packages by running ./bin/importmap

pin "application"
pin "sequence_editor_mode_storage", to: "sequence_editor_mode_storage.js"
pin "sequence_copy_text", to: "sequence_copy_text.js"
pin "sequence_step_content", to: "sequence_step_content.js"
pin "text_input_sanitizer", to: "text_input_sanitizer.js"
pin "thread_panel_index_drag", to: "thread_panel_index_drag.js"
pin "thread_branch_indicator_alignment", to: "thread_branch_indicator_alignment.js"
pin "workspace_autosave", to: "workspace_autosave.js"
pin "thread_workspace_storage", to: "thread_workspace_storage.js"
pin "thread_workspace_reconcile", to: "thread_workspace_reconcile.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Explicit pins so new sharing controllers appear after importmap/propshaft cache refresh.
pin "controllers/thread_share_controller", to: "controllers/thread_share_controller.js"
pin "controllers/project_sharing_controller", to: "controllers/project_sharing_controller.js"
pin "controllers/project_share_card_menu_controller", to: "controllers/project_share_card_menu_controller.js"
pin "controllers/thread_strand_panel_controller", to: "controllers/thread_strand_panel_controller.js"
