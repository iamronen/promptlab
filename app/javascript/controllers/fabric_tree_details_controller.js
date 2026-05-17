import { Controller } from "@hotwired/stimulus"

/** Prevents <details> toggle when clicking the inert title (menu uses stopPropagation on its trigger). */
export default class extends Controller {
  connect() {
    this.summary = this.element.querySelector(":scope > summary.fabric-tree-thread-summary")
    if (!this.summary) return
    this.onSummaryClickCapture = (event) => {
      if (event.target.closest(".fabric-tree-thread-label")) {
        event.preventDefault()
      }
    }
    this.summary.addEventListener("click", this.onSummaryClickCapture, true)
  }

  disconnect() {
    if (this.summary && this.onSummaryClickCapture) {
      this.summary.removeEventListener("click", this.onSummaryClickCapture, true)
    }
  }
}
