import { Controller } from "@hotwired/stimulus"

const STORAGE_LEFT = "promptlab:workspaceLeftPanePx"
const STORAGE_RIGHT = "promptlab:workspaceRightPanePx"

export default class extends Controller {
  static targets = ["leftHandle", "rightHandle"]

  connect() {
    this.gridEl =
      this.element.classList.contains("workspace--three-pane") || this.element.classList.contains("workspace--two-pane")
        ? this.element
        : null
    if (!this.gridEl) return
    this.boundPointerMove = this.onPointerMove.bind(this)
    this.boundPointerUp = this.onPointerEnd.bind(this)
    this.restoreWidths()
    this.keyboardStep = 8
  }

  disconnect() {
    this.endDrag()
  }

  restoreWidths() {
    const l = Number.parseInt(localStorage.getItem(STORAGE_LEFT), 10)
    const r = Number.parseInt(localStorage.getItem(STORAGE_RIGHT), 10)
    if (Number.isFinite(l) && l > 0) this.gridEl.style.setProperty("--ws-left-px", `${l}px`)
    if (Number.isFinite(r) && r > 0) this.gridEl.style.setProperty("--ws-right-px", `${r}px`)
  }

  parsePx(label) {
    const raw = getComputedStyle(this.gridEl).getPropertyValue(label).trim()
    const n = Number.parseFloat(raw)
    return Number.isFinite(n) ? n : null
  }

  readLeftPx() {
    return this.parsePx("--ws-left-px") ?? 246
  }

  readRightPx() {
    return this.parsePx("--ws-right-px") ?? 320
  }

  clampLeft(px) {
    const min = 180
    const max = Math.min(520, Math.floor(window.innerWidth * 0.48))
    return Math.round(Math.min(max, Math.max(min, px)))
  }

  clampRight(px) {
    const min = 220
    const max = Math.min(640, Math.floor(window.innerWidth * 0.48))
    return Math.round(Math.min(max, Math.max(min, px)))
  }

  persist() {
    localStorage.setItem(STORAGE_LEFT, String(this.readLeftPx()))
    localStorage.setItem(STORAGE_RIGHT, String(this.readRightPx()))
  }

  grabLeft(event) {
    if (event.pointerType === "mouse" && event.button !== 0) return
    if (this.startDrag("left", event.clientX)) {
      event.preventDefault()
      this.startLeftPx = this.readLeftPx()
    }
  }

  grabRight(event) {
    if (event.pointerType === "mouse" && event.button !== 0) return
    if (this.startDrag("right", event.clientX)) {
      event.preventDefault()
      this.startRightPx = this.readRightPx()
    }
  }

  startDrag(edge, clientX) {
    if (!this.gridEl || window.matchMedia("(max-width: 720px)").matches) return false
    this.dragEdge = edge
    this.startPointerX = clientX
    document.body.style.cursor = "col-resize"
    document.body.style.userSelect = "none"
    document.addEventListener("pointermove", this.boundPointerMove)
    document.addEventListener("pointerup", this.boundPointerUp, { capture: true })
    document.addEventListener("pointercancel", this.boundPointerUp, { capture: true })
    return true
  }

  onPointerMove(event) {
    if (!this.dragEdge) return
    const dx = event.clientX - this.startPointerX
    if (this.dragEdge === "left") {
      const next = this.clampLeft(this.startLeftPx + dx)
      this.gridEl.style.setProperty("--ws-left-px", `${next}px`)
    } else {
      // Right column's handle is its left edge: pointer right narrows (--ws-right-px decreases).
      const next = this.clampRight(this.startRightPx - dx)
      this.gridEl.style.setProperty("--ws-right-px", `${next}px`)
    }
  }

  onPointerEnd() {
    if (!this.dragEdge) return
    this.persist()
    this.endDrag()
  }

  endDrag() {
    this.dragEdge = null
    document.body.style.cursor = ""
    document.body.style.userSelect = ""
    document.removeEventListener("pointermove", this.boundPointerMove)
    document.removeEventListener("pointerup", this.boundPointerUp, { capture: true })
    document.removeEventListener("pointercancel", this.boundPointerUp, { capture: true })
  }

  resetWidths() {
    if (!this.gridEl) return
    this.gridEl.style.removeProperty("--ws-left-px")
    this.gridEl.style.removeProperty("--ws-right-px")
    localStorage.removeItem(STORAGE_LEFT)
    localStorage.removeItem(STORAGE_RIGHT)
  }

  keyLeft(event) {
    const k = event.key
    if (k !== "ArrowLeft" && k !== "ArrowRight") return
    event.preventDefault()
    const delta = k === "ArrowLeft" ? this.keyboardStep : -this.keyboardStep
    const next = this.clampLeft(this.readLeftPx() + delta)
    this.gridEl.style.setProperty("--ws-left-px", `${next}px`)
    this.persist()
  }

  keyRight(event) {
    const k = event.key
    if (k !== "ArrowLeft" && k !== "ArrowRight") return
    event.preventDefault()
    // Align with drag: ArrowLeft widens assistant; ArrowRight narrows it.
    const delta = k === "ArrowRight" ? -this.keyboardStep : this.keyboardStep
    const next = this.clampRight(this.readRightPx() + delta)
    this.gridEl.style.setProperty("--ws-right-px", `${next}px`)
    this.persist()
  }
}
