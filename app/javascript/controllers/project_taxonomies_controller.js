import { Controller } from "@hotwired/stimulus"

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

export default class extends Controller {
  static targets = ["list", "addTaxonomyPanel", "newTaxonomyName"]
  static values = { indexUrl: String }

  connect() {
    this.taxonomies = []
    this.draggedTermLi = null
    this._activeDragListUl = null
    this.valuesOrderSnapshot = null
    this.editingTermId = null

    this._boundVDragStart = this.onValuesDragStart.bind(this)
    this._boundVDragEnd = this.onValuesDragEnd.bind(this)
    this._boundVDragOver = this.onValuesDragOver.bind(this)
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
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" }
      })
      if (!res.ok) return
      this.taxonomies = await res.json()
      this.renderMainList(openIds)
    } catch (_) {
      /* ignore */
    }
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
</div>`
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
<details class="project-taxonomy-card"${openAttr} data-taxonomy-id="${t.id}" data-action="toggle->project-taxonomies#onTaxonomyDetailsToggle">
  <summary class="project-taxonomy-card-summary flex cursor-pointer list-none items-center gap-2 rounded-lg px-3 py-2.5 outline-none ring-prompt-accent/40 hover:bg-gray-50 focus-visible:ring-2 dark:hover:bg-gray-800/80 [&::-webkit-details-marker]:hidden">
    <span class="project-taxonomy-card-chevron shrink-0 text-prompt-muted" aria-hidden="true">▸</span>
    <span class="min-w-0 flex-1 truncate text-sm font-medium text-prompt-heading">${escapeHtml(t.name)}</span>
    <div class="sequence-nav-menu-wrap shrink-0 prompt-sequence-nav-host" data-controller="sequence-nav">
      <button type="button" class="tool-button sequence-nav-menu-trigger" aria-label="Taxonomy actions" title="Taxonomy actions"
        data-action="click->sequence-nav#toggleMenu">⋯</button>
      <div class="sequence-nav-menu" hidden data-sequence-nav-target="menu">
        <button type="button" class="sequence-nav-menu-button" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#renameTaxonomy">Rename</button>
        <button type="button" class="sequence-nav-menu-button sequence-nav-menu-button-danger" data-taxonomy-id="${t.id}" data-action="click->project-taxonomies#deleteTaxonomy">Delete</button>
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
  </div>
</details>`
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
      this.patchTaxonomy(id, { cardinality: "many", single_select_ui: null })
    } else {
      this.patchTaxonomy(id, { cardinality: "one", single_select_ui: tax.single_select_ui || "dropdown" })
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

  async patchTaxonomy(id, attrs) {
    const url = `${this.indexUrlValue}/${id}`
    const res = await fetch(url, {
      method: "PATCH",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ taxonomy: attrs })
    })
    if (res.ok) await this.loadTaxonomies()
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
  <div class="sequence-nav-menu-wrap shrink-0 prompt-sequence-nav-host" data-controller="sequence-nav">
    <button type="button" class="tool-button sequence-nav-menu-trigger" aria-label="Value actions" title="Value actions"
      data-action="click->sequence-nav#toggleMenu">⋯</button>
    <div class="sequence-nav-menu" hidden data-sequence-nav-target="menu">
      <button type="button" class="sequence-nav-menu-button" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#beginTermEdit">Edit</button>
      <button type="button" class="sequence-nav-menu-button sequence-nav-menu-button-danger" data-taxonomy-id="${taxonomyId}" data-term-id="${term.id}" data-action="click->project-taxonomies#deleteTerm">Delete</button>
    </div>
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

  async deleteTerm(event) {
    event.preventDefault()
    event.stopPropagation()
    const termId = parseInt(event.currentTarget.getAttribute("data-term-id") || "", 10)
    const taxonomyId = parseInt(event.currentTarget.getAttribute("data-taxonomy-id") || "", 10)
    if (!termId || !taxonomyId) return
    const tax = this.taxonomies.find((x) => x.id === taxonomyId)
    const term = tax?.terms?.find((t) => t.id === termId)
    if (!term) return
    if (!window.confirm(`Delete value “${term.label}”? Assignments on sequences will be removed.`)) return

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

  onValuesDragStart(event) {
    if (event.target.closest("button")) {
      event.preventDefault()
      return
    }
    const handle = event.target.closest(".taxonomy-term-drag-handle")
    if (!handle) {
      event.preventDefault()
      return
    }
    const li = handle.closest("li[data-term-id]")
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

  onValuesDragEnd() {
    if (!this.draggedTermLi) return
    this.draggedTermLi.classList.remove("project-taxonomy-term-row--dragging")
    const ul = this._activeDragListUl
    const changed = ul && this.valuesOrderSnapshot !== this.termOrderSignature(ul)
    this.draggedTermLi = null
    this._activeDragListUl = null
    this.valuesOrderSnapshot = null
    if (changed && ul) {
      window.setTimeout(() => this.persistTermOrder(ul), 80)
    }
  }

  onValuesDragOver(event) {
    if (!this.draggedTermLi || !this._activeDragListUl) return
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
