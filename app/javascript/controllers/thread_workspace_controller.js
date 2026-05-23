import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import {
  THREAD_WORKSPACE_STORAGE_VERSION,
  loadThreadWorkspaceState,
  mergePanelsFromStorage,
  saveThreadWorkspaceState,
  sanitizeOpenThreadIds
} from "thread_workspace_storage"
import { buildReconcileWantOrder } from "thread_workspace_reconcile"

const DEBOUNCE_MS = 400

/** @returns {boolean} */
function railsEnvIsDevelopment() {
  if (typeof document === "undefined") return false
  return document.querySelector('meta[name="rails-env"]')?.getAttribute("content") === "development"
}

function reconcileDepthStorageKey(projectId) {
  return `promptlab.tw.reconcileDepth.v1:${projectId}`
}

/** Dev-only: loud signal when Turbo.replace fires in a tight loop. */
function recordThreadWorkspaceVisitForDev(url) {
  if (!railsEnvIsDevelopment() || typeof window === "undefined") return
  const now = Date.now()
  /** @type {number[]} */
  const prev = Array.isArray(window.__THREAD_WORKSPACE_VISIT_TS__) ? window.__THREAD_WORKSPACE_VISIT_TS__ : []
  const recent = prev.filter((t) => now - t < 2000)
  recent.push(now)
  window.__THREAD_WORKSPACE_VISIT_TS__ = recent
  if (recent.length > 3) {
    console.error("[thread-workspace] Turbo visit storm (>3 replaces in 2s)", { url, count: recent.length })
  }
}

/**
 * True when two full URLs differ only in the `weave_thread` query value (path, hash, and all
 * other query keys match). Used to avoid Turbo.replace (which resets horizontal scroll) when
 * switching the focused thread in an already-open strip.
 * @param {string} curHref
 * @param {string} nextHref
 */
function onlyWeaveThreadQueryChanged(curHref, nextHref) {
  const a = new URL(curHref, window.location.origin)
  const b = new URL(nextHref, window.location.origin)
  if (a.pathname !== b.pathname || a.hash !== b.hash) return false

  const keys = new Set([...a.searchParams.keys(), ...b.searchParams.keys()])
  let anyChange = false
  for (const k of keys) {
    if (a.searchParams.get(k) === b.searchParams.get(k)) continue
    anyChange = true
    if (k !== "weave_thread") return false
  }
  return anyChange
}

/** Sequencing-workspace thread strip: multi-panel open set, dedupe + scroll, localStorage. */
export default class extends Controller {
  static targets = ["strip", "stripNav", "carouselRoot"]

  static values = {
    projectId: Number,
    allowedIds: Array,
    focusId: Number
  }

  connect() {
    this.persistTimer = null
    this.stripCarousel = null
    /** @type {ResizeObserver | null} */
    this.stripResizeObserver = null

    this.refreshAllowedSet()

    this.boundOpen = this.onOpenIntent.bind(this)
    window.addEventListener("thread-workspace:open", this.boundOpen)

    this.boundPersistFromPanel = (ev) => {
      const t = /** @type {Event} */ (ev).target
      if (!(t instanceof Node) || !this.hasStripTarget || !this.stripTarget.contains(t)) return
      this.schedulePersist()
    }
    document.addEventListener("thread-workspace:panel-expanded", this.boundPersistFromPanel)

    this.boundAfterTurboLoad = () => {
      const tid = this.parseWeaveThreadFromUrl()
      if (tid > 0 && this.hasStripTarget) this.scheduleScrollFocusedPanelIntoView(tid)
    }
    document.addEventListener("turbo:load", this.boundAfterTurboLoad)

    this.boundStripScroll = () => this.updateStripNavVisibility()
    if (this.hasStripTarget) this.stripTarget.addEventListener("scroll", this.boundStripScroll, { passive: true })

    if (this.hasStripTarget && this.hasStripNavTarget) {
      this.stripResizeObserver = new ResizeObserver(() => this.updateStripNavVisibility())
      this.stripResizeObserver.observe(this.stripTarget)
      const midCol = this.stripTarget.closest(".workspace-middle-column")
      const workspaceRow = this.stripTarget.closest(".workspace")
      if (midCol) this.stripResizeObserver.observe(midCol)
      if (workspaceRow) this.stripResizeObserver.observe(workspaceRow)
    }

    queueMicrotask(() => {
      this.refreshAllowedSet()
      const navigated = this.maybeReconcileStoredOpenSet()
      if (!navigated) this.schedulePersist()
    })
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.updateStripNavVisibility()
      })
    })
  }

  disconnect() {
    if (this.boundStripScroll && this.hasStripTarget) {
      this.stripTarget.removeEventListener("scroll", this.boundStripScroll)
    }
    if (this.stripResizeObserver) {
      this.stripResizeObserver.disconnect()
      this.stripResizeObserver = null
    }
    this.teardownStripCarousel()

    window.removeEventListener("thread-workspace:open", this.boundOpen)
    document.removeEventListener("thread-workspace:panel-expanded", this.boundPersistFromPanel)
    document.removeEventListener("turbo:load", this.boundAfterTurboLoad)
    if (this.persistTimer) window.clearTimeout(this.persistTimer)
  }

  refreshAllowedSet() {
    /** @type {unknown} */
    let raw = this.allowedIdsValue
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch {
        raw = []
      }
    }
    if (!Array.isArray(raw)) raw = []
    const fromServer = raw
      .map((x) => parseInt(String(x), 10))
      .filter((n) => Number.isFinite(n) && n > 0)

    const u = typeof window !== "undefined" ? new URL(window.location.href) : null
    const weaveParam = u?.searchParams.get("weave_thread")
    const fromWeave =
      weaveParam && /^\d+$/.test(weaveParam.trim()) ? [parseInt(weaveParam.trim(), 10)] : []

    const fromOpenParam = u?.searchParams.get("open_threads")
    const fromOpen =
      fromOpenParam
        ?.split(",")
        .map((s) => parseInt(s.trim(), 10))
        .filter((n) => Number.isFinite(n) && n > 0) ?? []

    const fromDom = this.hasStripTarget
      ? [...this.stripTarget.querySelectorAll("[data-thread-panel-id]")]
          .map((el) => parseInt(/** @type {HTMLElement} */ (el).dataset.threadPanelId || "0", 10))
          .filter((n) => n > 0)
      : []

    this.allowedSet = new Set([...fromServer, ...fromOpen, ...fromWeave, ...fromDom])
  }

  /** Allow navigation targets that may briefly be absent from SSR JSON (Turbo/Stimulus quirks). */
  primeAllowed(ids) {
    if (!this.allowedSet) this.refreshAllowedSet()
    for (const id of ids) {
      const n = parseInt(String(id), 10)
      if (n > 0) this.allowedSet.add(n)
    }
  }

  /** @returns {number[]} */
  domPanelOrder() {
    if (!this.hasStripTarget) return []
    return [...this.stripTarget.querySelectorAll("[data-thread-panel-id]")]
      .map((el) => parseInt(/** @type {HTMLElement} */ (el).dataset.threadPanelId || "0", 10))
      .filter((n) => n > 0)
  }

  onOpenIntent(event) {
    const e = /** @type {CustomEvent} */ (event)
    const id = parseInt(String(e.detail?.threadId || ""), 10)
    if (!(id > 0)) return

    this.refreshAllowedSet()
    this.primeAllowed([id])

    const openSet = new Set(this.domPanelOrder())
    if (openSet.has(id)) {
      this.scrollPanelIntoView(id)
      this.syncWeaveThreadParam(id)
      this.schedulePersist()
      return
    }

    const fromDetail = parseInt(String(e.detail?.insertAfterPanelThreadId ?? ""), 10)
    const anchorFromUrl = this.parseWeaveThreadFromUrl()
    /** @type {number} */
    let anchor =
      Number.isFinite(fromDetail) && fromDetail > 0 ? fromDetail : anchorFromUrl > 0 ? anchorFromUrl : 0

    const ordered = [...this.domPanelOrder()]
    const anchorIdx = anchor > 0 ? ordered.indexOf(anchor) : -1
    let next

    if (anchorIdx >= 0) {
      ordered.splice(anchorIdx + 1, 0, id)
      next = this.uniqOrder(ordered)
    } else {
      next = this.uniqOrder([...this.domPanelOrder(), id])
    }

    this.primeAllowed(next)
    this.visitOpenThreads(next, id)
  }

  /** @param {Event} event */
  closePanel(event) {
    const e = /** @type {CustomEvent | Event & { params?: Record<string, string> }} */ (event)
    const closeId = parseInt(String(e.params?.threadId ?? ""), 10)
    if (!(closeId > 0)) return

    this.refreshAllowedSet()
    const order = this.domPanelOrder()
    if (!order.includes(closeId)) return

    const remaining = sanitizeOpenThreadIds(
      order.filter((tid) => tid !== closeId),
      this.allowedSet
    )

    if (remaining.length === 0) {
      this.persistStoredPanels([], 0)
      this.visitFabricAfterClosingLastPanel()
      return
    }

    const focusWas = this.parseWeaveThreadFromUrl()
    let nextFocus =
      focusWas === closeId
        ? remaining[order.indexOf(closeId) - 1] ?? remaining[0]
        : remaining.includes(focusWas)
          ? focusWas
          : remaining[0]

    nextFocus = parseInt(String(nextFocus), 10)
    if (!(nextFocus > 0)) nextFocus = remaining[0]

    this.persistStoredPanels(remaining, nextFocus)
    this.visitOpenThreads(remaining, nextFocus)
  }

  /** Move panel toward the strip start (visual left in LTR). */
  /** @param {Event} event */
  movePanelLeft(event) {
    this.moveStripPanel(event, -1)
  }

  /** Move panel toward the strip end (visual right in LTR). */
  /** @param {Event} event */
  movePanelRight(event) {
    this.moveStripPanel(event, 1)
  }

  /**
   * @param {Event} event
   * @param {-1 | 1} delta
   */
  moveStripPanel(event, delta) {
    event.preventDefault()
    event.stopPropagation()

    const e = /** @type {Event & { params?: Record<string, string> }} */ (event)
    const moveId = parseInt(String(e.params?.threadId ?? ""), 10)
    if (!(moveId > 0)) return

    this.refreshAllowedSet()
    /** @type {number[]} */
    const order = [...this.domPanelOrder()]
    const i = order.indexOf(moveId)
    if (i < 0) return
    const j = i + delta
    if (j < 0 || j >= order.length) return
    ;[order[i], order[j]] = [order[j], order[i]]

    const focusParsed = this.parseWeaveThreadFromUrl()
    const focusPick = focusParsed > 0 ? focusParsed : moveId

    this.persistStoredPanels(order, focusPick)
    this.visitOpenThreads(order, focusPick)
  }

  /** Re-align after Turbo-driven body replace (layout may not be final on first frame). */
  scheduleScrollFocusedPanelIntoView(threadId) {
    const tid = parseInt(String(threadId), 10)
    if (!(tid > 0) || !this.hasStripTarget) return
    const run = () => this.scrollPanelIntoView(tid)
    queueMicrotask(run)
    requestAnimationFrame(() => {
      run()
      requestAnimationFrame(() => {
        run()
        window.setTimeout(run, 0)
        window.setTimeout(run, 80)
      })
    })
  }

  applyClientPanelFocus(threadId) {
    if (!this.hasStripTarget) return
    const tid = parseInt(String(threadId), 10)
    if (!(tid > 0)) return
    for (const el of this.stripTarget.querySelectorAll("[data-thread-panel-id]")) {
      const col = /** @type {HTMLElement} */ (el)
      const id = parseInt(col.dataset.threadPanelId || "0", 10)
      col.classList.toggle("workspace-thread-panel-column--focused", id === tid)
    }
  }

  scrollPanelIntoView(threadId) {
    if (!this.hasStripTarget) return
    const col = this.stripTarget.querySelector(`[data-thread-panel-id="${CSS.escape(String(threadId))}"]`)
    if (!(col instanceof HTMLElement)) return

    const scrollers = this.horizontalScrollContainersBetween(col)

    const pad = 8
    for (let iter = 0; iter < 10; iter++) {
      let adjusted = false
      for (const scroller of scrollers) {
        if (scroller.scrollWidth <= scroller.clientWidth + 1) continue
        const sR = scroller.getBoundingClientRect()
        const tR = col.getBoundingClientRect()
        if (tR.left < sR.left + pad) {
          scroller.scrollLeft += tR.left - sR.left - pad
          adjusted = true
        } else if (tR.right > sR.right - pad) {
          scroller.scrollLeft += tR.right - (sR.right - pad)
          adjusted = true
        }
      }
      if (!adjusted) break
    }
  }

  /**
   * Scrollable ancestors from the strip column up (inclusive of #workspace-thread-workspace-strip when scrollable).
   * `scrollIntoView({ inline: "nearest" })` often skips the real clipper (e.g. `.workspace-middle-column`).
   * @param {HTMLElement} stripColumnEl `[data-thread-panel-id]` element
   */
  horizontalScrollContainersBetween(stripColumnEl) {
    /** @type {HTMLElement[]} */
    const out = []
    let el = stripColumnEl.parentElement
    while (el && el !== document.documentElement) {
      const ox = getComputedStyle(el).overflowX
      if (ox === "auto" || ox === "scroll" || ox === "overlay") {
        out.push(el)
      }
      el = el.parentElement
    }
    return out
  }

  syncWeaveThreadParam(threadId) {
    const url = new URL(window.location.href)
    const domStr = this.domPanelOrder().join(",")

    if (domStr) url.searchParams.set("open_threads", domStr)
    else url.searchParams.delete("open_threads")

    url.searchParams.set("weave_thread", String(threadId))
    url.searchParams.delete("thread_partner")

    const next = `${url.pathname}${url.search}`
    const cur = `${window.location.pathname}${window.location.search}`
    if (next === cur) return

    if (typeof window !== "undefined" && onlyWeaveThreadQueryChanged(cur, next)) {
      window.history.replaceState(window.history.state, "", next)
      this.applyClientPanelFocus(threadId)
      return
    }

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        Turbo.visit(next, { action: "replace" })
      })
    })
  }

  /** @param {number[]} order @param {number} focusThreadId */
  visitOpenThreads(order, focusThreadId) {
    this.refreshAllowedSet()
    this.primeAllowed(order)

    const sanitized = sanitizeOpenThreadIds(order, this.allowedSet)
    const url = new URL(window.location.href)
    if (sanitized.length) url.searchParams.set("open_threads", sanitized.join(","))
    else url.searchParams.delete("open_threads")

    url.searchParams.set("weave_thread", String(focusThreadId))
    url.searchParams.delete("thread_partner")
    const next = url.toString()
    recordThreadWorkspaceVisitForDev(next)
    Turbo.visit(next, { action: "replace" })
  }

  /** Persist open set before Turbo navigation so reconcile does not resurrect closed threads. */
  /** @param {number[]} ids @param {number} focusThreadId */
  persistStoredPanels(ids, focusThreadId) {
    const saved = loadThreadWorkspaceState(this.projectIdValue)
    const merged = mergePanelsFromStorage(ids, saved?.panels)
    /** @type {import("thread_workspace_storage").ThreadWorkspaceState} */
    const payload = {
      version: THREAD_WORKSPACE_STORAGE_VERSION,
      panels: merged,
      ...(focusThreadId > 0 ? { focusId: focusThreadId } : {})
    }
    if (merged.length === 0) delete payload.focusId
    saveThreadWorkspaceState(this.projectIdValue, payload)
  }

  /** `workspace_mode=fabric`, clears thread-strip query keys (mirrors leaving sequencing UI). */
  visitFabricAfterClosingLastPanel() {
    const url = new URL(window.location.href)
    url.searchParams.set("workspace_mode", "fabric")
    url.searchParams.delete("open_threads")
    url.searchParams.delete("thread_partner")
    url.searchParams.delete("weave_thread")

    Turbo.visit(`${url.pathname}${url.search}`, { action: "replace" })
  }

  /**
   * Repair strip when localStorage lists more (or differently ordered) threads than the current URL/DOM.
   *
   * **Source of truth:** Server-rendered strip + query string. `?open_threads=` defines membership and
   * order when present; localStorage only *adds* threads missing from the URL (e.g. user returns via a
   * cold link). A depth guard + persist heal prevents runaway `Turbo.replace` loops if state ever diverges.
   *
   * @returns {boolean} true when a navigation was scheduled
   */
  maybeReconcileStoredOpenSet() {
    if (!this.hasStripTarget) return false

    this.refreshAllowedSet()

    const saved = loadThreadWorkspaceState(this.projectIdValue)
    if (!saved?.panels?.length) return false

    const domIds = this.domPanelOrder()
    this.primeAllowed(domIds)

    const focusUrl = this.parseWeaveThreadFromUrl()
    this.primeAllowed([focusUrl])

    const urlOpen = this.parseOpenThreadsFromUrl()
    if (urlOpen.length) this.primeAllowed(urlOpen)

    const wantOrder = buildReconcileWantOrder(saved.panels, urlOpen, focusUrl, this.allowedSet)
    if (!wantOrder.length) return false

    const wantStr = wantOrder.join(",")

    const depthKey = reconcileDepthStorageKey(this.projectIdValue)
    if (domIds.join(",") === wantStr) {
      try {
        sessionStorage.removeItem(depthKey)
      } catch {
        /* private mode */
      }
      return false
    }

    let depth = 0
    try {
      depth = parseInt(sessionStorage.getItem(depthKey) || "0", 10)
    } catch {
      depth = 0
    }
    if (depth >= 3) {
      console.warn("[thread-workspace] reconcile guard: too many auto navigations; syncing localStorage from DOM", {
        domIds,
        wantStr
      })
      try {
        sessionStorage.removeItem(depthKey)
      } catch {
        /* ignore */
      }
      this.persistNow()
      return false
    }
    try {
      sessionStorage.setItem(depthKey, String(depth + 1))
    } catch {
      /* ignore */
    }

    const focusPick = focusUrl > 0 ? focusUrl : wantOrder[0]
    this.visitOpenThreads(wantOrder, focusPick)
    return true
  }

  /** @returns {number[]} thread ids encoded in URL ?open_threads= */
  parseOpenThreadsFromUrl() {
    const u = typeof window !== "undefined" ? new URL(window.location.href) : null
    const raw = u?.searchParams.get("open_threads")?.trim()
    if (!raw) return []
    return raw
      .split(",")
      .map((s) => parseInt(s.trim(), 10))
      .filter((n) => Number.isFinite(n) && n > 0)
  }

  /** @param {number[]} ids */
  uniqOrder(ids) {
    const out = []
    const seen = new Set()
    for (const id of ids) {
      if (seen.has(id)) continue
      seen.add(id)
      out.push(id)
    }
    return out
  }

  /** Focus thread from URL; does not gate on allowedSet (allowedSet refreshed separately). */
  parseWeaveThreadFromUrl() {
    const tid = parseInt(new URL(window.location.href).searchParams.get("weave_thread") || "0", 10)
    return tid > 0 ? tid : 0
  }

  schedulePersist() {
    if (!this.hasStripTarget) return
    if (this.persistTimer) window.clearTimeout(this.persistTimer)
    this.persistTimer = window.setTimeout(() => this.persistNow(), DEBOUNCE_MS)
  }

  persistNow() {
    this.persistTimer = null
    if (!this.hasStripTarget) return

    this.refreshAllowedSet()

    /** @type {import("thread_workspace_storage").ThreadWorkspacePanel[]} */
    const panels = []
    for (const col of this.stripTarget.querySelectorAll("[data-thread-panel-id]")) {
      const id = parseInt(/** @type {HTMLElement} */ (col).dataset.threadPanelId || "0", 10)
      if (!id || !this.allowedSet.has(id)) continue
      const root = col.querySelector(".workspace-thread-panel-root")
      const rawMode = root?.dataset?.workspaceThreadPanelLayoutModeValue
      const layoutMode =
        rawMode === "index" || rawMode === "split" || rawMode === "editor" ? rawMode : "split"
      panels.push({ id, layoutMode })
    }

    const focusParsed = this.parseWeaveThreadFromUrl()
    const focusId = focusParsed > 0 ? focusParsed : this.focusIdValue > 0 ? this.focusIdValue : 0

    /** @type {import("thread_workspace_storage").ThreadWorkspaceState} */
    const payload = {
      version: THREAD_WORKSPACE_STORAGE_VERSION,
      panels,
      ...(focusId > 0 ? { focusId } : {})
    }
    saveThreadWorkspaceState(this.projectIdValue, payload)
  }

  updateStripNavVisibility() {
    if (!this.hasStripTarget || !this.hasStripNavTarget || !this.hasCarouselRootTarget) {
      this.teardownStripCarousel()
      return
    }

    const order = this.domPanelOrder()
    if (order.length < 2) {
      this.hideStripNav()
      this.teardownStripCarousel()
      return
    }

    this.showStripNav()
    this.ensureStripCarousel()
  }

  showStripNav() {
    if (!this.hasStripNavTarget) return
    this.stripNavTarget.hidden = false
    this.stripNavTarget.setAttribute("aria-hidden", "false")
  }

  hideStripNav() {
    if (!this.hasStripNavTarget) return
    this.stripNavTarget.hidden = true
    this.stripNavTarget.setAttribute("aria-hidden", "true")
  }

  teardownStripCarousel() {
    if (this.stripCarousel) {
      this.stripCarousel.destroyAndRemoveInstance()
      this.stripCarousel = null
    }
    this._stripCarouselAttempts = 0
    this._stripCarouselCreatedAt = null
  }

  ensureStripCarousel() {
    if (this.stripCarousel) return

    const CarouselCtor = typeof window !== "undefined" ? window.Carousel : null
    if (!CarouselCtor) {
      this._stripCarouselAttempts = (this._stripCarouselAttempts || 0) + 1
      if (this._stripCarouselAttempts <= 30) {
        window.setTimeout(() => this.updateStripNavVisibility(), 50)
      }
      return
    }
    this._stripCarouselAttempts = 0

    if (!this.hasCarouselRootTarget) return

    const root = this.carouselRootTarget
    const itemEls = [...root.querySelectorAll("[data-carousel-item]")]
    const indicatorEls = [...root.querySelectorAll("[data-thread-strip-nav-indicator]")]
    const order = this.domPanelOrder()

    if (
      itemEls.length !== order.length ||
      indicatorEls.length !== order.length ||
      order.length === 0
    ) {
      return
    }

    let defaultPosition = order.indexOf(this.parseWeaveThreadFromUrl())
    if (defaultPosition < 0 && this.focusIdValue > 0) {
      defaultPosition = order.indexOf(this.focusIdValue)
    }
    if (defaultPosition < 0) defaultPosition = 0
    if (defaultPosition > order.length - 1) defaultPosition = order.length - 1

    const items = itemEls.map((el, position) => ({ position, el }))
    const indicators = indicatorEls.map((el, position) => ({ position, el }))

    this.stripCarousel = new CarouselCtor(
      root,
      items,
      {
        defaultPosition,
        interval: 99999999,
        indicators: {
          activeClasses: "thread-strip-nav--is-active",
          inactiveClasses: "thread-strip-nav--is-inactive",
          items: indicators
        },
        onChange: (carousel) => this.onStripCarouselChange(carousel)
      },
      { id: root.id, override: true }
    )
    this._stripCarouselCreatedAt = Date.now()
  }

  /**
   * Focus a thread strip panel: URL + blue column outline + strip dots (when carousel is mounted).
   * Shared by nav indicators and clicking inside a panel column.
   * @param {number} threadId
   */
  activateThreadPanel(threadId) {
    if (!this.hasStripTarget) return
    const tid = parseInt(String(threadId), 10)
    if (!(tid > 0)) return

    const order = this.domPanelOrder()
    const position = order.indexOf(tid)
    if (position < 0) return

    if (this.stripCarousel) {
      this.stripCarousel.slideTo(position)
    } else {
      this.scrollPanelIntoView(tid)
      this.syncWeaveThreadParam(tid)
      this.schedulePersist()
    }
  }

  /**
   * Panel header lineage crumb: focus open strip panel or insert ancestor left of the originating panel + Turbo.visit.
   * Stops bubbling so the column wrapper does not steal focus via focusPanelColumn.
   */
  focusOrOpenAncestorFromBreadcrumb(event) {
    event.preventDefault()
    event.stopPropagation()

    const e = /** @type {Event & { params?: Record<string, string> }} */ (event)
    const ancestorId = parseInt(String(e.params?.ancestorId ?? ""), 10)
    const panelOwnerId = parseInt(String(e.params?.panelOwnerId ?? ""), 10)
    if (!(ancestorId > 0)) return

    this.refreshAllowedSet()
    this.primeAllowed([ancestorId, panelOwnerId])

    const order = [...this.domPanelOrder()]
    if (order.includes(ancestorId)) {
      this.activateThreadPanel(ancestorId)
      this.scheduleScrollFocusedPanelIntoView(ancestorId)
      return
    }

    let idx = panelOwnerId > 0 ? order.indexOf(panelOwnerId) : -1
    if (idx < 0) {
      const focusFromUrl = this.parseWeaveThreadFromUrl()
      idx = focusFromUrl > 0 ? order.indexOf(focusFromUrl) : -1
    }

    const inserted =
      idx >= 0
        ? [...order.slice(0, idx), ancestorId, ...order.slice(idx)]
        : [ancestorId, ...order]

    let nextOrder = this.uniqOrder(inserted)
    nextOrder = sanitizeOpenThreadIds(nextOrder, this.allowedSet)

    if (!nextOrder.includes(ancestorId)) {
      this.primeAllowed([ancestorId])
      nextOrder = sanitizeOpenThreadIds(this.uniqOrder(inserted), this.allowedSet)
    }

    if (!nextOrder.includes(ancestorId)) return

    this.persistStoredPanels(nextOrder, ancestorId)
    this.visitOpenThreads(nextOrder, ancestorId)
  }

  /** Clicking inside a thread panel column (not the close control) makes it the focused strip. */
  focusPanelColumn(event) {
    if (!this.hasStripTarget) return
    const t = event.target
    if (!(t instanceof Element)) return
    if (t.closest(".workspace-thread-panel-close-btn")) return

    const threadId = parseInt(String(/** @type {any} */ (event).params?.threadId ?? ""), 10)
    if (!(threadId > 0)) return

    this.activateThreadPanel(threadId)
  }

  /** Clicks handled here (runs before Flowbite’s bubble listener); stops duplicate slideTo / Turbo. */
  stripNavIndicatorClick(event) {
    if (!this.hasStripTarget || !this.hasCarouselRootTarget) return
    const threadId = parseInt(String(event.params.threadId || ""), 10)
    if (!(threadId > 0)) return

    event.preventDefault()
    event.stopImmediatePropagation()

    this.activateThreadPanel(threadId)
  }

  /** @param {any} carousel Flowbite Carousel instance */
  onStripCarouselChange(carousel) {
    if (!this.hasStripTarget) return
    const active = carousel.getActiveItem()
    const pos = active?.position
    if (pos === undefined || pos === null) return

    const order = this.domPanelOrder()
    const id = order[pos]
    if (!(id > 0)) return

    const focus = this.parseWeaveThreadFromUrl()
    if (id === focus) return

    const sinceCreate =
      typeof this._stripCarouselCreatedAt === "number" ? Date.now() - this._stripCarouselCreatedAt : 99999
    if (sinceCreate < 150) return

    this.scrollPanelIntoView(id)
    this.syncWeaveThreadParam(id)
    this.schedulePersist()
  }
}
