import { Controller } from "@hotwired/stimulus"
import {
  getSequenceEditorReadonlyPreference,
  setSequenceEditorReadonlyPreference
} from "sequence_editor_mode_storage"

const PIPELINE_SCROLL_AFTER_CREATE_KEY = "promptlab:scrollTransformationPipelineSeqId"

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
    "copyButton",
    "toolbar",
    "menu",
    "menuWrap",
    "modeReadonly",
    "modeEdit"
  ]

  static values = {
    defaultTitle: String,
    defaultIntent: String,
    readonly: Boolean,
    pipelineMode: { type: Boolean, default: false },
    nested: { type: Boolean, default: false },
    nestedFieldPrefix: { type: String, default: "" },
    saveSequenceUrl: { type: String, default: "" },
    pipelineCreateSequenceUrl: { type: String, default: "" }
  }

  connect() {
    this.draggedCard = null
    this.dragArmedCard = null
    this.dropIndicatorCard = null
    this.activeCard = null
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)

    if (this.nestedValue) {
      this.rootTransformationMain = this.element.closest("main.sequence-editor--transformation")
      this.boundReadonlySync = (event) => {
        if (!event.detail || typeof event.detail.readonly !== "boolean") return
        if (!this.rootTransformationMain?.contains(this.element)) return
        this.readonlyValue = event.detail.readonly
      }
      document.addEventListener("sequence-editor:readonly-sync", this.boundReadonlySync)
      if (this.rootTransformationMain?.classList.contains("sequence-editor--readonly")) {
        this.readonlyValue = true
      }
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
  }

  readonlyValueChanged() {
    this.applyReadonlyMode()
  }

  setMode(event) {
    if (this.nestedValue) return
    const mode = event.currentTarget.dataset.mode
    this.readonlyValue = mode === "readonly"
    setSequenceEditorReadonlyPreference(this.readonlyValue)
  }

  applyReadonlyMode() {
    this.element.classList.toggle("sequence-editor--readonly", this.readonlyValue)

    if (this.nestedValue) {
      if (this.hasTitleInputTarget) {
        this.titleInputTarget.readOnly = this.readonlyValue
        this.intentInputTarget.readOnly = this.readonlyValue
      }
    } else if (this.hasTitleInputTarget) {
      this.titleInputTarget.readOnly = this.readonlyValue
      this.intentInputTarget.readOnly = this.readonlyValue
    }

    if (this.pipelineModeValue && !this.nestedValue) {
      this.element.querySelectorAll(
        ".transformation-pipeline-child-title-input, .transformation-pipeline-child-intent-input"
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

    this.updateModeToggleUi()

    if (this.pipelineModeValue && !this.nestedValue) {
      document.dispatchEvent(
        new CustomEvent("sequence-editor:readonly-sync", { detail: { readonly: this.readonlyValue } })
      )
    }
  }

  updateModeToggleUi() {
    if (!this.hasModeReadonlyTarget || !this.hasModeEditTarget) return
    this.modeReadonlyTarget.setAttribute("aria-pressed", this.readonlyValue ? "true" : "false")
    this.modeEditTarget.setAttribute("aria-pressed", this.readonlyValue ? "false" : "true")
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
    if (this.nestedValue && this.boundReadonlySync) {
      document.removeEventListener("sequence-editor:readonly-sync", this.boundReadonlySync)
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
    }
  }

  addStep() {
    if (this.readonlyValue) return
    const card = this.insertStep({ anchorCard: null, placeBefore: false })
    this.activateCard(card)
  }

  addStepBefore(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    const newCard = this.insertStep({ anchorCard: card, placeBefore: true })
    this.activateCard(newCard)
  }

  addStepAfter(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    this.closeAllMenus()
    const newCard = this.insertStep({ anchorCard: card, placeBefore: false })
    this.activateCard(newCard)
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
        '.transformation-step-picker-area input.transformation-pipeline-sequence-id-field[type="hidden"]'
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
    }
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
    window.location.reload()
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
          `[data-transformation-pipeline-seq-id="${esc}"][data-sequence-editor-target="pipelineStepRow"]`
        )
        if (!row) return

        row.scrollIntoView({ block: "start", behavior: "auto", inline: "nearest" })

        if (this.readonlyValue) return
        const focusEl =
          row.querySelector(".transformation-pipeline-child-title-input") ||
          row.querySelector(".transformation-pipeline-child-intent-input")
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
      if (formEl) {
        if (typeof formEl.requestSubmit === "function") {
          formEl.requestSubmit(this.formSubmitButton(formEl))
        } else {
          formEl.submit()
        }
      }
    } catch (_err) {
      window.alert("Network error while creating sequence.")
      this.suppressPipelineSequenceChangeOnce = true
      selectEl.value = ""
    } finally {
      selectEl.disabled = false
    }
  }

  formSubmitButton(_formEl) {
    return (
      document.querySelector('button[type="submit"][form="sequence-edit-form"]') ||
      _formEl?.querySelector('button.editor-footer-save[type="submit"]')
    )
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
    this.setAllEditorsReadOnly()
    this.hideAllToolbars()
  }

  syncEditorValuesFromDOM() {
    if (this.pipelineModeValue) return
    this.editorTargets.forEach((editor) => {
      const row = editor.closest(".step-row")
      if (!row || row.hidden) return
      const inner = editor.closest(".step-card")
      const contentInput = inner?.querySelector('[data-sequence-editor-target="contentInput"]')
      if (contentInput) contentInput.value = editor.innerHTML.trim()
    })
  }

  setAllEditorsReadOnly() {
    if (this.pipelineModeValue) return
    this.editorTargets.forEach((editor) => {
      const row = editor.closest(".step-row")
      if (!row || row.hidden) return
      editor.contentEditable = "false"
    })
  }

  closeAllMenus() {
    this.menuTargets.forEach((menu) => {
      menu.hidden = true
    })
  }

  moveUp(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, -1)
  }

  moveDown(event) {
    if (this.readonlyValue) return
    const card = this.cardFromEvent(event)
    if (!card) return
    this.moveCardByOffset(card, 1)
  }

  handleEditorKeydown(event) {
    if (this.pipelineModeValue) return
    if (this.readonlyValue) return
    if (!event.ctrlKey) return

    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault()
      const card = this.cardFromEvent(event)
      if (!card) return

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

    const row = editor.closest(".step-row")
    const fragments = items.map((raw) => this.normalizePastedStepHtml(raw))

    editor.innerHTML = fragments[0]
    this.syncContentInputFromEditor(editor)

    let anchor = row
    for (let i = 1; i < fragments.length; i++) {
      anchor = this.insertStep({ anchorCard: anchor, placeBefore: false, content: fragments[i] })
    }

    this.activateCard(row)
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
    this.setAllEditorsReadOnly()
    if (this.pipelineModeValue) {
      const select = this.pipelineRowSequenceSelect(row)
      const titleInput = row.querySelector(".transformation-pipeline-child-title-input")

      const t = activatingEvent?.target
      if (
        t &&
        typeof t.closest === "function" &&
        (t.closest(".transformation-pipeline-child-title-input") ||
          t.closest(".transformation-pipeline-child-intent-input"))
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
    return row.querySelector(".transformation-step-picker-area [data-sequence-editor-target=\"sequenceSelect\"]")
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
  }

  syncNestedEditorsBeforeSubmit() {
    const root = this.element.closest("main.sequence-editor--transformation")
    if (!root) return

    root.querySelectorAll(".nested-sequence-editor").forEach((nestedEl) => {
      const stepsRoot = nestedEl.querySelector(":scope > .nested-sequence-editor-steps")
      if (!stepsRoot) return

      const prefix = nestedEl.getAttribute("data-sequence-editor-nested-field-prefix-value") || ""
      const cards = [...stepsRoot.querySelectorAll(":scope > .step-row")].filter((c) => !c.hidden)

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

  async saveNestedSequence(event) {
    if (!this.nestedValue || !this.saveSequenceUrlValue) return
    if (this.readonlyValue) return

    event.preventDefault()
    const btn = event.currentTarget
    const originalLabel = btn.textContent.trim()

    this.syncEditorValuesFromDOM()

    const stack = this.element.closest(".transformation-pipeline-edit-stack")
    const titleInput = stack?.querySelector(".transformation-pipeline-child-title-input")
    const intentInput = stack?.querySelector(".transformation-pipeline-child-intent-input")

    const stepsRoot = this.element.querySelector(":scope > .nested-sequence-editor-steps")
    const cards = [...stepsRoot.querySelectorAll(":scope > .step-row")].filter((c) => !c.hidden)

    const fd = new FormData()
    fd.append("_method", "patch")
    fd.append("authenticity_token", this.csrfToken())
    fd.append("sequence[title]", titleInput?.value ?? "")
    fd.append("sequence[intent]", intentInput?.value ?? "")

    cards.forEach((card, index) => {
      const editor = card.querySelector('[data-sequence-editor-target="editor"]')
      const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
      const content = editor ? editor.innerHTML.trim() : (contentInput?.value ?? "")
      fd.append(`sequence[steps_attributes][${index}][content]`, content)
      fd.append(`sequence[steps_attributes][${index}][position]`, String(index + 1))
      fd.append(`sequence[steps_attributes][${index}][_destroy]`, "false")
    })

    btn.disabled = true
    try {
      const response = await fetch(this.saveSequenceUrlValue, {
        method: "POST",
        body: fd,
        headers: {
          Accept: "text/html, application/xhtml+xml",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        btn.textContent = "Saved"
        setTimeout(() => {
          btn.textContent = originalLabel
        }, 2000)
      } else {
        btn.textContent = "Save failed"
        setTimeout(() => {
          btn.textContent = originalLabel
        }, 2500)
        window.alert("Could not save this sequence. Fix any errors and try again.")
      }
    } catch (_err) {
      btn.textContent = "Save failed"
      setTimeout(() => {
        btn.textContent = originalLabel
      }, 2500)
      window.alert("Network error while saving.")
    } finally {
      btn.disabled = false
    }
  }

  async copySequenceAsPrompt() {
    this.syncEditorsBeforeSubmit()

    if (!this.hasCopyButtonTarget || !this.hasTitleInputTarget) return

    const lines = []
    lines.push(`Title: ${this.titleInputTarget.value.trim()}`)
    lines.push(`Intent: ${this.intentInputTarget.value.trim()}`)
    lines.push("")
    lines.push("Steps:")

    this.visibleCards().forEach((card, index) => {
      if (this.pipelineModeValue) {
        const select = this.pipelineRowSequenceSelect(card)
        const opt = select?.selectedOptions?.[0]
        let title = opt ? opt.textContent.trim() : ""
        const titleInput = card.querySelector(".transformation-pipeline-child-title-input")
        const intentInput = card.querySelector(".transformation-pipeline-child-intent-input")
        if (!title && titleInput) title = titleInput.value.trim()
        lines.push(`${index + 1}. ${title}`)
        const intentLine = intentInput?.value?.trim()
        if (intentLine) lines.push(`   Intent: ${intentLine}`)
        const nested = card.querySelector(".nested-sequence-editor")
        if (nested) {
          nested.querySelectorAll(".rich-editor").forEach((ed, si) => {
            const text = this.htmlToText(ed.innerHTML).trim()
            if (text) lines.push(`   ${si + 1}. ${text}`)
          })
        }
      } else {
        const editor = card.querySelector('[data-sequence-editor-target="editor"]')
        const text = editor ? this.htmlToText(editor.innerHTML).trim() : ""
        lines.push(`${index + 1}. ${text}`)
      }
    })

    const output = lines.join("\n")
    try {
      await navigator.clipboard.writeText(output)
      this.copyButtonTarget.textContent = "copied!"
    } catch (_error) {
      this.copyButtonTarget.textContent = "copy failed"
    }
    window.setTimeout(() => {
      this.copyButtonTarget.textContent = "Copy as Prompt"
    }, 1200)
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
    this.draggedCard = null
    this.dragArmedCard = null
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

      label.textContent = String(index + 1)
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
      const article = card.querySelector(":scope > article.transformation-pipeline-step-card")
      if (!article) return

      const label = article.querySelector(".transformation-pipeline-step-number [data-sequence-editor-target=\"stepLabel\"]")
      const meta = article.querySelector(":scope > .step-hidden-fields")
      const positionInput = meta?.querySelector('[data-sequence-editor-target="positionInput"]')
      const sequenceIdField = article.querySelector(".transformation-pipeline-sequence-id-field")
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
        '.transformation-step-picker-area input.transformation-pipeline-sequence-id-field[type="hidden"]'
      )
      const childId = hiddenId?.value
      const titleInput = article.querySelector(".transformation-pipeline-child-title-input")
      const intentInput = article.querySelector(".transformation-pipeline-child-intent-input")
      if (titleInput && childId) titleInput.name = `nested_sequences[${childId}][title]`
      if (intentInput && childId) intentInput.name = `nested_sequences[${childId}][intent]`

      if (upButton) upButton.disabled = index === 0
      if (downButton) downButton.disabled = index === cards.length - 1

      const readonlySeqLabel = article.querySelector(
        ".transformation-readonly-sequence-index .step-label"
      )
      if (readonlySeqLabel) readonlySeqLabel.textContent = String(index + 1)

      article.querySelectorAll(".transformation-readonly-nested-step-row").forEach((row, stepIdx) => {
        const compound = row.querySelector(".transformation-readonly-nested-index .step-label")
        if (compound) compound.textContent = `${index + 1}.${stepIdx + 1}`
      })
    })
  }

  cardFromEvent(event) {
    if (this.pipelineModeValue && !this.nestedValue) {
      return event.currentTarget.closest('[data-sequence-editor-target="pipelineStepRow"]')
    }
    return event.currentTarget.closest(".step-row")
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

  htmlToText(html) {
    const fragment = document.createElement("div")
    fragment.innerHTML = html
    return fragment.innerText.replace(/\n{3,}/g, "\n\n")
  }
}
