import { Controller } from "@hotwired/stimulus"
import {
  threadPanelRootFrom,
  dispatchRevealThreadFrame,
  beginThreadPanelIndexDrag,
  endThreadPanelIndexDragSoon,
  clearThreadPanelIndexDrag,
  syncBundlePipelineDomFromIndexList,
  scrollBundlePipelineRowIntoView,
  THREAD_INDEX_REORDER_SUBMIT_DELAY_MS
} from "thread_panel_index_drag"
import { fetchAutosavePost } from "workspace_autosave"

// Thread index: reorder generative sequences inside a bundle via PATCH; jump to a step in the bundle editor frame.
export default class extends Controller {
  static targets = ["list"]

  static values = {
    updateUrl: String,
    editorReturn: String,
    bundleId: Number,
    bundleTitle: String,
    bundleIntent: String,
    prerequisiteIds: { type: Array, default: [] },
    weaveThread: String
  }

  connect() {
    this.draggedLi = null
    this.orderSnapshot = null
    this.boundDragStart = this.onListDragStart.bind(this)
    this.boundDragEnd = this.onListDragEnd.bind(this)
    this.boundDragOver = this.onDragOver.bind(this)
    this.boundDrop = this.onDrop.bind(this)
    if (this.hasListTarget) {
      this.listTarget.addEventListener("dragstart", this.boundDragStart)
      this.listTarget.addEventListener("dragend", this.boundDragEnd)
      this.listTarget.addEventListener("dragover", this.boundDragOver)
      this.listTarget.addEventListener("drop", this.boundDrop)
    }
  }

  disconnect() {
    if (this.hasListTarget) {
      this.listTarget.removeEventListener("dragstart", this.boundDragStart)
      this.listTarget.removeEventListener("dragend", this.boundDragEnd)
      this.listTarget.removeEventListener("dragover", this.boundDragOver)
      this.listTarget.removeEventListener("drop", this.boundDrop)
    }
    clearThreadPanelIndexDrag(threadPanelRootFrom(this.element))
  }

  orderIdsSignature() {
    return [...this.listTarget.querySelectorAll("li.workspace-thread-bundle-pipeline-item")]
      .map((li) => li.dataset.pipelineSequenceId)
      .join("\u001f")
  }

  onListDragStart(event) {
    const li = event.target.closest("li.workspace-thread-bundle-pipeline-item")
    if (!li || !this.listTarget.contains(li)) return
    if (event.target.closest("button")) {
      event.preventDefault()
      return
    }
    event.stopPropagation()
    this.draggedLi = li
    this.orderSnapshot = this.orderIdsSignature()
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", li.dataset.pipelineSequenceId || "")
    li.classList.add("workspace-thread-bundle-pipeline-item--dragging")

    const root = threadPanelRootFrom(this.element)
    beginThreadPanelIndexDrag(root)
    const seqId = li.dataset.pipelineSequenceId
    if (this.bundleIdValue) {
      const frameId = `thread_editor_bundle_${this.bundleIdValue}`
      const scrollWithinFrameId = seqId ? `thread-bundle-${this.bundleIdValue}-seq-${seqId}` : null
      dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)
    }
  }

  onListDragEnd() {
    const root = threadPanelRootFrom(this.element)
    endThreadPanelIndexDragSoon(root)

    if (!this.draggedLi) return
    this.draggedLi.classList.remove("workspace-thread-bundle-pipeline-item--dragging")
    const changed = this.orderSnapshot !== this.orderIdsSignature()
    this.draggedLi = null
    this.orderSnapshot = null
    if (changed) {
      window.setTimeout(() => {
        this.persistOrder()
      }, THREAD_INDEX_REORDER_SUBMIT_DELAY_MS)
    }
  }

  onDragOver(event) {
    if (!this.draggedLi || !this.listTarget.contains(this.draggedLi)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const over = event.target.closest("li.workspace-thread-bundle-pipeline-item")
    if (!over || over === this.draggedLi) return
    const rect = over.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    if (before) {
      this.listTarget.insertBefore(this.draggedLi, over)
    } else {
      this.listTarget.insertBefore(this.draggedLi, over.nextSibling)
    }

    syncBundlePipelineDomFromIndexList(this.bundleIdValue, this.listTarget)
    scrollBundlePipelineRowIntoView(this.bundleIdValue, this.draggedLi.dataset.pipelineSequenceId, this.listTarget)
  }

  onDrop(event) {
    event.preventDefault()
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  persistOrder() {
    if (!this.hasListTarget || !this.updateUrlValue) return
    const ids = [...this.listTarget.querySelectorAll("li.workspace-thread-bundle-pipeline-item")].map(
      (li) => li.dataset.pipelineSequenceId
    )
    const token = this.csrfToken()
    if (!token) return

    const fd = new FormData()
    fd.append("_method", "patch")
    fd.append("authenticity_token", token)
    const panelRoot = threadPanelRootFrom(this.element)
    const bidFrame = `thread_editor_bundle_${this.bundleIdValue}`
    const frame =
      typeof document !== "undefined"
        ? panelRoot?.querySelector(`#${CSS.escape(bidFrame)}`) ?? document.getElementById(bidFrame)
        : null
    const liveTitle =
      frame?.querySelector("input.bundle-pipeline-bundle-title-input")?.value ?? ""
    const sequenceTitle =
      typeof liveTitle === "string" && liveTitle.trim() !== ""
        ? liveTitle.trim()
        : this.bundleTitleValue ?? ""
    fd.append("sequence[title]", sequenceTitle)
    fd.append("sequence[intent]", this.bundleIntentValue ?? "")
    fd.append("sequence[prerequisite_bundle_ids][]", "")
    this.prerequisiteIdsValue.forEach((id) => {
      fd.append("sequence[prerequisite_bundle_ids][]", String(id))
    })

    ids.forEach((seqId, index) => {
      fd.append(`sequence[steps_attributes][${index}][sequence_id]`, String(seqId))
      fd.append(`sequence[steps_attributes][${index}][position]`, String(index + 1))
      fd.append(`sequence[steps_attributes][${index}][_destroy]`, "false")
    })

    fd.append("redirect_to", this.editorReturnValue || window.location.pathname + window.location.search)

    if (this.weaveThreadValue) {
      fd.append("weave_thread", this.weaveThreadValue)
    }

    void fetchAutosavePost(this.updateUrlValue, fd).then((res) => {
      if (!res.ok) console.warn("Bundle pipeline order autosave failed", res.status)
    })
  }

  viewNestedInThreadEditor(event) {
    event.preventDefault()
    event.stopPropagation()
    const seqId = event.currentTarget.dataset.pipelineSequenceId
    if (!seqId || !this.bundleIdValue) return
    const frameId = `thread_editor_bundle_${this.bundleIdValue}`
    const scrollWithinFrameId = `thread-bundle-${this.bundleIdValue}-seq-${seqId}`
    const root = threadPanelRootFrom(this.element) ?? document.querySelector(".workspace-thread-panel-root")
    if (!root) return
    dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId)
  }
}
