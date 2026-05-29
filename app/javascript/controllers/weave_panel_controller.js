import { Controller } from "@hotwired/stimulus"

// Thread strand tree: delegated to sequencing thread-workspace manager (see thread_workspace_controller).
export default class extends Controller {
  static values = { selectedId: String }

  connect() {
    this.syncSelectionVisual()
    this.boundFrameLoad = this.onFabricPanelFrameLoad.bind(this)
    document.addEventListener("turbo:frame-load", this.boundFrameLoad)
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.boundFrameLoad)
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()

    const id = event.currentTarget.dataset.threadId?.trim()
    if (!id) return

    this.selectedIdValue = id
    this.syncSelectionVisual()

    window.dispatchEvent(new CustomEvent("thread-workspace:open", { detail: { threadId: id } }))
  }

  onFabricPanelFrameLoad(event) {
    const frame = /** @type {HTMLElement | undefined} */ (event.target)
    if (frame?.id !== "fabric_thread_panel") return

    const url = new URL(window.location.href)
    const id = url.searchParams.get("weave_thread")?.trim()
    if (!id) return

    this.selectedIdValue = id
  }

  selectedIdValueChanged() {
    this.syncSelectionVisual()
  }

  syncSelectionVisual() {
    const selected = this.selectedIdValue
    this.element.querySelectorAll("[data-thread-id]").forEach((el) => {
      const tid = el.dataset.threadId?.trim()
      const on = tid === selected
      el.classList.toggle("is-selected", on)
      el.setAttribute("aria-pressed", on ? "true" : "false")
      if (el.tagName === "A") {
        if (on) el.setAttribute("aria-current", "page")
        else el.removeAttribute("aria-current")
      }
    })
  }
}
