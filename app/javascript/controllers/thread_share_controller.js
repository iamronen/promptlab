import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

export default class extends Controller {
  static targets = [
    "dialog",
    "body",
    "saveButton",
    "openShareButton",
    "deleteButton",
    "deleteConfirmDialog",
    "deleteConfirmMessage"
  ]
  static values = { shareUrlTemplate: String, publicShareUrlTemplate: String }

  connect() {
    this._activeThreadPublicId = null
    this._sharePayload = null
    this.boundHandleOpen = this.handleOpenEvent.bind(this)
    this.boundShareTriggerClick = this.onShareTriggerClick.bind(this)
    window.addEventListener("thread-share:open", this.boundHandleOpen)
    document.addEventListener("click", this.boundShareTriggerClick, true)
  }

  disconnect() {
    window.removeEventListener("thread-share:open", this.boundHandleOpen)
    document.removeEventListener("click", this.boundShareTriggerClick, true)
  }

  onShareTriggerClick(event) {
    if (event.__threadShareHandled) return

    const trigger = event.target.closest("[data-thread-share-open]")
    if (!trigger) return

    event.__threadShareHandled = true
    const publicId = trigger.getAttribute("data-thread-share-open")?.trim()
    if (!publicId) return

    event.preventDefault()
    event.stopPropagation()
    this.closeOpenMenus()
    this.openForPublicId(publicId)
  }

  closeOpenMenus() {
    document.querySelectorAll(".fabric-thread-menu-panel").forEach((el) => {
      el.hidden = true
    })
    document.querySelectorAll("[data-fabric-thread-menu-target='trigger']").forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
    document.querySelectorAll(".workspace-thread-panel-title-menu-panel").forEach((el) => {
      el.hidden = true
    })
    document.querySelectorAll('[data-workspace-thread-panel-title-target="menuTrigger"]').forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
    document.querySelectorAll("[data-project-share-card-menu-target='panel']").forEach((el) => {
      el.hidden = true
    })
    document.querySelectorAll("[data-project-share-card-menu-target='trigger']").forEach((btn) => {
      btn.setAttribute("aria-expanded", "false")
    })
  }

  handleOpenEvent(event) {
    const publicId = event.detail?.threadPublicId?.trim()
    if (!publicId) return
    this.openForPublicId(publicId)
  }

  threadPublicIdFromEvent(event) {
    return event.currentTarget.getAttribute("data-thread-public-id")?.trim() || this._activeThreadPublicId
  }

  shareUrlFor(publicId) {
    return this.shareUrlTemplateValue.replace("__ID__", encodeURIComponent(publicId))
  }

  publicShareUrlFor(publicId) {
    return this.publicShareUrlTemplateValue.replace("__ID__", encodeURIComponent(publicId))
  }

  get shareDialog() {
    if (this.hasDialogTarget) return this.dialogTarget
    return this.element.querySelector("dialog.thread-share-modal")
  }

  async open(event) {
    event.preventDefault()
    const publicId = this.threadPublicIdFromEvent(event)
    if (!publicId) return
    await this.openForPublicId(publicId)
  }

  async openForPublicId(publicId) {
    if (!this.shareUrlTemplateValue) {
      console.error("[thread-share] share URL template is missing on controller element")
      return
    }

    this._activeThreadPublicId = publicId
    let res
    try {
      res = await fetch(this.shareUrlFor(publicId), {
        credentials: "same-origin",
        cache: "no-store",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
    } catch (error) {
      console.error("[thread-share] fetch failed", error)
      return
    }

    if (!res.ok) {
      console.error("[thread-share] share request failed", res.status, res.statusText)
      return
    }

    let body
    try {
      body = await res.json()
    } catch (error) {
      console.error("[thread-share] invalid JSON response", error)
      return
    }

    this._sharePayload = body.share
    try {
      this.renderBody(body.share)
      this.updateFooter(body.share)
    } catch (error) {
      console.error("[thread-share] renderBody failed", error)
      return
    }
    const dialog = this.shareDialog
    if (dialog) dialog.showModal()
    else console.error("[thread-share] dialog element not found")
  }

  updateFooter(share) {
    if (this.hasSaveButtonTarget) {
      this.saveButtonTarget.textContent = share.share_defined ? "Update" : "Create"
    }
    if (this.hasOpenShareButtonTarget) {
      this.openShareButtonTarget.hidden = !(share.share_defined && share.share_enabled === true)
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.hidden = !share.share_defined
    }
  }

  openShare(event) {
    event.preventDefault()
    const publicId = this._activeThreadPublicId
    if (!publicId || !this.publicShareUrlTemplateValue) return

    window.open(this.publicShareUrlFor(publicId), "_blank", "noopener,noreferrer")
  }

  renderBody(share) {
    if (!this.hasBodyTarget) return

    const breadcrumbHtml = this.renderBreadcrumb(share)
    const defaultName = share.share_public_name || share.thread_title || ""
    const shareEnabled = share.share_enabled === true
    const scopeEverything = (share.share_scope || "everything") === "everything"
    const tease = share.share_tease === true
    const includedSet = new Set(share.included_thread_public_ids || [])
    const treeHtml = share.thread_tree
      ? this.renderTree(share.thread_tree, includedSet, 0, null)
      : `<p class="m-0 text-sm text-prompt-muted">No descendant threads.</p>`

    this.bodyTarget.innerHTML = `
<div class="thread-share-modal-section thread-share-modal-section--status">
  ${breadcrumbHtml}
  <div class="thread-share-modal-field mt-4">
    <label class="thread-share-modal-label" for="thread-share-public-name">Share name</label>
    <input
      id="thread-share-public-name"
      type="text"
      class="thread-share-modal-input w-full rounded-lg border border-prompt-field-border px-2 py-2 text-[0.9rem]"
      value="${escapeHtml(defaultName)}"
      data-thread-share-target="sharePublicNameInput"
      autocomplete="off"
    />
  </div>
  <div class="thread-share-modal-field mt-4">
    <label class="project-sharing-switch">
      <input
        type="checkbox"
        role="switch"
        class="project-sharing-switch__input"
        data-thread-share-target="shareEnabledInput"
        ${shareEnabled ? "checked" : ""}
      />
      <span class="project-sharing-switch__track" aria-hidden="true"></span>
      <span class="project-sharing-switch__label">Share enabled</span>
    </label>
  </div>
</div>
<div class="thread-share-modal-section thread-share-modal-section--contents mt-5 border-t border-gray-200 pt-5 dark:border-gray-700">
  <fieldset class="thread-share-scope-fieldset m-0 border-0 p-0">
    <legend class="thread-share-modal-label mb-2">Share contents</legend>
    <div class="thread-share-scope-toggle flex flex-wrap gap-2">
      <label class="thread-share-scope-option">
        <input
          type="radio"
          name="thread-share-scope"
          value="everything"
          data-thread-share-target="scopeInput"
          data-action="change->thread-share#onScopeChange"
          ${scopeEverything ? "checked" : ""}
        />
        <span>Share everything</span>
      </label>
      <label class="thread-share-scope-option">
        <input
          type="radio"
          name="thread-share-scope"
          value="selected"
          data-thread-share-target="scopeInput"
          data-action="change->thread-share#onScopeChange"
          ${scopeEverything ? "" : "checked"}
        />
        <span>Share selected threads</span>
      </label>
    </div>
  </fieldset>
  <div
    class="thread-share-selected-panel mt-4"
    data-thread-share-target="selectedPanel"
    ${scopeEverything ? "hidden" : ""}
  >
    <div class="thread-share-modal-field">
      <label class="project-sharing-switch">
        <input
          type="checkbox"
          role="switch"
          class="project-sharing-switch__input"
          data-thread-share-target="teaseInput"
          ${tease ? "checked" : ""}
        />
        <span class="project-sharing-switch__track" aria-hidden="true"></span>
        <span class="project-sharing-switch__label">Tease hidden threads</span>
      </label>
      <p class="m-0 mt-1 text-xs text-prompt-muted">When on, readers see hints that additional child threads exist but are not included in this share.</p>
    </div>
    <div class="thread-share-tree-wrap mt-4" data-thread-share-target="treeWrap">
      <ul class="thread-share-tree-roots m-0 list-none p-0" role="tree" data-thread-share-target="treeRoot">
        ${treeHtml}
      </ul>
    </div>
  </div>
</div>`

    this.syncVisibilitySwitchStates()
  }

  renderBreadcrumb(share) {
    const crumb = share.breadcrumb
    if (!crumb || !crumb.segments?.length) {
      return `<nav class="thread-share-breadcrumb" aria-label="Thread location"><span class="text-prompt-muted">${escapeHtml(share.thread_title || "")}</span></nav>`
    }

    const parts = []
    if (crumb.ellipsis) {
      parts.push(`<span class="workspace-thread-panel-title-breadcrumb-ellipsis" aria-hidden="true">…</span>`)
      parts.push(`<span class="workspace-thread-panel-title-breadcrumb-sep" aria-hidden="true">/</span>`)
    }
    crumb.segments.forEach((seg, idx) => {
      if (idx > 0 || crumb.ellipsis) {
        parts.push(`<span class="workspace-thread-panel-title-breadcrumb-sep" aria-hidden="true">/</span>`)
      }
      if (seg.current) {
        parts.push(`<span class="workspace-thread-panel-title-breadcrumb-current text-prompt-muted">${escapeHtml(seg.title)}</span>`)
      } else {
        parts.push(`<span class="workspace-thread-panel-title-breadcrumb-ancestor text-prompt-muted">${escapeHtml(seg.title)}</span>`)
      }
    })
    return `<nav class="thread-share-breadcrumb project-share-card-breadcrumb workspace-thread-panel-title-breadcrumb" aria-label="Thread location">${parts.join("")}</nav>`
  }

  renderTree(node, includedSet, depth, parentPublicId) {
    const isRoot = depth === 0
    const children = node.children || []
    const hasChildren = children.length > 0
    const parentIncluded = isRoot || (parentPublicId && includedSet.has(parentPublicId))
    const switchEnabled = isRoot ? false : depth === 1 || parentIncluded
    const isIncluded = includedSet.has(node.public_id)

    if (isRoot) {
      const childHtml = children
        .map((child) => this.renderTree(child, includedSet, depth + 1, node.public_id))
        .join("")
      return `
<li class="thread-share-tree-root-item" role="none">
  <div class="thread-share-tree-row thread-share-tree-row--root">
    <span class="thread-share-tree-switch-spacer" aria-hidden="true"></span>
    <span class="thread-share-tree-chevron-spacer" aria-hidden="true"></span>
    <span class="thread-share-tree-title font-medium text-prompt-heading">${escapeHtml(node.title)}</span>
  </div>
  ${childHtml ? `<ul class="thread-share-tree-children m-0 list-none p-0" role="group">${childHtml}</ul>` : ""}
</li>`
    }

    const switchHtml = this.visibilitySwitchHtml(
      node.public_id,
      isIncluded,
      switchEnabled && !isRoot
    )

    if (hasChildren) {
      const childHtml = children
        .map((child) => this.renderTree(child, includedSet, depth + 1, node.public_id))
        .join("")
      return `
<li class="thread-share-tree-item" role="none">
  <details class="thread-share-tree-node fabric-tree-node fabric-tree-node-thread">
    <summary class="thread-share-tree-summary fabric-tree-thread-summary">
      <span class="thread-share-tree-row fabric-tree-row">
        ${switchHtml}
        <span class="fabric-tree-chevron-cell" aria-hidden="true">
          <svg class="fabric-tree-chevron" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><polyline points="9 18 15 12 9 6"/></svg>
        </span>
        <span class="thread-share-tree-title fabric-tree-thread-select">${escapeHtml(node.title)}</span>
      </span>
    </summary>
    <ul class="thread-share-tree-children fabric-tree-thread-children m-0 list-none p-0" role="group">${childHtml}</ul>
  </details>
</li>`
    }

    return `
<li class="thread-share-tree-item thread-share-tree-item--leaf" role="none">
  <div class="thread-share-tree-row fabric-tree-row fabric-tree-row--leaf">
    ${switchHtml}
    <span class="fabric-tree-chevron-cell fabric-tree-chevron-cell--blank" aria-hidden="true"></span>
    <span class="thread-share-tree-title fabric-tree-thread-select">${escapeHtml(node.title)}</span>
  </div>
</li>`
  }

  visibilitySwitchHtml(publicId, checked, enabled) {
    return `
<span class="thread-share-tree-switch-cell">
  <label class="project-sharing-switch project-sharing-switch--compact thread-share-visibility-switch">
    <input
      type="checkbox"
      role="switch"
      class="project-sharing-switch__input thread-share-visibility-input"
      value="${escapeHtml(publicId)}"
      data-thread-share-target="visibilityInput"
      data-action="change->thread-share#onVisibilityChange"
      ${checked ? "checked" : ""}
      ${enabled ? "" : "disabled"}
      aria-label="Include thread in share"
    />
    <span class="project-sharing-switch__track" aria-hidden="true"></span>
  </label>
</span>`
  }

  onScopeChange() {
    const selected = this.selectedScope() === "selected"
    const panel = this.bodyTarget?.querySelector(".thread-share-selected-panel")
    if (panel) panel.hidden = !selected
  }

  selectedScope() {
    const checked = this.bodyTarget?.querySelector("[data-thread-share-target='scopeInput']:checked")
    return checked?.value || "everything"
  }

  onVisibilityChange(event) {
    const input = event.currentTarget
    const publicId = input.value
    const checked = input.checked

    if (!checked) {
      this.uncheckDescendants(publicId)
    }
    this.syncVisibilitySwitchStates()
  }

  uncheckDescendants(publicId) {
    const root = this.bodyTarget?.querySelector("[data-thread-share-target='treeRoot']")
    if (!root) return

    const start = root.querySelector(`[data-thread-share-target='visibilityInput'][value="${CSS.escape(publicId)}"]`)
    if (!start) return

    const item = start.closest(".thread-share-tree-item, .thread-share-tree-root-item")
    if (!item) return

    item.querySelectorAll("[data-thread-share-target='visibilityInput']").forEach((el) => {
      if (el !== start) {
        el.checked = false
        el.disabled = true
      }
    })
  }

  syncVisibilitySwitchStates() {
    const root = this.bodyTarget?.querySelector("[data-thread-share-target='treeRoot']")
    if (!root) return

    const walk = (listItem, parentIncluded) => {
      const row = listItem.querySelector(":scope > .thread-share-tree-row, :scope > details > .thread-share-tree-summary .thread-share-tree-row")
      const input = row?.querySelector("[data-thread-share-target='visibilityInput']")
      const isRoot = listItem.classList.contains("thread-share-tree-root-item")

      let included = isRoot
      if (input) {
        if (!parentIncluded) {
          input.disabled = true
          input.checked = false
        } else {
          input.disabled = false
          included = input.checked
        }
      }

      const childLists = listItem.querySelectorAll(":scope > ul, :scope > details > ul")
      childLists.forEach((ul) => {
        ul.querySelectorAll(":scope > .thread-share-tree-item").forEach((child) => walk(child, included))
      })
    }

    root.querySelectorAll(":scope > .thread-share-tree-root-item").forEach((rootItem) => walk(rootItem, true))
  }

  close(event) {
    event?.preventDefault()
    this.shareDialog?.close()
    this._activeThreadPublicId = null
    this._sharePayload = null
  }

  onDialogBackdrop(event) {
    if (event.target === this.shareDialog) this.close(event)
  }

  collectIncludedPublicIds() {
    if (this.selectedScope() !== "selected") return []

    return [...(this.bodyTarget?.querySelectorAll("[data-thread-share-target='visibilityInput']:checked:not(:disabled)") || [])].map(
      (el) => el.value
    )
  }

  async save(event) {
    event.preventDefault()
    const publicId = this._activeThreadPublicId
    if (!publicId) return

    const nameInput = this.bodyTarget?.querySelector("[data-thread-share-target='sharePublicNameInput']")
    const enabledInput = this.bodyTarget?.querySelector("[data-thread-share-target='shareEnabledInput']")
    const teaseInput = this.bodyTarget?.querySelector("[data-thread-share-target='teaseInput']")

    await this.patchShare(publicId, {
      operation: "save",
      share_public_name: nameInput?.value?.trim() ?? "",
      share_scope: this.selectedScope(),
      share_tease: teaseInput?.checked ?? false,
      share_enabled: enabledInput?.checked ?? false,
      included_thread_public_ids: this.collectIncludedPublicIds()
    })
    this.close()
  }

  async enableShare(event) {
    event.preventDefault()
    const publicId = this.threadPublicIdFromEvent(event)
    if (!publicId) return
    await this.patchShare(publicId, { operation: "enable" })
  }

  async disableShare(event) {
    event.preventDefault()
    const publicId = this.threadPublicIdFromEvent(event)
    if (!publicId) return
    await this.patchShare(publicId, { operation: "disable" })
  }

  openDeleteConfirm(event) {
    event.preventDefault()
    const title =
      this.bodyTarget?.querySelector("[data-thread-share-target='sharePublicNameInput']")?.value?.trim() ||
      this._sharePayload?.share_public_title ||
      "this share"
    if (this.hasDeleteConfirmMessageTarget) {
      this.deleteConfirmMessageTarget.textContent = `Delete share “${title}”? This cannot be undone.`
    }
    if (this.hasDeleteConfirmDialogTarget) this.deleteConfirmDialogTarget.showModal()
  }

  openDeleteConfirmFromMenu(event) {
    event.preventDefault()
    const publicId = this.threadPublicIdFromEvent(event)
    const title = event.currentTarget.getAttribute("data-share-title")?.trim() || "this share"
    if (!publicId) return

    this._activeThreadPublicId = publicId
    if (this.hasDeleteConfirmMessageTarget) {
      this.deleteConfirmMessageTarget.textContent = `Delete share “${title}”? This cannot be undone.`
    }
    if (this.hasDeleteConfirmDialogTarget) this.deleteConfirmDialogTarget.showModal()
  }

  cancelDeleteConfirm(event) {
    event.preventDefault()
    if (this.hasDeleteConfirmDialogTarget) this.deleteConfirmDialogTarget.close()
  }

  onDeleteConfirmBackdrop(event) {
    if (event.target === this.deleteConfirmDialogTarget) this.cancelDeleteConfirm(event)
  }

  async confirmDelete(event) {
    event.preventDefault()
    const publicId = this._activeThreadPublicId
    if (!publicId) return

    const res = await fetch(this.shareUrlFor(publicId), {
      method: "DELETE",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "text/vnd.turbo-stream.html, application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      }
    })

    if (this.hasDeleteConfirmDialogTarget) this.deleteConfirmDialogTarget.close()
    if (this.hasDialogTarget && this.dialogTarget.open) this.close()

    if (!res.ok) return
    await this.applyMutationResponse(res)
    this._activeThreadPublicId = null
    this._sharePayload = null
  }

  async patchShare(publicId, shareAttrs) {
    const res = await fetch(this.shareUrlFor(publicId), {
      method: "PATCH",
      credentials: "same-origin",
      cache: "no-store",
      headers: {
        Accept: "text/vnd.turbo-stream.html, application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ share: shareAttrs })
    })

    if (!res.ok) return
    await this.applyMutationResponse(res)
  }

  async applyMutationResponse(res) {
    const contentType = res.headers.get("Content-Type") || ""
    if (contentType.includes("turbo-stream")) {
      const html = await res.text()
      Turbo.renderStreamMessage(html)
      return
    }

    try {
      await res.json()
    } catch (_) {
      /* ignore */
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") ?? ""
  }
}
