# Pin npm packages by running ./bin/importmap

pin "application"
pin "sequence_editor_mode_storage", to: "sequence_editor_mode_storage.js"
pin "thread_panel_index_drag", to: "thread_panel_index_drag.js"
pin "workspace_autosave", to: "workspace_autosave.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
