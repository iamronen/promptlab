import { Controller } from "@hotwired/stimulus"
import {
  getSequenceEditorReadonlyPreference,
  setSequenceEditorReadonlyPreference
} from "sequence_editor_mode_storage"

export default class extends Controller {
  static targets = ["modeReadonly", "modeEdit"]

  connect() {
    this.syncFromStorage = () => this.syncToggleFromPreference()
    document.addEventListener("turbo:load", this.syncFromStorage)
    this.syncToggleFromPreference()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.syncFromStorage)
  }

  syncToggleFromPreference() {
    const pref = getSequenceEditorReadonlyPreference()
    const readonly = pref === null ? true : pref
    this.updateToggleUi(readonly)
  }

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    const readonly = mode === "readonly"
    setSequenceEditorReadonlyPreference(readonly)
    this.updateToggleUi(readonly)
  }

  updateToggleUi(readonly) {
    if (!this.hasModeReadonlyTarget || !this.hasModeEditTarget) return
    this.modeReadonlyTarget.setAttribute("aria-pressed", readonly ? "true" : "false")
    this.modeEditTarget.setAttribute("aria-pressed", readonly ? "false" : "true")
  }
}
