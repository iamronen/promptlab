import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const url = event.currentTarget.getAttribute("data-create-src")
    if (!url || !this.hasDialogTarget || !this.hasFrameTarget) return

    this.closeAllSequenceNavMenus()

    this.frameTarget.src = url
    this.dialogTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget) return
    this.dialogTarget.close()
    this.clearFrame()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close(event)
  }

  clearFrame() {
    if (!this.hasFrameTarget) return
    this.frameTarget.innerHTML = ""
    this.frameTarget.removeAttribute("src")
  }

  closeAllSequenceNavMenus() {
    document.querySelectorAll('[data-sequence-nav-target="menu"]').forEach((menu) => {
      menu.hidden = true
    })
  }
}
