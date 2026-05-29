import { Controller } from "@hotwired/stimulus"
import { loadThreadWorkspaceState, parsePanelLayoutMode, parseStandaloneLayoutMode, normalizeThreadPublicId } from "thread_workspace_storage"
import { THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS, scrollIntoEditorStack, resolveEditorFrame } from "thread_panel_index_drag"

const DEFAULT_KEY = "promptlab.workspaceThreadPanelMaximized"

/** Strip-level thread-workspace ancestor (hosts data-thread-workspace-project-id-value). */
function closestThreadWorkspaceRoot(el) {
  return /** @type {HTMLElement | null} */ (el?.closest?.('[data-controller~="thread-workspace"]'))
}

/** Index column + optional editor column; persisted layout mode. */
export default class extends Controller {
  static targets = [
    "editorColumn",
    "indexColumn",
    "indexModeBtn",
    "splitModeBtn",
    "editorModeBtn",
    "browseBodiesCollapseBtn",
    "browseBodiesExpandBtn",
    "browseControls",
    "toolbar"
  ]
  static values = {
    layoutMode: { type: String, default: "split" },
    /** Strand editor: true = steps visible per sequence; false = title + intent only. */
    browseBodiesExpanded: { type: Boolean, default: true },
    storageKey: { type: String, default: DEFAULT_KEY },
    /** When true (thread-workspace-managed strip), persist layout via thread-workspace storage only. */
    managed: { type: Boolean, default: false }
  }

  connect() {
    /** Skip panel-expanded pings during initial hydrate (first paint stable). */
    this.suppressHydrationEmit = true
    this.boundRevealFrame = this.onRevealFrame.bind(this)
    this.boundFontSizeApplied = this.onFontSizeApplied.bind(this)
    this.element.addEventListener("workspace-thread-panel:reveal-frame", this.boundRevealFrame)
    document.addEventListener("workspace-font-size:applied", this.boundFontSizeApplied)
    if (this.managedValue) this.hydrateManagedLayoutFromThreadWorkspace()
    else {
      try {
        const raw = window.localStorage.getItem(this.storageKeyValue)
        const mode = parseStandaloneLayoutMode(raw)
        if (mode) this.layoutModeValue = mode
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

  /** Managed strip: layout mode comes from thread-workspace localStorage synchronously — avoids SSR vs deferred sync toggling the UI repeatedly. */
  hydrateManagedLayoutFromThreadWorkspace() {
    const col = this.element.closest("[data-thread-panel-id]")
    const id = normalizeThreadPublicId(col?.dataset?.threadPanelId)
    const mgrEl = closestThreadWorkspaceRoot(this.element)
    const proj = parseInt(mgrEl?.dataset?.threadWorkspaceProjectIdValue || "0", 10)
    if (!id || !proj) return
    try {
      const saved = loadThreadWorkspaceState(proj)
      const row = saved?.panels?.find((p) => p.id === id)
      if (!row) return
      const mode = parsePanelLayoutMode(row)
      if (this.layoutModeValue !== mode) this.layoutModeValue = mode
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
    this.layoutModeValue = "split"
    const scroll = () => {
      const frame =
        resolveEditorFrame(this.element, { frameId }) ??
        (typeof frameId === "string" ? document.getElementById(frameId) : null)
      const scrollOuter = frame?.closest(".workspace-thread-editor-child") || frame
      const inner =
        scrollWithinFrameId && frame
          ? frame.querySelector(`#${CSS.escape(scrollWithinFrameId)}`)
          : null
      const target = inner || scrollOuter
      if (!target) return

      scrollIntoEditorStack(target)

      if (!scrollWithinFrameId || !frame) return
      const scrollInner = () => {
        const el = frame.querySelector(`#${CSS.escape(scrollWithinFrameId)}`)
        if (el) scrollIntoEditorStack(el)
      }
      scrollInner()
      frame.addEventListener("turbo:frame-load", scrollInner, { once: true })
      window.setTimeout(scrollInner, 400)
      window.setTimeout(scrollInner, 1100)
    }
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        requestAnimationFrame(scroll)
      })
    })
  }

  setLayoutIndex() {
    if (this.element.classList.contains(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)) return
    this.layoutModeValue = "index"
  }

  setLayoutSplit() {
    this.layoutModeValue = "split"
  }

  setLayoutEditor() {
    this.layoutModeValue = "editor"
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

  layoutModeValueChanged() {
    if (!this.managedValue) {
      try {
        window.localStorage.setItem(this.storageKeyValue, this.layoutModeValue)
      } catch (_) {
        /* ignore */
      }
    }
    this.syncUi()
    const skipEmit = !this.managedValue || this.suppressHydrationEmit === true
    if (!skipEmit) {
      const col = this.element.closest("[data-thread-panel-id]")
      const id = normalizeThreadPublicId(col?.dataset?.threadPanelId)
      if (id) {
        this.element.dispatchEvent(
          new CustomEvent("thread-workspace:panel-expanded", {
            bubbles: true,
            detail: { panelId: id, layoutMode: this.layoutModeValue }
          })
        )
      }
    }
  }

  syncUi() {
    const mode = this.layoutModeValue
    const showEditor = mode !== "index"
    const showIndex = mode !== "editor"

    this.element.classList.toggle("workspace-thread-panel-root--maximized", showEditor)
    this.element.classList.toggle("workspace-thread-panel-root--editor-only", mode === "editor")

    if (this.hasEditorColumnTarget) this.editorColumnTarget.hidden = !showEditor
    if (this.hasIndexColumnTarget) this.indexColumnTarget.hidden = !showIndex
    if (this.hasBrowseControlsTarget) this.browseControlsTarget.hidden = mode === "index"

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle("workspace-thread-panel-toolbar--index", mode === "index")
      this.toolbarTarget.classList.toggle("workspace-thread-panel-toolbar--split", mode === "split")
      this.toolbarTarget.classList.toggle("workspace-thread-panel-toolbar--editor", mode === "editor")
    }

    if (this.hasIndexModeBtnTarget)
      this.indexModeBtnTarget.setAttribute("aria-pressed", mode === "index" ? "true" : "false")
    if (this.hasSplitModeBtnTarget)
      this.splitModeBtnTarget.setAttribute("aria-pressed", mode === "split" ? "true" : "false")
    if (this.hasEditorModeBtnTarget)
      this.editorModeBtnTarget.setAttribute("aria-pressed", mode === "editor" ? "true" : "false")

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
