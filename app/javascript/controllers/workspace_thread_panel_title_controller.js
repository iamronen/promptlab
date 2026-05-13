import { Controller } from "@hotwired/stimulus"
import { fetchAutosavePost } from "workspace_autosave"

/** Explicit edit / save / cancel for thread strand titles in the thread panel header. */
export default class extends Controller {
  static targets = ["display", "editButton", "saveButton", "cancelButton"]
  static values = {
    updateUrl: String
  }

  connect() {
    this.editing = false
    this.originalTitle = ""
    this._saving = false
    this._boundBlur = this.onInputBlur.bind(this)
    this._boundKeydown = this.onInputKeydown.bind(this)
  }

  disconnect() {
    this.teardownInput()
  }

  openEditor(event) {
    event.preventDefault()
    if (this.editing) return
    this.originalTitle = this.displayTarget.textContent.trim()
    this.editing = true

    const input = document.createElement("input")
    input.type = "text"
    input.className =
      "workspace-thread-panel-title-input prompt-thread-panel-title-input"
    input.value = this.originalTitle
    input.setAttribute("aria-label", "Thread title")
    input.addEventListener("blur", this._boundBlur)
    input.addEventListener("keydown", this._boundKeydown)

    this.displayTarget.hidden = true
    this.displayTarget.insertAdjacentElement("afterend", input)
    this.inputEl = input

    this.editButtonTarget.hidden = true
    this.saveButtonTarget.hidden = false
    this.cancelButtonTarget.hidden = false

    requestAnimationFrame(() => {
      input.focus()
      const len = input.value.length
      input.setSelectionRange(len, len)
    })
  }

  cancelEdit(event) {
    event?.preventDefault?.()
    this.abortEdit()
  }

  async save(event) {
    event?.preventDefault?.()
    if (!this.editing || !this.inputEl || this._saving) return

    const title = this.inputEl.value.trim()
    if (!title) {
      window.alert("Thread title cannot be blank.")
      return
    }

    const body = new FormData()
    body.append("sequence[title]", title)
    body.append("_method", "patch")

    this._saving = true
    try {
      const response = await fetchAutosavePost(this.updateUrlValue, body)
      if (response.ok) {
        let json = {}
        try {
          json = await response.json()
        } catch (_) {
          /* ignore */
        }
        const nextTitle = (json.title ?? title).toString()
        this.displayTarget.textContent = nextTitle
        this.finishEdit()
        return
      }

      let msg = "Could not save thread title."
      try {
        const err = await response.json()
        if (Array.isArray(err.errors) && err.errors.length) msg = err.errors.join("\n")
      } catch (_) {
        /* ignore */
      }
      window.alert(msg)
    } catch (_) {
      window.alert("Could not save thread title (network error).")
    } finally {
      this._saving = false
    }
  }

  abortEdit() {
    if (!this.editing) return
    this.displayTarget.textContent = this.originalTitle
    this.finishEdit()
  }

  finishEdit() {
    this.teardownInput()
    this.editing = false

    this.editButtonTarget.hidden = false
    this.saveButtonTarget.hidden = true
    this.cancelButtonTarget.hidden = true

    this.displayTarget.hidden = false
  }

  teardownInput() {
    if (!this.inputEl) return
    this.inputEl.removeEventListener("blur", this._boundBlur)
    this.inputEl.removeEventListener("keydown", this._boundKeydown)
    this.inputEl.remove()
    this.inputEl = null
  }

  onInputBlur() {
    window.setTimeout(() => {
      if (!this.editing || this._saving) return
      const ae = document.activeElement
      if (ae === this.inputEl || ae === this.saveButtonTarget || ae === this.cancelButtonTarget) return
      this.abortEdit()
    }, 0)
  }

  onInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.save()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.cancelEdit()
    }
  }
}
