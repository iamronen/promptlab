import { Controller } from "@hotwired/stimulus"
import {
  getSequenceEditorReadonlyPreference,
  setSequenceEditorReadonlyPreference
} from "sequence_editor_mode_storage"

export default class extends Controller {
  static targets = ["modeReadonly", "modeEdit"]

  connect() {
    this.syncFromStorage = () => this.syncToggleFromPreference()
    this.broadcastModeToEditors = () => this.broadcastReadonlyPreferenceToEditors()
    document.addEventListener("turbo:load", this.syncFromStorage)
    document.addEventListener("turbo:frame-load", this.broadcastModeToEditors)
    this.syncToggleFromPreference()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.syncFromStorage)
    document.removeEventListener("turbo:frame-load", this.broadcastModeToEditors)
  }

  broadcastReadonlyPreferenceToEditors() {
    const pref = getSequenceEditorReadonlyPreference()
    if (pref === null) return
    document.dispatchEvent(
      new CustomEvent("sequence-editor:global-mode", { detail: { readonly: pref } })
    )
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
    document.dispatchEvent(
      new CustomEvent("sequence-editor:global-mode", { detail: { readonly } })
    )
  }

  updateToggleUi(readonly) {
    if (!this.hasModeReadonlyTarget || !this.hasModeEditTarget) return
    this.modeReadonlyTarget.setAttribute("aria-pressed", readonly ? "true" : "false")
    this.modeEditTarget.setAttribute("aria-pressed", readonly ? "false" : "true")
  }
}
