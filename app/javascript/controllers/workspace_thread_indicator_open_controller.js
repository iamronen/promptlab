import { Controller } from "@hotwired/stimulus"

/** Eye on branched-thread pill: open/focus workspace strip panel via thread_workspace_controller. */
export default class extends Controller {
  static values = {
    threadId: Number,
    insertAfterPanelThreadId: Number
  }

  /** @param {MouseEvent} event */
  openPanel(event) {
    event.preventDefault()
    event.stopPropagation()

    const id = parseInt(String(this.threadIdValue), 10)
    if (!(id > 0)) return

    /** @type {{ threadId: number; insertAfterPanelThreadId?: number }} */
    const detail = { threadId: id }

    const anchor = parseInt(String(this.insertAfterPanelThreadIdValue || 0), 10)
    if (anchor > 0) detail.insertAfterPanelThreadId = anchor

    window.dispatchEvent(new CustomEvent("thread-workspace:open", { detail }))
  }
}
