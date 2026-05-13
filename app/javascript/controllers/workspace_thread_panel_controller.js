import { Controller } from "@hotwired/stimulus"
import { THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS } from "thread_panel_index_drag"

const DEFAULT_KEY = "promptlab.workspaceThreadPanelMaximized"

/** Index column + optional editor column; persisted expand/collapse. */
export default class extends Controller {
  static targets = ["editorColumn", "collapseBtn", "expandBtn"]
  static values = {
    expanded: { type: Boolean, default: true },
    storageKey: { type: String, default: DEFAULT_KEY }
  }

  connect() {
    this.boundRevealFrame = this.onRevealFrame.bind(this)
    this.boundFontSizeApplied = this.onFontSizeApplied.bind(this)
    this.element.addEventListener("workspace-thread-panel:reveal-frame", this.boundRevealFrame)
    document.addEventListener("workspace-font-size:applied", this.boundFontSizeApplied)
    try {
      const raw = window.localStorage.getItem(this.storageKeyValue)
      if (raw === "true") this.expandedValue = true
      else if (raw === "false") this.expandedValue = false
    } catch (_) {
      /* ignore */
    }
    this.syncUi()
  }

  disconnect() {
    this.element.removeEventListener("workspace-thread-panel:reveal-frame", this.boundRevealFrame)
    document.removeEventListener("workspace-font-size:applied", this.boundFontSizeApplied)
  }

  onFontSizeApplied() {
    this.clampAncestorHorizontalScroll()
  }

  onRevealFrame(event) {
    const { frameId, scrollWithinFrameId } = event.detail || {}
    if (!frameId) return
    this.expandAndScrollToFrame(frameId, scrollWithinFrameId)
  }

  expandAndScrollToFrame(frameId, scrollWithinFrameId) {
    this.expandedValue = true
    const scroll = () => {
      const frame =
        (typeof frameId === "string" && this.element.querySelector(`#${CSS.escape(frameId)}`)) ||
        (typeof frameId === "string" ? document.getElementById(frameId) : null)
      const scrollOuter = frame?.closest(".workspace-thread-editor-child") || frame
      scrollOuter?.scrollIntoView({ behavior: "smooth", block: "start" })
      if (!scrollWithinFrameId || !frame) return
      const scrollInner = () => {
        const inner = frame.querySelector(`#${CSS.escape(scrollWithinFrameId)}`)
        inner?.scrollIntoView({ behavior: "smooth", block: "nearest" })
      }
      scrollInner()
      frame.addEventListener("turbo:frame-load", scrollInner, { once: true })
      window.setTimeout(scrollInner, 400)
      window.setTimeout(scrollInner, 1100)
    }
    requestAnimationFrame(() => {
      requestAnimationFrame(scroll)
    })
  }

  collapse() {
    if (this.element.classList.contains(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)) return
    this.expandedValue = false
  }

  expand() {
    this.expandedValue = true
  }

  expandedValueChanged() {
    try {
      window.localStorage.setItem(this.storageKeyValue, String(this.expandedValue))
    } catch (_) {
      /* ignore */
    }
    this.syncUi()
  }

  syncUi() {
    this.element.classList.toggle("workspace-thread-panel-root--maximized", this.expandedValue)
    if (this.hasEditorColumnTarget) this.editorColumnTarget.hidden = !this.expandedValue

    if (this.hasCollapseBtnTarget)
      this.collapseBtnTarget.setAttribute("aria-pressed", !this.expandedValue ? "true" : "false")
    if (this.hasExpandBtnTarget)
      this.expandBtnTarget.setAttribute("aria-pressed", this.expandedValue ? "true" : "false")

    this.clampAncestorHorizontalScroll()
  }

  /** After width changes, drop stale scrollLeft so scrollbars do not retain slack range. */
  clampAncestorHorizontalScroll() {
    const run = () => {
      let el = this.element.parentElement
      while (el) {
        const { overflowX } = window.getComputedStyle(el)
        if (overflowX === "auto" || overflowX === "scroll") {
          const max = Math.max(0, el.scrollWidth - el.clientWidth)
          if (el.scrollLeft > max) el.scrollLeft = max
        }
        el = el.parentElement
      }
    }
    requestAnimationFrame(() => requestAnimationFrame(run))
  }
}
