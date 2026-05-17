import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame", "titleDisplay", "titleEdit", "nameInput", "deleteConfirmDialog"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = event.currentTarget.getAttribute("data-settings-src")
    if (!url || !this.hasDialogTarget || !this.hasFrameTarget) return

    this.closeAllSequenceNavMenus()

    this.frameTarget.src = url
    this.dialogTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    if (this.hasDeleteConfirmDialogTarget) this.deleteConfirmDialogTarget.close()
    if (!this.hasDialogTarget) return
    this.dialogTarget.close()
    this.clearFrame()
    this._nameBeforeEdit = null
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close(event)
  }

  resetNameEdit() {
    this.resetNameEditPanels()
  }

  beginEditName(event) {
    event.preventDefault()
    if (!this.hasTitleDisplayTarget || !this.hasTitleEditTarget || !this.hasNameInputTarget) return

    this._nameBeforeEdit = this.titleDisplayTarget.querySelector("h2")?.textContent?.trim() ?? ""
    this.titleDisplayTarget.hidden = true
    this.titleEditTarget.hidden = false
    requestAnimationFrame(() => {
      this.nameInputTarget.focus()
      this.nameInputTarget.select()
    })
  }

  cancelEditName(event) {
    event.preventDefault()
    if (!this.hasNameInputTarget || !this.hasTitleDisplayTarget || !this.hasTitleEditTarget) return

    this.nameInputTarget.value = this._nameBeforeEdit ?? this.nameInputTarget.defaultValue
    this.titleEditTarget.hidden = true
    this.titleDisplayTarget.hidden = false
    this._nameBeforeEdit = null
  }

  openDeleteConfirm(event) {
    event.preventDefault()
    if (!this.hasDeleteConfirmDialogTarget) return
    this.deleteConfirmDialogTarget.showModal()
  }

  closeDeleteConfirm(event) {
    event.preventDefault()
    if (!this.hasDeleteConfirmDialogTarget) return
    this.deleteConfirmDialogTarget.close()
  }

  stopDeleteDialogBackdrop(event) {
    if (event.target === this.deleteConfirmDialogTarget) this.closeDeleteConfirm(event)
  }

  clearFrame() {
    if (!this.hasFrameTarget) return
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }

  resetNameEditPanels() {
    if (!this.hasTitleDisplayTarget || !this.hasTitleEditTarget || !this.hasNameInputTarget) return
    this.titleDisplayTarget.hidden = false
    this.titleEditTarget.hidden = true
    if (this._nameBeforeEdit != null) this.nameInputTarget.value = this._nameBeforeEdit
    this._nameBeforeEdit = null
  }

  closeAllSequenceNavMenus() {
    document.querySelectorAll('[data-sequence-nav-target="menu"]').forEach((menu) => {
      menu.hidden = true
    })
  }
}
