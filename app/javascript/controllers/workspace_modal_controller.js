import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "bundleFrame", "sequenceFrame"]

  connect() {
    this.maybeAutoOpenSequenceModal()
  }

  maybeAutoOpenSequenceModal() {
    const el = document.querySelector("[data-sequence-modal-auto-open-url]")
    if (!el) return
    const url = el.getAttribute("data-sequence-modal-auto-open-url")
    el.remove()
    if (!url || !this.hasSequenceFrameTarget) return

    this.clearBundleModal()
    this.sequenceFrameTarget.src = url
    this.dialogTarget.showModal()

    const u = new URL(window.location.href)
    if (u.searchParams.get("editor_mode") === "edit") {
      u.searchParams.delete("editor_mode")
      window.history.replaceState({}, "", `${u.pathname}${u.search}${u.hash}`)
    }
  }

  openBundleFromButton(event) {
    const url = event.currentTarget.getAttribute("data-bundle-edit-url")
    if (!url) return
    this.openUrlInModal(url)
  }

  openUrlInModal(url) {
    if (!this.hasDialogTarget) return
    if (url.includes("/bundles/")) {
      if (!this.hasBundleFrameTarget) return
      this.clearSequenceModal()
      this.bundleFrameTarget.src = url
    } else {
      if (!this.hasSequenceFrameTarget) return
      this.clearBundleModal()
      this.sequenceFrameTarget.src = url
    }
    this.dialogTarget.showModal()
  }

  openBundleWithUrl(url) {
    this.openUrlInModal(url)
  }

  openSequenceFromLink(event) {
    if (this.ignoreLinkModifiers(event)) return
    event.preventDefault()
    const url = event.currentTarget.getAttribute("href")
    if (!url || !this.hasSequenceFrameTarget) return
    this.clearBundleModal()
    this.sequenceFrameTarget.src = url
    this.dialogTarget.showModal()
  }

  openBundleFromLink(event) {
    if (this.ignoreLinkModifiers(event)) return
    event.preventDefault()
    const url = event.currentTarget.getAttribute("href")
    if (!url || !this.hasBundleFrameTarget) return
    this.clearSequenceModal()
    this.bundleFrameTarget.src = url
    this.dialogTarget.showModal()
  }

  ignoreLinkModifiers(event) {
    return event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0
  }

  close() {
    if (!this.hasDialogTarget) return
    this.dialogTarget.close()
    this.clearBundleModal()
    this.clearSequenceModal()
  }

  clearBundleModal() {
    if (!this.hasBundleFrameTarget) return
    this.bundleFrameTarget.innerHTML = ""
    this.bundleFrameTarget.removeAttribute("src")
    this.bundleFrameTarget.removeAttribute("complete")
  }

  clearSequenceModal() {
    if (!this.hasSequenceFrameTarget) return
    this.sequenceFrameTarget.innerHTML = ""
    this.sequenceFrameTarget.removeAttribute("src")
    this.sequenceFrameTarget.removeAttribute("complete")
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
