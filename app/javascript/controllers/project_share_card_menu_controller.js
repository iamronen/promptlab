import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]

  connect() {
    this.boundDoc = this.onDocumentClick.bind(this)
    this.boundKey = this.onKeydown.bind(this)
    document.addEventListener("click", this.boundDoc)
    document.addEventListener("keydown", this.boundKey)
  }

  disconnect() {
    document.removeEventListener("click", this.boundDoc)
    document.removeEventListener("keydown", this.boundKey)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const opening = !!this.panelTarget.hidden
    document.querySelectorAll(".fabric-thread-menu-panel").forEach((el) => {
      el.hidden = true
    })
    document.querySelectorAll("[data-project-share-card-menu-target='trigger']").forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
    this.panelTarget.hidden = !opening
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", opening ? "true" : "false")
    }
  }

  close(event) {
    event?.preventDefault()
    this.hide()
  }

  stopPanelBubble(event) {
    event.stopPropagation()
  }

  onDocumentClick(event) {
    if (this.element.contains(event.target)) return
    this.hide()
  }

  onKeydown(event) {
    if (event.key !== "Escape") return
    this.hide()
  }

  hide() {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
  }
}
