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
  static targets = ["root"]

  static values = {
    taxonomiesUrl: String,
    assignmentsUrl: String,
    sequenceId: { type: Number, default: 0 }
  }

  connect() {
    /** @type {Record<number, number[]>} */
    this.termIdsByTaxonomy = {}
    /** @type {unknown[]} */
    this.taxonomies = []
    /** @type {boolean} */
    this.readonly = true
    this.persistInFlight = false
    /** @type {((e: Event) => void) | null} */
    this.pickerCloser = null
    /** @type {HTMLElement | null} */
    this.pickerWrap = null

    this.boundWorkspaceReadonly = () => queueMicrotask(() => this.refreshReadonlyFromDom())
    document.addEventListener("sequence-editor:global-mode", this.boundWorkspaceReadonly)
    document.addEventListener("sequence-editor:readonly-sync", this.boundWorkspaceReadonly)

    this.refreshReadonlyFromDom()
    void this.bootstrap()
  }

  disconnect() {
    this.closePicker()
    if (this.boundWorkspaceReadonly) {
      document.removeEventListener("sequence-editor:global-mode", this.boundWorkspaceReadonly)
      document.removeEventListener("sequence-editor:readonly-sync", this.boundWorkspaceReadonly)
    }
  }

  refreshReadonlyFromDom() {
    const main = this.element.closest("main.sequence-editor")
    const ro = !!main?.classList.contains("sequence-editor--readonly")
    if (this.readonly !== ro) {
      this.readonly = ro
      if (this.taxonomies?.length) this.render()
    } else if (!this.taxonomies?.length) {
      this.readonly = ro
    }
  }

  async bootstrap() {
    if (!this.hasRootTarget) return
    this.rootTarget.replaceChildren()

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

      /** @type {any[]} */
      const taxonomies = await taxRes.json()
      /** @type {{ assignments?: any[] }} */
      const assignBody = await asnRes.json()

      this.taxonomies = [...taxonomies].sort((a, b) => {
        const pa = Number(a.position) || 0
        const pb = Number(b.position) || 0
        return pa !== pb ? pa - pb : Number(a.id) - Number(b.id)
      })

      const assignments = assignBody.assignments || []
      this.applyAssignmentsPayload(assignments)
      this.refreshReadonlyFromDom()
      this.render()
    } catch {
      this.rootTarget.innerHTML =
        `<p class="sequence-meta-taxonomy-load-error">${escapeHtml("Could not load taxonomies.")}</p>`
    }
  }

  /** @param {any[]} assignments */
  applyAssignmentsPayload(assignments) {
    /** @type {Record<number, number[]>} */
    const grouped = {}

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
    }

    const next = {}
    for (const t of this.taxonomies) next[t.id] = grouped[t.id] ? [...grouped[t.id]] : []
    this.termIdsByTaxonomy = next
  }

  buildAssignmentsBody() {
    return this.taxonomies.map((t) => ({
      taxonomy_id: Number(t.id),
      taxonomy_term_ids: [...(this.termIdsByTaxonomy[t.id] || [])].map(Number)
    }))
  }

  render() {
    if (!this.hasRootTarget) return
    this.closePicker()
    this.rootTarget.innerHTML = ""
    const frag = document.createDocumentFragment()

    for (const tax of this.taxonomies) {
      const rowEl = document.createElement("div")
      rowEl.className = "sequence-meta-taxonomy-row"
      rowEl.dataset.taxonomyId = String(tax.id)

      const labelEl = document.createElement("div")
      labelEl.className = "sequence-meta-taxonomy-row__label"
      const taxonomyName = tax.name || ""
      labelEl.textContent = taxonomyName ? `${taxonomyName}:` : ""
      rowEl.appendChild(labelEl)

      const valuesEl = document.createElement("div")
      valuesEl.className = "sequence-meta-taxonomy-row__values"
      rowEl.appendChild(valuesEl)

      if (tax.cardinality === "many") {
        this.renderMany(valuesEl, tax)
      } else {
        this.renderOne(valuesEl, tax)
      }

      frag.appendChild(rowEl)
    }

    this.rootTarget.appendChild(frag)
    if (this.persistErrorTexts?.length) this.showPersistError(this.persistErrorTexts)
  }

  /** @param {HTMLElement} el @param {any} tax */
  renderMany(el, tax) {
    const terms = tax.terms || []
    /** @type {number[]} */
    const selected = sortTermIdsLikeTaxonomy(this.termIdsByTaxonomy[tax.id] || [], terms)

    for (const termId of selected) {
      const term = terms.find((t) => t.id === termId)
      const labelText = term?.label ?? ""
      el.appendChild(
        this.renderChip(labelText, this.readonly, this.readonly ? null : () => void this.removeManyTerm(tax, termId))
      )
    }

    const selectedSet = new Set(selected)
    const remaining = terms.filter((t) => !selectedSet.has(t.id))

    if (!this.readonly && remaining.length > 0) {
      const addBtn = document.createElement("button")
      addBtn.type = "button"
      addBtn.className = "sequence-meta-taxonomy-add-btn"
      addBtn.textContent = "+"
      addBtn.setAttribute("aria-label", "Add taxonomy value")
      addBtn.title = "Add value"
      addBtn.addEventListener("click", (e) => {
        e.preventDefault()
        void this.openManyAddPicker(addBtn.closest(".sequence-meta-taxonomy-row")?.querySelector(".sequence-meta-taxonomy-row__values") || el, tax, remaining.map((x) => x.id))
      })
      el.appendChild(addBtn)
    }
  }

  /** @returns {HTMLElement} */
  renderChip(labelText, readOnlyMode, removeHandler) {
    const pill = document.createElement("span")
    pill.className = "sequence-meta-taxonomy-chip"
    pill.dataset.readonlyChip = readOnlyMode ? "1" : "0"

    const label = document.createElement("span")
    label.className = "sequence-meta-taxonomy-chip__label"
    label.textContent = labelText || ""
    pill.appendChild(label)

    if (!readOnlyMode && removeHandler) {
      const rm = document.createElement("button")
      rm.type = "button"
      rm.className = "sequence-meta-taxonomy-chip__remove"
      rm.textContent = "×"
      rm.setAttribute("aria-label", "Remove value")
      rm.title = "Remove"
      rm.addEventListener("click", (e) => {
        e.preventDefault()
        removeHandler()
      })
      pill.appendChild(rm)
    }

    return pill
  }

  /** @param {HTMLElement} valuesEl @param {any} tax @param {number[]} availableTermIds */
  async openManyAddPicker(valuesEl, tax, availableTermIds) {
    this.closePicker()
    const terms = (tax.terms || []).filter((t) => availableTermIds.includes(t.id))
    if (!terms.length) return

    const wrapper = document.createElement("div")
    wrapper.className = "sequence-meta-taxonomy-picker"
    const sel = document.createElement("select")
    sel.className = "sequence-meta-taxonomy-picker__select"
    sel.setAttribute("aria-label", "Choose value to add")

    const opt0 = document.createElement("option")
    opt0.value = ""
    opt0.textContent = "Choose a value…"
    sel.appendChild(opt0)

    for (const t of terms.sort((a, b) => (a.position ?? 0) - (b.position ?? 0))) {
      const o = document.createElement("option")
      o.value = String(t.id)
      o.textContent = t.label || ""
      sel.appendChild(o)
    }

    wrapper.appendChild(sel)
    valuesEl.appendChild(wrapper)
    this.pickerWrap = wrapper

    this.pickerCloser = (evt) => {
      if (!(evt instanceof MouseEvent)) return
      if (wrapper.contains(evt.target)) return
      this.closePicker()
    }
    setTimeout(() => document.addEventListener("mousedown", this.pickerCloser, true), 0)

    sel.addEventListener("change", () => {
      const v = parseInt(sel.value, 10)
      if (Number.isFinite(v) && v > 0) {
        const ids = [...(this.termIdsByTaxonomy[tax.id] || [])]
        if (!ids.includes(v)) ids.push(v)
        this.termIdsByTaxonomy[tax.id] = sortTermIdsLikeTaxonomy(ids, tax.terms || [])
        void this.persist()
      }
      this.closePicker()
    })

    sel.focus({ preventScroll: true })
  }

  closePicker() {
    if (this.pickerCloser) {
      document.removeEventListener("mousedown", this.pickerCloser, true)
      this.pickerCloser = null
    }
    this.pickerWrap?.remove()
    this.pickerWrap = null
  }

  /** @param {any} tax @param {number} termId */
  removeManyTerm(tax, termId) {
    if (this.readonly) return
    const ids = (this.termIdsByTaxonomy[tax.id] || []).filter((x) => Number(x) !== Number(termId))
    this.termIdsByTaxonomy[tax.id] = ids
    void this.persist()
  }

  /** @param {HTMLElement} el @param {any} tax */
  renderOne(el, tax) {
    const terms = tax.terms || []
    const ids = this.termIdsByTaxonomy[tax.id] || []
    const selId = ids[0]

    const ui = tax.single_select_ui === "button_group" ? "button_group" : "dropdown"

    if (this.readonly) {
      const term = terms.find((t) => t.id === selId)
      const text = term?.label || ""
      const span = document.createElement("span")
      span.className = "sequence-meta-taxonomy-value-readonly"
      span.textContent = text || "—"
      el.appendChild(span)
      return
    }

    if (ui === "button_group") {
      const grp = document.createElement("div")
      grp.className = "sequence-meta-taxonomy-buttons sequence-meta-taxonomy-buttons--segmented"
      grp.setAttribute("role", "group")
      grp.setAttribute("aria-label", tax.name || "Taxonomy")

      for (const term of terms.sort((a, b) => (a.position ?? 0) - (b.position ?? 0))) {
        const btn = document.createElement("button")
        btn.type = "button"
        btn.className = "sequence-meta-taxonomy-choice-btn"
        if (selId === term.id) {
          btn.classList.add("sequence-meta-taxonomy-choice-btn--selected")
          btn.setAttribute("aria-pressed", "true")
        } else {
          btn.setAttribute("aria-pressed", "false")
        }
        btn.dataset.termId = String(term.id)
        btn.textContent = term.label || ""
        btn.addEventListener("click", () => void this.pickOneTaxonomy(tax, term.id))
        grp.appendChild(btn)
      }

      el.appendChild(grp)
      return
    }

    const sel = document.createElement("select")
    sel.className = "sequence-meta-taxonomy-single-select"
    sel.setAttribute("aria-label", tax.name || "Taxonomy")

    const unset = document.createElement("option")
    unset.value = ""
    unset.textContent = "—"
    unset.selected = !selId
    sel.appendChild(unset)

    for (const t of terms.sort((a, b) => (a.position ?? 0) - (b.position ?? 0))) {
      const o = document.createElement("option")
      o.value = String(t.id)
      o.textContent = t.label || ""
      if (selId === t.id) o.selected = true
      sel.appendChild(o)
    }

    sel.addEventListener("change", () => {
      const v = parseInt(sel.value, 10)
      if (!Number.isFinite(v) || v <= 0) {
        void this.pickOneTaxonomy(tax, null)
      } else {
        void this.pickOneTaxonomy(tax, v)
      }
    })

    el.appendChild(sel)
  }

  /** @param {any} tax @param {number | null} termId */
  async pickOneTaxonomy(tax, termId) {
    if (this.readonly) return
    if (termId != null && termId > 0) this.termIdsByTaxonomy[tax.id] = [termId]
    else this.termIdsByTaxonomy[tax.id] = []
    await this.persist()
  }

  /** @param {string[]} messages */
  showPersistError(messages) {
    const p = document.createElement("div")
    p.className = "sequence-meta-taxonomy-persist-errors"
    p.setAttribute("role", "alert")
    p.innerHTML = messages.map((m) => `<span>${escapeHtml(m)}</span>`).join(" ")
    if (this.hasRootTarget) this.rootTarget.appendChild(p)
  }

  clearPersistError() {
    if (!this.hasRootTarget) return
    this.rootTarget.querySelectorAll(".sequence-meta-taxonomy-persist-errors").forEach((x) => x.remove())
    this.rootTarget.querySelectorAll(".sequence-meta-taxonomy-load-error").forEach((x) => x.remove())
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

  async persist() {
    if (this.readonly || this.persistInFlight) return
    this.persistInFlight = true
    this.persistErrorTexts = []

    try {
      this.clearPersistError()
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
        if (this.hasRootTarget) this.render()
        return
      }

      const assignments = body.assignments || []
      this.applyAssignmentsPayload(assignments)

      if (this.hasRootTarget) this.render()
    } catch {
      this.persistErrorTexts = ["Taxonomy assignments could not be saved."]
      await this.reloadAssignmentsFromServer()
      if (this.hasRootTarget) this.render()
    } finally {
      this.persistInFlight = false
    }
  }
}
