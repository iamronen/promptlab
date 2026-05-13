import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "promptlab:workspaceFontSizeV2"

const LEVELS = {
  sm: 0.875,
  md: 1,
  lg: 1.125
}

export default class extends Controller {
  static targets = ["scaleRoot", "tierSm", "tierMd", "tierLg"]

  connect() {
    this.restoreAndApply()
  }

  restoreAndApply() {
    let level = "md"
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      if (raw === "sm" || raw === "md" || raw === "lg") level = raw
    } catch (_) {
      /* ignore */
    }
    this.applyLevel(level)
  }

  setSize(event) {
    const level = event.params.size
    if (level !== "sm" && level !== "md" && level !== "lg") return
    try {
      window.localStorage.setItem(STORAGE_KEY, level)
    } catch (_) {
      /* ignore */
    }
    this.applyLevel(level)
  }

  applyLevel(level) {
    if (!this.hasScaleRootTarget) return

    const scale = LEVELS[level]
    if (scale === 1) {
      this.scaleRootTarget.style.removeProperty("zoom")
    } else {
      this.scaleRootTarget.style.zoom = String(scale)
    }

    this.syncTierButtons(level)

    this.scaleRootTarget.dispatchEvent(
      new CustomEvent("workspace-font-size:applied", {
        bubbles: true,
        detail: { scale, level }
      })
    )

    this.scheduleClampHorizontalScroll()
  }

  syncTierButtons(level) {
    if (this.hasTierSmTarget) this.tierSmTarget.setAttribute("aria-pressed", level === "sm" ? "true" : "false")
    if (this.hasTierMdTarget) this.tierMdTarget.setAttribute("aria-pressed", level === "md" ? "true" : "false")
    if (this.hasTierLgTarget) this.tierLgTarget.setAttribute("aria-pressed", level === "lg" ? "true" : "false")
  }

  scheduleClampHorizontalScroll() {
    const run = () => {
      if (!this.hasScaleRootTarget) return
      let el = this.scaleRootTarget
      while (el) {
        const { overflowX } = window.getComputedStyle(el)
        if (overflowX === "auto" || overflowX === "scroll") {
          const max = Math.max(0, el.scrollWidth - el.clientWidth)
          if (el.scrollLeft > max) el.scrollLeft = max
        }
        el = el.parentElement
      }
    }
    window.requestAnimationFrame(() => window.requestAnimationFrame(run))
  }
}
