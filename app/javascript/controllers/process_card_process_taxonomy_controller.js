import { Controller } from "@hotwired/stimulus"

/** @param {string | number | null | undefined} text */
function escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text == null ? "" : String(text)
  return div.innerHTML
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
}

/** @param {number[]} ids @param {{ id: number }[]} orderedTerms */
function sortTermIdsLikeTaxonomy(ids, orderedTerms) {
  const selected = new Set(ids)
  const out = orderedTerms.filter((t) => selected.has(t.id)).map((t) => t.id)
  for (const id of ids) {
    if (!out.includes(id)) out.push(id)
  }
  return out
}

export default class extends Controller {
  static targets = [
    "displayRoot",
    "editRoot",
    "label",
    "editLabel",
    "value",
    "date",
    "modifyButton",
    "select",
    "errorRoot"
  ]

  static values = {
    taxonomiesUrl: String,
    assignmentsUrl: String,
    taxonomyId: Number,
    sequenceId: { type: Number, default: 0 },
    subjectContext: { type: String, default: "standalone" },
    processBoardUrl: String
  }

  connect() {
    this.boundAssignmentsChanged = (event) => this.onProcessCardAssignmentsChanged(event)
    document.addEventListener("process-card:assignments-changed", this.boundAssignmentsChanged)

    /** @type {Record<number, number[]>} */
    this.termIdsByTaxonomy = {}
    /** @type {Record<number, { assigned_at?: string, histories?: any[] }>} */
    this.assignmentMetaByTaxonomy = {}
    /** @type {any[]} */
    this.taxonomies = []
    /** @type {any | null} */
    this.processTaxonomy = null
    this.editing = false
    this.persistInFlight = false
    /** @type {string[]} */
    this.persistErrorTexts = []

    void this.bootstrap()
  }

  disconnect() {
    if (this.boundAssignmentsChanged) {
      document.removeEventListener("process-card:assignments-changed", this.boundAssignmentsChanged)
    }
  }

  /** @param {CustomEvent} event */
  onProcessCardAssignmentsChanged(event) {
    const sequenceId = event.detail?.sequenceId
    if (sequenceId != null && Number(sequenceId) !== Number(this.sequenceIdValue)) return
    void this.syncAfterExternalAssignmentsChange()
  }

  async syncAfterExternalAssignmentsChange() {
    try {
      const opts = {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      }
      const asnRes = await fetch(this.assignmentsUrlValue, opts)
      if (!asnRes.ok) return
      const assignBody = await asnRes.json()
      this.applyAssignmentsPayload(assignBody.assignments || [])

      if (
        !this.processTaxonomy ||
        !this.taxonomyVisibleForContext(this.processTaxonomy, this.subjectContextValue) ||
        this.isProcessTaxonomyExcluded(this.processTaxonomy)
      ) {
        this.element.classList.add("hidden")
        this.editing = false
        return
      }

      this.element.classList.remove("hidden")
      this.populateSelect()
      this.renderDisplay()
    } catch {
      /* keep current state */
    }
  }

  async bootstrap() {
    try {
      const opts = {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      }
      const [taxRes, asnRes] = await Promise.all([
        fetch(this.taxonomiesUrlValue, opts),
        fetch(this.assignmentsUrlValue, opts)
      ])
      if (!taxRes.ok || !asnRes.ok) throw new Error("Could not load taxonomy data.")

      /** @type {{ taxonomies?: any[] }} */
      const taxBody = await taxRes.json()
      /** @type {{ assignments?: any[] }} */
      const assignBody = await asnRes.json()

      this.taxonomies = [...(taxBody.taxonomies || [])].sort((a, b) => {
        const pa = Number(a.position) || 0
        const pb = Number(b.position) || 0
        return pa !== pb ? pa - pb : Number(a.id) - Number(b.id)
      })

      this.applyAssignmentsPayload(assignBody.assignments || [])

      const taxonomyId = Number(this.taxonomyIdValue)
      this.processTaxonomy = this.taxonomies.find((t) => Number(t.id) === taxonomyId) || null

      if (
        !this.processTaxonomy ||
        !this.taxonomyVisibleForContext(this.processTaxonomy, this.subjectContextValue) ||
        this.isProcessTaxonomyExcluded(this.processTaxonomy)
      ) {
        this.element.classList.add("hidden")
        return
      }

      this.populateSelect()
      this.renderDisplay()
    } catch {
      this.showLoadError()
    }
  }

  /** @param {any[]} assignments */
  applyAssignmentsPayload(assignments) {
    /** @type {Record<number, number[]>} */
    const grouped = {}
    /** @type {Record<number, { assigned_at?: string, histories?: any[] }>} */
    const meta = {}

    const rows = [...assignments].sort((a, b) => {
      const ta = Number(a.taxonomy_id)
      const tb = Number(b.taxonomy_id)
      return ta !== tb ? ta - tb : Number(a.id) - Number(b.id)
    })

    for (const row of rows) {
      const tid = Number(row.taxonomy_id)
      if (!tid || Number.isNaN(tid)) continue
      const termId = Number(row.taxonomy_term_id)
      if (!termId || Number.isNaN(termId)) continue
      grouped[tid] = grouped[tid] || []
      if (!grouped[tid].includes(termId)) grouped[tid].push(termId)
      meta[tid] = {
        assigned_at: row.assigned_at,
        histories: Array.isArray(row.histories) ? row.histories : []
      }
    }

    const next = {}
    for (const t of this.taxonomies) next[t.id] = grouped[t.id] ? [...grouped[t.id]] : []
    this.termIdsByTaxonomy = next
    this.assignmentMetaByTaxonomy = meta
  }

  /** @param {any} tax @param {Record<number, number[]>} [termIdsByTaxonomy] */
  isProcessTaxonomyExcluded(tax, termIdsByTaxonomy = this.termIdsByTaxonomy) {
    if (tax.process_tracking !== true) return false
    const rules = tax.exclusion_rules || []
    if (!rules.length) return false
    return rules.some((rule) => {
      const triggerIds = termIdsByTaxonomy[rule.excluding_taxonomy_id] || []
      const excluding = (rule.excluding_term_ids || []).map(Number)
      return triggerIds.some((id) => excluding.includes(Number(id)))
    })
  }

  stripExcludedProcessTaxonomies() {
    for (const tax of this.taxonomies) {
      if (tax.process_tracking === true && this.isProcessTaxonomyExcluded(tax)) {
        this.termIdsByTaxonomy[tax.id] = []
      }
    }
  }

  /** @param {any} tax @param {string} context */
  taxonomyVisibleForContext(tax, context) {
    if (context === "bundle") return tax.applies_to_bundles === true
    if (context === "bundle_pipeline") {
      if (tax.applies_to_sequences === false) return false
      if (tax.applies_to_bundles === true && tax.applies_to_bundle_pipeline_sequences !== true) return false
      return true
    }
    return tax.applies_to_sequences !== false
  }

  /** @param {string | undefined} iso */
  formatDateTime(iso) {
    if (!iso) return ""
    try {
      const d = new Date(iso)
      if (Number.isNaN(d.getTime())) return iso
      return d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })
    } catch {
      return iso
    }
  }

  currentTermId() {
    if (!this.processTaxonomy) return null
    const ids = this.termIdsByTaxonomy[this.processTaxonomy.id] || []
    return ids[0] ?? null
  }

  currentTermLabel() {
    if (!this.processTaxonomy) return ""
    const termId = this.currentTermId()
    if (!termId) return ""
    const term = (this.processTaxonomy.terms || []).find((t) => t.id === termId)
    return term?.label ?? ""
  }

  taxonomyLabelText() {
    const name = this.processTaxonomy?.name || ""
    return name ? `${name}:` : ""
  }

  populateSelect() {
    if (!this.hasSelectTarget || !this.processTaxonomy) return

    const terms = [...(this.processTaxonomy.terms || [])].sort(
      (a, b) => (a.position ?? 0) - (b.position ?? 0)
    )
    const selId = this.currentTermId()

    this.selectTarget.replaceChildren()

    const unset = document.createElement("option")
    unset.value = ""
    unset.textContent = "—"
    unset.selected = !selId
    this.selectTarget.appendChild(unset)

    for (const term of terms) {
      const option = document.createElement("option")
      option.value = String(term.id)
      option.textContent = term.label || ""
      if (selId === term.id) option.selected = true
      this.selectTarget.appendChild(option)
    }
  }

  renderDisplay() {
    if (!this.processTaxonomy) return

    this.editing = false
    this.clearError()

    const labelText = this.taxonomyLabelText()
    if (this.hasLabelTarget) this.labelTarget.textContent = labelText
    if (this.hasEditLabelTarget) this.editLabelTarget.textContent = labelText

    const valueText = this.currentTermLabel() || "—"
    if (this.hasValueTarget) this.valueTarget.textContent = valueText

    const meta = this.assignmentMetaByTaxonomy[this.processTaxonomy.id]
    const assignedAt = meta?.assigned_at
    if (this.hasDateTarget) {
      if (assignedAt && this.currentTermId()) {
        this.dateTarget.textContent = this.formatDateTime(assignedAt)
        this.dateTarget.classList.remove("hidden")
      } else {
        this.dateTarget.textContent = ""
        this.dateTarget.classList.add("hidden")
      }
    }

    if (this.hasDisplayRootTarget) this.displayRootTarget.classList.remove("hidden")
    if (this.hasEditRootTarget) this.editRootTarget.classList.add("hidden")
  }

  beginEdit() {
    if (!this.processTaxonomy || this.persistInFlight) return

    this.editing = true
    this.clearError()
    this.populateSelect()

    if (this.hasDisplayRootTarget) this.displayRootTarget.classList.add("hidden")
    if (this.hasEditRootTarget) this.editRootTarget.classList.remove("hidden")
  }

  cancelEdit() {
    this.renderDisplay()
  }

  async update() {
    if (!this.processTaxonomy || this.persistInFlight) return

    const raw = this.hasSelectTarget ? this.selectTarget.value : ""
    const termId = raw ? parseInt(raw, 10) : null

    if (termId != null && Number.isFinite(termId) && termId > 0) {
      this.termIdsByTaxonomy[this.processTaxonomy.id] = [termId]
    } else {
      this.termIdsByTaxonomy[this.processTaxonomy.id] = []
    }

    await this.persist()
  }

  taxonomiesForAssignmentsPayload() {
    const context = this.subjectContextValue || "standalone"
    return this.taxonomies.filter((tax) => {
      if (!this.taxonomyVisibleForContext(tax, context)) return false
      if (tax.process_tracking === true && this.isProcessTaxonomyExcluded(tax)) return true
      return true
    })
  }

  buildAssignmentsBody() {
    this.stripExcludedProcessTaxonomies()
    return this.taxonomiesForAssignmentsPayload().map((t) => ({
      taxonomy_id: Number(t.id),
      taxonomy_term_ids: [...(this.termIdsByTaxonomy[t.id] || [])].map(Number)
    }))
  }

  async reloadAssignmentsFromServer() {
    try {
      const res = await fetch(this.assignmentsUrlValue, {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      if (!res.ok) return
      const body = await res.json()
      this.applyAssignmentsPayload(body.assignments || [])
    } catch {
      /* keep local state */
    }
  }

  clearError() {
    this.persistErrorTexts = []
    if (!this.hasErrorRootTarget) return
    this.errorRootTarget.textContent = ""
    this.errorRootTarget.classList.add("hidden")
  }

  /** @param {string[]} messages */
  showError(messages) {
    if (!this.hasErrorRootTarget) return
    this.errorRootTarget.innerHTML = messages.map((m) => `<span>${escapeHtml(m)}</span>`).join(" ")
    this.errorRootTarget.classList.remove("hidden")
  }

  showLoadError() {
    if (this.hasDisplayRootTarget) this.displayRootTarget.classList.add("hidden")
    if (this.hasEditRootTarget) this.editRootTarget.classList.add("hidden")
    this.showError(["Could not load process taxonomy."])
  }

  refreshProcessBoard() {
    if (!this.processBoardUrlValue) return
    const frame = document.getElementById("process_board")
    if (!frame) return
    frame.src = this.processBoardUrlValue
  }

  async persist() {
    if (this.persistInFlight) return
    this.persistInFlight = true
    this.persistErrorTexts = []

    try {
      this.clearError()
      const res = await fetch(this.assignmentsUrlValue, {
        method: "PUT",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken()
        },
        body: JSON.stringify({ assignments: this.buildAssignmentsBody() })
      })

      const body =
        res.headers.get("content-type")?.includes("application/json") ? await res.json() : {}

      if (!res.ok) {
        const errs = Array.isArray(body.errors) ? body.errors : [JSON.stringify(body) || `Save failed (${res.status}).`]
        this.persistErrorTexts = errs.filter(Boolean).map(String)
        await this.reloadAssignmentsFromServer()
        this.populateSelect()
        this.showError(this.persistErrorTexts)
        return
      }

      this.applyAssignmentsPayload(body.assignments || [])
      this.renderDisplay()
      this.refreshProcessBoard()
    } catch {
      this.persistErrorTexts = ["Process taxonomy could not be saved."]
      await this.reloadAssignmentsFromServer()
      this.populateSelect()
      this.showError(this.persistErrorTexts)
    } finally {
      this.persistInFlight = false
    }
  }
}
