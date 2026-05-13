import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Thread strand tree: select a strand and refresh the workspace (work panel + URL ?weave_thread=).
export default class extends Controller {
  static values = { selectedId: Number }

  connect() {
    this.syncSelectionVisual()
  }

  select(event) {
    const raw = event.currentTarget.dataset.threadId
    const id = parseInt(raw, 10)
    if (!id) return

    this.selectedIdValue = id
    this.syncSelectionVisual()

    const url = new URL(window.location.href)
    url.searchParams.set("weave_thread", String(id))
    url.searchParams.delete("thread_partner")
    Turbo.visit(url.toString(), { action: "replace" })
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
