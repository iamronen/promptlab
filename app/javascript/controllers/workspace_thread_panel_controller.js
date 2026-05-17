import { Controller } from "@hotwired/stimulus"
import { loadThreadWorkspaceState } from "thread_workspace_storage"
import { THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS } from "thread_panel_index_drag"

const DEFAULT_KEY = "promptlab.workspaceThreadPanelMaximized"

/** Strip-level thread-workspace ancestor (hosts data-thread-workspace-project-id-value). */
function closestThreadWorkspaceRoot(el) {
  return /** @type {HTMLElement | null} */ (el?.closest?.('[data-controller~="thread-workspace"]'))
}

/** Index column + optional editor column; persisted expand/collapse. */
export default class extends Controller {
  static targets = ["editorColumn", "collapseBtn", "expandBtn", "browseBodiesCollapseBtn", "browseBodiesExpandBtn"]
  static values = {
    expanded: { type: Boolean, default: true },
    /** Strand editor: true = steps visible per sequence; false = title + intent only. */
    browseBodiesExpanded: { type: Boolean, default: true },
    storageKey: { type: String, default: DEFAULT_KEY },
    /** When true (thread-workspace-managed strip), persist expand/collapse via thread-workspace storage only. */
    managed: { type: Boolean, default: false }
  }

  connect() {
    /** Skip panel-expanded pings during initial hydrate (first paint stable). */
    this.suppressHydrationEmit = true
    this.boundRevealFrame = this.onRevealFrame.bind(this)
    this.boundFontSizeApplied = this.onFontSizeApplied.bind(this)
    this.element.addEventListener("workspace-thread-panel:reveal-frame", this.boundRevealFrame)
    document.addEventListener("workspace-font-size:applied", this.boundFontSizeApplied)
    if (this.managedValue) this.hydrateManagedExpandedFromThreadWorkspace()
    else {
      try {
        const raw = window.localStorage.getItem(this.storageKeyValue)
        if (raw === "true") this.expandedValue = true
        else if (raw === "false") this.expandedValue = false
      } catch (_) {
        /* ignore */
      }
    }
    this.syncUi()
    this.syncBrowseBodiesAttr()
    this.syncBrowseBodiesIndicator()
    queueMicrotask(() => {
      this.suppressHydrationEmit = false
    })
  }

  disconnect() {
    this.element.removeEventListener("workspace-thread-panel:reveal-frame", this.boundRevealFrame)
    document.removeEventListener("workspace-font-size:applied", this.boundFontSizeApplied)
  }

  /** Managed strip: expanded comes from thread-workspace localStorage synchronously — avoids SSR true vs deferred sync false toggling the UI repeatedly. */
  hydrateManagedExpandedFromThreadWorkspace() {
    const col = this.element.closest("[data-thread-panel-id]")
    const id = parseInt(col?.dataset?.threadPanelId || "0", 10)
    const mgrEl = closestThreadWorkspaceRoot(this.element)
    const proj = parseInt(mgrEl?.dataset?.threadWorkspaceProjectIdValue || "0", 10)
    if (!id || !proj) return
    try {
      const saved = loadThreadWorkspaceState(proj)
      const row = saved?.panels?.find((p) => p.id === id)
      if (!row || typeof row.expanded !== "boolean") return
      if (this.expandedValue !== row.expanded) this.expandedValue = !!row.expanded
    } catch (_) {
      /* ignore */
    }
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

  browseBodiesCollapseAll() {
    if (this.element.classList.contains(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)) return
    this.browseBodiesExpandedValue = false
  }

  browseBodiesExpandAll() {
    if (this.element.classList.contains(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)) return
    this.browseBodiesExpandedValue = true
  }

  browseBodiesExpandedValueChanged() {
    this.syncBrowseBodiesAttr()
    this.syncBrowseBodiesIndicator()
    this.element.dispatchEvent(
      new CustomEvent("thread-editor-browse-bodies-changed", {
        bubbles: true,
        detail: { expanded: this.browseBodiesExpandedValue }
      })
    )
  }

  syncBrowseBodiesAttr() {
    this.element.setAttribute("data-thread-browse-bodies-expanded", this.browseBodiesExpandedValue ? "true" : "false")
  }

  syncBrowseBodiesIndicator() {
    if (this.hasBrowseBodiesCollapseBtnTarget)
      this.browseBodiesCollapseBtnTarget.setAttribute(
        "aria-pressed",
        !this.browseBodiesExpandedValue ? "true" : "false"
      )
    if (this.hasBrowseBodiesExpandBtnTarget)
      this.browseBodiesExpandBtnTarget.setAttribute(
        "aria-pressed",
        this.browseBodiesExpandedValue ? "true" : "false"
      )
  }

  expandedValueChanged() {
    if (!this.managedValue) {
      try {
        window.localStorage.setItem(this.storageKeyValue, String(this.expandedValue))
      } catch (_) {
        /* ignore */
      }
    }
    this.syncUi()
    const skipEmit = !this.managedValue || this.suppressHydrationEmit === true
    if (!skipEmit) {
      const col = this.element.closest("[data-thread-panel-id]")
      const id = parseInt(col?.dataset?.threadPanelId || "0", 10)
      if (id > 0) {
        this.element.dispatchEvent(
          new CustomEvent("thread-workspace:panel-expanded", {
            bubbles: true,
            detail: { panelId: id, expanded: this.expandedValue }
          })
        )
      }
    }
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
