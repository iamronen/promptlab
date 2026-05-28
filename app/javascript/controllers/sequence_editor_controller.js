import { Controller } from "@hotwired/stimulus"
import { getSequenceEditorReadonlyPreference } from "sequence_editor_mode_storage"
import {
  fetchAutosaveForm,
  fetchAutosavePipelineChildMeta,
  fetchAutosaveSequenceMeta
} from "workspace_autosave"
import {
  buildBundlePipelineChildCopyTextFromPipelineRow,
  parseCopyTextDataset
} from "sequence_copy_text"
import { trimStepEditorHtml } from "sequence_step_content"
import { trimTrailingWhitespaceInPlace } from "text_input_sanitizer"

/** Generative step row (vs bundle pipeline slot: data-editor-kind="bundle_pipeline_slot"). */
const SEQUENCE_STEP_ROW_SELECTOR = '[data-editor-kind="sequence_step"]'
const SEQUENCE_STEP_ROW_ACTIVE_DRAG_CLASS = "step-row--sequence-active"
/** Sentinel row at end of steps list (thread-branch indicator); new steps insert before this. */
const STEPS_LIST_END_ANCHOR_SELECTOR = "[data-sequence-editor-steps-end-anchor]"

const PIPELINE_SCROLL_AFTER_CREATE_KEY = "promptlab:scrollBundlePipelineSeqId"

export default class extends Controller {
  static targets = [
    "form",
    "titleInput",
    "intentInput",
    "stepsList",
    "pipelineStepsList",
    "stepCard",
    "pipelineStepRow",
    "stepLabel",
    "positionInput",
    "destroyInput",
    "contentInput",
    "editor",
    "stepTemplate",
    "menu",
    "menuWrap"
  ]

  static values = {
    defaultTitle: String,
    defaultIntent: String,
    readonly: Boolean,
    pipelineMode: { type: Boolean, default: false },
    nested: { type: Boolean, default: false },
    nestedFieldPrefix: { type: String, default: "" },
    pipelineCreateSequenceUrl: { type: String, default: "" },
    bundleId: { type: Number, default: 0 },
    unbundleProjectId: { type: Number, default: 0 },
    unbundleThreadId: { type: Number, default: 0 }
  }

  connect() {
    this.draggedCard = null
    this.dragArmedCard = null
    this.dropIndicatorCard = null
    this.activeCard = null
    this.sequenceStepDragActiveMarkedRow = null
    this.suppressThreadEmbedHandleClick = false
    this.stepDragMoved = false
    this.boundStepMouseMove = this.onStepMouseMove.bind(this)
    this.boundStepMouseUp = this.onStepMouseUp.bind(this)
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)

    this.autosaveInFlight = false
    this.autosaveQueued = false
    this.autosaveQueuedSaveSteps = true
    this.autosaveQueuedMetaOnly = false
    this.dragCardSiblingsOrder = null

    if (this.nestedValue) {
      this.rootBundleMain = this.element.closest("main.sequence-editor--bundle")
      this.boundReadonlySync = (event) => {
        if (!event.detail || typeof event.detail.readonly !== "boolean") return
        if (!this.rootBundleMain?.contains(this.element)) return
        this.readonlyValue = event.detail.readonly
      }
      document.addEventListener("sequence-editor:readonly-sync", this.boundReadonlySync)
      if (this.rootBundleMain?.classList.contains("sequence-editor--readonly")) {
        this.readonlyValue = true
      }
    } else {
      this.boundGlobalMode = (event) => {
        if (!event.detail || typeof event.detail.readonly !== "boolean") return
        this.readonlyValue = event.detail.readonly
      }
      document.addEventListener("sequence-editor:global-mode", this.boundGlobalMode)
    }

    const url = new URL(window.location.href)
    if (!this.nestedValue) {
      const pref = getSequenceEditorReadonlyPreference()
      if (pref !== null) {
        this.readonlyValue = pref
      }
    }

    this.reindexSteps()
    this.activeCard = null
    this.applyReadonlyMode()
    this.maybeScrollToNewPipelineSequence()
    this.setupAutosaveListeners()

    this.boundIntentInputAutosize = (e) => {
      const t = e.target
      if (t?.tagName !== "TEXTAREA" || !t.classList?.contains("sequence-intent-input")) return
      this.autosizeIntentTextarea(t)
    }
    this.element.addEventListener("input", this.boundIntentInputAutosize)
    this.scheduleResizeAllIntentTextareas()
    if (document.fonts?.ready) {
      void document.fonts.ready.then(() => this.scheduleResizeAllIntentTextareas())
    }
  }

  readonlyValueChanged() {
    this.applyReadonlyMode()
  }

  get threadEmbedStructuralControlsEnabled() {
    return this.element.querySelector(".step-order-rail--thread-handle") !== null
  }

  readonlyBlocksStructure() {
    return this.readonlyValue && !this.threadEmbedStructuralControlsEnabled
  }

  applyReadonlyMode() {
    this.element.classList.toggle("sequence-editor--readonly", this.readonlyValue)

    if (this.nestedValue) {
      if (this.hasTitleInputTarget) {
        this.titleInputTarget.readOnly = this.readonlyValue
        if (this.hasIntentInputTarget) this.intentInputTarget.readOnly = this.readonlyValue
      }
    } else if (this.hasTitleInputTarget) {
      this.titleInputTarget.readOnly = this.readonlyValue
      if (this.hasIntentInputTarget) this.intentInputTarget.readOnly = this.readonlyValue
    }

    if (this.pipelineModeValue && !this.nestedValue) {
      this.element.querySelectorAll(
        ".bundle-pipeline-bundle-title-input, .bundle-pipeline-child-title-input, .bundle-pipeline-child-intent-input"
      ).forEach((el) => {
        el.readOnly = this.readonlyValue
      })
    }

    if (this.readonlyValue) {
      this.closeAllMenus()
      this.deactivateEditing()
      this.setAllEditorsReadOnly()
      this.topLevelStepRowsForDrag().forEach((card) => {
        card.setAttribute("draggable", "false")
      })
      this.clearDropIndicator()
      this.dragArmedCard = null
      this.draggedCard = null
      this.teardownStepPointerDrag()
    } else {
      this.installDragAndDrop()
      this.setAllEditorsReadOnly()
    }

    if (this.pipelineModeValue && !this.nestedValue) {
      document.dispatchEvent(
        new CustomEvent("sequence-editor:readonly-sync", { detail: { readonly: this.readonlyValue } })
      )
    }

    this.scheduleResizeAllIntentTextareas()
  }

  disconnect() {
    this.clearSequenceStepDragActiveMarker()
    this.teardownAutosaveListeners()
    this.teardownStepPointerDrag()
    document.removeEventListener("click", this.boundOutsideClick)
    if (this.nestedValue && this.boundReadonlySync) {
      document.removeEventListener("sequence-editor:readonly-sync", this.boundReadonlySync)
    }
    if (!this.nestedValue && this.boundGlobalMode) {
      document.removeEventListener("sequence-editor:global-mode", this.boundGlobalMode)
    }
    if (this.boundIntentInputAutosize) {
      this.element.removeEventListener("input", this.boundIntentInputAutosize)
    }
  }

  selectAllIfDefault(event) {
    if (this.readonlyValue) return
    const el = event.currentTarget
    let defaultText = ""
    if (el === this.titleInputTarget) defaultText = this.defaultTitleValue
    else if (el === this.intentInputTarget) defaultText = this.defaultIntentValue
    else return

    if (!defaultText || el.value !== defaultText) return

    requestAnimationFrame(() => {
      el.select()
    })
  }

  restoreDefaultIfEmpty(event) {
    if (this.readonlyValue) return
    const el = event.currentTarget
    if (el.value.trim() !== "") return

    if (el === this.titleInputTarget && this.defaultTitleValue) {
      el.value = this.defaultTitleValue
    } else if (el === this.intentInputTarget && this.defaultIntentValue) {
      el.value = this.defaultIntentValue
      this.autosizeIntentTextarea(el)
    }
  }

  autosizeIntentTextarea(textarea) {
    if (!textarea || textarea.tagName !== "TEXTAREA" || !textarea.classList.contains("sequence-intent-input")) return
    textarea.style.height = "auto"
    const maxPx = this.intentTextareaMaxHeightPx(textarea)
    const nextHeight = Number.isFinite(maxPx) ? Math.min(textarea.scrollHeight, maxPx) : textarea.scrollHeight
    textarea.style.height = `${nextHeight}px`
  }

  intentTextareaMaxHeightPx(textarea) {
    const raw = window.getComputedStyle(textarea).maxHeight
    if (!raw || raw === "none") return Number.POSITIVE_INFINITY
    const parsed = parseFloat(raw)
    return Number.isFinite(parsed) ? parsed : Number.POSITIVE_INFINITY
  }

  resizeAllIntentTextareas() {
    this.element.querySelectorAll("textarea.sequence-intent-input").forEach((el) => this.autosizeIntentTextarea(el))
  }

  scheduleResizeAllIntentTextareas() {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => this.resizeAllIntentTextareas())
    })
  }

  addStep() {
    if (this.readonlyValue) return
    if (this.pipelineModeValue && !this.nestedValue) {
      void this.pipelineAddStep({ anchorCard: null, placeBefore: false })
      return
    }
    const card = this.insertStep({ anchorCard: null, placeBefore: false })
    this.activateCard(card)
    this.queueStructureAutosave()
  }

  addStepBefore(event) {
    if (this.readonlyBlocksStructure()) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    if (this.pipelineModeValue && !this.nestedValue) {
      void this.pipelineAddStep({ anchorCard: card, placeBefore: true })
      return
    }
    const newCard = this.insertStep({ anchorCard: card, placeBefore: true })
    this.activateCard(newCard)
    this.queueStructureAutosave()
  }

  addStepAfter(event) {
    if (this.readonlyBlocksStructure()) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    if (this.pipelineModeValue && !this.nestedValue) {
      void this.pipelineAddStep({ anchorCard: card, placeBefore: false })
      return
    }
    const newCard = this.insertStep({ anchorCard: card, placeBefore: false })
    this.activateCard(newCard)
    this.queueStructureAutosave()
  }

  duplicateStep(event) {
    if (this.readonlyBlocksStructure()) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    let content = ""
    let sequenceId = ""
    if (this.pipelineModeValue) {
      const hidden = card.querySelector(".bundle-pipeline-sequence-id-field")
      sequenceId = hidden?.value || ""
    } else {
      const editor = card.querySelector('[data-sequence-editor-target="editor"]')
      content = editor ? editor.innerHTML.trim() : ""
    }
    const duplicated = this.insertStep({ anchorCard: card, placeBefore: false, content, sequenceId })
    this.activateCard(duplicated)
    if (this.pipelineModeValue && sequenceId) {
      window.location.reload()
      return
    }
    this.queueStructureAutosave()
  }

  async pipelineAddStep({ anchorCard = null, placeBefore = false }) {
    if (this.readonlyBlocksStructure() || this.pipelineAddInFlight) return
    this.pipelineAddInFlight = true
    this.closeAllMenus()

    try {
      const created = await this.createPipelineSequence()
      if (!created) return

      const card = this.insertStep({
        anchorCard,
        placeBefore,
        sequenceId: String(created.id)
      })
      if (!card) return

      try {
        sessionStorage.setItem(PIPELINE_SCROLL_AFTER_CREATE_KEY, String(created.id))
      } catch (_e) {
        /* ignore private mode / quota */
      }

      this.syncEditorsBeforeSubmit()
      const formEl = this.autosaveFormEl()
      if (formEl) await this.autosaveFormAsync(formEl)
      window.location.reload()
    } finally {
      this.pipelineAddInFlight = false
    }
  }

  async createPipelineSequence() {
    if (!this.pipelineCreateSequenceUrlValue) {
      window.alert("Create sequence is not configured.")
      return null
    }

    try {
      const response = await fetch(this.pipelineCreateSequenceUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": this.csrfToken()
        }
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        const msg = Array.isArray(data.error) ? data.error.join(" ") : (data.error || "Could not create sequence.")
        window.alert(msg)
        return null
      }

      const id = data.id
      if (id === undefined || id === null) {
        window.alert("Invalid response while creating sequence.")
        return null
      }

      return { id, title: data.title ?? "" }
    } catch (_err) {
      window.alert("Network error while creating sequence.")
      return null
    }
  }

  maybeScrollToNewPipelineSequence() {
    if (!this.pipelineModeValue || this.nestedValue || !this.pipelineCreateSequenceUrlValue) return

    let raw = ""
    try {
      raw = sessionStorage.getItem(PIPELINE_SCROLL_AFTER_CREATE_KEY) || ""
    } catch (_e) {
      return
    }
    const idStr = raw.trim()
    if (!/^\d+$/.test(idStr)) return

    try {
      sessionStorage.removeItem(PIPELINE_SCROLL_AFTER_CREATE_KEY)
    } catch (_e) {
      /* ignore */
    }

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        const esc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape(idStr) : idStr
        const row = document.querySelector(
          `[data-bundle-pipeline-seq-id="${esc}"][data-sequence-editor-target="pipelineStepRow"]`
        )
        if (!row) return

        row.scrollIntoView({ block: "start", behavior: "auto", inline: "nearest" })

        if (this.readonlyValue) return
        const focusEl =
          row.querySelector(".bundle-pipeline-child-title-input") ||
          row.querySelector(".bundle-pipeline-child-intent-input")
        if (!focusEl || typeof focusEl.focus !== "function") return
        try {
          focusEl.focus({ preventScroll: true })
        } catch (_e2) {
          focusEl.focus()
        }
      })
    })
  }

  toggleMenu(event) {
    if (this.readonlyValue) return
    event.stopPropagation()
    const menuWrap = event.currentTarget.closest(".step-menu-wrap")
    const menu = menuWrap.querySelector('[data-sequence-editor-target="menu"]')
    const open = !menu.hidden

    this.closeAllMenus()
    menu.hidden = open
  }

  openThreadEmbedStepMenu(event) {
    if (this.readonlyBlocksStructure()) return
    event.preventDefault()
    event.stopPropagation()
    this.showThreadEmbedStepHandleMenu(event.currentTarget)
  }

  threadHandleMenuKeydown(event) {
    if (this.readonlyBlocksStructure()) return
    const keyOk = event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")
    if (!keyOk) return
    event.preventDefault()
    event.stopPropagation()
    this.showThreadEmbedStepHandleMenu(event.currentTarget)
  }

  toggleThreadEmbedStepHandleMenu(event) {
    if (this.readonlyBlocksStructure()) return
    if (this.suppressThreadEmbedHandleClick) return
    event.preventDefault()
    event.stopPropagation()
    const button = event.currentTarget
    if (!button.matches?.(".thread-embed-sequence-step-drag-handle")) return
    const wrap = button.closest(".thread-step-handle-wrap")
    const menu = wrap?.querySelector(".step-menu--thread-handle[data-sequence-editor-target=\"menu\"]")
    if (!menu) return
    const wasOpen = !menu.hidden
    this.closeAllMenus()
    if (wasOpen) return
    menu.hidden = false
    button.setAttribute("aria-expanded", "true")
  }

  showThreadEmbedStepHandleMenu(button) {
    if (this.readonlyBlocksStructure()) return
    const wrap = button?.closest(".thread-step-handle-wrap")
    const menu = wrap?.querySelector(".step-menu--thread-handle[data-sequence-editor-target=\"menu\"]")
    if (!menu) return
    this.closeAllMenus()
    menu.hidden = false
    button?.setAttribute("aria-expanded", "true")
  }

  copyPipelineChildAsText(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeAllMenus()

    const pipelineRow = event.currentTarget.closest('[data-editor-kind="bundle_pipeline_slot"]')
    let text = buildBundlePipelineChildCopyTextFromPipelineRow(pipelineRow)

    if (!text) {
      text = parseCopyTextDataset(event.currentTarget.dataset.copyText)
    }

    if (!text) return
    void navigator.clipboard.writeText(text)
  }

  unbundlePipelineChild(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeAllMenus()

    const pipelineRow = event.currentTarget.closest('[data-editor-kind="bundle_pipeline_slot"]')
    const sequenceIdRaw = pipelineRow?.dataset?.bundlePipelineSeqId || pipelineRow?.getAttribute("data-bundle-pipeline-seq-id")
    const sequenceId = sequenceIdRaw ? parseInt(String(sequenceIdRaw), 10) : 0

    if (
      !sequenceId ||
      !this.bundleIdValue ||
      !this.hasUnbundleProjectIdValue ||
      !this.unbundleProjectIdValue ||
      !this.hasUnbundleThreadIdValue ||
      !this.unbundleThreadIdValue
    ) {
      window.alert("Unbundle is not available in this context.")
      return
    }

    const form = this.element.querySelector("form.sequence-form")
    const redirectTo =
      form?.querySelector('input[name="redirect_to"]')?.value || `${window.location.pathname}${window.location.search}`
    const weaveThread = form?.querySelector('input[name="weave_thread"]')?.value

    const url = `/projects/${this.unbundleProjectIdValue}/sequences/${this.unbundleThreadIdValue}/thread_unbundle_pipeline_sequence`
    const fd = new FormData()
    const token = this.csrfToken()
    if (!token) {
      window.alert("Missing CSRF token.")
      return
    }
    fd.append("authenticity_token", token)
    fd.append("bundle_id", String(this.bundleIdValue))
    fd.append("sequence_id", String(sequenceId))
    fd.append("redirect_to", redirectTo)
    if (weaveThread) fd.append("weave_thread", weaveThread)

    void (async () => {
      try {
        const response = await fetch(url, {
          method: "POST",
          credentials: "same-origin",
          headers: {
            Accept: "text/html, application/xhtml+xml",
            "X-CSRF-Token": token,
            "X-Requested-With": "XMLHttpRequest"
          },
          body: fd
        })
        if (response.ok) {
          if (response.redirected && response.url) {
            if (window.Turbo && typeof window.Turbo.visit === "function") {
              window.Turbo.visit(response.url)
            } else {
              window.location.assign(response.url)
            }
          } else {
            window.location.reload()
          }
          return
        }
        window.alert("Could not unbundle.")
      } catch (_err) {
        window.alert("Network error while unbundling.")
      }
    })()
  }

  handleOutsideClick(event) {
    if (event.target.closest(".step-menu-wrap")) return
    if (event.target.closest(".sequence-nav-menu-wrap")) return
    this.closeAllMenus()

    if (this.readonlyValue) return

    if (this.activeCard && !this.activeCard.contains(event.target)) {
      this.deactivateEditing()
    }
  }

  deactivateEditing() {
    this.syncEditorValuesFromDOM()
    this.activeCard = null
    this.clearSequenceStepDragActiveMarker()
    this.setAllEditorsReadOnly()
  }

  clearSequenceStepDragActiveMarker() {
    if (!this.sequenceStepDragActiveMarkedRow) return
    this.sequenceStepDragActiveMarkedRow.classList.remove(SEQUENCE_STEP_ROW_ACTIVE_DRAG_CLASS)
    this.sequenceStepDragActiveMarkedRow = null
  }

  refreshSequenceStepDragActiveMarker() {
    this.clearSequenceStepDragActiveMarker()
    const row = this.activeCard
    if (!row || typeof row.matches !== "function") return
    if (!row.matches(SEQUENCE_STEP_ROW_SELECTOR)) return
    row.classList.add(SEQUENCE_STEP_ROW_ACTIVE_DRAG_CLASS)
    this.sequenceStepDragActiveMarkedRow = row
  }

  syncEditorValuesFromDOM() {
    if (this.pipelineModeValue) return
    this.editorTargets.forEach((editor) => {
      const row = editor.closest(SEQUENCE_STEP_ROW_SELECTOR)
      if (!row || row.hidden) return
      this.syncAndTrimStepEditor(editor)
    })
  }

  syncAndTrimStepEditor(editor) {
    const inner = editor.closest(".step-card")
    const contentInput = inner?.querySelector('[data-sequence-editor-target="contentInput"]')
    const trimmed = trimStepEditorHtml(editor.innerHTML)
    if (editor.innerHTML !== trimmed) editor.innerHTML = trimmed
    if (contentInput) contentInput.value = trimmed
    return trimmed
  }

  setAllEditorsReadOnly() {
    if (this.pipelineModeValue) return
    this.editorTargets.forEach((editor) => {
      const row = editor.closest(SEQUENCE_STEP_ROW_SELECTOR)
      if (!row || row.hidden) return
      editor.contentEditable = "false"
    })
  }

  closeAllMenus() {
    this.menuTargets.forEach((menu) => {
      menu.hidden = true
    })
    this.element.querySelectorAll(".thread-embed-sequence-step-drag-handle").forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
  }

  moveUp(event) {
    if (this.readonlyBlocksStructure()) return
    this.closeAllMenus()
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, -1)
  }

  moveDown(event) {
    if (this.readonlyBlocksStructure()) return
    this.closeAllMenus()
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, 1)
  }

  handleEditorKeydown(event) {
    if (this.pipelineModeValue) return
    if (this.readonlyValue) return
    if (!event.ctrlKey) return

    const editor = event.currentTarget
    if (editor.contentEditable === "true") {
      const key = event.key.toLowerCase()
      if (key === "b" || key === "i") {
        event.preventDefault()
        document.execCommand(key === "b" ? "bold" : "italic", false)
        this.syncContentInputFromEditor(editor)
        this.markAutosaveDirty()
        return
      }

      if (event.shiftKey && (key === "p" || key === "n")) {
        event.preventDefault()
        const card = editor.closest(SEQUENCE_STEP_ROW_SELECTOR)
        if (!card) return
        this.focusStepByOffset(card, key === "p" ? -1 : 1)
        return
      }

      if (event.shiftKey && key === "d") {
        event.preventDefault()
        const card = editor.closest(SEQUENCE_STEP_ROW_SELECTOR)
        this.removeStepCard(card)
        return
      }
    }

    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      const card = this.cardFromEvent(event)
      if (!card) return

      if (event.shiftKey) {
        event.preventDefault()
        this.closeAllMenus()
        const newCard = this.insertStep({
          anchorCard: card,
          placeBefore: event.key === "ArrowUp"
        })
        if (newCard) {
          this.activateCard(newCard)
          this.queueStructureAutosave()
        }
        return
      }

      event.preventDefault()
      this.moveCardByOffset(card, event.key === "ArrowUp" ? -1 : 1)
      this.activateCard(card)
      const editor = card.querySelector('[data-sequence-editor-target="editor"]')
      if (editor) editor.focus()
    }
  }

  handleEditorPaste(event) {
    if (this.pipelineModeValue) return
    if (this.readonlyValue) return
    const editor = event.currentTarget
    if (editor.contentEditable !== "true") return

    const html = event.clipboardData?.getData("text/html") ?? ""
    const plain = event.clipboardData?.getData("text/plain") ?? ""
    const items = this.extractListItemsFromClipboard(html, plain)
    if (!items || items.length < 2) return

    event.preventDefault()
    event.stopPropagation()

    const row = editor.closest(SEQUENCE_STEP_ROW_SELECTOR)
    const fragments = items.map((raw) => this.normalizePastedStepHtml(raw))

    editor.innerHTML = fragments[0]
    this.syncContentInputFromEditor(editor)

    let anchor = row
    for (let i = 1; i < fragments.length; i++) {
      anchor = this.insertStep({ anchorCard: anchor, placeBefore: false, content: fragments[i] })
    }

    this.activateCard(row)
    this.queueStructureAutosave()
  }

  extractListItemsFromClipboard(html, plain) {
    const fromHtmlLists = this.tryParseHtmlList(html)
    if (fromHtmlLists && fromHtmlLists.length >= 2) return fromHtmlLists

    const fromHtmlParagraphs = this.tryParseHtmlParagraphList(html)
    if (fromHtmlParagraphs && fromHtmlParagraphs.length >= 2) return fromHtmlParagraphs

    const fromPlain = this.tryParsePlainTextList(plain)
    if (fromPlain && fromPlain.length >= 2) return fromPlain

    return null
  }

  tryParseHtmlParagraphList(html) {
    if (!html || !html.trim()) return null
    try {
      const doc = new DOMParser().parseFromString(html, "text/html")
      const kids = [...doc.body.children].filter((el) => el.tagName === "P")
      if (kids.length < 2) return null

      const marker = /^(?:[-*+]|\d+[.)]|[•◦▪▸])\s+/
      const items = []
      for (const p of kids) {
        const text = p.textContent.trim()
        if (!marker.test(text)) return null
        items.push(p.innerHTML.trim())
      }
      return items.length >= 2 ? items : null
    } catch (_err) {
      return null
    }
  }

  tryParseHtmlList(html) {
    if (!html || !html.trim()) return null
    try {
      const doc = new DOMParser().parseFromString(html, "text/html")
      const lists = doc.querySelectorAll("ul, ol")
      if (!lists.length) return null

      const items = []
      lists.forEach((list) => {
        list.querySelectorAll(":scope > li").forEach((li) => {
          const inner = li.innerHTML.trim()
          if (inner) items.push(inner)
        })
      })
      return items.length >= 2 ? items : null
    } catch (_err) {
      return null
    }
  }

  tryParsePlainTextList(text) {
    if (!text || typeof text !== "string") return null
    const lines = text.split(/\r?\n/)
    const items = []
    let current = null

    for (const line of lines) {
      const trimmed = line.trim()
      const markerMatch = trimmed.match(/^(?:[-*+]|\d+[.)]|[•◦▪▸])\s+(.*)$/)

      if (markerMatch) {
        if (current !== null) items.push(current)
        current = markerMatch[1].trim()
      } else if (trimmed === "") {
        continue
      } else if (current !== null) {
        current += "\n" + trimmed
      } else {
        return null
      }
    }

    if (current !== null) items.push(current)
    return items.length >= 2 ? items : null
  }

  normalizePastedStepHtml(raw) {
    const s = raw.trim()
    if (!s) return "<p></p>"
    if (/<[a-z][^>]*>/i.test(s)) {
      return s
    }
    return `<p>${this.escapeHtml(s).replace(/\n/g, "<br>")}</p>`
  }

  escapeHtml(text) {
    const el = document.createElement("div")
    el.textContent = text
    return el.innerHTML
  }

  syncContentInputFromEditor(editor) {
    const card = editor.closest(".step-card")
    const contentInput = card?.querySelector('[data-sequence-editor-target="contentInput"]')
    if (contentInput) contentInput.value = editor.innerHTML.trim()
  }

  stepsListElement() {
    if (this.pipelineModeValue && this.hasPipelineStepsListTarget) return this.pipelineStepsListTarget
    if (this.hasStepsListTarget) return this.stepsListTarget
    return this.element.querySelector('[data-sequence-editor-target="stepsList"]')
  }

  topLevelStepRowsForDrag() {
    if (this.pipelineModeValue && this.hasPipelineStepRowTarget) return this.pipelineStepRowTargets
    return this.stepCardTargets
  }

  visibleCards() {
    return this.topLevelStepRowsForDrag().filter((card) => !card.hidden)
  }

  moveCardByOffset(card, offset) {
    if (this.readonlyBlocksStructure()) return
    const cards = this.visibleCards()
    const index = cards.indexOf(card)
    if (index < 0) return

    const destinationIndex = index + offset
    if (destinationIndex < 0 || destinationIndex >= cards.length) return

    const destination = cards[destinationIndex]
    const list = this.stepsListElement()
    if (offset < 0) {
      list.insertBefore(card, destination)
    } else {
      list.insertBefore(destination, card)
    }
    this.reindexSteps()
    this.queueStructureAutosave()
  }

  focusStepByOffset(card, offset) {
    const cards = this.visibleCards()
    const index = cards.indexOf(card)
    if (index < 0) return

    const targetIndex = index + offset
    if (targetIndex < 0 || targetIndex >= cards.length) return

    this.activateCard(cards[targetIndex])
  }

  deleteStep(event) {
    this.removeStepCard(this.cardFromEvent(event))
  }

  removeStepCard(card) {
    if (this.readonlyBlocksStructure() || !card) return

    this.closeAllMenus()
    card.remove()

    if (this.activeCard === card) {
      this.deactivateEditing()
    }

    this.reindexSteps()
    this.queueStructureAutosave()
  }

  activateStep(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.activateCard(card, event)
  }

  activateCard(row, activatingEvent = null) {
    if (this.readonlyValue) return
    if (!row || row.hidden) return
    this.syncEditorValuesFromDOM()
    this.activeCard = row
    this.refreshSequenceStepDragActiveMarker()
    this.setAllEditorsReadOnly()
    if (this.pipelineModeValue) {
      const titleInput = row.querySelector(".bundle-pipeline-child-title-input")

      const t = activatingEvent?.target
      if (
        t &&
        typeof t.closest === "function" &&
        (t.closest(".bundle-pipeline-child-title-input") ||
          t.closest(".bundle-pipeline-child-intent-input"))
      ) {
        return
      }

      if (titleInput && !this.readonlyValue) {
        requestAnimationFrame(() => titleInput.focus())
      }
      return
    }
    const editor = row.querySelector('[data-sequence-editor-target="editor"]')
    if (editor) editor.contentEditable = "true"
    if (editor) {
      requestAnimationFrame(() => editor.focus())
    }
  }

  syncEditor(event) {
    if (this.readonlyValue) return
    const editor = event.currentTarget
    const card = editor.closest(".step-card")
    const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
    if (!contentInput) return
    contentInput.value = editor.innerHTML.trim()
    this.markAutosaveDirty()
  }

  syncNestedEditorsBeforeSubmit() {
    const root = this.element.closest("main.sequence-editor--bundle")
    if (!root) return

    root.querySelectorAll(".nested-sequence-editor").forEach((nestedEl) => {
      const stepsRoot = nestedEl.querySelector(":scope > .nested-sequence-editor-steps")
      if (!stepsRoot) return

      const prefix = nestedEl.getAttribute("data-sequence-editor-nested-field-prefix-value") || ""
      const cards = [...stepsRoot.querySelectorAll(`:scope > ${SEQUENCE_STEP_ROW_SELECTOR}`)].filter((c) => !c.hidden)

      cards.forEach((card, index) => {
        const label = card.querySelector('[data-sequence-editor-target="stepLabel"]')
        const positionInput = card.querySelector('[data-sequence-editor-target="positionInput"]')
        const destroyInput = card.querySelector('[data-sequence-editor-target="destroyInput"]')
        const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
        const editor = card.querySelector('[data-sequence-editor-target="editor"]')
        const upButton = card.querySelector('[data-step-control="up"]')
        const downButton = card.querySelector('[data-step-control="down"]')

        if (label) label.textContent = String(index + 1)
        if (positionInput) {
          positionInput.value = String(index + 1)
          if (prefix) positionInput.name = `${prefix}[steps_attributes][${index}][position]`
        }
        if (destroyInput && prefix) destroyInput.name = `${prefix}[steps_attributes][${index}][_destroy]`
        if (contentInput) {
          if (editor) contentInput.value = this.syncAndTrimStepEditor(editor)
          if (prefix) contentInput.name = `${prefix}[steps_attributes][${index}][content]`
        }
        if (upButton) upButton.disabled = index === 0
        if (downButton) downButton.disabled = index === cards.length - 1
      })
    })
  }

  syncEditorsBeforeSubmit() {
    this.syncTextInputsBeforeSubmit()
    if (this.pipelineModeValue && !this.nestedValue) {
      this.syncNestedEditorsBeforeSubmit()
    }
    if (!this.pipelineModeValue) {
      this.editorTargets.forEach((editor) => {
        this.syncAndTrimStepEditor(editor)
      })
    }
    this.reindexSteps()
  }

  syncTextInputsBeforeSubmit() {
    if (this.hasTitleInputTarget) trimTrailingWhitespaceInPlace(this.titleInputTarget)
    if (this.hasIntentInputTarget) trimTrailingWhitespaceInPlace(this.intentInputTarget)
    this.element
      .querySelectorAll(
        ".bundle-pipeline-bundle-title-input, .bundle-pipeline-child-title-input, .bundle-pipeline-child-intent-input"
      )
      .forEach((input) => trimTrailingWhitespaceInPlace(input))
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  installDragAndDrop() {
    this.topLevelStepRowsForDrag().forEach((card) => {
      card.setAttribute("draggable", "false")
    })
  }

  stepRowAtClientY(clientY) {
    const cards = this.visibleCards()
    for (const row of cards) {
      const rect = row.getBoundingClientRect()
      if (clientY >= rect.top && clientY <= rect.bottom) return row
    }

    let nearest = null
    let nearestDist = Infinity
    for (const row of cards) {
      const rect = row.getBoundingClientRect()
      const centerY = rect.top + rect.height / 2
      const dist = Math.abs(clientY - centerY)
      if (dist < nearestDist) {
        nearestDist = dist
        nearest = row
      }
    }
    return nearest
  }

  teardownStepPointerDrag() {
    document.removeEventListener("mousemove", this.boundStepMouseMove)
    document.removeEventListener("mouseup", this.boundStepMouseUp, true)
    if (this.draggedCard) {
      this.draggedCard.classList.remove("dragging")
    }
    this.stepDragMoved = false
    this.dragArmedCard = null
    this.draggedCard = null
    this.dragCardSiblingsOrder = null
    this.clearDropIndicator()
  }

  onStepMouseMove(event) {
    if (!this.dragArmedCard || this.readonlyBlocksStructure()) return

    const dy = Math.abs(event.clientY - this.stepDragStartY)
    if (!this.stepDragMoved) {
      if (dy < 4) return
      this.stepDragMoved = true
      this.draggedCard = this.dragArmedCard
      this.dragCardSiblingsOrder = this.visibleCards().slice()
      this.draggedCard.classList.add("dragging")
      this.suppressThreadEmbedHandleClick = true
    }

    event.preventDefault()

    const target = this.stepRowAtClientY(event.clientY)
    if (!target || target === this.draggedCard) return

    const rect = target.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    const list = this.stepsListElement()
    if (!list) return

    const reference = before ? target : target.nextElementSibling
    if (reference === this.draggedCard) return
    list.insertBefore(this.draggedCard, reference)
    this.applyDropIndicator(target, before)
  }

  onStepMouseUp() {
    document.removeEventListener("mousemove", this.boundStepMouseMove)
    document.removeEventListener("mouseup", this.boundStepMouseUp, true)

    if (this.draggedCard) {
      this.draggedCard.classList.remove("dragging")
      this.clearDropIndicator()
      const before = this.dragCardSiblingsOrder
      const after = this.visibleCards()
      const orderChanged =
        !before ||
        before.length !== after.length ||
        after.some((c, i) => c !== before[i])
      if (orderChanged) {
        this.reindexSteps()
        this.queueStructureAutosave()
      }
      window.setTimeout(() => {
        this.suppressThreadEmbedHandleClick = false
      }, 0)
    }

    this.stepDragMoved = false
    this.dragArmedCard = null
    this.draggedCard = null
    this.dragCardSiblingsOrder = null
  }

  armDrag(event) {
    if (this.readonlyBlocksStructure()) return
    if (event.button !== undefined && event.button !== 0) return

    const card = this.cardFromEvent(event)
    if (!card) return

    this.teardownStepPointerDrag()
    this.dragArmedCard = card
    this.stepDragStartY = event.clientY
    this.stepDragMoved = false

    document.addEventListener("mousemove", this.boundStepMouseMove)
    document.addEventListener("mouseup", this.boundStepMouseUp, true)
  }

  disarmDrag(_event) {
    // Pointer drag completes on document mouseup (see armDrag).
  }

  applyDropIndicator(card, before) {
    if (this.dropIndicatorCard && this.dropIndicatorCard !== card) {
      this.dropIndicatorCard.classList.remove("drop-before", "drop-after")
    }

    this.dropIndicatorCard = card
    card.classList.toggle("drop-before", before)
    card.classList.toggle("drop-after", !before)
  }

  clearDropIndicator() {
    if (!this.dropIndicatorCard) return
    this.dropIndicatorCard.classList.remove("drop-before", "drop-after")
    this.dropIndicatorCard = null
  }

  reindexSteps() {
    if (this.pipelineModeValue && !this.nestedValue) {
      this.reindexPipelineSteps()
      return
    }

    const cards = this.visibleCards()
    const prefix = this.nestedFieldPrefixValue
    const fieldBase = prefix ? `${prefix}[steps_attributes]` : "sequence[steps_attributes]"

    cards.forEach((card, index) => {
      const label = card.querySelector('[data-sequence-editor-target="stepLabel"]')
      const positionInput = card.querySelector('[data-sequence-editor-target="positionInput"]')
      const destroyInput = card.querySelector('[data-sequence-editor-target="destroyInput"]')
      const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
      const upButton = card.querySelector('[data-step-control="up"]')
      const downButton = card.querySelector('[data-step-control="down"]')

      const base = `${fieldBase}[${index}]`
      if (label) label.textContent = String(index + 1)
      if (positionInput) {
        positionInput.value = String(index + 1)
        positionInput.name = `${base}[position]`
      }
      if (destroyInput) destroyInput.name = `${base}[_destroy]`
      if (contentInput) contentInput.name = `${base}[content]`

      if (upButton) upButton.disabled = index === 0
      if (downButton) downButton.disabled = index === cards.length - 1
    })
  }

  reindexPipelineSteps() {
    const cards = this.visibleCards()
    cards.forEach((card, index) => {
      const article = card.querySelector(":scope > article.bundle-pipeline-step-card")
      if (!article) return

      const label = article.querySelector(".bundle-pipeline-step-number [data-sequence-editor-target=\"stepLabel\"]")
      const meta = article.querySelector(":scope > .step-hidden-fields")
      const positionInput = meta?.querySelector('[data-sequence-editor-target="positionInput"]')
      const sequenceIdField = article.querySelector(".bundle-pipeline-sequence-id-field")
      const upButton = card.querySelector(':scope > .step-order-rail [data-step-control="up"]')
      const downButton = card.querySelector(':scope > .step-order-rail [data-step-control="down"]')

      if (label) label.textContent = String(index + 1)
      if (positionInput) {
        positionInput.value = String(index + 1)
        positionInput.name = `sequence[steps_attributes][${index}][position]`
      }
      const destroyInput = meta?.querySelector('[data-sequence-editor-target="destroyInput"]')
      if (destroyInput) {
        destroyInput.name = `sequence[steps_attributes][${index}][_destroy]`
      }
      if (sequenceIdField) {
        sequenceIdField.name = `sequence[steps_attributes][${index}][sequence_id]`
      }

      const hiddenId = article.querySelector(
        'input.bundle-pipeline-sequence-id-field[type="hidden"]'
      )
      const childId = hiddenId?.value
      const titleInput = article.querySelector(".bundle-pipeline-child-title-input")
      const intentInput = article.querySelector(".bundle-pipeline-child-intent-input")
      if (titleInput && childId) titleInput.name = `nested_sequences[${childId}][title]`
      if (intentInput && childId) intentInput.name = `nested_sequences[${childId}][intent]`

      if (upButton) upButton.disabled = index === 0
      if (downButton) downButton.disabled = index === cards.length - 1
    })
  }

  cardFromEvent(event) {
    if (this.pipelineModeValue && !this.nestedValue) {
      return event.currentTarget.closest('[data-sequence-editor-target="pipelineStepRow"]')
    }
    return event.currentTarget.closest(SEQUENCE_STEP_ROW_SELECTOR)
  }

  insertStep({ anchorCard = null, placeBefore = false, content = "", sequenceId = "" }) {
    if (this.readonlyBlocksStructure()) return null
    const token = `${Date.now()}_${Math.floor(Math.random() * 100000)}`
    const html = this.stepTemplateTarget.innerHTML.replaceAll("NEW_RECORD", token)

    const list = this.stepsListElement()
    const endAnchor = list.querySelector(STEPS_LIST_END_ANCHOR_SELECTOR)

    if (anchorCard && placeBefore) {
      anchorCard.insertAdjacentHTML("beforebegin", html)
    } else if (anchorCard) {
      const next = anchorCard.nextElementSibling
      if (next && next.matches(STEPS_LIST_END_ANCHOR_SELECTOR)) {
        next.insertAdjacentHTML("beforebegin", html)
      } else {
        anchorCard.insertAdjacentHTML("afterend", html)
      }
    } else if (endAnchor) {
      endAnchor.insertAdjacentHTML("beforebegin", html)
    } else {
      list.insertAdjacentHTML("beforeend", html)
    }

    const cards = this.visibleCards()
    const card = anchorCard
      ? placeBefore
        ? anchorCard.previousElementSibling
        : anchorCard.nextElementSibling
      : cards[cards.length - 1]

    if (this.pipelineModeValue) {
      const field = card?.querySelector(".bundle-pipeline-sequence-id-field")
      if (field && sequenceId) field.value = String(sequenceId)
    } else {
      const editor = card.querySelector('[data-sequence-editor-target="editor"]')
      const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
      if (editor && contentInput) {
        editor.innerHTML = content
        contentInput.value = content
      }
    }

    this.installDragAndDrop()
    this.reindexSteps()
    return card
  }

  setupAutosaveListeners() {
    this.boundGenerativeStepFocusOut = this.onGenerativeStepEditorFocusOut.bind(this)
    this.boundPipelineMetaFocusOut = this.onPipelineMetaFocusOut.bind(this)
    this.boundNestedEditorFocusOut = this.onNestedStepEditorFocusOut.bind(this)
    this.boundDocVisibility = this.onDocumentVisibilityChange.bind(this)
    this.boundPageHide = this.onDocumentPageHide.bind(this)

    if (!this.nestedValue) {
      document.addEventListener("visibilitychange", this.boundDocVisibility)
      window.addEventListener("pagehide", this.boundPageHide)
    }

    if (!this.nestedValue && !this.pipelineModeValue) {
      this.element.addEventListener("focusout", this.boundGenerativeStepFocusOut, true)
    }
    if (this.pipelineModeValue && !this.nestedValue) {
      this.element.addEventListener("focusout", this.boundPipelineMetaFocusOut, true)
      this.boundPipelineChildInput = this.onPipelineChildInput.bind(this)
      this.element.addEventListener("input", this.boundPipelineChildInput, true)
    }
    if (this.nestedValue) {
      this.element.addEventListener("focusout", this.boundNestedEditorFocusOut, true)
    }
  }

  teardownAutosaveListeners() {
    if (this.boundGenerativeStepFocusOut) {
      this.element.removeEventListener("focusout", this.boundGenerativeStepFocusOut, true)
    }
    if (this.boundPipelineMetaFocusOut) {
      this.element.removeEventListener("focusout", this.boundPipelineMetaFocusOut, true)
    }
    if (this.boundPipelineChildInput) {
      this.element.removeEventListener("input", this.boundPipelineChildInput, true)
    }
    if (this.boundNestedEditorFocusOut) {
      this.element.removeEventListener("focusout", this.boundNestedEditorFocusOut, true)
    }
    if (this.boundDocVisibility) {
      document.removeEventListener("visibilitychange", this.boundDocVisibility)
    }
    if (this.boundPageHide) {
      window.removeEventListener("pagehide", this.boundPageHide)
    }
  }

  autosaveFormEl() {
    if (this.hasFormTarget) return this.formTarget
    return this.element.closest("form#sequence-edit-form")
  }

  markAutosaveDirty() {
    const form = this.autosaveFormEl()
    if (form) form.dataset.promptlabAutosaveDirty = "1"
  }

  clearAutosaveDirty(form) {
    const f = form || this.autosaveFormEl()
    if (f) delete f.dataset.promptlabAutosaveDirty
  }

  async autosaveFormAsync(form, { saveSteps = true, trigger = "unknown" } = {}) {
    if (!form || this.readonlyBlocksStructure()) return
    if (this.autosaveInFlight) {
      this.autosaveQueued = true
      this.autosaveQueuedSaveSteps = saveSteps
      return
    }
    this.syncEditorsBeforeSubmit()
    this.autosaveInFlight = true
    try {
      const res = await fetchAutosaveForm(form, { saveSteps })
      await this.handleAutosaveResponse(res, form)
    } catch (err) {
      console.warn("Autosave request failed", err)
    } finally {
      this.autosaveInFlight = false
      if (this.autosaveQueued) {
        const queuedSaveSteps = this.autosaveQueuedSaveSteps
        this.autosaveQueued = false
        this.autosaveQueuedSaveSteps = true
        await this.autosaveFormAsync(form, { saveSteps: queuedSaveSteps })
      }
    }
  }

  async autosaveSequenceMetaAsync(form) {
    if (!form || this.readonlyBlocksStructure()) return
    if (this.autosaveInFlight) {
      this.autosaveQueued = true
      this.autosaveQueuedMetaOnly = true
      return
    }
    this.syncTextInputsBeforeSubmit()
    this.autosaveInFlight = true
    try {
      const res = await fetchAutosaveSequenceMeta(form)
      await this.handleAutosaveResponse(res, form)
    } catch (err) {
      console.warn("Autosave request failed", err)
    } finally {
      this.autosaveInFlight = false
      if (this.autosaveQueued) {
        const metaOnly = this.autosaveQueuedMetaOnly
        this.autosaveQueued = false
        this.autosaveQueuedMetaOnly = false
        if (metaOnly) await this.autosaveSequenceMetaAsync(form)
        else await this.autosaveFormAsync(form, { saveSteps: this.autosaveQueuedSaveSteps ?? true })
      }
    }
  }

  async autosavePipelineChildMetaAsync(form, pipelineRow) {
    if (!form || !pipelineRow || this.readonlyBlocksStructure()) return
    if (this.autosaveInFlight) {
      this.autosaveQueued = true
      this.autosaveQueuedMetaOnly = true
      return
    }
    this.syncTextInputsBeforeSubmit()
    this.autosaveInFlight = true
    try {
      const res = await fetchAutosavePipelineChildMeta(form, pipelineRow)
      await this.handleAutosaveResponse(res, form)
    } catch (err) {
      console.warn("Autosave request failed", err)
    } finally {
      this.autosaveInFlight = false
      if (this.autosaveQueued) {
        const metaOnly = this.autosaveQueuedMetaOnly
        this.autosaveQueued = false
        this.autosaveQueuedMetaOnly = false
        if (metaOnly) await this.autosavePipelineChildMetaAsync(form, pipelineRow)
        else await this.autosaveFormAsync(form, { saveSteps: this.autosaveQueuedSaveSteps ?? true })
      }
    }
  }

  async handleAutosaveResponse(res, form) {
    if (res.ok) {
      this.clearAutosaveDirty(form)
      const ct = res.headers.get("Content-Type") || ""
      if (ct.includes("application/json")) {
        const data = await res.json().catch(() => null)
        this.applyAutosaveResponseToThreadIndex(data)
      }
    } else if (res.status === 422) {
      const data = await res.json().catch(() => ({}))
      console.warn("Autosave failed", data.errors)
    }
  }

  flushAutosaveIfDirty() {
    if (this.readonlyValue) return
    const form = this.autosaveFormEl()
    if (!form || form.dataset.promptlabAutosaveDirty !== "1") return
    void this.autosaveFormAsync(form, { saveSteps: true, trigger: "flush_dirty" })
  }

  onDocumentVisibilityChange() {
    if (document.visibilityState === "hidden") this.flushAutosaveIfDirty()
  }

  onDocumentPageHide() {
    this.flushAutosaveIfDirty()
  }

  autosaveOnMetaBlur() {
    if (this.readonlyValue || this.nestedValue) return
    requestAnimationFrame(() => void this.autosaveSequenceMetaAsync(this.autosaveFormEl()))
  }

  markAutosaveDirtyFromInput() {
    if (this.readonlyValue) return
    this.markAutosaveDirty()
  }

  onGenerativeStepEditorFocusOut(event) {
    if (this.readonlyValue || this.pipelineModeValue || this.nestedValue) return
    const t = event.target
    if (!t.matches?.('[data-sequence-editor-target="editor"]')) return
    const area = t.closest(".step-content-area")
    const rel = event.relatedTarget
    if (rel && area?.contains(rel)) return
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl(), { saveSteps: true, trigger: "step_focus_out" }))
  }

  onPipelineMetaFocusOut(event) {
    if (this.readonlyValue || !this.pipelineModeValue || this.nestedValue) return
    const t = event.target
    if (
      !t.classList?.contains("bundle-pipeline-child-title-input") &&
      !t.classList?.contains("bundle-pipeline-child-intent-input") &&
      !t.classList?.contains("bundle-pipeline-bundle-title-input")
    ) {
      return
    }
    const pipelineRow = t.closest('[data-sequence-editor-target="pipelineStepRow"]')
    requestAnimationFrame(() =>
      void this.autosavePipelineChildMetaAsync(this.autosaveFormEl(), pipelineRow)
    )
  }

  onPipelineChildInput(event) {
    if (this.readonlyValue || !this.pipelineModeValue || this.nestedValue) return
    const t = event.target
    if (
      !t.classList?.contains("bundle-pipeline-child-title-input") &&
      !t.classList?.contains("bundle-pipeline-child-intent-input") &&
      !t.classList?.contains("bundle-pipeline-bundle-title-input")
    ) {
      return
    }
    this.markAutosaveDirty()
  }

  onNestedStepEditorFocusOut(event) {
    if (this.readonlyValue || !this.nestedValue) return
    const t = event.target
    if (!t.matches?.('[data-sequence-editor-target="editor"]')) return
    const area = t.closest(".step-content-area")
    const rel = event.relatedTarget
    if (rel && area?.contains(rel)) return
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl(), { saveSteps: true }))
  }

  queueStructureAutosave() {
    if (this.readonlyBlocksStructure()) return
    this.markAutosaveDirty()
    void this.autosaveFormAsync(this.autosaveFormEl(), { saveSteps: true, trigger: "structure_autosave" })
  }

  /** @param {Record<string, unknown> | null} data */
  applyAutosaveResponseToThreadIndex(data) {
    if (!data || typeof data !== "object") return

    if (data.sequence_id != null) {
      const id = String(data.sequence_id)
      const title = typeof data.title === "string" ? data.title : ""
      const li = document.querySelector(
        `.workspace-thread-panel-strand .workspace-thread-strand-row[data-strand-step="s:${CSS.escape(id)}"]`
      )
      const nameEl = li?.querySelector(".workspace-thread-tf-title-static .workspace-thread-tf-name")
      if (nameEl) {
        nameEl.textContent = this.truncateForThreadIndex(title, 120)
        nameEl.setAttribute("title", title)
      }
    }

    const pipeline = data.pipeline_sequences
    const bundleId = data.bundle_id
    if (bundleId != null) {
      const bEsc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape(String(bundleId)) : String(bundleId)
      const bundleLi = document.querySelector(
        `.workspace-thread-panel-strand .workspace-thread-strand-row[data-strand-step="b:${bEsc}"]`
      )
      if (typeof data.bundle_title === "string") {
        const bundleIdxHost = bundleLi?.querySelector('[data-controller~="bundle-pipeline-index"]')
        if (bundleIdxHost) {
          bundleIdxHost.setAttribute("data-bundle-pipeline-index-bundle-title-value", data.bundle_title)
        }
      }
      if (!Array.isArray(pipeline)) return
      for (const row of pipeline) {
        if (!row || typeof row !== "object") continue
        const sid = row.id
        if (sid == null) continue
        const id = String(sid)
        const title = typeof row.title === "string" ? row.title : ""
        const esc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape(id) : id
        const item = bundleLi?.querySelector(
          `li.workspace-thread-bundle-pipeline-item[data-pipeline-sequence-id="${esc}"]`
        )
        const nameEl = item?.querySelector(".workspace-thread-bundle-pipeline-name")
        if (nameEl) {
          nameEl.textContent = this.truncateForThreadIndex(title, 120)
        }
      }
    }
  }

  truncateForThreadIndex(text, maxLen) {
    const s = String(text)
    if (s.length <= maxLen) return s
    return `${s.slice(0, Math.max(0, maxLen - 1))}…`
  }
}
