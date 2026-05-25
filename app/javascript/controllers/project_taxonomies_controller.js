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
    "defaultProcessTaxonomyHelp"
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
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  collectOpenTaxonomyIds() {
    const openIds = new Set()
    if (!this.hasListTarget) return openIds
    this.listTarget.querySelectorAll("details.project-taxonomy-card[open]").forEach((el) => {
      const id = el.getAttribute("data-taxonomy-id")
      if (id) openIds.add(parseInt(id, 10))
    })
    return openIds
  }

  async loadTaxonomies(preserveOpenIds = null) {
    if (!this.indexUrlValue) return
    const openIds = preserveOpenIds ?? this.collectOpenTaxonomyIds()
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
      this.renderMainList(openIds)
      this.renderDefaultProcessTaxonomySelect()
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

  onTaxonomyDetailsToggle(event) {
    const detail = event.currentTarget
    if (!detail.open || !this.hasListTarget) return
    this.listTarget.querySelectorAll("details.project-taxonomy-card").forEach((other) => {
      if (other !== detail) other.removeAttribute("open")
    })
  }

  cardinalityFieldsetHtml(t) {
    const oneChecked = t.cardinality === "one" ? " checked" : ""
    const manyChecked = t.cardinality === "many" ? " checked" : ""
    return `
<div class="project-taxonomy-card-settings space-y-3 border-b border-gray-100 pb-4 dark:border-gray-700">
  <fieldset class="m-0 space-y-2 border-0 p-0">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Selection</legend>
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
  </fieldset>
  ${this.singleSelectUiFieldsetHtml(t)}
  ${this.processTrackingFieldsetHtml(t)}
  ${this.appliesToFieldsetHtml(t)}
</div>`
  }

  defaultValueFieldsetHtml(t) {
    const enabled = t.default_value_enabled === true
    const checked = enabled ? " checked" : ""
    const terms = [...(t.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0))
    const hasTerms = terms.length > 0
    const selectedId = t.default_taxonomy_term_id
    const hasSelection = selectedId != null && terms.some((term) => term.id === selectedId)
    const detailsHidden = enabled ? "" : " hidden"
    const applyHidden = enabled && hasSelection ? "" : " hidden"
    const selectDisabled = !hasTerms ? " disabled" : ""
    const unassigned = t.unassigned_applicable_count ?? 0

    const options = hasTerms
      ? terms
          .map((term) => {
            const selected = term.id === selectedId ? " selected" : ""
            return `<option value="${term.id}"${selected}>${escapeHtml(term.label)}</option>`
          })
          .join("")
      : '<option value="">No values yet</option>'

    return `
  <fieldset class="project-taxonomy-default-value m-0 mt-4 space-y-2 border-0 border-t border-gray-100 p-0 pt-4 dark:border-gray-700">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Default value</legend>
    <label class="flex cursor-pointer items-center gap-2 text-sm text-prompt-heading">
      <input type="checkbox" class="shrink-0"${checked}
        data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onDefaultValueEnabledChange click->project-taxonomies#stopSummaryToggle" />
      <span>Set default value</span>
    </label>
    <div class="project-taxonomy-default-value-details space-y-2 pl-0${detailsHidden}" data-taxonomy-id="${t.id}"${enabled ? "" : " hidden"}>
      <label class="block text-xs text-prompt-muted" for="default-term-${t.id}">Default value</label>
      <select id="default-term-${t.id}" class="w-full max-w-md rounded-lg border border-prompt-field-border px-2 py-2 text-sm text-prompt-heading"${selectDisabled}
        data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onDefaultTaxonomyTermChange">
        <option value="">Select a value…</option>
        ${options}
      </select>
      <button type="button" class="prompt-btn-primary px-3 py-2 text-[0.85rem] project-taxonomy-apply-default-value${applyHidden}"
        data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#applyDefaultValue"${enabled && hasSelection ? "" : " hidden"}>
        Apply${unassigned > 0 ? ` (${unassigned})` : ""}
      </button>
    </div>
  </fieldset>`
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
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onAppliesToSequencesChange click->project-taxonomies#stopSummaryToggle" />
        <span>Sequences</span>
      </label>
      <label class="flex cursor-pointer items-center gap-2">
        <input type="checkbox" class="shrink-0"${bundleChecked}
          data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onAppliesToBundlesChange click->project-taxonomies#stopSummaryToggle" />
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
              data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onBundlePipelineSequencesChange click->project-taxonomies#stopSummaryToggle" />
            <span>Do not apply to sequences inside bundles</span>
          </label>
          <label class="flex cursor-pointer items-center gap-2">
            <input type="radio" class="shrink-0" name="taxonomy-${t.id}-bundle-pipeline" value="true"${pipelineOnChecked}
              data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onBundlePipelineSequencesChange click->project-taxonomies#stopSummaryToggle" />
            <span>Apply also to sequences inside bundles</span>
          </label>
        </div>
      </fieldset>`
  }

  processTrackingFieldsetHtml(t) {
    const hiddenClass = t.cardinality === "one" ? "" : " project-taxonomy-process-tracking--hidden"
    const checked = t.process_tracking === true ? " checked" : ""
    const exclusionHtml =
      t.process_tracking === true ? this.exclusionRulesFieldsetHtml(t) : ""
    return `
  <fieldset class="project-taxonomy-process-tracking m-0 space-y-2 border-0 p-0${hiddenClass}">
    <legend class="mb-1 block text-xs font-semibold uppercase tracking-wide text-prompt-muted">Process</legend>
    <label class="flex cursor-pointer items-center gap-2 text-sm text-prompt-heading">
      <input type="checkbox" class="shrink-0"${checked}
        data-taxonomy-id="${t.id}" data-action="change->project-taxonomies#onProcessTrackingChange click->project-taxonomies#stopSummaryToggle" />
      <span>Track process over time</span>
    </label>
    ${exclusionHtml}
  </fieldset>`
  }

  exclusionRulesFieldsetHtml(t) {
    const rules = Array.isArray(t.exclusion_rules) ? t.exclusion_rules : []
    const rows = rules.map((rule, idx) => this.exclusionRuleRowHtml(t, rule, idx)).join("")
    return `
  <div class="project-taxonomy-exclusion-rules mt-3 space-y-2 border-t border-gray-100 pt-3 dark:border-gray-700" data-taxonomy-id="${t.id}">
    <p class="m-0 text-xs font-semibold uppercase tracking-wide text-prompt-muted">Exclusion rules</p>
    <p class="m-0 text-xs text-prompt-muted">When a sequence or bundle has any selected value on the trigger taxonomy, it is excluded from this process taxonomy.</p>
    <div class="project-taxonomy-exclusion-rules-list space-y-3" data-exclusion-rules-list="${t.id}">
      ${rows || '<p class="project-taxonomy-exclusion-rules-empty m-0 text-xs text-prompt-muted">No exclusion rules yet.</p>'}
    </div>
    <button type="button" class="prompt-btn-secondary px-3 py-2 text-[0.85rem]"
      data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#addExclusionRule click->project-taxonomies#stopSummaryToggle">
      Add exclusion rule
    </button>
  </div>`
  }

  exclusionRuleRowHtml(processTaxonomy, rule, ruleIndex) {
    const processId = processTaxonomy.id
    const excludingTaxonomyId = rule.excluding_taxonomy_id
    const selectedTermIds = new Set((rule.excluding_term_ids || []).map(Number))
    const otherTaxonomies = this.taxonomies.filter((x) => x.id !== processId)
    const taxonomyOptions = otherTaxonomies
      .map((tax) => {
        const selected = tax.id === excludingTaxonomyId ? " selected" : ""
        return `<option value="${tax.id}"${selected}>${escapeHtml(tax.name)}</option>`
      })
      .join("")

    const triggerTax = this.taxonomies.find((x) => x.id === excludingTaxonomyId)
    const terms = triggerTax ? [...(triggerTax.terms || [])].sort((a, b) => (a.position || 0) - (b.position || 0)) : []
    const termChecks =
      terms.length > 0
        ? terms
            .map((term) => {
              const checked = selectedTermIds.has(term.id) ? " checked" : ""
              return `<label class="flex cursor-pointer items-center gap-2 text-sm text-prompt-heading">
      <input type="checkbox" class="shrink-0" value="${term.id}"${checked}
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
        data-action="change->project-taxonomies#onExclusionRuleTermChange click->project-taxonomies#stopSummaryToggle" />
      <span>${escapeHtml(term.label)}</span>
    </label>`
            })
            .join("")
        : '<p class="m-0 text-xs text-prompt-muted">Select a trigger taxonomy with values.</p>'

    return `
  <div class="project-taxonomy-exclusion-rule rounded-lg border border-gray-100 p-3 dark:border-gray-700"
    data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}">
    <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
      <label class="block text-xs text-prompt-muted" for="exclusion-taxonomy-${processId}-${ruleIndex}">When assigned</label>
      <button type="button" class="sequence-nav-menu-button sequence-nav-menu-button-danger text-xs"
        data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
        data-action="click->project-taxonomies#removeExclusionRule click->project-taxonomies#stopSummaryToggle">Remove</button>
    </div>
    <select id="exclusion-taxonomy-${processId}-${ruleIndex}" class="mb-2 w-full max-w-md rounded-lg border border-prompt-field-border px-2 py-2 text-sm text-prompt-heading"
      data-process-taxonomy-id="${processId}" data-rule-index="${ruleIndex}"
      data-action="change->project-taxonomies#onExclusionRuleTaxonomyChange click->project-taxonomies#stopSummaryToggle">
      <option value="">Select taxonomy…</option>
      ${taxonomyOptions}
    </select>
    <div class="space-y-1">${termChecks}</div>
  </div>`
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
    const openIds = this.collectOpenTaxonomyIds()
    openIds.add(processTaxonomyId)
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
      this.renderMainList(openIds)
    } else {
      await this.loadTaxonomies(openIds)
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
    const openIds = this.collectOpenTaxonomyIds()
    openIds.add(processId)
    this.renderMainList(openIds)
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

    const openIds = this.collectOpenTaxonomyIds()
    openIds.add(processId)
    this.renderMainList(openIds)
  }

  onExclusionRuleTermChange(event) {
    event.stopPropagation()
    const processId = parseInt(event.currentTarget.getAttribute("data-process-taxonomy-id") || "", 10)
    const ruleIndex = parseInt(event.currentTarget.getAttribute("data-rule-index") || "", 10)
    const termId = parseInt(event.currentTarget.value || "", 10)
    const tax = this.taxonomies.find((x) => x.id === processId)
    if (!tax) return

    const rules = [...(tax.exclusion_rules || [])]
    const rule = rules[ruleIndex]
    if (!rule) return

    const ids = new Set((rule.excluding_term_ids || []).map(Number))
    if (event.currentTarget.checked) ids.add(termId)
    else ids.delete(termId)
    rule.excluding_term_ids = [...ids]
    tax.exclusion_rules = rules

    void this.putExclusionRules(processId, this.exclusionRulesPayloadFor(processId))
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

  taxonomyCardMenuHtml(t) {
    return `
        <div class="step-menu-submenu-host project-taxonomy-move-submenu-host">
          <div class="step-menu-submenu-title sequence-nav-menu-button">Move <span class="step-menu-flyout-chevron" aria-hidden="true">›</span></div>
          <div class="step-submenu project-taxonomy-move-submenu">
            <button type="button" class="sequence-nav-menu-button" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#moveTaxonomyUp">Up</button>
            <button type="button" class="sequence-nav-menu-button" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#moveTaxonomyDown">Down</button>
          </div>
        </div>
        <button type="button" class="sequence-nav-menu-button" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#renameTaxonomy">Rename</button>
        <button type="button" class="sequence-nav-menu-button sequence-nav-menu-button-danger" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#deleteTaxonomy">Delete</button>`
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

  renderMainList(openIds = null) {
    if (!this.hasListTarget) return
    const preserved = openIds ?? this.collectOpenTaxonomyIds()
    if (!this.taxonomies.length) {
      this.listTarget.innerHTML =
        '<p class="project-taxonomies-empty m-0 text-sm text-prompt-muted">No taxonomies yet.</p>'
      return
    }
    const sorted = [...this.taxonomies].sort((a, b) => (a.position || 0) - (b.position || 0) || a.id - b.id)
    this.listTarget.innerHTML = sorted
      .map((t) => {
        const openAttr = preserved.has(t.id) ? " open" : ""
        return `
<div class="project-taxonomy-card-wrap" draggable="true" data-taxonomy-id="${t.id}">
<details class="project-taxonomy-card"${openAttr} data-taxonomy-id="${t.id}" data-action="toggle->project-taxonomies#onTaxonomyDetailsToggle">
  <summary class="project-taxonomy-card-summary flex cursor-pointer list-none items-center gap-2 rounded-lg px-3 py-2.5 outline-none ring-prompt-accent/40 hover:bg-gray-50 focus-visible:ring-2 dark:hover:bg-gray-800/80 [&::-webkit-details-marker]:hidden">
    <span class="project-taxonomy-card-chevron shrink-0 text-prompt-muted" aria-hidden="true">▸</span>
    <span class="taxonomy-drag-handle shrink-0 cursor-grab select-none rounded px-0.5 text-prompt-muted hover:bg-gray-100 dark:hover:bg-gray-700" title="Drag to reorder" aria-label="Drag to reorder"
      data-action="mousedown->project-taxonomies#armTaxonomyDrag click->project-taxonomies#stopSummaryToggle">⠿</span>
    <span class="min-w-0 flex-1 truncate text-sm font-medium text-prompt-heading">${escapeHtml(t.name)}</span>
    <div class="sequence-nav-menu-wrap shrink-0 prompt-sequence-nav-host" data-controller="sequence-nav">
      <button type="button" class="tool-button sequence-nav-menu-trigger" aria-label="Taxonomy actions" title="Taxonomy actions"
        data-action="click->sequence-nav#toggleMenu">⋯</button>
      <div class="sequence-nav-menu" hidden data-sequence-nav-target="menu">
        ${this.taxonomyCardMenuHtml(t)}
      </div>
    </div>
  </summary>
  <div class="project-taxonomy-card-body border-t border-gray-100 px-3 pb-4 pt-3 dark:border-gray-700">
    ${this.cardinalityFieldsetHtml(t)}
    <p class="mb-2 mt-4 text-xs font-semibold uppercase tracking-wide text-prompt-muted">Values</p>
    <ul class="taxonomy-values-term-list m-0 max-h-[min(40vh,280px)] list-none overflow-y-auto" data-taxonomy-term-list="${t.id}">${this.termsListInnerHtml(
          t
        )}</ul>
    <div class="project-taxonomy-card-add-row mt-3 flex flex-wrap items-stretch gap-2">
      <label class="visually-hidden" for="new-term-${t.id}">New value for ${escapeHtml(t.name)}</label>
      <input id="new-term-${t.id}" type="text"
        class="min-w-[10rem] flex-1 rounded-lg border border-prompt-field-border px-2 py-2 text-[0.9rem]"
        placeholder="New value" autocomplete="off" data-taxonomy-id="${t.id}"
        data-action="keydown->project-taxonomies#onNewTermKeydown" />
      <button type="button" class="prompt-btn-primary shrink-0 px-3 py-2 text-[0.85rem]" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#addTerm">
        Add value
      </button>
    </div>
    ${this.defaultValueFieldsetHtml(t)}
  </div>
</details>
</div>`
      })
      .join("")
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
      const openIds = this.collectOpenTaxonomyIds()
      openIds.add(created.id)
      await this.loadTaxonomies(openIds)
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
    if (!this.hasListTarget) return
    const value = applyToPipeline ? "true" : "false"
    const input = this.listTarget.querySelector(
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

  async onDefaultValueEnabledChange(event) {
    event.stopPropagation()
    const input = event.currentTarget
    const id = parseInt(input.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return

    const desired = !!input.checked
    const previous = tax.default_value_enabled === true
    if (desired === previous) return

    const attrs = desired
      ? { default_value_enabled: true }
      : { default_value_enabled: false, default_taxonomy_term_id: null }
    const result = await this.patchTaxonomy(id, attrs)
    if (!result.ok) input.checked = previous
  }

  async onDefaultTaxonomyTermChange(event) {
    event.stopPropagation()
    const select = event.currentTarget
    const id = parseInt(select.getAttribute("data-taxonomy-id") || "", 10)
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return

    const termId = parseInt(select.value || "", 10)
    const previousId = tax.default_taxonomy_term_id ?? null
    if (!termId) {
      const result = await this.patchTaxonomy(id, { default_taxonomy_term_id: null })
      if (!result.ok && previousId != null) select.value = String(previousId)
      return
    }

    const result = await this.patchTaxonomy(id, {
      default_value_enabled: true,
      default_taxonomy_term_id: termId
    })
    if (!result.ok) {
      select.value = previousId != null ? String(previousId) : ""
    }
  }

  async applyDefaultValue(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return

    const url = `${this.indexUrlValue}/${id}/apply_default_value`
    const res = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      }
    })

    if (!res.ok) return

    const openIds = this.collectOpenTaxonomyIds()
    openIds.add(id)
    await this.loadTaxonomies(openIds)
  }

  renameTaxonomy(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    const tax = this.taxonomies.find((x) => x.id === id)
    if (!tax) return
    const next = window.prompt("Rename taxonomy", tax.name)
    if (next == null) return
    const name = next.trim()
    if (!name || name === tax.name) return
    this.patchTaxonomy(id, { name })
  }

  stopSummaryToggle(event) {
    event.stopPropagation()
  }

  armTaxonomyDrag(event) {
    event.stopPropagation()
    this._taxonomyDragArmed = true
    document.addEventListener("mouseup", this._boundDisarmTaxonomyDrag, { once: true })
  }

  disarmTaxonomyDrag() {
    if (!this.draggedTaxonomyEl) this._taxonomyDragArmed = false
  }

  moveTaxonomyUp(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    const ids = this.sortedTaxonomyIds()
    const idx = ids.indexOf(id)
    if (idx <= 0) return
    const next = [...ids]
    ;[next[idx - 1], next[idx]] = [next[idx], next[idx - 1]]
    void this.reorderTaxonomies(next)
  }

  moveTaxonomyDown(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!id) return
    const ids = this.sortedTaxonomyIds()
    const idx = ids.indexOf(id)
    if (idx < 0 || idx >= ids.length - 1) return
    const next = [...ids]
    ;[next[idx], next[idx + 1]] = [next[idx + 1], next[idx]]
    void this.reorderTaxonomies(next)
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
    const openIds = this.collectOpenTaxonomyIds()
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
        this.renderMainList(openIds)
        this.renderDefaultProcessTaxonomySelect()
      }
    } catch (_) {
      /* ignore */
    }

    await this.loadTaxonomies(openIds)
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
      await this.loadTaxonomies()
    }
  }

  termListForTaxonomyId(taxonomyId) {
    return this.listTarget?.querySelector(`ul[data-taxonomy-term-list="${taxonomyId}"]`)
  }

  renderTermsListForTaxonomy(taxonomy) {
    const ul = this.termListForTaxonomyId(taxonomy.id)
    if (!ul) return
    ul.innerHTML = this.termsListInnerHtml(taxonomy)
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
