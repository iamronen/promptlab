/** @param {Element | null | undefined} el */
export function threadPanelRootFrom(el) {
  return el?.closest?.(".workspace-thread-panel-root") ?? document.querySelector(".workspace-thread-panel-root")
}

export const THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS = "workspace-thread-panel-root--index-drag-active"

const STRAY_BLOCK_MS = 480

/**
 * @param {Element} root
 * @returns {(e: Event) => void}
 */
function createStrayHeaderActivationBlocker(root) {
  return (e) => {
    if (!root.classList.contains(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)) return
    const t = e.target
    if (!(t && typeof t.closest === "function")) return
    if (
      t.closest(".workspace-thread-panel-win-btn") ||
      t.closest(".workspace-thread-panel-map-btn") ||
      t.closest(".workspace-thread-panel-title-actions") ||
      t.closest(".workspace-header-strip .sequence-mode-toggle") ||
      t.closest(".workspace-header-strip .sequence-mode-btn")
    ) {
      e.preventDefault()
      e.stopImmediatePropagation()
    }
  }
}

/** @param {Element} root */
function attachStrayHeaderBlockers(root) {
  if (root._threadPanelStrayBlockersAttached) return
  const fn = createStrayHeaderActivationBlocker(root)
  root._threadPanelStrayBlockFn = fn
  document.addEventListener("click", fn, true)
  document.addEventListener("pointerup", fn, true)
  root._threadPanelStrayBlockersAttached = true
}

/** @param {Element} root */
function detachStrayHeaderBlockers(root) {
  if (!root._threadPanelStrayBlockFn) return
  document.removeEventListener("click", root._threadPanelStrayBlockFn, true)
  document.removeEventListener("pointerup", root._threadPanelStrayBlockFn, true)
  root._threadPanelStrayBlockFn = null
  root._threadPanelStrayBlockersAttached = false
}

/** @param {string | undefined} stepKey */
export function strandStepToFrameId(stepKey) {
  if (!stepKey) return null
  return stepKey.startsWith("b:")
    ? `thread_editor_bundle_${stepKey.slice(2)}`
    : `thread_editor_sequence_${stepKey.slice(2)}`
}

/**
 * @param {Element | null} root
 * @param {string} frameId
 * @param {string | null} [scrollWithinFrameId]
 */
export function dispatchRevealThreadFrame(root, frameId, scrollWithinFrameId = null) {
  if (!root || !frameId) return
  const detail = { frameId }
  if (scrollWithinFrameId) detail.scrollWithinFrameId = scrollWithinFrameId
  root.dispatchEvent(
    new CustomEvent("workspace-thread-panel:reveal-frame", {
      bubbles: false,
      detail
    })
  )
}

/** @param {Element | null} root */
export function beginThreadPanelIndexDrag(root) {
  if (!root) return
  window.clearTimeout(root._threadPanelIndexDragEndTimer)
  root.classList.add(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)
  attachStrayHeaderBlockers(root)
}

/** @param {Element | null} root */
export function endThreadPanelIndexDragSoon(root) {
  if (!root) return
  window.clearTimeout(root._threadPanelIndexDragEndTimer)
  root._threadPanelIndexDragEndTimer = window.setTimeout(() => {
    root.classList.remove(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)
    root._threadPanelIndexDragEndTimer = null
    detachStrayHeaderBlockers(root)
  }, STRAY_BLOCK_MS)
}

/** @param {Element | null} root */
export function clearThreadPanelIndexDrag(root) {
  if (!root) return
  window.clearTimeout(root._threadPanelIndexDragEndTimer)
  root._threadPanelIndexDragEndTimer = null
  root.classList.remove(THREAD_PANEL_INDEX_DRAG_ACTIVE_CLASS)
  detachStrayHeaderBlockers(root)
}

/** Delay before submitting reorder forms so stray activations are suppressed first. */
export const THREAD_INDEX_REORDER_SUBMIT_DELAY_MS = 160

/** @param {HTMLElement | null} listEl strand ol */
export function editorStackFromStrandList(listEl) {
  const split = listEl?.closest?.(".workspace-thread-panel-split")
  return split?.querySelector('[data-thread-strand-panel-target="editorStack"]') ?? null
}

/**
 * @param {HTMLElement | null} listEl strand ol
 */
export function syncEditorStackOrderFromStrandList(listEl) {
  const stack = editorStackFromStrandList(listEl)
  if (!listEl || !stack) return

  const orderedKeys = [...listEl.querySelectorAll(".workspace-thread-strand-row")]
    .map((el) => el.dataset.strandStep)
    .filter(Boolean)

  const wrappers = orderedKeys
    .map((key) =>
      stack.querySelector(`.workspace-thread-editor-child[data-strand-step="${CSS.escape(key)}"]`)
    )
    .filter(Boolean)
  if (!wrappers.length) return

  const rectsBefore = new Map()
  wrappers.forEach((w) => rectsBefore.set(w, w.getBoundingClientRect()))

  wrappers.forEach((w) => stack.appendChild(w))

  stack.querySelectorAll(".workspace-thread-editor-child").forEach((wrapper, idx) => {
    const badge = wrapper.querySelector(".workspace-thread-editor-step-badge")
    if (badge) badge.textContent = String(idx + 1)
  })

  window.requestAnimationFrame(() => {
    wrappers.forEach((w) => {
      const before = rectsBefore.get(w)
      if (!before) return
      const after = w.getBoundingClientRect()
      const dx = before.left - after.left
      const dy = before.top - after.top
      if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) return

      w.style.transition = "transform 0s"
      w.style.transform = `translate(${dx}px, ${dy}px)`
      w.getBoundingClientRect()
      window.requestAnimationFrame(() => {
        w.style.transition = "transform 0.22s ease-out"
        w.style.transform = ""
        const done = () => {
          w.removeEventListener("transitionend", onEnd)
          w.style.transition = ""
          w.style.transform = ""
        }
        const onEnd = () => done()
        w.addEventListener("transitionend", onEnd, { once: true })
        window.setTimeout(done, 280)
      })
    })
  })
}

/** @param {HTMLElement | null} frameEl */
export function scrollThreadEditorFrameIntoStack(frameEl) {
  if (!frameEl) return
  const wrapper = frameEl.closest(".workspace-thread-editor-child")
  ;(wrapper || frameEl).scrollIntoView({ block: "nearest", behavior: "smooth" })
}

/**
 * @param {number | string} bundleId
 * @param {HTMLElement | null} listEl pipeline ol in thread index
 */
export function syncBundlePipelineDomFromIndexList(bundleId, listEl) {
  const bid = String(bundleId)
  const frameId = `thread_editor_bundle_${bid}`
  const root = listEl?.closest?.(".workspace-thread-panel-root")
  const frame =
    (root?.querySelector(`#${CSS.escape(frameId)}`) ?? document.getElementById(frameId)) ?? null
  if (!frame || !listEl) return

  const list = frame.querySelector('[data-sequence-editor-target="pipelineStepsList"]')
  if (!list) return

  const orderedIds = [...listEl.querySelectorAll("li.workspace-thread-bundle-pipeline-item")]
    .map((li) => li.dataset.pipelineSequenceId)
    .filter(Boolean)

  const rows = orderedIds
    .map((id) => list.querySelector(`[data-bundle-pipeline-seq-id="${CSS.escape(id)}"]`))
    .filter(Boolean)

  if (!rows.length) return

  rows.forEach((row) => list.appendChild(row))

  const main = frame.querySelector("main.sequence-editor")
  if (main && window.Stimulus) {
    try {
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(main, "sequence-editor")
      ctrl?.reindexSteps?.()
    } catch (_e) {
      /* Stimulus may not be ready inside lazy frame */
    }
  }
}

/**
 * @param {number | string} bundleId
 * @param {string | undefined} pipelineSequenceId
 * @param {HTMLElement | null | undefined} listEl optional thread index list for scoping duplicate bundle frames
 */
export function scrollBundlePipelineRowIntoView(bundleId, pipelineSequenceId, listEl) {
  if (!pipelineSequenceId) return
  const bid = String(bundleId)
  const id = `thread-bundle-${bid}-seq-${pipelineSequenceId}`
  const frameId = `thread_editor_bundle_${bid}`
  const root = listEl?.closest?.(".workspace-thread-panel-root")
  const frame =
    (root?.querySelector(`#${CSS.escape(frameId)}`) ?? document.getElementById(frameId)) ?? null
  const inner = frame?.querySelector(`#${CSS.escape(id)}`)
  inner?.scrollIntoView({ block: "nearest", behavior: "smooth" })
}
