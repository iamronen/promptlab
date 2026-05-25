import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "anchor"]

  connect() {
    this.boundCloseOnOutside = this.closeOnOutside.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
  }

  disconnect() {
    this.removeDocumentListeners()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.panelTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.boundCloseOnOutside)
    document.addEventListener("keydown", this.boundCloseOnEscape)
  }

  close() {
    if (!this.hasPanelTarget) return

    this.panelTarget.hidden = true
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
    this.removeDocumentListeners()
  }

  closeOnOutside(event) {
    if (this.anchorTarget.contains(event.target)) return
    this.close()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }

  removeDocumentListeners() {
    document.removeEventListener("click", this.boundCloseOnOutside)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
  }
}
