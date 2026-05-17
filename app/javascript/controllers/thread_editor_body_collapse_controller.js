import { Controller } from "@hotwired/stimulus"

/** Thread embed only: collapses sequence/bundle bodies to title + intent (per-row toggle + strand header “browse all”). */
export default class extends Controller {
  static targets = ["toggle"]

  static values = {
    expanded: { type: Boolean, default: true }
  }

  connect() {
    this.panelEl = /** @type {HTMLElement | null} */ (this.element.closest('[data-controller~="workspace-thread-panel"]'))
    this.boundBrowseAll = this.onBrowseAllBodies.bind(this)
    this.panelEl?.addEventListener("thread-editor-browse-bodies-changed", this.boundBrowseAll)
    const raw = this.panelEl?.getAttribute("data-thread-browse-bodies-expanded")
    if (raw === "true") this.expandedValue = true
    else if (raw === "false") this.expandedValue = false
  }

  disconnect() {
    this.panelEl?.removeEventListener("thread-editor-browse-bodies-changed", this.boundBrowseAll)
  }

  onBrowseAllBodies(event) {
    if (!this.panelEl || event.target !== this.panelEl) return
    const next = !!event.detail?.expanded
    if (this.expandedValue === next) return
    this.expandedValue = next
  }

  toggle(event) {
    event.preventDefault()
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    const next = this.expandedValue
    this.element.classList.toggle("thread-editor-body-collapsed", !next)
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(next))
    this.element.dispatchEvent(
      new CustomEvent("thread-editor-sequence-body-toggled", {
        bubbles: true,
        detail: { expanded: next }
      })
    )
  }
}
