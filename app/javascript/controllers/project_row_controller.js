import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewPanel", "renamePanel", "nameInput"]

  showRename(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeAllSequenceNavMenus()
    this.viewPanelTarget.hidden = true
    this.renamePanelTarget.hidden = false
    requestAnimationFrame(() => {
      this.nameInputTarget.focus()
      this.nameInputTarget.select()
    })
  }

  cancelRename(event) {
    event.preventDefault()
    this.renamePanelTarget.hidden = true
    this.viewPanelTarget.hidden = false
  }

  closeAllSequenceNavMenus() {
    document.querySelectorAll('[data-sequence-nav-target="menu"]').forEach((menu) => {
      menu.hidden = true
    })
  }
}
