import { Controller } from "@hotwired/stimulus"
import { fetchAutosavePost } from "workspace_autosave"
import { trimTrailingWhitespace, trimTrailingWhitespaceInPlace } from "text_input_sanitizer"

/** Title edit (rename) + strand options menu (rename, move). */
export default class extends Controller {
  static targets = ["currentTitle", "saveButton", "cancelButton", "menuPanel", "menuTrigger", "deleteDialog"]
  static values = {
    updateUrl: String
  }

  connect() {
    this.editing = false
    this.originalTitle = ""
    this._saving = false
    this._boundBlur = this.onInputBlur.bind(this)
    this._boundKeydown = this.onInputKeydown.bind(this)
    this._boundDocClick = this.onDocumentClick.bind(this)
    this._boundDocKey = this.onDocumentKeydown.bind(this)
    document.addEventListener("click", this._boundDocClick)
    document.addEventListener("keydown", this._boundDocKey)
  }

  disconnect() {
    document.removeEventListener("click", this._boundDocClick)
    document.removeEventListener("keydown", this._boundDocKey)
    this.teardownInput()
    if (this.hasDeleteDialogTarget && typeof this.deleteDialogTarget.close === "function") {
      try {
        this.deleteDialogTarget.close()
      } catch (_) {
        /* ignore */
      }
    }
  }

  toggleTitleMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasMenuPanelTarget) return
    const opening = !!this.menuPanelTarget.hidden
    document.querySelectorAll(".workspace-thread-panel-title-menu-panel").forEach((el) => {
      el.hidden = true
    })
    document.querySelectorAll('[data-workspace-thread-panel-title-target="menuTrigger"]').forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
    this.menuPanelTarget.hidden = !opening
    if (opening) this.closePanelMoveSubmenus()
    if (this.hasMenuTriggerTarget) {
      this.menuTriggerTarget.setAttribute("aria-expanded", opening ? "true" : "false")
    }
  }

  hideTitleMenu() {
    if (!this.hasMenuPanelTarget || this.menuPanelTarget.hidden) return
    this.closePanelMoveSubmenus()
    this.menuPanelTarget.hidden = true
    if (this.hasMenuTriggerTarget) this.menuTriggerTarget.setAttribute("aria-expanded", "false")
  }

  closePanelMoveSubmenus() {
    if (!this.hasMenuPanelTarget) return
    this.menuPanelTarget.querySelectorAll(".workspace-thread-panel-title-submenu").forEach((el) => {
      el.hidden = true
    })
    this.menuPanelTarget.querySelectorAll(".workspace-thread-panel-title-menu-item--parent").forEach((b) => {
      b.setAttribute("aria-expanded", "false")
    })
  }

  toggleMoveSubmenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const group = btn.closest(".workspace-thread-panel-title-menu-group")
    const sid = btn.dataset.submenuId
    const topMenu = btn.closest('[data-workspace-thread-panel-title-target="menuPanel"]')
    const sub = group?.querySelector(
      `.workspace-thread-panel-title-submenu[data-submenu-id="${CSS.escape(String(sid || ""))}"]`
    )
    if (!sub || !(topMenu instanceof HTMLElement)) return
    const willOpen = sub.hidden
    topMenu.querySelectorAll(".workspace-thread-panel-title-submenu").forEach((el) => {
      el.hidden = true
    })
    topMenu.querySelectorAll(".workspace-thread-panel-title-menu-item--parent").forEach((el) => {
      el.setAttribute("aria-expanded", "false")
    })
    if (willOpen) {
      sub.hidden = false
      btn.setAttribute("aria-expanded", "true")
    }
  }

  /** Run before thread-workspace#closePanel so the click does not bubble to the strip column. */
  menuItemActivate(event) {
    event.preventDefault()
    event.stopPropagation()
    this.hideTitleMenu()
  }

  renameFromMenu(event) {
    this.menuItemActivate(event)
    this.openEditor()
  }

  openDeleteConfirm(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasDeleteDialogTarget) return
    this.hideTitleMenu()
    this.deleteDialogTarget.showModal()
  }

  cancelDeleteConfirm(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    this.closeDeleteConfirm()
  }

  closeDeleteConfirm() {
    if (!this.hasDeleteDialogTarget) return
    this.deleteDialogTarget.close()
  }

  onDocumentClick(event) {
    const t = event.target
    if (!(t instanceof Node)) return
    if (this.hasMenuPanelTarget && this.menuPanelTarget.contains(t)) return
    if (this.hasMenuTriggerTarget && this.menuTriggerTarget.contains(t)) return
    this.hideTitleMenu()
  }

  onDocumentKeydown(event) {
    if (event.key !== "Escape") return
    this.hideTitleMenu()
  }

  stopMenuPanelBubble(event) {
    event.stopPropagation()
  }

  openEditor(event) {
    event?.preventDefault?.()
    if (this.editing) return
    this.originalTitle = this.currentTitleTarget.textContent.trim()
    this.editing = true

    const input = document.createElement("input")
    input.type = "text"
    input.className =
      "workspace-thread-panel-title-input prompt-thread-panel-title-input"
    input.value = this.originalTitle
    input.setAttribute("aria-label", "Thread title")
    input.addEventListener("blur", this._boundBlur)
    input.addEventListener("keydown", this._boundKeydown)

    this.currentTitleTarget.hidden = true
    this.currentTitleTarget.insertAdjacentElement("afterend", input)
    this.inputEl = input

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

    const title = trimTrailingWhitespace(this.inputEl.value)
    if (!title.trim()) {
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
        this.currentTitleTarget.textContent = nextTitle
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
    this.currentTitleTarget.textContent = this.originalTitle
    this.finishEdit()
  }

  finishEdit() {
    this.teardownInput()
    this.editing = false

    this.saveButtonTarget.hidden = true
    this.cancelButtonTarget.hidden = true

    this.currentTitleTarget.hidden = false
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
