import { Controller } from "@hotwired/stimulus"
import {
  buildBundleCopyTextFromEditorRoot,
  buildSequenceCopyTextFromEditorRoot,
  parseCopyTextDataset
} from "sequence_copy_text"
import {
  threadPanelRootFrom,
  dispatchRevealThreadFrame,
  beginThreadPanelIndexDrag,
  endThreadPanelIndexDragSoon,
  clearThreadPanelIndexDrag,
  syncEditorStackOrderFromStrandList,
  scrollThreadEditorFrameIntoStack,
  THREAD_INDEX_REORDER_SUBMIT_DELAY_MS,
  editorFrameForStrandStep,
  sequenceInnerIdForEditorFrame
} from "thread_panel_index_drag"
import { fetchAutosavePost } from "workspace_autosave"
import {
  disconnectThreadBranchStrandBridgeAlignment,
  syncThreadBranchStrandBridgeAlignment
} from "thread_branch_indicator_alignment"

export default class extends Controller {
  static targets = ["indexList", "editorStack"]

  static values = {
    updateUrl: String,
    editorReturn: String,
    weaveThread: String
  }

  connect() {
    this.draggedRow = null
    this.draggedStepKey = null
    this.suppressOrderMenuClick = false
    this.gripPressActive = false
    this.gripPointerMoved = false
    this.gripPointerDownX = 0
    this.gripPointerDownY = 0
    this.boundDocClick = this.onDocumentClick.bind(this)
    this.boundGripPointerMove = this.onGripPointerMove.bind(this)
    this.boundDragStart = this.onDragStart.bind(this)
    this.boundDragEnd = this.onDragEnd.bind(this)
    this.boundDragOverIndex = this.onDragOverIndex.bind(this)
    this.boundDragOverEditor = this.onDragOverEditor.bind(this)
    this.boundDrop = this.onDrop.bind(this)
    document.addEventListener("click", this.boundDocClick)
    if (this.hasIndexListTarget) {
      this.indexListTarget.addEventListener("dragstart", this.boundDragStart)
      this.indexListTarget.addEventListener("dragend", this.boundDragEnd)
      this.indexListTarget.addEventListener("dragover", this.boundDragOverIndex)
      this.indexListTarget.addEventListener("drop", this.boundDrop)
    }
    if (this.hasEditorStackTarget) {
      this.editorStackTarget.addEventListener("dragstart", this.boundDragStart)
      this.editorStackTarget.addEventListener("dragend", this.boundDragEnd)
      this.editorStackTarget.addEventListener("dragover", this.boundDragOverEditor)
      this.editorStackTarget.addEventListener("drop", this.boundDrop)
    }

    this.scrollStrandRowIntoViewIfNeeded()
    this.revealAndFocusNewSequenceIfNeeded()
    this.revealAndFocusBundleIfNeeded()

    syncThreadBranchStrandBridgeAlignment(this.element)
    this.boundThreadBranchAlign = () => syncThreadBranchStrandBridgeAlignment(this.element)
    if (this.hasEditorStackTarget) {
      this.editorStackTarget.addEventListener("turbo:frame-load", this.boundThreadBranchAlign)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocClick)
    this.stopGripPointerTracking()
    if (this.hasIndexListTarget) {
      this.indexListTarget.removeEventListener("dragstart", this.boundDragStart)
      this.indexListTarget.removeEventListener("dragend", this.boundDragEnd)
      this.indexListTarget.removeEventListener("dragover", this.boundDragOverIndex)
      this.indexListTarget.removeEventListener("drop", this.boundDrop)
    }
    if (this.hasEditorStackTarget) {
      this.editorStackTarget.removeEventListener("dragstart", this.boundDragStart)
      this.editorStackTarget.removeEventListener("dragend", this.boundDragEnd)
      this.editorStackTarget.removeEventListener("dragover", this.boundDragOverEditor)
      this.editorStackTarget.removeEventListener("drop", this.boundDrop)
    }
    clearThreadPanelIndexDrag(threadPanelRootFrom(this.element))
    if (this.hasEditorStackTarget && this.boundThreadBranchAlign) {
      this.editorStackTarget.removeEventListener("turbo:frame-load", this.boundThreadBranchAlign)
    }
    disconnectThreadBranchStrandBridgeAlignment(this.element)
  }

  scrollStrandRowIntoViewIfNeeded() {
    const u = new URL(window.location.href)
    const bundleId = u.searchParams.get("focus_bundle_id")
    const seqId = u.searchParams.get("focus_transformation_id")
    if ((!bundleId && !seqId) || !this.hasIndexListTarget) return
    requestAnimationFrame(() => {
      const sel = bundleId
        ? `.workspace-thread-strand-row[data-strand-step="b:${bundleId}"]`
        : `.workspace-thread-strand-row[data-strand-step="s:${seqId}"]`
      const row = this.indexListTarget.querySelector(sel)
      row?.scrollIntoView({ block: "nearest", behavior: "smooth" })
    })
  }

  revealAndFocusNewSequenceIfNeeded() {
    const u = new URL(window.location.href)
    const seqId = u.searchParams.get("focus_transformation_id")
    if (!seqId || !this.hasIndexListTarget) return

    const row = this.indexListTarget.querySelector(`.workspace-thread-strand-row[data-strand-step="s:${seqId}"]`)
    if (!row) return

    const root = threadPanelRootFrom(this.element)
    const editorFrame = editorFrameForStrandStep(root, `s:${seqId}`)
    const frameId = editorFrame?.id
    if (!frameId) return
    const scrollWithinFrameId = sequenceInnerIdForEditorFrame(editorFrame)
    dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)

    let focused = false
    const stripFocusParam = () => {
      if (!focused) return
      const cur = new URL(window.location.href)
      if (!cur.searchParams.has("focus_transformation_id")) return
      cur.searchParams.delete("focus_transformation_id")
      const qs = cur.searchParams.toString()
      window.history.replaceState(window.history.state, "", `${cur.pathname}${qs ? `?${qs}` : ""}${cur.hash}`)
    }

    const focusTitle = () => {
      const frame = document.getElementById(frameId)
      const editorRoot = frame?.querySelector("[data-controller~='sequence-editor']")
      const input = frame?.querySelector('[data-sequence-editor-target="titleInput"]')
      if (!input || input.readOnly) return

      input.focus({ preventScroll: true })
      const defaultTitle = editorRoot?.getAttribute("data-sequence-editor-default-title-value") || ""
      if (defaultTitle && input.value === defaultTitle) {
        input.select()
      }
      focused = true
      stripFocusParam()
    }

    const frameEl = document.getElementById(frameId)
    if (!frameEl) return

    frameEl.addEventListener("turbo:frame-load", focusTitle, { once: true })
    window.setTimeout(focusTitle, 400)
    window.setTimeout(focusTitle, 1100)
  }

  revealAndFocusBundleIfNeeded() {
    const u = new URL(window.location.href)
    const bundleId = u.searchParams.get("focus_bundle_id")
    if (!bundleId || !this.hasIndexListTarget) return

    const row = this.indexListTarget.querySelector(`.workspace-thread-strand-row[data-strand-step="b:${bundleId}"]`)
    if (!row) return

    const root = threadPanelRootFrom(this.element)
    const editorFrame = editorFrameForStrandStep(root, `b:${bundleId}`)
    const frameId = editorFrame?.id
    if (!frameId) return
    dispatchRevealThreadFrame(root, frameId, null)

    const stripFocusParam = () => {
      const cur = new URL(window.location.href)
      if (!cur.searchParams.has("focus_bundle_id")) return
      cur.searchParams.delete("focus_bundle_id")
      const qs = cur.searchParams.toString()
      window.history.replaceState(window.history.state, "", `${cur.pathname}${qs ? `?${qs}` : ""}${cur.hash}`)
    }

    const scrollBundle = () => {
      const frame = document.getElementById(frameId)
      if (!frame) return
      stripFocusParam()
    }

    const frameEl = document.getElementById(frameId)
    if (!frameEl) return

    frameEl.addEventListener("turbo:frame-load", scrollBundle, { once: true })
    window.setTimeout(scrollBundle, 400)
    window.setTimeout(scrollBundle, 1100)
  }

  onDocumentClick(event) {
    if (event.target.closest?.(".workspace-thread-tf-drag-handle")) return
    const inWrap = !!event.target.closest?.(".workspace-thread-tf-order-menu-wrap")
    const inPanel = this.element.contains(event.target)
    if (!inPanel) {
      this.closeAllOrderMenus()
      this.closeBranchMenus()
      return
    }
    if (!event.target.closest(".workspace-thread-branch-menu-host")) {
      this.closeBranchMenus()
    }
    if (!inWrap) {
      this.closeAllOrderMenus()
    }
  }

  closeBranchMenus() {
    this.element.querySelectorAll(".workspace-thread-branch-menu-panel").forEach((el) => {
      el.hidden = true
    })
    this.element.querySelectorAll(".workspace-thread-branch-menu-host [data-workspace-thread-branch-menu-target='trigger']").forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
  }

  closeAllOrderMenus() {
    this.element.querySelectorAll(".workspace-thread-tf-order-menu").forEach((m) => {
      m.hidden = true
    })
    this.element.querySelectorAll(".workspace-thread-tf-order-submenu").forEach((s) => {
      s.hidden = true
    })
    this.element.querySelectorAll(".workspace-thread-tf-order-menu-item--parent").forEach((b) => {
      b.setAttribute("aria-expanded", "false")
    })
    this.element.querySelectorAll(".workspace-thread-tf-drag-handle").forEach((h) => {
      h.setAttribute("aria-expanded", "false")
    })
  }

  closeOrderSubmenus(menuEl) {
    if (!menuEl) return
    menuEl.querySelectorAll(".workspace-thread-tf-order-submenu").forEach((el) => {
      el.hidden = true
    })
    menuEl.querySelectorAll(".workspace-thread-tf-order-menu-item--parent").forEach((el) => {
      el.setAttribute("aria-expanded", "false")
    })
  }

  toggleOrderMenu(event) {
    if (this.suppressOrderMenuClick) return
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    this.toggleOrderMenuFromButton(event.currentTarget)
  }

  toggleOrderMenuFromButton(button) {
    const wrap = button?.closest(".workspace-thread-tf-order-menu-wrap")
    const menu = wrap?.querySelector(".workspace-thread-tf-order-menu")
    if (!menu) return
    const wasOpen = !menu.hidden
    this.closeAllOrderMenus()
    if (wasOpen) return
    this.showOrderMenu(button)
  }

  showOrderMenu(button) {
    const wrap = button?.closest(".workspace-thread-tf-order-menu-wrap")
    const menu = wrap?.querySelector(".workspace-thread-tf-order-menu")
    const handle = wrap?.querySelector(".workspace-thread-tf-drag-handle")
    if (!menu) return
    menu.hidden = false
    if (handle) handle.setAttribute("aria-expanded", "true")
  }

  toggleOrderSubmenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const group = btn.closest(".workspace-thread-tf-order-menu-group")
    const sid = btn.dataset.submenuId
    const topMenu = btn.closest(".workspace-thread-tf-order-menu")
    const sub = group?.querySelector(`.workspace-thread-tf-order-submenu[data-submenu-id="${sid}"]`)
    if (!sub) return
    const willOpen = sub.hidden
    this.closeOrderSubmenus(topMenu)
    if (willOpen) {
      sub.hidden = false
      btn.setAttribute("aria-expanded", "true")
    }
  }

  viewInThreadEditor(event) {
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget.closest(".workspace-thread-strand-row")
    const stepKey = row?.dataset.strandStep
    if (!stepKey) return
    this.closeAllOrderMenus()
    const root = threadPanelRootFrom(this.element)
    const frame = editorFrameForStrandStep(root, stepKey)
    const frameId = frame?.id
    if (!frameId) return
    const scrollWithinFrameId =
      stepKey.startsWith("s:") ? sequenceInnerIdForEditorFrame(frame) : null
    dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)
  }

  copySequenceAsText(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeAllOrderMenus()

    const row = this.findStrandRowFromButton(event)
    const stepKey = row?.dataset.strandStep
    if (!stepKey?.startsWith("s:")) return

    const seqId = stepKey.slice(2)
    let text = null

    const editorInner = document.getElementById(`thread_editor_sequence_inner_${seqId}`)
    if (editorInner) {
      text = buildSequenceCopyTextFromEditorRoot(editorInner)
    }

    if (!text) {
      text = parseCopyTextDataset(event.currentTarget.dataset.copyText)
    }

    if (!text) return
    void navigator.clipboard.writeText(text)
  }

  copyBundleAsText(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeAllOrderMenus()

    const row = this.findStrandRowFromButton(event)
    const stepKey = row?.dataset.strandStep
    if (!stepKey?.startsWith("b:")) return

    const bundleId = stepKey.slice(2)
    let text = null

    const bundleFrame = document.getElementById(`thread_editor_bundle_${bundleId}`)
    const bundleMain = bundleFrame?.querySelector("main.sequence-editor--bundle")
    if (bundleMain) {
      text = buildBundleCopyTextFromEditorRoot(bundleMain)
    }

    if (!text) {
      text = parseCopyTextDataset(event.currentTarget.dataset.copyText)
    }

    if (!text) return
    void navigator.clipboard.writeText(text)
  }

  moveUp(event) {
    event.stopPropagation()
    this.closeAllOrderMenus()
    const row = this.findStrandRowFromButton(event)
    if (!row || !this.hasIndexListTarget) return
    const key = row.dataset.strandStep
    const idxRow = this.indexListTarget.querySelector(
      `.workspace-thread-strand-row[data-strand-step="${CSS.escape(key)}"]`
    )
    const prev = idxRow?.previousElementSibling
    if (
      !idxRow ||
      !prev ||
      !prev.matches?.(".workspace-thread-strand-row")
    )
      return
    this.indexListTarget.insertBefore(idxRow, prev)
    syncEditorStackOrderFromStrandList(this.indexListTarget)
    this.persistOrder()
  }

  moveDown(event) {
    event.stopPropagation()
    this.closeAllOrderMenus()
    const row = this.findStrandRowFromButton(event)
    if (!row || !this.hasIndexListTarget) return
    const key = row.dataset.strandStep
    const idxRow = this.indexListTarget.querySelector(
      `.workspace-thread-strand-row[data-strand-step="${CSS.escape(key)}"]`
    )
    const next = idxRow?.nextElementSibling
    if (
      !idxRow ||
      !next ||
      !next.matches?.(".workspace-thread-strand-row")
    )
      return
    this.indexListTarget.insertBefore(next, idxRow)
    syncEditorStackOrderFromStrandList(this.indexListTarget)
    this.persistOrder()
  }

  findStrandRowFromButton(event) {
    return event.currentTarget.closest(".workspace-thread-strand-row")
  }

  noteGripPress(event) {
    if (event.button !== undefined && event.button !== 0) return
    this.gripPressActive = true
    this.gripPointerMoved = false
    this.gripPointerDownX = event.clientX
    this.gripPointerDownY = event.clientY
    const row = event.currentTarget.closest(".workspace-thread-strand-row")
    if (row) row.draggable = true
    window.addEventListener("pointermove", this.boundGripPointerMove)
  }

  onGripPointerMove(event) {
    if (!this.gripPressActive) return
    const dx = event.clientX - this.gripPointerDownX
    const dy = event.clientY - this.gripPointerDownY
    if (Math.hypot(dx, dy) >= 4) this.gripPointerMoved = true
  }

  stopGripPointerTracking() {
    window.removeEventListener("pointermove", this.boundGripPointerMove)
  }

  disarmStrandRowDrag(row) {
    if (row) row.draggable = false
  }

  releaseGripPress(event) {
    this.stopGripPointerTracking()
    const button = event.currentTarget
    const row = button?.closest?.(".workspace-thread-strand-row")
    if (this.draggedRow) {
      this.disarmStrandRowDrag(row)
      return
    }
    if (event.type !== "mouseup" || !button?.matches?.(".workspace-thread-tf-drag-handle")) {
      window.setTimeout(() => {
        this.gripPressActive = false
        this.disarmStrandRowDrag(row)
      }, 0)
      return
    }

    this.disarmStrandRowDrag(row)
    this.gripPressActive = false
  }

  onDragStart(event) {
    const row = event.target.closest?.(".workspace-thread-strand-row")
    if (!row || !this.element.contains(row)) {
      event.preventDefault()
      return
    }
    if (!this.gripPointerMoved) {
      event.preventDefault()
      return
    }
    if (!this.gripPressActive) {
      event.preventDefault()
      return
    }

    this.draggedRow = row
    this.draggedStepKey = this.draggedRow.dataset.strandStep
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedStepKey || "")
    this.draggedRow.classList.add("workspace-thread-tf--dragging")
    this.suppressOrderMenuClick = true
    this.closeAllOrderMenus()

    const root = threadPanelRootFrom(this.element)
    beginThreadPanelIndexDrag(root)
    const stepKey = this.draggedStepKey
    const frame = editorFrameForStrandStep(root, stepKey)
    if (frame?.id) {
      const scrollWithinFrameId =
        stepKey && stepKey.startsWith("s:") ? sequenceInnerIdForEditorFrame(frame) : null
      dispatchRevealThreadFrame(root, frame.id, scrollWithinFrameId)
    }
  }

  onDragEnd() {
    const root = threadPanelRootFrom(this.element)
    endThreadPanelIndexDragSoon(root)

    if (this.draggedRow) {
      this.draggedRow.classList.remove("workspace-thread-tf--dragging")
    }
    this.draggedRow = null
    this.draggedStepKey = null
    this.gripPressActive = false
    this.gripPointerMoved = false
    this.stopGripPointerTracking()
    this.element.querySelectorAll(".workspace-thread-strand-row").forEach((strandRow) => {
      strandRow.draggable = false
    })
    window.setTimeout(() => {
      this.suppressOrderMenuClick = false
    }, 0)
    window.setTimeout(() => {
      this.persistOrder()
    }, THREAD_INDEX_REORDER_SUBMIT_DELAY_MS)
  }

  onDragOverIndex(event) {
    this.onDragOverInContainer(event, this.indexListTarget)
  }

  onDragOverEditor(event) {
    this.onDragOverInContainer(event, this.editorStackTarget)
  }

  onDragOverInContainer(event, container) {
    if (!this.draggedRow || !this.draggedStepKey || !container) return
    const dragOnIndex = this.hasIndexListTarget && this.indexListTarget.contains(this.draggedRow)
    const dragOnEditor = this.hasEditorStackTarget && this.editorStackTarget.contains(this.draggedRow)
    if (container === this.indexListTarget && !dragOnIndex) return
    if (container === this.editorStackTarget && !dragOnEditor) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const overRow = event.target.closest(".workspace-thread-strand-row")
    if (!overRow || !container.contains(overRow) || overRow === this.draggedRow) return
    const overKey = overRow.dataset.strandStep
    if (!overKey || overKey === this.draggedStepKey) return
    const rect = overRow.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    this.insertStrandRelative(this.draggedStepKey, overKey, before)
    const root = threadPanelRootFrom(this.element)
    const frame = editorFrameForStrandStep(root, this.draggedStepKey)
    scrollThreadEditorFrameIntoStack(frame)
  }

  /**
   * @param {string} dragKey
   * @param {string} overKey
   * @param {boolean} before
   */
  insertStrandRelative(dragKey, overKey, before) {
    if (!this.hasIndexListTarget) return
    const idxDrag = this.indexListTarget.querySelector(
      `.workspace-thread-strand-row[data-strand-step="${CSS.escape(dragKey)}"]`
    )
    const idxOver = this.indexListTarget.querySelector(
      `.workspace-thread-strand-row[data-strand-step="${CSS.escape(overKey)}"]`
    )
    if (!idxDrag || !idxOver) return

    if (before) {
      this.indexListTarget.insertBefore(idxDrag, idxOver)
    } else {
      const idxNext = idxOver.nextElementSibling
      if (idxNext) this.indexListTarget.insertBefore(idxDrag, idxNext)
      else this.indexListTarget.appendChild(idxDrag)
    }

    if (this.hasEditorStackTarget) {
      const edDrag = this.editorStackTarget.querySelector(
        `.workspace-thread-editor-child[data-strand-step="${CSS.escape(dragKey)}"]`
      )
      const edOver = this.editorStackTarget.querySelector(
        `.workspace-thread-editor-child[data-strand-step="${CSS.escape(overKey)}"]`
      )
      if (edDrag && edOver) {
        if (before) {
          this.editorStackTarget.insertBefore(edDrag, edOver)
        } else {
          const edNext = edOver.nextElementSibling
          if (edNext) this.editorStackTarget.insertBefore(edDrag, edNext)
          else this.editorStackTarget.appendChild(edDrag)
        }
      }
    }
  }

  onDrop(event) {
    event.preventDefault()
  }

  persistOrder() {
    if (!this.hasIndexListTarget || !this.updateUrlValue) return
    const tokens = [...this.indexListTarget.querySelectorAll(".workspace-thread-strand-row")].map(
      (el) => el.dataset.strandStep
    )
    const fd = new FormData()
    fd.append("_method", "patch")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return
    fd.append("authenticity_token", token)
    fd.append("redirect_to", this.editorReturnValue || window.location.pathname + window.location.search)
    if (this.weaveThreadValue) fd.append("weave_thread", this.weaveThreadValue)
    tokens.forEach((tok) => fd.append("strand_step_tokens[]", tok))
    void fetchAutosavePost(this.updateUrlValue, fd).then((res) => {
      if (!res.ok) console.warn("Strand order autosave failed", res.status)
    })
  }
}