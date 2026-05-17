import { Controller } from "@hotwired/stimulus"
import {
  threadPanelRootFrom,
  strandStepToFrameId,
  dispatchRevealThreadFrame,
  beginThreadPanelIndexDrag,
  endThreadPanelIndexDragSoon,
  clearThreadPanelIndexDrag,
  syncEditorStackOrderFromStrandList,
  scrollThreadEditorFrameIntoStack,
  THREAD_INDEX_REORDER_SUBMIT_DELAY_MS
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
    this.boundDocClick = this.onDocumentClick.bind(this)
    this.boundDragStart = this.onDragStart.bind(this)
    this.boundDragEnd = this.onDragEnd.bind(this)
    this.boundDragOverIndex = this.onDragOverIndex.bind(this)
    this.boundDragOverEditor = this.onDragOverEditor.bind(this)
    this.boundDrop = this.onDrop.bind(this)
    document.addEventListener("click", this.boundDocClick)
    if (this.hasIndexListTarget) {
      this.indexListTarget.addEventListener("dragover", this.boundDragOverIndex)
      this.indexListTarget.addEventListener("drop", this.boundDrop)
    }
    if (this.hasEditorStackTarget) {
      this.editorStackTarget.addEventListener("dragover", this.boundDragOverEditor)
      this.editorStackTarget.addEventListener("drop", this.boundDrop)
    }

    this.scrollStrandRowIntoViewIfNeeded()

    syncThreadBranchStrandBridgeAlignment(this.element)
    this.boundThreadBranchAlign = () => syncThreadBranchStrandBridgeAlignment(this.element)
    if (this.hasEditorStackTarget) {
      this.editorStackTarget.addEventListener("turbo:frame-load", this.boundThreadBranchAlign)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocClick)
    if (this.hasIndexListTarget) {
      this.indexListTarget.removeEventListener("dragover", this.boundDragOverIndex)
      this.indexListTarget.removeEventListener("drop", this.boundDrop)
    }
    if (this.hasEditorStackTarget) {
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

  onDocumentClick(event) {
    if (!this.element.contains(event.target)) {
      this.closeAllOrderMenus()
      this.closeBranchMenus()
      return
    }
    if (!event.target.closest(".workspace-thread-branch-menu-host")) {
      this.closeBranchMenus()
    }
    if (!event.target.closest(".workspace-thread-tf-order-menu-wrap")) {
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
    event.preventDefault()
    event.stopPropagation()
    const wrap = event.currentTarget.closest(".workspace-thread-tf-order-menu-wrap")
    const menu = wrap?.querySelector(".workspace-thread-tf-order-menu")
    const handle = wrap?.querySelector(".workspace-thread-tf-drag-handle")
    if (!menu) return
    const wasOpen = !menu.hidden
    this.closeAllOrderMenus()
    if (wasOpen) return
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
    const frameId = strandStepToFrameId(stepKey)
    if (!frameId) return
    this.closeAllOrderMenus()
    const root = threadPanelRootFrom(this.element)
    const scrollWithinFrameId =
      stepKey && stepKey.startsWith("s:") ? `thread_editor_sequence_inner_${stepKey.slice(2)}` : null
    dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)
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

  armDrag(event) {
    const row = event.currentTarget.closest(".workspace-thread-strand-row")
    if (!row) return
    row.setAttribute("draggable", "true")
    row.addEventListener("dragstart", this.boundDragStart)
    row.addEventListener("dragend", this.boundDragEnd)
  }

  disarmDrag(event) {
    const row = event.currentTarget.closest(".workspace-thread-strand-row")
    if (!row || this.draggedRow) return
    this.teardownDragRow(row)
  }

  onDragStart(event) {
    this.draggedRow = event.currentTarget
    this.draggedStepKey = this.draggedRow.dataset.strandStep
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedStepKey || "")
    this.draggedRow.classList.add("workspace-thread-tf--dragging")
    this.closeAllOrderMenus()

    const root = threadPanelRootFrom(this.element)
    beginThreadPanelIndexDrag(root)
    const stepKey = this.draggedStepKey
    const frameId = strandStepToFrameId(stepKey)
    if (frameId) {
      const scrollWithinFrameId =
        stepKey && stepKey.startsWith("s:") ? `thread_editor_sequence_inner_${stepKey.slice(2)}` : null
      dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)
    }
  }

  onDragEnd() {
    const root = threadPanelRootFrom(this.element)
    endThreadPanelIndexDragSoon(root)

    if (this.draggedRow) {
      this.draggedRow.classList.remove("workspace-thread-tf--dragging")
      this.teardownDragRow(this.draggedRow)
    }
    this.draggedRow = null
    this.draggedStepKey = null
    window.setTimeout(() => {
      this.persistOrder()
    }, THREAD_INDEX_REORDER_SUBMIT_DELAY_MS)
  }

  teardownDragRow(row) {
    row.removeAttribute("draggable")
    row.removeEventListener("dragstart", this.boundDragStart)
    row.removeEventListener("dragend", this.boundDragEnd)
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
    const fid = strandStepToFrameId(this.draggedStepKey)
    if (fid) {
      const el =
        (this.hasEditorStackTarget && this.editorStackTarget.querySelector(`#${CSS.escape(fid)}`)) ||
        (typeof document !== "undefined" ? document.getElementById(fid) : null)
      scrollThreadEditorFrameIntoStack(el)
    }
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