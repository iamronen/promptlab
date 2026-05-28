import { Controller } from "@hotwired/stimulus"

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

const EDIT_VALUE_SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>'

const DELETE_VALUE_SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>'

const TAXONOMY_SETTINGS_GEAR_SVG =
  '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>'

export default class extends Controller {
  static targets = [
    "list",
    "addTaxonomyPanel",
    "newTaxonomyName",
    "deleteTermDialog",
    "deleteTermDialogMessage",
    "bundleSettingsDialog",
    "bundleSettingsDialogMessage",
    "defaultProcessTaxonomySelect",
    "defaultProcessTaxonomyHelp",
    "settingsDialog",
    "settingsDialogBody",
    "settingsDialogDeleteButton",
    "taxonomyNameEditInput"
  ]
  static values = { indexUrl: String, updateUrl: String }

  connect() {
    this.taxonomies = []
    this.defaultProcessTaxonomyId = null
    this.draggedTermLi = null
    this._activeDragListUl = null
    this.valuesOrderSnapshot = null
    this.draggedTaxonomyEl = null
    this.taxonomyOrderSnapshot = null
    this._taxonomyDragArmed = false
    this.editingTermId = null
    this._pendingDeleteTerm = null
    this._pendingBundleSettingsChange = null
    this._bundleSettingsConfirmInFlight = false
    this._activeSettingsTaxonomyId = null
    this.editingTaxonomyNameId = null
    this._exclusionTermPickerWrap = null
    this._exclusionTermPickerCloser = null

    this._boundVDragStart = this.onValuesDragStart.bind(this)
    this._boundVDragEnd = this.onValuesDragEnd.bind(this)
    this._boundVDragOver = this.onValuesDragOver.bind(this)
    this._boundDisarmTaxonomyDrag = this.disarmTaxonomyDrag.bind(this)
    this.element.addEventListener("dragstart", this._boundVDragStart)
    this.element.addEventListener("dragend", this._boundVDragEnd)
    this.element.addEventListener("dragover", this._boundVDragOver)

    this.loadTaxonomies()
    this.hideAddTaxonomyPanel()
  }

  disconnect() {
    this.element.removeEventListener("dragstart", this._boundVDragStart)
    this.element.removeEventListener("dragend", this._boundVDragEnd)
    this.element.removeEventListener("dragover", this._boundVDragOver)
    this._pendingDeleteTerm = null
    this._pendingBundleSettingsChange = null
    this._bundleSettingsConfirmInFlight = false
    if (this.hasDeleteTermDialogTarget && this.deleteTermDialogTarget.open) {
      this.deleteTermDialogTarget.close()
    }
    if (this.hasBundleSettingsDialogTarget && this.bundleSettingsDialogTarget.open) {
      this.bundleSettingsDialogTarget.close()
    }
    if (this.hasSettingsDialogTarget && this.settingsDialogTarget.open) {
      this.settingsDialogTarget.close()
    }
    this._activeSettingsTaxonomyId = null
    this.editingTaxonomyNameId = null
    this.closeExclusionTermPicker()
    this.closeEndStateTermPicker()
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  async loadTaxonomies() {
    if (!this.indexUrlValue) return
    const activeId = this._activeSettingsTaxonomyId
    try {
      const res = await fetch(this.indexUrlValue, {
        credentials: "same-origin",
        cache: "no-store",
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" }
      })
      if (!res.ok) return
      const data = await res.json()
      this.taxonomies = data.taxonomies || []
      this.defaultProcessTaxonomyId = data.default_process_taxonomy_id ?? null
      this.renderMainList()
      this.renderDefaultProcessTaxonomySelect()
      if (activeId != null) {
        if (this.taxonomies.some((t) => t.id === activeId)) {
          this.refreshActiveSettingsModal()
        } else {
          this.closeTaxonomySettings()
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  mergeTaxonomyFromServer(updated) {
    if (!updated?.id) return false
    const idx = this.taxonomies.findIndex((x) => x.id === updated.id)
    if (idx < 0) return false
    this.taxonomies[idx] = updated
    return true
  }

  openTaxonomySettings(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    this.openTaxonomySettingsById(id)
  }

  openTaxonomySettingsById(id) {
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax || !this.hasSettingsDialogTarget) return

    this._activeSettingsTaxonomyId = id
    this.editingTaxonomyNameId = null
    this.renderTaxonomySettingsModal(tax)
    this.settingsDialogTarget.showModal()
  }

  closeTaxonomySettings(event) {
    event?.preventDefault()
    if (this.hasSettingsDialogTarget && this.settingsDialogTarget.open) {
      this.settingsDialogTarget.close()
    }
    this._activeSettingsTaxonomyId = null
    this.editingTaxonomyNameId = null
  }

  onSettingsDialogBackdrop(event) {
    if (event.target === this.settingsDialogTarget) this.closeTaxonomySettings(event)
  }

  renderTaxonomySettingsModal(t) {
    if (this.hasSettingsDialogBodyTarget) {
      this.settingsDialogBodyTarget.innerHTML = this.taxonomySettingsBodyHtml(t)
    }
    if (this.hasSettingsDialogDeleteButtonTarget) {
      this.settingsDialogDeleteButtonTarget.setAttribute("data-taxonomy-id", String(t.id))
    }
  }

  refreshActiveSettingsModal() {
    if (this._activeSettingsTaxonomyId == null) return
    const tax = this.taxonomies.find((x) => x.id === this._activeSettingsTaxonomyId)
    if (!tax) {
      this.closeTaxonomySettings()
      return
    }
    if (this.hasSettingsDialogTarget && this.settingsDialogTarget.open) {
      this.closeExclusionTermPicker()
      this.closeEndStateTermPicker()
      this.renderTaxonomySettingsModal(tax)
    }
  }

  taxonomySettingsSectionHtml(title, innerHtml, { hidden = false, sectionClass = "" } = {}) {
    const hiddenAttr = hidden ? " hidden" : ""
    const extraClass = sectionClass ? ` ${sectionClass}` : ""
    return `
<section class="taxonomy-settings-section${extraClass}"${hiddenAttr}>
  <h3 class="taxonomy-settings-section-title">${escapeHtml(title)}</h3>
  <div class="taxonomy-settings-section-body space-y-3">${innerHtml}</div>
</section>`
  }

  taxonomySettingsBodyHtml(t) {
    return `
<div class="taxonomy-settings-layout">
  <div class="taxonomy-settings-top">
    ${this.configurationSectionHtml(t)}
    ${this.valuesSectionHtml(t)}
  </div>
  ${this.processTrackingSectionHtml(t)}
</div>`
  }

  configurationSectionHtml(t) {
    const inner = `
${this.taxonomyNameRowHtml(t)}
${this.appliesToFieldsetHtml(t)}
${this.selectionFieldsetHtml(t)}
${this.singleSelectUiFieldsetHtml(t)}`
    return this.taxonomySettingsSectionHtml("Configuration", inner)
  }

  taxonomyNameRowHtml(t) {
    if (this.editingTaxonomyNameId === t.id) {
      return `
<div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-2">
  <label class="shrink-0 text-sm text-prompt-heading" for="taxonomy-name-edit-${t.id}">Taxonomy name</label>
  <input id="taxonomy-name-edit-${t.id}" type="text"
    class="min-w-0 flex-1 rounded-lg border border-prompt-field-border px-2 py-1.5 text-sm font-medium text-prompt-heading"
    value="${escapeHtml(t.name)}" autocomplete="off"
    data-project-taxonomies-target="taxonomyNameEditInput" data-taxonomy-id="${t.id}"
    data-action="keydown->project-taxonomies#onTaxonomyNameEditKeydown" />
  <div class="flex shrink-0 gap-1">
    <button type="button" class="prompt-btn-primary px-2 py-1 text-[0.8rem]"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#saveTaxonomyNameEdit">Save</button>
    <button type="button" class="prompt-btn-secondary px-2 py-1 text-[0.8rem]"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#cancelTaxonomyNameEdit">Cancel</button>
  </div>
</div>`
    }
    return `
<div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
  <span class="shrink-0 text-sm text-prompt-heading">Taxonomy name</span>
  <div class="flex min-w-0 max-w-full items-center gap-1">
    <span class="min-w-0 truncate text-sm font-medium text-prompt-heading">${escapeHtml(t.name)}</span>
    <button type="button" class="tool-button shrink-0" title="Edit name" aria-label="Edit name"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#beginTaxonomyNameEdit">${EDIT_VALUE_SVG}</button>
  </div>
</div>`
  }

  valuesSectionHtml(t) {
    const inner = `
<ul class="taxonomy-values-term-list m-0 list-none overflow-y-auto" data-taxonomy-term-list="${t.id}">${this.termsListInnerHtml(
      t
    )}</ul>
<div class="project-taxonomy-card-add-row flex flex-wrap items-stretch gap-2">
  <label class="visually-hidden" for="new-term-${t.id}">New value for ${escapeHtml(t.name)}</label>
  <input id="new-term-${t.id}" type="text"
    class="min-w-[10rem] flex-1 rounded-lg border border-prompt-field-border px-2 py-2 text-[0.9rem]"
    placeholder="New value" autocomplete="off" data-taxonomy-id="${t.id}"
    data-action="keydown->project-taxonomies#onNewTermKeydown" />
  <button type="button" class="prompt-btn-primary shrink-0 px-3 py-2 text-[0.85rem]" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#addTerm">
    Add value
  </button>
</div>
${this.defaultValueFieldsetHtml(t)}`
    return this.taxonomySettingsSectionHtml("Values", inner, { sectionClass: "taxonomy-settings-section--values" })
  }

  processTrackingSectionHtml(t) {
    const hidden = t.cardinality !== "one"
    const inner = this.processTrackingFieldsetHtml(t)
    return this.taxonomySettingsSectionHtml("Process Tracking", inner, { hidden })
  }

  selectionFieldsetHtml(t) {
    const oneChecked = t.cardinality === "one" ? " checked" : ""
    const manyChecked = t.cardinality === "many" ? " checked" : ""
    return `
  <fieldset class="m-0 space-y-2 border-0 p-0">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Value selection</legend>
    <div class="flex flex-wrap gap-x-4 gap-y-2 text-sm text-prompt-heading">
      <label class="flex cursor-pointer items-center gap-2">
        <input type="radio" class="shrink-0" name="taxonomy-${t.id}-cardinality" value="one"${oneChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onCardinalityChange" />
        <span>Single</span>
      </label>
      <label class="flex cursor-pointer items-center gap-2">
        <input type="radio" class="shrink-0" name="taxonomy-${t.id}-cardinality" value="many"${manyChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onCardinalityChange" />
        <span>Multiple</span>
      </label>
    </div>
  </fieldset>`
  }

  defaultValueSelectedTermId(t) {
    const id = t.default_taxonomy_term_id
    if (!t.default_value_enabled || id == null) return null
    const terms = t.terms || []
    return terms.some((term) => term.id === id) ? id : null
  }

  defaultValueSelectOptionsHtml(t) {
    const selectedId = this.defaultValueSelectedTermId(t)
    const noneSelected = selectedId == null ? " selected" : ""
    const terms = [...(t.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
    const termOptions = terms
      .map((term) => {
        const selected = term.id === selectedId ? " selected" : ""
        return `<option value="${term.id}"${selected}>${escapeHtml(term.label)}</option>`
      })
      .join("")
    return `<option value=""${noneSelected}>None</option>${termOptions}`
  }

  defaultValueFieldsetHtml(t) {
    return `
  <fieldset class="project-taxonomy-default-value m-0 border-0 p-0">
    <div class="flex flex-wrap items-center gap-x-2 gap-y-2">
      <label class="shrink-0 text-sm text-prompt-heading" for="default-term-${t.id}">Default value</label>
      <select id="default-term-${t.id}" data-default-value-select="${t.id}"
        class="min-w-[10rem] max-w-md flex-1 rounded-lg border border-prompt-field-border px-2 py-2 text-sm text-prompt-heading"
        data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onDefaultTaxonomyTermChange">
        ${this.defaultValueSelectOptionsHtml(t)}
      </select>
    </div>
  </fieldset>`
  }

  refreshDefaultValueSelect(taxonomy) {
    const select = this.element.querySelector(`select[data-default-value-select="${taxonomy.id}"]`)
    if (!select) return
    select.innerHTML = this.defaultValueSelectOptionsHtml(taxonomy)
    const selectedId = this.defaultValueSelectedTermId(taxonomy)
    select.value = selectedId != null ? String(selectedId) : ""
  }

  appliesToFieldsetHtml(t) {
    const seqChecked = t.applies_to_sequences !== false ? " checked" : ""
    const bundleChecked = t.applies_to_bundles === true ? " checked" : ""
    const bundlesEnabled = t.applies_to_bundles === true
    const pipelineFieldsetHtml =
      t.process_tracking === true || !bundlesEnabled ? "" : this.bundlePipelineFieldsetHtml(t)

    return `
  <fieldset class="project-taxonomy-applies-to m-0 space-y-2 border-0 p-0">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Applies to</legend>
    <div class="space-y-2 text-sm text-prompt-heading">
      <label class="flex cursor-pointer items-center gap-2">
        <input type="checkbox" class="shrink-0"${seqChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onAppliesToSequencesChange" />
        <span>Sequences</span>
      </label>
      <label class="flex cursor-pointer items-center gap-2">
        <input type="checkbox" class="shrink-0"${bundleChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onAppliesToBundlesChange" />
        <span>Bundles</span>
      </label>
      ${pipelineFieldsetHtml}
    </div>
  </fieldset>`
  }

  bundlePipelineFieldsetHtml(t) {
    const pipelineOffChecked = t.applies_to_bundle_pipeline_sequences !== true ? " checked" : ""
    const pipelineOnChecked = t.applies_to_bundle_pipeline_sequences === true ? " checked" : ""

    return `
      <fieldset class="project-taxonomy-bundle-pipeline m-0 ml-5 space-y-2 border-0 p-0">
        <legend class="mb-1 block text-xs font-medium text-prompt-muted">Sequences inside bundles</legend>
        <div class="flex flex-col gap-y-2">
          <label class="flex cursor-pointer items-center gap-2">
            <input type="radio" class="shrink-0" name="taxonomy-${t.id}-bundle-pipeline" value="false"${pipelineOffChecked}
              data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onBundlePipelineSequencesChange" />
            <span>Do not apply to sequences inside bundles</span>
          </label>
          <label class="flex cursor-pointer items-center gap-2">
            <input type="radio" class="shrink-0" name="taxonomy-${t.id}-bundle-pipeline" value="true"${pipelineOnChecked}
              data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onBundlePipelineSequencesChange" />
            <span>Apply also to sequences inside bundles</span>
          </label>
        </div>
      </fieldset>`
  }

  processTrackingFieldsetHtml(t) {
    const checked = t.process_tracking === true ? " checked" : ""
    const endStateHtml =
      t.process_tracking === true ? this.endStateValuesFieldsetHtml(t) : ""
    const exclusionHtml =
      t.process_tracking === true ? this.exclusionRulesFieldsetHtml(t) : ""
    return `
  <fieldset class="project-taxonomy-process-tracking m-0 space-y-2 border-0 p-0">
    <label class="flex cursor-pointer items-center gap-2 text-sm text-prompt-heading">
      <input type="checkbox" class="shrink-0"${checked}
        data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onProcessTrackingChange" />
      <span>Track process over time</span>
    </label>
    ${endStateHtml}
    ${exclusionHtml}
  </fieldset>`
  }

  endStateValuesFieldsetHtml(t) {
    return `
  <div class="project-taxonomy-end-state-values mt-3 space-y-2 border-t border-gray-100 pt-3 dark:border-gray-700" data-taxonomy-id="${t.id}">
    <p class="m-0 text-xs font-semibold uppercase tracking-wide text-prompt-muted">End state values</p>
    <div class="project-taxonomy-end-state-values-inner">
      ${this.endStateValuesCellHtml(t)}
    </div>
  </div>`
  }

  endStateValuesCellHtml(t) {
    const taxonomyId = t.id
    const selectedTermIds = [...(t.end_state_term_ids || [])].map(Number).filter((id) => id > 0)
    const terms = [...(t.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))

    if (!terms.length) {
      return '<p class="project-taxonomy-end-state-values-empty m-0 text-xs text-prompt-muted">No values in this taxonomy yet.</p>'
    }

    const selectedSet = new Set(selectedTermIds)
    const chips = selectedTermIds
      .map((termId) => {
        const term = terms.find((x) => x.id === termId)
        if (!term) return ""
        return `<span class="sequence-meta-taxonomy-chip">
      <span class="sequence-meta-taxonomy-chip__label">${escapeHtml(term.label)}</span>
      <button type="button" class="sequence-meta-taxonomy-chip__remove" aria-label="Remove value" title="Remove"
        data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}"
        data-action="click->project-taxonomies#removeEndStateTerm">×</button>
    </span>`
      })
      .join("")

    const remaining = terms.filter((term) => !selectedSet.has(term.id))
    const addBtn =
      remaining.length > 0
        ? `<button type="button" class="sequence-meta-taxonomy-add-btn" aria-label="Add end state value" title="Add value"
        data-taxonomy-id="${taxonomyId}"
        data-action="click->project-taxonomies#openEndStateTermPicker">+</button>`
        : ""

    return `<div class="project-taxonomy-end-state-values-chips sequence-meta-taxonomy-row__values" data-end-state-values="${taxonomyId}">${chips}${addBtn}</div>`
  }

  closeEndStateTermPicker() {
    if (this._endStateTermPickerWrap) {
      this._endStateTermPickerWrap.remove()
      this._endStateTermPickerWrap = null
    }
    if (this._endStateTermPickerCloser) {
      document.removeEventListener("mousedown", this._endStateTermPickerCloser, true)
      this._endStateTermPickerCloser = null
    }
  }

  openEndStateTermPicker(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeEndStateTermPicker()

    const btn = event.currentTarget
    const taxonomyId = parseInt(btn.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    if (!tax) return

    const terms = [...(tax.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
    const selectedSet = new Set((tax.end_state_term_ids || []).map(Number))
    const remaining = terms.filter((term) => !selectedSet.has(term.id))
    if (!remaining.length) return

    const valuesInner = btn.closest("[data-end-state-values]")
    if (!valuesInner) return

    const wrapper = document.createElement("div")
    wrapper.className = "sequence-meta-taxonomy-picker"
    const sel = document.createElement("select")
    sel.className = "sequence-meta-taxonomy-picker__select"
    sel.setAttribute("aria-label", "Choose end state value")
    sel.setAttribute("data-taxonomy-id", String(taxonomyId))
    sel.addEventListener("change", (evt) => this.onEndStateTermPickerChange(evt))

    const opt0 = document.createElement("option")
    opt0.value = ""
    opt0.textContent = "Choose a value…"
    sel.appendChild(opt0)

    for (const term of remaining) {
      const o = document.createElement("option")
      o.value = String(term.id)
      o.textContent = term.label || ""
      sel.appendChild(o)
    }

    wrapper.appendChild(sel)
    valuesInner.appendChild(wrapper)
    this._endStateTermPickerWrap = wrapper

    this._endStateTermPickerCloser = (evt) => {
      if (!(evt instanceof MouseEvent)) return
      if (wrapper.contains(evt.target)) return
      this.closeEndStateTermPicker()
    }
    setTimeout(() => document.addEventListener("mousedown", this._endStateTermPickerCloser, true), 0)

    sel.focus()
  }

  onEndStateTermPickerChange(event) {
    event.stopPropagation()
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const termId = parseInt(event.currentTarget.value || "", 10)
    this.closeEndStateTermPicker()
    if (!Number.isFinite(termId) || termId <= 0) return

    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    if (!tax) return

    const ids = new Set((tax.end_state_term_ids || []).map(Number))
    ids.add(termId)
    tax.end_state_term_ids = [...ids]

    void this.putEndStateTerms(taxonomyId, tax.end_state_term_ids)
  }

  removeEndStateTerm(event) {
    event.preventDefault()
    event.stopPropagation()
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    if (!tax) return

    tax.end_state_term_ids = (tax.end_state_term_ids || []).map(Number).filter((id) => id !== termId)

    void this.putEndStateTerms(taxonomyId, tax.end_state_term_ids)
  }

  async putEndStateTerms(taxonomyId, termIds) {
    const url = `${this.indexUrlValue}/${taxonomyId}/end_state_terms`
    const res = await fetch(url, {
      method: "PUT",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ end_state_term_ids: termIds })
    })

    if (!res.ok) return { ok: false }

    const updated = await res.json()
    if (this.mergeTaxonomyFromServer(updated)) {
      this.renderMainList()
      this.refreshActiveSettingsModal()
    } else {
      await this.loadTaxonomies()
    }
    return { ok: true }
  }

  exclusionRulesFieldsetHtml(t) {
    const rules = Array.isArray(t.exclusion_rules) ? t.exclusion_rules : []
    const rows = rules.map((rule, idx) => this.exclusionRuleRowHtml(t, rule, idx)).join("")
    const emptyRow =
      '<tr class="project-taxonomy-exclusion-rules-empty"><td colspan="3" class="text-xs text-prompt-muted">No exclusion rules yet.</td></tr>'
    return `
  <div class="project-taxonomy-exclusion-rules mt-3 space-y-2 border-t border-gray-100 pt-3 dark:border-gray-700" data-taxonomy-id="${t.id}">
    <p class="m-0 text-xs font-semibold uppercase tracking-wide text-prompt-muted">Exclusion rules</p>
    <p class="m-0 text-xs text-prompt-muted">When a sequence or bundle has any selected value on the trigger taxonomy, it is excluded from this process taxonomy.</p>
    <div class="project-taxonomy-exclusion-rules-table-wrap overflow-x-auto">
      <table class="project-taxonomy-exclusion-rules-table w-full border-collapse text-sm">
        <thead>
          <tr>
            <th scope="col" class="project-taxonomy-exclusion-rules-table__heading">Taxonomy</th>
            <th scope="col" class="project-taxonomy-exclusion-rules-table__heading">Excluded values</th>
            <th scope="col" class="project-taxonomy-exclusion-rules-table__heading project-taxonomy-exclusion-rules-table__heading--actions"><span class="visually-hidden">Actions</span></th>
          </tr>
        </thead>
        <tbody class="project-taxonomy-exclusion-rules-list" data-exclusion-rules-list="${t.id}">
          ${rows || emptyRow}
        </tbody>
      </table>
    </div>
    <button type="button" class="prompt-btn-secondary px-3 py-2 text-[0.85rem]"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#addExclusionRule">
      Add exclusion rule
    </button>
  </div>`
  }

  exclusionRuleRowHtml(processTaxonomy, rule, ruleIndex) {
    const processId = processTaxonomy.id
    const excludingTaxonomyId = rule.excluding_taxonomy_id
    const otherTaxonomies = this.taxonomies.filter((x) => x.id !== processId)
    const taxonomyOptions = otherTaxonomies
      .map((tax) => {
        const selected = tax.id === excludingTaxonomyId ? " selected" : ""
        return `<option value="${tax.id}"${selected}>${escapeHtml(tax.name)}</option>`
      })
      .join("")

    return `
  <tr class="project-taxonomy-exclusion-rule-row"
    data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}">
    <td class="project-taxonomy-exclusion-rule-taxonomy align-top">
      <label class="visually-hidden" for="exclusion-taxonomy-${processId}-${ruleIndex}">Taxonomy</label>
      <select id="exclusion-taxonomy-${processId}-${ruleIndex}" class="w-full min-w-[8rem] rounded-lg border border-prompt-field-border px-2 py-2 text-sm text-prompt-heading"
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
        data-action="change->project-taxonomies#onExclusionRuleTaxonomyChange">
        <option value="">Select taxonomy…</option>
        ${taxonomyOptions}
      </select>
    </td>
    <td class="project-taxonomy-exclusion-rule-values align-top">
      ${this.exclusionRuleValuesCellHtml(processTaxonomy, rule, ruleIndex)}
    </td>
    <td class="project-taxonomy-exclusion-rule-actions align-top">
      <button type="button" class="sequence-nav-menu-button sequence-nav-menu-button-danger text-xs whitespace-nowrap"
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
        data-action="click->project-taxonomies#removeExclusionRule">Remove</button>
    </td>
  </tr>`
  }

  exclusionRuleValuesCellHtml(processTaxonomy, rule, ruleIndex) {
    const processId = processTaxonomy.id
    const excludingTaxonomyId = rule.excluding_taxonomy_id
    const selectedTermIds = [...(rule.excluding_term_ids || [])].map(Number).filter((id) => id > 0)
    const triggerTax = this.taxonomies.find((x) => x.id === excludingTaxonomyId)
    const terms = triggerTax
      ? [...(triggerTax.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
      : []

    if (!excludingTaxonomyId) {
      return '<p class="project-taxonomy-exclusion-rule-values-empty m-0 text-xs text-prompt-muted">Select a taxonomy.</p>'
    }
    if (!terms.length) {
      return '<p class="project-taxonomy-exclusion-rule-values-empty m-0 text-xs text-prompt-muted">No values in this taxonomy.</p>'
    }

    const selectedSet = new Set(selectedTermIds)
    const chips = selectedTermIds
      .map((termId) => {
        const term = terms.find((x) => x.id === termId)
        if (!term) return ""
        return `<span class="sequence-meta-taxonomy-chip">
      <span class="sequence-meta-taxonomy-chip__label">${escapeHtml(term.label)}</span>
      <button type="button" class="sequence-meta-taxonomy-chip__remove" aria-label="Remove value" title="Remove"
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}" data-term-id="${term.id}"
        data-action="click->project-taxonomies#removeExclusionTerm">×</button>
    </span>`
      })
      .join("")

    const remaining = terms.filter((term) => !selectedSet.has(term.id))
    const addBtn =
      remaining.length > 0
        ? `<button type="button" class="sequence-meta-taxonomy-add-btn" aria-label="Add excluded value" title="Add value"
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
        data-action="click->project-taxonomies#openExclusionTermPicker">+</button>`
        : ""

    return `<div class="project-taxonomy-exclusion-rule-values-inner sequence-meta-taxonomy-row__values" data-exclusion-rule-values="${processId}-${ruleIndex}">${chips}${addBtn}</div>`
  }

  closeExclusionTermPicker() {
    if (this._exclusionTermPickerWrap) {
      this._exclusionTermPickerWrap.remove()
      this._exclusionTermPickerWrap = null
    }
    if (this._exclusionTermPickerCloser) {
      document.removeEventListener("mousedown", this._exclusionTermPickerCloser, true)
      this._exclusionTermPickerCloser = null
    }
  }

  openExclusionTermPicker(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeExclusionTermPicker()
    this.closeEndStateTermPicker()

    const btn = event.currentTarget
    const processId = parseInt(btn.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(btn.getAttribute("data-rule-index") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    const rule = tax?.exclusion_rules?.[ruleIndex]
    if (!tax || !rule) return

    const excludingTaxonomyId = rule.excluding_taxonomy_id
    const triggerTax = this.taxonomies.find((x) => x.id === excludingTaxonomyId)
    const terms = triggerTax
      ? [...(triggerTax.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
      : []
    const selectedSet = new Set((rule.excluding_term_ids || []).map(Number))
    const remaining = terms.filter((term) => !selectedSet.has(term.id))
    if (!remaining.length) return

    const valuesInner = btn.closest("[data-exclusion-rule-values]")
    if (!valuesInner) return

    const wrapper = document.createElement("div")
    wrapper.className = "sequence-meta-taxonomy-picker"
    const sel = document.createElement("select")
    sel.className = "sequence-meta-taxonomy-picker__select"
    sel.setAttribute("aria-label", "Choose value to exclude")
    sel.setAttribute("data-process-taxonomy-id", String(processId))
    sel.setAttribute("data-rule-index", String(ruleIndex))
    sel.addEventListener("change", (evt) => this.onExclusionTermPickerChange(evt))

    const opt0 = document.createElement("option")
    opt0.value = ""
    opt0.textContent = "Choose a value…"
    sel.appendChild(opt0)

    for (const term of remaining) {
      const o = document.createElement("option")
      o.value = String(term.id)
      o.textContent = term.label || ""
      sel.appendChild(o)
    }

    wrapper.appendChild(sel)
    valuesInner.appendChild(wrapper)
    this._exclusionTermPickerWrap = wrapper

    this._exclusionTermPickerCloser = (evt) => {
      if (!(evt instanceof MouseEvent)) return
      if (wrapper.contains(evt.target)) return
      this.closeExclusionTermPicker()
    }
    setTimeout(() => document.addEventListener("mousedown", this._exclusionTermPickerCloser, true), 0)

    sel.focus()
  }

  onExclusionTermPickerChange(event) {
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(event.currentTarget.getAttribute("data-rule-index") || "", 10)
    const termId = parseInt(event.currentTarget.value || "", 10)
    this.closeExclusionTermPicker()
    if (!Number.isFinite(termId) || termId <= 0) return

    const tax = this.taxonomies.find((x) => x.id === processId)
    const rules = [...(tax?.exclusion_rules || [])]
    const rule = rules[ruleIndex]
    if (!tax || !rule) return

    const ids = new Set((rule.excluding_term_ids || []).map(Number))
    ids.add(termId)
    rule.excluding_term_ids = [...ids]
    tax.exclusion_rules = rules

    void this.putExclusionRules(processId, this.exclusionRulesPayloadFor(processId))
  }

  removeExclusionTerm(event) {
    event.preventDefault()
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(event.currentTarget.getAttribute("data-rule-index") || "", 10)
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    const rules = [...(tax?.exclusion_rules || [])]
    const rule = rules[ruleIndex]
    if (!tax || !rule) return

    rule.excluding_term_ids = (rule.excluding_term_ids || []).map(Number).filter((id) => id !== termId)
    tax.exclusion_rules = rules

    void this.putExclusionRules(processId, this.exclusionRulesPayloadFor(processId))
  }

  exclusionRulesPayloadFor(processTaxonomyId) {
    const tax = this.taxonomies.find((x) => x.id === processTaxonomyId)
    if (!tax) return []
    const rules = Array.isArray(tax.exclusion_rules) ? tax.exclusion_rules : []
    return rules
      .map((rule) => ({
        excluding_taxonomy_id: rule.excluding_taxonomy_id,
        excluding_term_ids: [...(rule.excluding_term_ids || [])].map(Number).filter((id) => id > 0)
      }))
      .filter((row) => row.excluding_taxonomy_id > 0 && row.excluding_term_ids.length > 0)
  }

  async putExclusionRules(processTaxonomyId, rules) {
    const url = `${this.indexUrlValue}/${processTaxonomyId}/exclusion_rules`
    const res = await fetch(url, {
      method: "PUT",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ exclusion_rules: rules })
    })

    if (!res.ok) return { ok: false }

    const updated = await res.json()
    if (this.mergeTaxonomyFromServer(updated)) {
      this.renderMainList()
      this.refreshActiveSettingsModal()
    } else {
      await this.loadTaxonomies()
    }
    return { ok: true }
  }

  addExclusionRule(event) {
    event.preventDefault()
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    if (!tax || tax.process_tracking !== true) return

    const other = this.taxonomies.find((x) => x.id !== processId)
    if (!other) return

    const rules = [...(tax.exclusion_rules || [])]
    const usedIds = new Set(rules.map((r) => r.excluding_taxonomy_id))
    const candidate = this.taxonomies.find((x) => x.id !== processId && !usedIds.has(x.id))
    if (!candidate) return

    rules.push({
      id: null,
      excluding_taxonomy_id: candidate.id,
      excluding_taxonomy_name: candidate.name,
      excluding_term_ids: [],
      excluding_terms: []
    })
    tax.exclusion_rules = rules
    this.refreshActiveSettingsModal()
  }

  removeExclusionRule(event) {
    event.preventDefault()
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(event.currentTarget.getAttribute("data-rule-index") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    if (!tax) return

    const rules = [...(tax.exclusion_rules || [])]
    rules.splice(ruleIndex, 1)
    tax.exclusion_rules = rules
    void this.putExclusionRules(processId, this.exclusionRulesPayloadFor(processId))
  }

  onExclusionRuleTaxonomyChange(event) {
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(event.currentTarget.getAttribute("data-rule-index") || "", 10)
    const excludingTaxonomyId = parseInt(event.currentTarget.value || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    if (!tax) return

    const rules = [...(tax.exclusion_rules || [])]
    const rule = rules[ruleIndex]
    if (!rule) return

    const triggerTax = this.taxonomies.find((x) => x.id === excludingTaxonomyId)
    rule.excluding_taxonomy_id = excludingTaxonomyId
    rule.excluding_taxonomy_name = triggerTax?.name || ""
    rule.excluding_term_ids = []
    rule.excluding_terms = []
    tax.exclusion_rules = rules
    this.refreshActiveSettingsModal()
  }

  singleSelectUiFieldsetHtml(t) {
    const hiddenClass = t.cardinality === "one" ? "" : " project-taxonomy-single-select-ui--hidden"
    const ui = t.single_select_ui || "dropdown"
    const ddChecked = ui === "dropdown" ? " checked" : ""
    const bgChecked = ui === "button_group" ? " checked" : ""
    return `
  <fieldset class="project-taxonomy-single-select-ui m-0 space-y-2 border-0 p-0${hiddenClass}">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Input type</legend>
    <div class="flex flex-wrap gap-x-4 gap-y-2 text-sm text-prompt-heading">
      <label class="flex cursor-pointer items-center gap-2">
        <input type="radio" class="shrink-0" name="taxonomy-${t.id}-single-ui" value="dropdown"${ddChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onSingleSelectUiChange" />
        <span>Dropdown</span>
      </label>
      <label class="flex cursor-pointer items-center gap-2">
        <input type="radio" class="shrink-0" name="taxonomy-${t.id}-single-ui" value="button_group"${bgChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onSingleSelectUiChange" />
        <span>Button group</span>
      </label>
    </div>
  </fieldset>`
  }

  termsListInnerHtml(taxonomy) {
    const terms = [...(taxonomy.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
    if (!terms.length) {
      return '<li class="project-taxonomy-values-empty m-0 list-none py-2 text-sm text-prompt-muted">No values yet — add one below.</li>'
    }
    return terms.map((term) => this.termRowHtml(taxonomy.id, term)).join("")
  }

  renderMainList() {
    if (!this.hasListTarget) return
    if (!this.taxonomies.length) {
      this.listTarget.innerHTML =
        '<p class="project-taxonomies-empty m-0 text-sm text-prompt-muted">No taxonomies yet.</p>'
      return
    }
    const sorted = [...this.taxonomies].sort((a, b) => (a.position || 0) - (b.position || 0) || a.id - b.id)
    this.listTarget.innerHTML = sorted
      .map(
        (t) => `
<div class="project-taxonomy-card-wrap" draggable="true" data-taxonomy-id="${t.id}">
  <div class="project-taxonomy-card project-taxonomy-card--row flex items-center gap-2 rounded-lg px-3 py-2.5">
    <span class="taxonomy-drag-handle shrink-0 cursor-grab select-none rounded px-0.5 text-prompt-muted hover:bg-gray-100 dark:hover:bg-gray-700" title="Drag to reorder" aria-label="Drag to reorder"
      data-action="mousedown->project-taxonomies#armTaxonomyDrag">⠿</span>
    <span class="min-w-0 flex-1 truncate text-sm font-medium text-prompt-heading">${escapeHtml(t.name)}</span>
    <button type="button" class="tool-button shrink-0" aria-label="Taxonomy settings" title="Taxonomy settings"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#openTaxonomySettings">${TAXONOMY_SETTINGS_GEAR_SVG}</button>
  </div>
</div>`
      )
      .join("")
  }

  sortedTaxonomyIds() {
    return [...this.taxonomies]
      .sort((a, b) => (a.position || 0) - (b.position || 0) || a.id - b.id)
      .map((t) => t.id)
  }

  processTaxonomies() {
    return [...this.taxonomies]
      .filter((t) => t.process_tracking === true)
      .sort((a, b) => (a.position || 0) - (b.position || 0) || a.id - b.id)
  }

  renderDefaultProcessTaxonomySelect() {
    if (!this.hasDefaultProcessTaxonomySelectTarget) return

    const select = this.defaultProcessTaxonomySelectTarget
    const processTaxonomies = this.processTaxonomies()
    const hasProcessTaxonomies = processTaxonomies.length > 0

    select.replaceChildren()
    select.disabled = !hasProcessTaxonomies

    if (this.hasDefaultProcessTaxonomyHelpTarget) {
      this.defaultProcessTaxonomyHelpTarget.hidden = hasProcessTaxonomies
    }

    if (!hasProcessTaxonomies) return

    for (const tax of processTaxonomies) {
      const option = document.createElement("option")
      option.value = String(tax.id)
      option.textContent = tax.name
      if (this.defaultProcessTaxonomyId != null && tax.id === this.defaultProcessTaxonomyId) {
        option.selected = true
      }
      select.appendChild(option)
    }
  }

  async onDefaultProcessTaxonomyChange(event) {
    if (!this.updateUrlValue) return
    const select = event.currentTarget
    const taxonomyId = parseInt(select.value || "", 10)
    if (!taxonomyId) return

    const previousId = this.defaultProcessTaxonomyId
    this.defaultProcessTaxonomyId = taxonomyId

    const res = await fetch(this.updateUrlValue, {
      method: "PATCH",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ project: { default_process_taxonomy_id: taxonomyId } })
    })

    if (!res.ok) {
      this.defaultProcessTaxonomyId = previousId
      this.renderDefaultProcessTaxonomySelect()
      return
    }

    try {
      const body = await res.json()
      this.defaultProcessTaxonomyId = body.default_process_taxonomy_id ?? taxonomyId
    } catch (_) {
      /* keep local selection */
    }
    this.renderDefaultProcessTaxonomySelect()
  }

  onNewTaxonomyKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.createTaxonomy(event)
    }
  }

  onNewTermKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addTermFromField(event.target)
    }
  }

  openAddTaxonomyPanel(event) {
    event.preventDefault()
    if (!this.hasAddTaxonomyPanelTarget) return
    this.addTaxonomyPanelTarget.hidden = false
    if (this.hasNewTaxonomyNameTarget) {
      requestAnimationFrame(() => {
        this.newTaxonomyNameTarget.focus()
      })
    }
  }

  hideAddTaxonomyPanel() {
    if (!this.hasAddTaxonomyPanelTarget) return
    this.addTaxonomyPanelTarget.hidden = true
    if (this.hasNewTaxonomyNameTarget) this.newTaxonomyNameTarget.value = ""
  }

  cancelAddTaxonomyPanel(event) {
    event.preventDefault()
    this.hideAddTaxonomyPanel()
  }

  async createTaxonomy(event) {
    event.preventDefault()
    if (!this.hasNewTaxonomyNameTarget) return
    const name = this.newTaxonomyNameTarget.value.trim()
    if (!name) return

    const res = await fetch(this.indexUrlValue, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ taxonomy: { name, cardinality: "many" } })
    })
    if (res.status === 201) {
      this.hideAddTaxonomyPanel()
      const created = await res.json()
      await this.loadTaxonomies()
      this.openTaxonomySettingsById(created.id)
    }
  }

  onCardinalityChange(event) {
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const val = event.currentTarget.value
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax || (val !== "one" && val !== "many")) return
    if (val === "many") {
      this.patchTaxonomy(id, { cardinality: "many", single_select_ui: null, process_tracking: false })
    } else {
      this.patchTaxonomy(id, { cardinality: "one", single_select_ui: tax.single_select_ui || "dropdown" })
    }
  }

  async onProcessTrackingChange(event) {
    event.stopPropagation()
    const input = event.currentTarget
    const id = parseInt(input.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax || tax.cardinality !== "one") return

    const desired = !!input.checked
    const result = await this.patchTaxonomy(id, { process_tracking: desired })
    if (!result.ok) input.checked = !desired
  }

  async onAppliesToSequencesChange(event) {
    event.stopPropagation()
    const input = event.currentTarget
    const id = parseInt(input.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return

    const desired = !!input.checked
    if (desired === (tax.applies_to_sequences !== false)) return

    const result = await this.patchTaxonomy(id, { applies_to_sequences: desired })
    if (!result.ok) input.checked = !desired
  }

  async onAppliesToBundlesChange(event) {
    event.stopPropagation()
    const input = event.currentTarget
    const id = parseInt(input.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return

    const desired = !!input.checked
    const previous = tax.applies_to_bundles === true
    if (desired === previous) return

    const result = await this.patchTaxonomy(id, { applies_to_bundles: desired })
    if (result.ok) return

    if (result.conflict) {
      this._pendingBundleSettingsChange = {
        id,
        attrs: desired
          ? { applies_to_bundles: true }
          : { applies_to_bundles: false, applies_to_bundle_pipeline_sequences: false }
      }
      this.showBundleSettingsDialog(result.conflict.message)
      return
    }

    input.checked = previous
  }

  async onBundlePipelineSequencesChange(event) {
    event.stopPropagation()
    const input = event.currentTarget
    const id = parseInt(input.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax || tax.process_tracking === true || tax.applies_to_bundles !== true) return

    const desired = input.value === "true"
    const previous = tax.applies_to_bundle_pipeline_sequences === true
    if (desired === previous) return

    const result = await this.patchTaxonomy(id, { applies_to_bundle_pipeline_sequences: desired })
    if (result.ok) return

    if (result.conflict) {
      this._pendingBundleSettingsChange = { id, attrs: { applies_to_bundle_pipeline_sequences: desired } }
      this.showBundleSettingsDialog(result.conflict.message)
      return
    }

    this.setBundlePipelineRadio(id, previous)
  }

  setBundlePipelineRadio(taxonomyId, applyToPipeline) {
    const value = applyToPipeline ? "true" : "false"
    const input = this.element.querySelector(
      `input[name="taxonomy-${taxonomyId}-bundle-pipeline"][value="${value}"]`
    )
    if (input) input.checked = true
  }

  showBundleSettingsDialog(message) {
    if (this.hasBundleSettingsDialogMessageTarget) {
      this.bundleSettingsDialogMessageTarget.textContent = message
    }
    if (this.hasBundleSettingsDialogTarget) this.bundleSettingsDialogTarget.showModal()
  }

  onBundleSettingsDialogBackdrop(event) {
    if (event.target === this.bundleSettingsDialogTarget) this.cancelBundleSettingsDialog(event)
  }

  cancelBundleSettingsDialog(event) {
    event?.preventDefault()
    this._pendingBundleSettingsChange = null
    if (this.hasBundleSettingsDialogTarget) this.bundleSettingsDialogTarget.close()
    void this.loadTaxonomies()
  }

  async confirmBundleSettingsDialog(event) {
    event.preventDefault()
    event.stopPropagation()
    if (this._bundleSettingsConfirmInFlight) return

    const pending = this._pendingBundleSettingsChange
    if (!pending) return

    this._bundleSettingsConfirmInFlight = true
    if (this.hasBundleSettingsDialogTarget) this.bundleSettingsDialogTarget.close()

    try {
      const result = await this.patchTaxonomy(pending.id, pending.attrs, { confirmDeletions: true })
      if (result.ok) {
        this._pendingBundleSettingsChange = null
        return
      }

      this._pendingBundleSettingsChange = pending
      if (result.conflict) {
        window.alert(
          result.conflict.message ||
            "Could not apply this change. Assignments may still exist — try again or refresh the page."
        )
      } else if (result.errors?.length) {
        window.alert(result.errors.join("\n"))
      } else {
        window.alert("Could not apply this change. Please refresh the page and try again.")
      }
      await this.loadTaxonomies()
    } finally {
      this._bundleSettingsConfirmInFlight = false
    }
  }

  onSingleSelectUiChange(event) {
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax || tax.cardinality !== "one") return
    const val = event.currentTarget.value
    if (val !== "dropdown" && val !== "button_group") return
    this.patchTaxonomy(id, { single_select_ui: val })
  }

  async onDefaultTaxonomyTermChange(event) {
    event.stopPropagation()
    const select = event.currentTarget
    const id = parseInt(select.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return

    const termId = parseInt(select.value || "", 10) || null
    const previousId = this.defaultValueSelectedTermId(tax)
    if (termId === previousId) return

    const result = termId
      ? await this.patchTaxonomy(id, { default_value_enabled: true, default_taxonomy_term_id: termId })
      : await this.patchTaxonomy(id, { default_value_enabled: false, default_taxonomy_term_id: null })

    if (!result.ok) {
      select.value = previousId != null ? String(previousId) : ""
    }
  }

  beginTaxonomyNameEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    this.editingTaxonomyNameId = id
    this.refreshActiveSettingsModal()
    requestAnimationFrame(() => {
      if (this.hasTaxonomyNameEditInputTarget) {
        this.taxonomyNameEditInputTarget.focus()
        this.taxonomyNameEditInputTarget.select()
      }
    })
  }

  cancelTaxonomyNameEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    this.editingTaxonomyNameId = null
    this.refreshActiveSettingsModal()
  }

  onTaxonomyNameEditKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.saveTaxonomyNameEdit(event)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.cancelTaxonomyNameEdit(event)
    }
  }

  async saveTaxonomyNameEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    const id =
      parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10) ||
      this.editingTaxonomyNameId
    if (!id) return
    const input = this.hasTaxonomyNameEditInputTarget ? this.taxonomyNameEditInputTarget : null
    if (!input) return
    const name = input.value.trim()
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!name || !tax) return
    if (name === tax.name) {
      this.editingTaxonomyNameId = null
      this.refreshActiveSettingsModal()
      return
    }
    const result = await this.patchTaxonomy(id, { name })
    if (result.ok) {
      this.editingTaxonomyNameId = null
      this.refreshActiveSettingsModal()
    }
  }

  armTaxonomyDrag(event) {
    event.stopPropagation()
    this._taxonomyDragArmed = true
    document.addEventListener("mouseup", this._boundDisarmTaxonomyDrag, { once: true })
  }

  disarmTaxonomyDrag() {
    if (!this.draggedTaxonomyEl) this._taxonomyDragArmed = false
  }

  async reorderTaxonomies(ids) {
    if (!ids.length) return
    const url = `${this.indexUrlValue}/reorder`
    const res = await fetch(url, {
      method: "PUT",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ ordered_taxonomy_ids: ids })
    })
    if (res.ok) await this.loadTaxonomies()
  }

  async patchTaxonomy(id, attrs, { confirmDeletions = false } = {}) {
    let url = `${this.indexUrlValue}/${id}`
    if (confirmDeletions) url += `${url.includes("?") ? "&" : "?"}confirm_deletions=1`

    const body = { taxonomy: attrs }
    if (confirmDeletions) body.confirm_deletions = true

    const headers = {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": this.csrfToken(),
      "X-Requested-With": "XMLHttpRequest"
    }
    if (confirmDeletions) headers["X-Confirm-Deletions"] = "1"

    const res = await fetch(url, {
      method: "PATCH",
      credentials: "same-origin",
      cache: "no-store",
      headers,
      body: JSON.stringify(body)
    })

    if (res.status === 409) {
      try {
        const conflict = await res.json()
        return { ok: false, conflict }
      } catch (_) {
        return { ok: false }
      }
    }

    if (!res.ok) {
      try {
        const body = await res.json()
        if (Array.isArray(body?.errors) && body.errors.length) {
          return { ok: false, errors: body.errors }
        }
      } catch (_) {
        /* ignore */
      }
      return { ok: false }
    }

    try {
      const updated = await res.json()
      if (updated?.id && this.mergeTaxonomyFromServer(updated)) {
        this.renderMainList()
        this.renderDefaultProcessTaxonomySelect()
        this.refreshActiveSettingsModal()
      }
    } catch (_) {
      /* ignore */
    }

    await this.loadTaxonomies()
    return { ok: true }
  }

  deleteTaxonomy(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return
    if (!window.confirm(`Delete taxonomy “${tax.name}” and all its values? This cannot be undone.`)) return
    this.deleteTaxonomyById(id)
  }

  async deleteTaxonomyById(id) {
    const url = `${this.indexUrlValue}/${id}`
    const res = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    if (res.status === 204) {
      this.editingTermId = null
      if (this._activeSettingsTaxonomyId === id) {
        this.closeTaxonomySettings()
      }
      await this.loadTaxonomies()
    }
  }

  termListForTaxonomyId(taxonomyId) {
    return this.element.querySelector(`ul[data-taxonomy-term-list="${taxonomyId}"]`)
  }

  renderTermsListForTaxonomy(taxonomy) {
    const ul = this.termListForTaxonomyId(taxonomy.id)
    if (!ul) return
    ul.innerHTML = this.termsListInnerHtml(taxonomy)
    this.refreshDefaultValueSelect(taxonomy)
  }

  termRowHtml(taxonomyId, term) {
    const editing = this.editingTermId === term.id
    if (editing) {
      return `
<li class="project-taxonomy-term-row flex flex-wrap items-center gap-2 border-b border-gray-100 py-2 last:border-b-0 dark:border-gray-700" data-term-id="${term.id}" draggable="false">
  <input type="text" class="min-w-0 flex-1 rounded-lg border border-prompt-field-border px-2 py-1.5 text-sm" value="${escapeHtml(term.label)}"
    data-project-taxonomies-target="termEditInput" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" autocomplete="off" />
  <div class="flex shrink-0 gap-1">
    <button type="button" class="prompt-btn-primary px-2 py-1 text-[0.8rem]" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#saveTermEdit">Save</button>
    <button type="button" class="prompt-btn-secondary px-2 py-1 text-[0.8rem]" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#cancelTermEdit">Cancel</button>
  </div>
</li>`
    }
    const count = term.applied_sequence_count ?? 0
    return `
<li class="project-taxonomy-term-row flex items-center gap-2 border-b border-gray-100 py-2 last:border-b-0 dark:border-gray-700" data-term-id="${term.id}" draggable="true">
  <span class="taxonomy-term-drag-handle shrink-0 cursor-grab select-none rounded px-0.5 text-prompt-muted hover:bg-gray-100 dark:hover:bg-gray-700" title="Drag to reorder" aria-label="Drag to reorder">⠿</span>
  <span class="min-w-0 flex-1 text-sm text-prompt-heading">${escapeHtml(term.label)} <span class="text-prompt-muted">(${count})</span></span>
  <div class="flex shrink-0 items-center gap-0.5">
    <button type="button" class="tool-button" title="Edit value" aria-label="Edit value" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#beginTermEdit">${EDIT_VALUE_SVG}</button>
    <button type="button" class="tool-button step-toolbox-delete" title="Delete value" aria-label="Delete value" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#requestDeleteTerm">${DELETE_VALUE_SVG}</button>
  </div>
</li>`
  }

  taxonomyForTermEdit() {
    if (!this.editingTermId) return null
    for (const tax of this.taxonomies) {
      if (tax.terms?.some((t) => t.id === this.editingTermId)) return tax
    }
    return null
  }

  beginTermEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!termId || !taxonomyId) return
    this.editingTermId = termId
    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    if (tax) this.renderTermsListForTaxonomy(tax)
    requestAnimationFrame(() => {
      const ul = this.termListForTaxonomyId(taxonomyId)
      const inp = ul?.querySelector('[data-project-taxonomies-target="termEditInput"]')
      if (inp) {
        inp.focus()
        inp.select()
      }
    })
  }

  cancelTermEdit(event) {
    event.preventDefault()
    event.stopPropagation()
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    this.editingTermId = null
    const tax = taxonomyId ? this.taxonomies.find((x) => x.id === taxonomyId) : this.taxonomyForTermEdit()
    if (tax) this.renderTermsListForTaxonomy(tax)
  }

  async saveTermEdit(event) {
    event.preventDefault()
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const ul = this.termListForTaxonomyId(taxonomyId)
    const inp = ul?.querySelector(`input[data-term-id="${termId}"]`)
    if (!inp || !taxonomyId || !termId) return
    const label = inp.value.trim()
    if (!label) return

    const url = `${this.indexUrlValue}/${taxonomyId}/terms/${termId}`
    const res = await fetch(url, {
      method: "PATCH",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ taxonomy_term: { label } })
    })
    if (res.ok) {
      this.editingTermId = null
      await this.loadTaxonomies()
    }
  }

  requestDeleteTerm(event) {
    event.preventDefault()
    event.stopPropagation()
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!termId || !taxonomyId) return
    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    const term = tax?.terms?.find((t) => t.id === termId)
    if (!term) return
    const count = term.applied_sequence_count ?? 0
    if (count === 0) {
      this.performDeleteTerm(taxonomyId, termId)
      return
    }
    this._pendingDeleteTerm = { taxonomyId, termId }
    const seqWord = count === 1 ? "sequence" : "sequences"
    const msg = `“${term.label}” is assigned on ${count} ${seqWord}. Deleting it will remove those assignments. This cannot be undone.`
    if (this.hasDeleteTermDialogMessageTarget) {
      this.deleteTermDialogMessageTarget.textContent = msg
    }
    if (this.hasDeleteTermDialogTarget) this.deleteTermDialogTarget.showModal()
  }

  onDeleteTermDialogBackdrop(event) {
    if (event.target === this.deleteTermDialogTarget) this.cancelDeleteTermDialog(event)
  }

  cancelDeleteTermDialog(event) {
    event?.preventDefault()
    this._pendingDeleteTerm = null
    if (this.hasDeleteTermDialogTarget) this.deleteTermDialogTarget.close()
  }

  async confirmDeleteTermDialog(event) {
    event.preventDefault()
    const pending = this._pendingDeleteTerm
    this._pendingDeleteTerm = null
    if (this.hasDeleteTermDialogTarget) this.deleteTermDialogTarget.close()
    if (!pending) return
    await this.performDeleteTerm(pending.taxonomyId, pending.termId)
  }

  async performDeleteTerm(taxonomyId, termId) {
    const url = `${this.indexUrlValue}/${taxonomyId}/terms/${termId}`
    const res = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    if (res.status === 204) {
      this.editingTermId = null
      await this.loadTaxonomies()
    }
  }

  addTerm(event) {
    event.preventDefault()
    const tid = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    const row = event.currentTarget.closest(".project-taxonomy-card-add-row")
    const input = row?.querySelector(`input[data-taxonomy-id="${tid}"]`)
    if (input) this.addTermFromField(input)
  }

  async addTermFromField(field) {
    const taxonomyId = parseInt(field.getAttribute("data-taxonomy-id") || "", 10)
    if (!taxonomyId) return
    const label = field.value.trim()
    if (!label) return

    const url = `${this.indexUrlValue}/${taxonomyId}/terms`
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ taxonomy_term: { label } })
    })
    if (res.status === 201) {
      field.value = ""
      await this.loadTaxonomies()
    }
  }

  termOrderSignature(ul) {
    if (!ul) return ""
    return [...ul.querySelectorAll("li[data-term-id]")]
      .map((li) => li.getAttribute("data-term-id"))
      .join("\u001f")
  }

  taxonomyOrderSignature() {
    if (!this.hasListTarget) return ""
    return [...this.listTarget.querySelectorAll(".project-taxonomy-card-wrap[data-taxonomy-id]")]
      .map((el) => el.getAttribute("data-taxonomy-id"))
      .join("\u001f")
  }

  onValuesDragStart(event) {
    if (event.target.closest("button")) {
      event.preventDefault()
      this._taxonomyDragArmed = false
      return
    }
    const termLi = event.target.closest("li[data-term-id]")
    const termList = termLi?.closest("ul[data-taxonomy-term-list]")
    if (termLi && termList && termLi.getAttribute("draggable") !== "false") {
      this._taxonomyDragArmed = false
      this.startTermDrag(event, termLi)
      return
    }
    const wrap = event.target.closest(".project-taxonomy-card-wrap[data-taxonomy-id]")
    if (wrap) {
      if (this._taxonomyDragArmed) {
        this._taxonomyDragArmed = false
        this.startTaxonomyDrag(event, wrap)
      } else {
        event.preventDefault()
      }
      return
    }
    this._taxonomyDragArmed = false
    event.preventDefault()
  }

  startTermDrag(event, fromEl) {
    const li = fromEl.matches("li[data-term-id]") ? fromEl : fromEl.closest("li[data-term-id]")
    const ul = li?.closest("ul[data-taxonomy-term-list]")
    if (!li || !ul || !this.element.contains(ul)) return
    event.stopPropagation()
    this.draggedTermLi = li
    this._activeDragListUl = ul
    this.valuesOrderSnapshot = this.termOrderSignature(ul)
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", li.getAttribute("data-term-id") || "")
    li.classList.add("project-taxonomy-term-row--dragging")
  }

  startTaxonomyDrag(event, wrap) {
    if (!wrap || !this.hasListTarget || !this.listTarget.contains(wrap)) return
    event.stopPropagation()
    this.draggedTaxonomyEl = wrap
    this.taxonomyOrderSnapshot = this.taxonomyOrderSignature()
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", wrap.getAttribute("data-taxonomy-id") || "")
    wrap.classList.add("project-taxonomy-card--dragging")
  }

  onValuesDragEnd() {
    this._taxonomyDragArmed = false
    if (this.draggedTermLi) {
      this.draggedTermLi.classList.remove("project-taxonomy-term-row--dragging")
      const ul = this._activeDragListUl
      const changed = ul && this.valuesOrderSnapshot !== this.termOrderSignature(ul)
      this.draggedTermLi = null
      this._activeDragListUl = null
      this.valuesOrderSnapshot = null
      if (changed && ul) {
        window.setTimeout(() => this.persistTermOrder(ul), 80)
      }
      return
    }

    if (!this.draggedTaxonomyEl) return
    this.draggedTaxonomyEl.classList.remove("project-taxonomy-card--dragging")
    const changed = this.taxonomyOrderSnapshot !== this.taxonomyOrderSignature()
    this.draggedTaxonomyEl = null
    this.taxonomyOrderSnapshot = null
    if (changed) {
      window.setTimeout(() => this.persistTaxonomyOrder(), 80)
    }
  }

  onValuesDragOver(event) {
    if (this.draggedTermLi && this._activeDragListUl) {
      this.onTermDragOver(event)
      return
    }
    if (this.draggedTaxonomyEl) {
      this.onTaxonomyDragOver(event)
    }
  }

  onTermDragOver(event) {
    const ul = this._activeDragListUl
    if (!ul.contains(this.draggedTermLi)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const over = event.target.closest("li[data-term-id]")
    if (!over || over === this.draggedTermLi || !ul.contains(over)) return
    const rect = over.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    if (before) {
      ul.insertBefore(this.draggedTermLi, over)
    } else {
      ul.insertBefore(this.draggedTermLi, over.nextSibling)
    }
  }

  onTaxonomyDragOver(event) {
    if (!this.hasListTarget) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const over = event.target.closest(".project-taxonomy-card-wrap[data-taxonomy-id]")
    if (!over || over === this.draggedTaxonomyEl || !this.listTarget.contains(over)) return
    const rect = over.getBoundingClientRect()
    const before = event.clientY < rect.top + rect.height / 2
    if (before) {
      this.listTarget.insertBefore(this.draggedTaxonomyEl, over)
    } else {
      this.listTarget.insertBefore(this.draggedTaxonomyEl, over.nextSibling)
    }
  }

  async persistTaxonomyOrder() {
    if (!this.hasListTarget) return
    const ids = [...this.listTarget.querySelectorAll(".project-taxonomy-card-wrap[data-taxonomy-id]")].map((el) =>
      parseInt(el.getAttribute("data-taxonomy-id") || "0", 10)
    )
    if (!ids.length) return
    await this.reorderTaxonomies(ids)
  }

  async persistTermOrder(ul) {
    const taxonomyId = parseInt(ul.getAttribute("data-taxonomy-term-list") || "0", 10)
    if (!taxonomyId) return
    const ids = [...ul.querySelectorAll("li[data-term-id]")].map((li) =>
      parseInt(li.getAttribute("data-term-id") || "0", 10)
    )
    if (!ids.length) return
    const url = `${this.indexUrlValue}/${taxonomyId}/terms/reorder`
    const res = await fetch(url, {
      method: "PUT",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ ordered_term_ids: ids })
    })
    if (res.ok) await this.loadTaxonomies()
  }
}
