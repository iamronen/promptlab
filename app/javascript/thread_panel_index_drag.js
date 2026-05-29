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

/** @param {Element | null | undefined} el */
export function editorStackScrollContainerFrom(el) {
  return el?.closest?.(".workspace-thread-panel-editor-stack") ?? null
}

/**
 * Scroll el vertically within container without scrollIntoView (avoids scrolling the page / wrong clipper).
 * @param {Element | null | undefined} el
 * @param {Element | null | undefined} container
 * @param {{ padding?: number, behavior?: ScrollBehavior }} [options]
 * @returns {boolean}
 */
export function scrollElementIntoVerticalContainer(el, container, options = {}) {
  if (!(el instanceof Element) || !(container instanceof Element)) return false

  const pad = options.padding ?? 8
  const behavior = options.behavior ?? "smooth"
  const containerRect = container.getBoundingClientRect()
  const elementRect = el.getBoundingClientRect()

  if (containerRect.height <= 0) return false

  let nextScrollTop = container.scrollTop

  if (elementRect.top < containerRect.top + pad) {
    nextScrollTop += elementRect.top - containerRect.top - pad
  } else if (elementRect.bottom > containerRect.bottom - pad) {
    nextScrollTop += elementRect.bottom - containerRect.bottom + pad
  } else {
    return false
  }

  const maxScroll = Math.max(0, container.scrollHeight - container.clientHeight)
  nextScrollTop = Math.max(0, Math.min(nextScrollTop, maxScroll))

  if (Math.abs(nextScrollTop - container.scrollTop) < 1) return false

  container.scrollTo({ top: nextScrollTop, behavior })
  return true
}

/** @param {Element | null | undefined} el @param {{ padding?: number, behavior?: ScrollBehavior }} [options] */
export function scrollIntoEditorStack(el, options = {}) {
  const stack = editorStackScrollContainerFrom(el)
  if (!stack || !el) return false
  return scrollElementIntoVerticalContainer(el, stack, options)
}

/**
 * @param {Element | null | undefined} root
 * @param {string | null | undefined} stepKey
 */
export function editorChildForStrandStep(root, stepKey) {
  if (!root || !stepKey) return null
  return root.querySelector(`.workspace-thread-editor-child[data-strand-step="${CSS.escape(stepKey)}"]`)
}

/**
 * @param {Element | null | undefined} root
 * @param {string | null | undefined} stepKey
 */
export function editorFrameForStrandStep(root, stepKey) {
  const child = editorChildForStrandStep(root, stepKey)
  if (!child) return null
  return child.querySelector(
    "turbo-frame.workspace-thread-panel-editor-frame, turbo-frame[id^='thread_editor_']"
  )
}

/** @param {Element | null | undefined} frame */
export function sequenceInnerIdForEditorFrame(frame) {
  const inner = frame?.querySelector("[id^='thread_editor_sequence_inner_']")
  return inner?.id ?? null
}

/**
 * @param {Element | null | undefined} root
 * @param {{ stepKey?: string | null, frameId?: string | null }} ids
 */
export function resolveEditorFrame(root, { stepKey = null, frameId = null } = {}) {
  if (stepKey) {
    const byStep = editorFrameForStrandStep(root, stepKey)
    if (byStep) return byStep
  }
  if (frameId) {
    return root?.querySelector(`#${CSS.escape(frameId)}`) ?? document.getElementById(frameId)
  }
  return null
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
  const wrapper = frameEl.closest(".workspace-thread-editor-child") || frameEl
  scrollIntoEditorStack(wrapper)
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
  const root = listEl?.closest?.(".workspace-thread-panel-root")
  const frame =
    resolveEditorFrame(root, { frameId: `thread_editor_bundle_${bid}` }) ??
    document.getElementById(`thread_editor_bundle_${bid}`)
  const inner = frame?.querySelector(`#${CSS.escape(id)}`)
  if (!inner) return
  scrollIntoEditorStack(inner)
}
