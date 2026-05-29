import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "sharesList"]
  static values = { updateUrl: String }

  connect() {
    this.syncSharesListVisibility()
  }

  async onToggleChange(event) {
    if (!this.updateUrlValue) return

    const input = event.currentTarget
    const desired = !!input.checked
    const previous = !desired

    this.syncSharesListVisibility()

    const res = await fetch(this.updateUrlValue, {
      method: "PATCH",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ project: { sharing_allowed: desired } })
    })

    if (!res.ok) {
      input.checked = previous
      this.syncSharesListVisibility()
    }
  }

  syncSharesListVisibility() {
    if (!this.hasSharesListTarget || !this.hasToggleTarget) return
    this.sharesListTarget.hidden = !this.toggleTarget.checked
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ?? ""
  }
}
