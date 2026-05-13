import { Controller } from "@hotwired/stimulus"
import { getSequenceEditorReadonlyPreference } from "sequence_editor_mode_storage"
import { fetchAutosaveForm } from "workspace_autosave"

/** Generative step row (vs bundle pipeline slot: data-editor-kind="bundle_pipeline_slot"). */
const SEQUENCE_STEP_ROW_SELECTOR = '[data-editor-kind="sequence_step"]'
const SEQUENCE_STEP_ROW_ACTIVE_DRAG_CLASS = "step-row--sequence-active"

function formatStepOrdinalLabelForStepRow(stepRowEl, ordinal) {
  const stepCard = stepRowEl.querySelector(":scope > article.step-card.step-card--thread-embed-steps")
  if (stepCard) return `${ordinal}:`
  return String(ordinal)
}

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
    "sequenceOptionsTemplate",
    "sequenceSelect",
    "toolbar",
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
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)

    this.autosaveInFlight = false
    this.autosaveQueued = false
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
    if (url.searchParams.get("editor_mode") === "edit") {
      this.readonlyValue = false
      url.searchParams.delete("editor_mode")
      const qs = url.searchParams.toString()
      const path = `${url.pathname}${qs ? `?${qs}` : ""}${url.hash}`
      window.history.replaceState(window.history.state, "", path)
    } else if (!this.nestedValue) {
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

    if (this.hasSequenceSelectTarget) {
      this.sequenceSelectTargets.forEach((sel) => {
        const inNested = sel.closest(".nested-sequence-editor")
        if (this.pipelineModeValue && inNested) return
        sel.disabled = this.readonlyValue
      })
    }

    if (this.readonlyValue) {
      this.closeAllMenus()
      this.deactivateEditing()
      this.setAllEditorsReadOnly()
      this.hideAllToolbars()
      this.topLevelStepRowsForDrag().forEach((card) => {
        card.setAttribute("draggable", "false")
      })
      this.clearDropIndicator()
      this.dragArmedCard = null
      this.draggedCard = null
    } else {
      this.installDragAndDrop()
      this.setAllEditorsReadOnly()
      this.hideAllToolbars()
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
    const card = this.insertStep({ anchorCard: null, placeBefore: false })
    this.activateCard(card)
    this.queueStructureAutosave()
  }

  addStepBefore(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    const newCard = this.insertStep({ anchorCard: card, placeBefore: true })
    this.activateCard(newCard)
    this.queueStructureAutosave()
  }

  addStepAfter(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    const newCard = this.insertStep({ anchorCard: card, placeBefore: false })
    this.activateCard(newCard)
    this.queueStructureAutosave()
  }

  duplicateStep(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    let content = ""
    let sequenceId = ""
    if (this.pipelineModeValue) {
      const select = this.pipelineRowSequenceSelect(card)
      const hidden = card.querySelector(
        '.bundle-step-picker-area input.bundle-pipeline-sequence-id-field[type="hidden"]'
      )
      sequenceId = select?.value || hidden?.value || ""
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

  pipelineSequenceSelectChanged(event) {
    if (this.readonlyValue || !this.pipelineModeValue || this.nestedValue) return
    const sel = event.currentTarget
    if (this.suppressPipelineSequenceChangeOnce) {
      this.suppressPipelineSequenceChangeOnce = false
      return
    }
    if (sel.value === "__new__") {
      this.createPipelineSequenceFromSelect(sel)
      return
    }
    if (!sel.value) return

    this.syncEditorsBeforeSubmit()
    try {
      sessionStorage.setItem(PIPELINE_SCROLL_AFTER_CREATE_KEY, String(sel.value))
    } catch (_e) {
      /* ignore private mode / quota */
    }

    const formEl = sel.closest("form")
    if (formEl) void this.autosaveFormAsync(formEl)
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

  async createPipelineSequenceFromSelect(selectEl) {
    if (!this.pipelineCreateSequenceUrlValue) {
      window.alert("Create sequence is not configured.")
      this.suppressPipelineSequenceChangeOnce = true
      selectEl.value = ""
      return
    }

    selectEl.disabled = true
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
        this.suppressPipelineSequenceChangeOnce = true
        selectEl.value = ""
        return
      }

      const id = data.id
      const title = data.title ?? ""
      if (id === undefined || id === null) {
        window.alert("Invalid response while creating sequence.")
        this.suppressPipelineSequenceChangeOnce = true
        selectEl.value = ""
        return
      }

      // Disabled controls are omitted from form submission — re-enable before PATCH.
      selectEl.disabled = false

      this.appendPipelineSequenceOptionToAllSelectors(String(id), String(title))

      this.suppressPipelineSequenceChangeOnce = true
      selectEl.value = String(id)
      this.syncEditorsBeforeSubmit()
      try {
        sessionStorage.setItem(PIPELINE_SCROLL_AFTER_CREATE_KEY, String(id))
      } catch (_e) {
        /* ignore private mode / quota */
      }

      const formEl = selectEl.closest("form")
      if (formEl) void this.autosaveFormAsync(formEl)
    } catch (_err) {
      window.alert("Network error while creating sequence.")
      this.suppressPipelineSequenceChangeOnce = true
      selectEl.value = ""
    } finally {
      selectEl.disabled = false
    }
  }

  appendPipelineSequenceOptionToAllSelectors(idStr, title) {
    const newOptFrom = () => {
      const opt = document.createElement("option")
      opt.value = idStr
      opt.textContent = title
      return opt
    }

    const appendToSelect = (select) => {
      if ([...select.options].some((o) => o.value === idStr)) return
      const sentinel = [...select.options].find((o) => o.value === "__new__")
      const opt = newOptFrom()
      if (sentinel) select.insertBefore(opt, sentinel)
      else select.appendChild(opt)
    }

    this.sequenceSelectTargets.forEach((sel) => appendToSelect(sel))

    if (this.hasSequenceOptionsTemplateTarget) {
      const tpl = this.sequenceOptionsTemplateTarget.content
      if (![...tpl.querySelectorAll("option")].some((o) => o.value === idStr)) {
        const sentinelTpl = tpl.querySelector('option[value="__new__"]')
        const opt = newOptFrom()
        if (sentinelTpl) tpl.insertBefore(opt, sentinelTpl)
        else tpl.appendChild(opt)
      }
    }
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
    if (this.readonlyValue) return
    event.preventDefault()
    event.stopPropagation()
    this.showThreadEmbedStepHandleMenu(event.currentTarget)
  }

  threadHandleMenuKeydown(event) {
    if (this.readonlyValue) return
    const keyOk = event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")
    if (!keyOk) return
    event.preventDefault()
    event.stopPropagation()
    this.showThreadEmbedStepHandleMenu(event.currentTarget)
  }

  toggleThreadEmbedStepHandleMenu(event) {
    if (this.readonlyValue) return
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
    if (this.readonlyValue) return
    const wrap = button?.closest(".thread-step-handle-wrap")
    const menu = wrap?.querySelector(".step-menu--thread-handle[data-sequence-editor-target=\"menu\"]")
    if (!menu) return
    this.closeAllMenus()
    menu.hidden = false
    button?.setAttribute("aria-expanded", "true")
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
    if (this.readonlyValue) return

    if (event.target.closest(".step-menu-wrap")) return
    if (event.target.closest(".sequence-nav-menu-wrap")) return
    this.closeAllMenus()

    if (this.activeCard && !this.activeCard.contains(event.target)) {
      this.deactivateEditing()
    }
  }

  deactivateEditing() {
    this.syncEditorValuesFromDOM()
    this.activeCard = null
    this.clearSequenceStepDragActiveMarker()
    this.setAllEditorsReadOnly()
    this.hideAllToolbars()
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
      const inner = editor.closest(".step-card")
      const contentInput = inner?.querySelector('[data-sequence-editor-target="contentInput"]')
      if (contentInput) contentInput.value = editor.innerHTML.trim()
    })
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
    if (this.readonlyValue) return
    this.closeAllMenus()
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, -1)
  }

  moveDown(event) {
    if (this.readonlyValue) return
    this.closeAllMenus()
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, 1)
  }

  handleEditorKeydown(event) {
    if (this.pipelineModeValue) return
    if (this.readonlyValue) return
    if (!event.ctrlKey) return

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
    return this.stepsListTarget
  }

  topLevelStepRowsForDrag() {
    if (this.pipelineModeValue && this.hasPipelineStepRowTarget) return this.pipelineStepRowTargets
    return this.stepCardTargets
  }

  visibleCards() {
    return this.topLevelStepRowsForDrag().filter((card) => !card.hidden)
  }

  moveCardByOffset(card, offset) {
    if (this.readonlyValue) return
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

  deleteStep(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    if (!card) return

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
      const select = this.pipelineRowSequenceSelect(row)
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

      if (select && !this.readonlyValue) {
        requestAnimationFrame(() => select.focus())
      } else if (titleInput && !this.readonlyValue) {
        requestAnimationFrame(() => titleInput.focus())
      }
      return
    }
    const editor = row.querySelector('[data-sequence-editor-target="editor"]')
    if (editor) editor.contentEditable = "true"
    this.hideAllToolbars()
    const toolbar = row.querySelector('[data-sequence-editor-target="toolbar"]')
    if (toolbar) toolbar.hidden = false
    if (editor) {
      requestAnimationFrame(() => editor.focus())
    }
  }

  pipelineRowSequenceSelect(row) {
    return row.querySelector(".bundle-step-picker-area [data-sequence-editor-target=\"sequenceSelect\"]")
  }

  hideAllToolbars() {
    this.toolbarTargets.forEach((toolbar) => {
      toolbar.hidden = true
    })
  }

  formatText(event) {
    if (this.readonlyValue) return
    const format = event.currentTarget.dataset.format
    if (!format) return

    document.execCommand(format, false)
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

        if (label) label.textContent = formatStepOrdinalLabelForStepRow(card, index + 1)
        if (positionInput) {
          positionInput.value = String(index + 1)
          if (prefix) positionInput.name = `${prefix}[steps_attributes][${index}][position]`
        }
        if (destroyInput && prefix) destroyInput.name = `${prefix}[steps_attributes][${index}][_destroy]`
        if (contentInput) {
          if (editor) contentInput.value = editor.innerHTML.trim()
          if (prefix) contentInput.name = `${prefix}[steps_attributes][${index}][content]`
        }
        if (upButton) upButton.disabled = index === 0
        if (downButton) downButton.disabled = index === cards.length - 1
      })
    })
  }

  syncEditorsBeforeSubmit() {
    if (this.pipelineModeValue && !this.nestedValue) {
      this.syncNestedEditorsBeforeSubmit()
    }
    if (!this.pipelineModeValue) {
      this.editorTargets.forEach((editor) => {
        const card = editor.closest(".step-card")
        const contentInput = card?.querySelector('[data-sequence-editor-target="contentInput"]')
        if (contentInput) contentInput.value = editor.innerHTML.trim()
      })
    }
    this.reindexSteps()
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  installDragAndDrop() {
    this.topLevelStepRowsForDrag().forEach((card) => {
      card.setAttribute("draggable", "false")
      card.removeEventListener("dragstart", this.onDragStart)
      card.removeEventListener("dragover", this.onDragOver)
      card.removeEventListener("drop", this.onDrop)
      card.removeEventListener("dragend", this.onDragEnd)

      card.addEventListener("dragstart", this.onDragStart)
      card.addEventListener("dragover", this.onDragOver)
      card.addEventListener("drop", this.onDrop)
      card.addEventListener("dragend", this.onDragEnd)
    })
  }

  onDragStart = (event) => {
    if (!this.dragArmedCard || this.dragArmedCard !== event.currentTarget) {
      event.preventDefault()
      return
    }

    this.draggedCard = event.currentTarget
    this.dragCardSiblingsOrder = this.visibleCards().slice()
    event.dataTransfer.setData("text/plain", "step")
    event.dataTransfer.effectAllowed = "move"
    event.currentTarget.classList.add("dragging")
  }

  onDragOver = (event) => {
    if (!this.draggedCard) return
    event.preventDefault()

    const target = event.currentTarget
    if (!target || target === this.draggedCard) return

    const targetRect = target.getBoundingClientRect()
    const before = event.clientY < targetRect.top + targetRect.height / 2
    this.applyDropIndicator(target, before)
  }

  onDrop = (event) => {
    if (!this.draggedCard) return

    event.preventDefault()
    const target = event.currentTarget
    if (!target || this.draggedCard === target) return

    const targetRect = target.getBoundingClientRect()
    const before = event.clientY < targetRect.top + targetRect.height / 2
    const list = this.stepsListElement()
    list.insertBefore(this.draggedCard, before ? target : target.nextSibling)
    this.clearDropIndicator()
    this.reindexSteps()
  }

  onDragEnd = (event) => {
    event.currentTarget.classList.remove("dragging")
    event.currentTarget.setAttribute("draggable", "false")
    this.clearDropIndicator()
    const before = this.dragCardSiblingsOrder
    this.draggedCard = null
    this.dragArmedCard = null
    const after = this.visibleCards()
    const orderChanged =
      !before ||
      before.length !== after.length ||
      after.some((c, i) => c !== before[i])
    this.dragCardSiblingsOrder = null
    if (orderChanged) this.queueStructureAutosave()
  }

  armDrag(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    if (!card) return

    this.dragArmedCard = card
    card.setAttribute("draggable", "true")
  }

  disarmDrag(event) {
    const card = this.cardFromEvent(event)
    if (!card) return

    if (this.draggedCard === card) return

    card.setAttribute("draggable", "false")
    if (this.dragArmedCard === card) {
      this.dragArmedCard = null
    }
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

    cards.forEach((card, index) => {
      const label = card.querySelector('[data-sequence-editor-target="stepLabel"]')
      const positionInput = card.querySelector('[data-sequence-editor-target="positionInput"]')
      const sequenceSelect = card.querySelector('[data-sequence-editor-target="sequenceSelect"]')
      const destroyInput = card.querySelector('[data-sequence-editor-target="destroyInput"]')
      const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
      const upButton = card.querySelector('[data-step-control="up"]')
      const downButton = card.querySelector('[data-step-control="down"]')

      if (label) label.textContent = formatStepOrdinalLabelForStepRow(card, index + 1)
      positionInput.value = String(index + 1)
      if (prefix) {
        const base = `${prefix}[steps_attributes][${index}]`
        positionInput.name = `${base}[position]`
        destroyInput.name = `${base}[_destroy]`
        if (contentInput) contentInput.name = `${base}[content]`
      }
      if (sequenceSelect) {
        sequenceSelect.name = `sequence[steps_attributes][${index}][sequence_id]`
      }

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
        '.bundle-step-picker-area input.bundle-pipeline-sequence-id-field[type="hidden"]'
      )
      const childId = hiddenId?.value
      const titleInput = article.querySelector(".bundle-pipeline-child-title-input")
      const intentInput = article.querySelector(".bundle-pipeline-child-intent-input")
      if (titleInput && childId) titleInput.name = `nested_sequences[${childId}][title]`
      if (intentInput && childId) intentInput.name = `nested_sequences[${childId}][intent]`

      if (upButton) upButton.disabled = index === 0
      if (downButton) downButton.disabled = index === cards.length - 1

      const readonlySeqLabel = article.querySelector(
        ".bundle-readonly-sequence-index .step-label"
      )
      if (readonlySeqLabel) readonlySeqLabel.textContent = String(index + 1)

      article.querySelectorAll(".bundle-readonly-nested-step-row").forEach((row, stepIdx) => {
        const compound = row.querySelector(".bundle-readonly-nested-index .step-label")
        if (compound) compound.textContent = `${index + 1}.${stepIdx + 1}`
      })
    })
  }

  cardFromEvent(event) {
    if (this.pipelineModeValue && !this.nestedValue) {
      return event.currentTarget.closest('[data-sequence-editor-target="pipelineStepRow"]')
    }
    return event.currentTarget.closest(SEQUENCE_STEP_ROW_SELECTOR)
  }

  insertStep({ anchorCard = null, placeBefore = false, content = "", sequenceId = "" }) {
    if (this.readonlyValue) return null
    const token = `${Date.now()}_${Math.floor(Math.random() * 100000)}`
    const html = this.stepTemplateTarget.innerHTML.replaceAll("NEW_RECORD", token)

    const list = this.stepsListElement()
    if (anchorCard && placeBefore) {
      anchorCard.insertAdjacentHTML("beforebegin", html)
    } else if (anchorCard) {
      anchorCard.insertAdjacentHTML("afterend", html)
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
      const select = this.pipelineRowSequenceSelect(card)
      if (select && this.hasSequenceOptionsTemplateTarget) {
        select.innerHTML = ""
        select.appendChild(this.sequenceOptionsTemplateTarget.content.cloneNode(true))
        if (sequenceId) select.value = String(sequenceId)
      }
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

  async autosaveFormAsync(form) {
    if (!form || this.readonlyValue) return
    if (this.autosaveInFlight) {
      this.autosaveQueued = true
      return
    }
    this.syncEditorsBeforeSubmit()
    this.autosaveInFlight = true
    try {
      const res = await fetchAutosaveForm(form)
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
    } catch (err) {
      console.warn("Autosave request failed", err)
    } finally {
      this.autosaveInFlight = false
      if (this.autosaveQueued) {
        this.autosaveQueued = false
        await this.autosaveFormAsync(form)
      }
    }
  }

  flushAutosaveIfDirty() {
    if (this.readonlyValue) return
    const form = this.autosaveFormEl()
    if (!form || form.dataset.promptlabAutosaveDirty !== "1") return
    void this.autosaveFormAsync(form)
  }

  onDocumentVisibilityChange() {
    if (document.visibilityState === "hidden") this.flushAutosaveIfDirty()
  }

  onDocumentPageHide() {
    this.flushAutosaveIfDirty()
  }

  autosaveOnMetaBlur() {
    if (this.readonlyValue || this.nestedValue) return
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl()))
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
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl()))
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
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl()))
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
    requestAnimationFrame(() => void this.autosaveFormAsync(this.autosaveFormEl()))
  }

  queueStructureAutosave() {
    if (this.readonlyValue) return
    this.markAutosaveDirty()
    void this.autosaveFormAsync(this.autosaveFormEl())
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

  htmlToText(html) {
    const fragment = document.createElement("div")
    fragment.innerHTML = html
    return fragment.innerText.replace(/\n{3,}/g, "\n\n")
  }
}
