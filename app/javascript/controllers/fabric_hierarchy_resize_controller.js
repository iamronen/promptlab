import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "promptlab:fabricHierarchyPx"
const DEFAULT_PX = 320

export default class extends Controller {
  static targets = ["handle", "hierarchyPane"]

  connect() {
    this.dragging = false
    this.boundPointerMove = this.onPointerMove.bind(this)
    this.boundPointerUp = this.onPointerEnd.bind(this)
    this.keyboardStep = 8
    this.restoreWidth()
  }

  disconnect() {
    this.endDragListeners()
  }

  restoreWidth() {
    const n = Number.parseInt(localStorage.getItem(STORAGE_KEY), 10)
    if (!Number.isFinite(n) || n <= 0) return
    this.element.style.setProperty("--fabric-hierarchy-px", `${this.clamp(n)}px`)
  }

  clamp(px) {
    const min = 220
    const max = Math.min(520, Math.floor(window.innerWidth * 0.38))
    return Math.round(Math.min(max, Math.max(min, px)))
  }

  readHierarchyWidthPx() {
    if (this.hasHierarchyPaneTarget) {
      const w = Math.round(this.hierarchyPaneTarget.getBoundingClientRect().width)
      if (w > 0) return w
    }
    const raw = getComputedStyle(this.element).getPropertyValue("--fabric-hierarchy-px").trim()
    const num = Number.parseFloat(raw)
    return Number.isFinite(num) ? Math.round(num) : DEFAULT_PX
  }

  grab(event) {
    if (window.matchMedia("(max-width: 720px)").matches) return
    if (event.pointerType === "mouse" && event.button !== 0) return
    event.preventDefault()
    this.dragging = true
    this.startPointerX = event.clientX
    this.startWidthPx = this.readHierarchyWidthPx()
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"
    document.addEventListener("pointermove", this.boundPointerMove)
    document.addEventListener("pointerup", this.boundPointerUp, { capture: true })
    document.addEventListener("pointercancel", this.boundPointerUp, { capture: true })
  }

  onPointerMove(event) {
    if (!this.dragging) return
    const dx = event.clientX - this.startPointerX
    const next = this.clamp(this.startWidthPx + dx)
    this.element.style.setProperty("--fabric-hierarchy-px", `${next}px`)
  }

  onPointerEnd() {
    if (!this.dragging) return
    const w = this.clamp(this.readHierarchyWidthPx())
    this.element.style.setProperty("--fabric-hierarchy-px", `${w}px`)
    try {
      localStorage.setItem(STORAGE_KEY, String(w))
    } catch (_) {
      /* ignore */
    }
    this.endDragListeners()
  }

  endDragListeners() {
    if (!this.dragging) return
    this.dragging = false
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
    document.removeEventListener("pointermove", this.boundPointerMove)
    document.removeEventListener("pointerup", this.boundPointerUp, { capture: true })
    document.removeEventListener("pointercancel", this.boundPointerUp, { capture: true })
  }

  resetWidth(event) {
    event.preventDefault()
    this.element.style.removeProperty("--fabric-hierarchy-px")
    try {
      localStorage.removeItem(STORAGE_KEY)
    } catch (_) {
      /* ignore */
    }
  }

  keyResize(event) {
    const k = event.key
    if (k !== "ArrowLeft" && k !== "ArrowRight") return
    if (window.matchMedia("(max-width: 720px)").matches) return
    event.preventDefault()
    const current = this.readHierarchyWidthPx()
    const delta = k === "ArrowRight" ? this.keyboardStep : -this.keyboardStep
    const next = this.clamp(current + delta)
    this.element.style.setProperty("--fabric-hierarchy-px", `${next}px`)
    try {
      localStorage.setItem(STORAGE_KEY, String(next))
    } catch (_) {
      /* ignore */
    }
  }
}
