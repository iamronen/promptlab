import { Controller } from "@hotwired/stimulus"

/**
 * Hides the thread-branch strand band attached below a turbo-loaded editor row when that editor body is collapsed.
 */
export default class extends Controller {
  connect() {
    this.boundBody = this.onBodyToggled.bind(this)
    this.element.addEventListener("thread-editor-sequence-body-toggled", this.boundBody)
  }

  disconnect() {
    this.element.removeEventListener("thread-editor-sequence-body-toggled", this.boundBody)
  }

  onBodyToggled(event) {
    const frame = /** @type {HTMLElement | null} */ (this.element.querySelector(":scope > .thread-strand-child__content turbo-frame"))
    if (!frame) return
    const outermost = /** @type {HTMLElement | undefined} */ (frame.firstElementChild || undefined)
    if (!outermost || /** @type {unknown} */ (event.target) !== outermost) return
    const expanded =
      event.detail &&
      typeof (/** @type { { expanded?: unknown } } */ (event.detail)).expanded === "boolean"
        ? /** @type { { expanded: boolean } } */ (event.detail).expanded
        : true
    this.element.classList.toggle("workspace-thread-editor-child--body-collapsed", !expanded)
  }
}
