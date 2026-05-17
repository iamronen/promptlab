# Pin npm packages by running ./bin/importmap

pin "application"
pin "sequence_editor_mode_storage", to: "sequence_editor_mode_storage.js"
pin "thread_panel_index_drag", to: "thread_panel_index_drag.js"
pin "thread_branch_indicator_alignment", to: "thread_branch_indicator_alignment.js"
pin "workspace_autosave", to: "workspace_autosave.js"
pin "thread_workspace_storage", to: "thread_workspace_storage.js"
pin "thread_workspace_reconcile", to: "thread_workspace_reconcile.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
