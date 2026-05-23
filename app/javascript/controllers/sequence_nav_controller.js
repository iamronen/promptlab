import { Controller } from "@hotwired/stimulus"
import { parseCopyTextDataset } from "sequence_copy_text"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.boundOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
  }

  toggleMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const wrap = event.currentTarget.closest(".sequence-nav-menu-wrap")
    const menu = wrap.querySelector('[data-sequence-nav-target="menu"]')
    const wasOpen = !menu.hidden

    this.closeAllMenus()
    menu.hidden = wasOpen
  }

  handleOutsideClick(event) {
    if (event.target.closest(".sequence-nav-menu-wrap")) return
    this.closeAllMenus()
  }

  closeAllMenus() {
    this.menuTargets.forEach((menu) => {
      menu.hidden = true
    })
  }

  copyAsText(event) {
    event.preventDefault()
    event.stopPropagation()

    const text = parseCopyTextDataset(event.currentTarget.dataset.copyText)
    if (!text) return

    void navigator.clipboard.writeText(text)
    this.closeAllMenus()
  }
}
