import { Controller } from "@hotwired/stimulus"

const STORAGE = "promptlab:workspaceAssistantOpen"

/** Toggles the right assistant column; persists preference and expands the grid middle track when hidden. */
export default class extends Controller {
  static targets = ["workspace", "assistant", "button"]

  connect() {
    this.applyFromStorage()
  }

  isOpen() {
    return localStorage.getItem(STORAGE) !== "false"
  }

  applyFromStorage() {
    this.setOpen(this.isOpen(), { persist: false })
  }

  toggle() {
    this.setOpen(!this.isOpen(), { persist: true })
  }

  /**
   * @param {boolean} open
   * @param {{ persist?: boolean }} opts
   */
  setOpen(open, opts = {}) {
    const { persist = true } = opts
    if (persist) {
      localStorage.setItem(STORAGE, open ? "true" : "false")
    }

    const grid = this.hasWorkspaceTarget ? this.workspaceTarget : null
    const panel = this.hasAssistantTarget ? this.assistantTarget : null

    grid?.classList.toggle("workspace--assistant-collapsed", !open)

    const shell = grid?.closest(".workspace-shell")
    shell?.classList.toggle("workspace-shell--assistant-collapsed", !open)

    if (panel) {
      panel.hidden = !open
      panel.setAttribute("aria-hidden", open ? "false" : "true")
    }

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", open ? "true" : "false")
      const label = open ? "Hide assistant panel" : "Show assistant panel"
      this.buttonTarget.setAttribute("aria-label", label)
      this.buttonTarget.title = label
    }
  }
}
