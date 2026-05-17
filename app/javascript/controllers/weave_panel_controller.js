import { Controller } from "@hotwired/stimulus"

// Thread strand tree: delegated to sequencing thread-workspace manager (see thread_workspace_controller).
export default class extends Controller {
  static values = { selectedId: Number }

  connect() {
    this.syncSelectionVisual()
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()

    const raw = event.currentTarget.dataset.threadId
    const id = parseInt(raw, 10)
    if (!id) return

    this.selectedIdValue = id
    this.syncSelectionVisual()

    window.dispatchEvent(new CustomEvent("thread-workspace:open", { detail: { threadId: id } }))
  }

  selectedIdValueChanged() {
    this.syncSelectionVisual()
  }

  syncSelectionVisual() {
    const selected = this.selectedIdValue
    this.element.querySelectorAll("[data-thread-id]").forEach((el) => {
      const tid = parseInt(el.dataset.threadId, 10)
      const on = tid === selected
      el.classList.toggle("is-selected", on)
      el.setAttribute("aria-pressed", on ? "true" : "false")
    })
  }
}
