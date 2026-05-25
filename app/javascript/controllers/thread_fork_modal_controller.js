import { Controller } from "@hotwired/stimulus"
import { trimTrailingWhitespaceInPlace } from "text_input_sanitizer"

export default class extends Controller {
  static targets = ["dialog", "form", "titleInput", "parentSequenceIdInput", "redirectToInput", "scopeParamsContainer"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const action = btn.getAttribute("data-fork-url")
    if (!action || !this.hasDialogTarget || !this.hasFormTarget) return

    this.formTarget.action = action

    if (this.hasParentSequenceIdInputTarget) {
      this.parentSequenceIdInputTarget.value = btn.getAttribute("data-parent-sequence-id") || ""
    }
    if (this.hasRedirectToInputTarget) {
      this.redirectToInputTarget.value = btn.getAttribute("data-redirect-to") || ""
    }
    if (this.hasScopeParamsContainerTarget) {
      this.scopeParamsContainerTarget.innerHTML = ""
      let scopeParams = {}
      try {
        scopeParams = JSON.parse(btn.getAttribute("data-scope-params") || "{}")
      } catch (_) {
        /* ignore */
      }
      for (const [key, value] of Object.entries(scopeParams)) {
        if (value == null || value === "") continue
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = key
        input.value = String(value)
        this.scopeParamsContainerTarget.appendChild(input)
      }
    }

    if (this.hasTitleInputTarget) {
      this.titleInputTarget.value = ""
    }

    this.dialogTarget.showModal()
    requestAnimationFrame(() => {
      this.titleInputTarget?.focus()
    })
  }

  submit(event) {
    if (this.hasTitleInputTarget) trimTrailingWhitespaceInPlace(this.titleInputTarget)
  }

  close(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget) return
    this.dialogTarget.close()
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.value = ""
    }
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.close(event)
  }
}
