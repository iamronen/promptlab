import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { active: String }

  connect() {
    this.syncPanels()
  }

  activate(event) {
    event.preventDefault()
    const kind = event.currentTarget.dataset.kind
    if (!kind) return
    this.activeValue = kind
  }

  activeValueChanged() {
    this.syncPanels()
  }

  syncPanels() {
    const active = this.activeValue
    if (!active) return
    this.tabTargets.forEach((tab) => {
      const sel = tab.dataset.kind === active
      tab.setAttribute("aria-selected", sel ? "true" : "false")
      tab.tabIndex = sel ? 0 : -1
    })
    this.panelTargets.forEach((panel) => {
      const show = panel.dataset.kind === active
      panel.hidden = !show
    })
  }
}
