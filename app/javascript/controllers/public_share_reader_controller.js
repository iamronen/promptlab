import { Controller } from "@hotwired/stimulus"

const SLIDE_MS = 300
const MULTI_HOP_PAUSE_MS = 350
const CONTENT_FONT_SCALE_STORAGE_KEY = "promptlab:publicShareReaderContentFontScale"

const CONTENT_FONT_SCALES = {
  80: 0.8,
  100: 1,
  120: 1.2
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function decodeHtmlEntities(text) {
  const textarea = document.createElement("textarea")
  textarea.innerHTML = text
  return textarea.value
}

function parseReaderPayload(raw) {
  let json = String(raw || "").trim()
  if (!json) return {}

  if (/&(?:quot|#39|lt|gt|amp);/.test(json)) {
    json = decodeHtmlEntities(json)
  }

  return JSON.parse(json)
}

function normalizeStepContent(html) {
  let normalized = String(html || "")
  if (!normalized) return ""

  if (/&lt;(?:\/)?(?:strong|em|b|i|u|p|br|span)\b/i.test(normalized)) {
    const textarea = document.createElement("textarea")
    textarea.innerHTML = normalized
    normalized = textarea.value
  }

  const template = document.createElement("template")
  template.innerHTML = normalized
  template.content.querySelectorAll("b").forEach((node) => {
    const strong = document.createElement("strong")
    strong.innerHTML = node.innerHTML
    node.replaceWith(strong)
  })
  template.content.querySelectorAll("i").forEach((node) => {
    const em = document.createElement("em")
    em.innerHTML = node.innerHTML
    node.replaceWith(em)
  })

  return template.innerHTML
}

const ARROW_RIGHT_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>`

const NO_ENTRANCE_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/></svg>`

export default class extends Controller {
  static targets = [
    "payloadSource",
    "topNav",
    "toolbarIndex",
    "contentShell",
    "tier80",
    "tier100",
    "tier120",
    "drawer",
    "drawerList",
    "viewport",
    "contentPanel",
    "bottomNav"
  ]

  connect() {
    this.payload = parseReaderPayload(this.payloadSourceTarget.textContent)
    this.payloadSourceTarget.remove()
    this.shareRootId = this.payload.share_root_public_id
    this.showTopNav = this.payload.show_top_nav === true
    this.threads = this.payload.threads || {}
    this.currentThreadId = this.payload.initial_thread_public_id
    this.drawerOpen = false
    this.animating = false
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    this.renderCurrentThread({ animate: false })
    this.restoreContentFontScale()
    this.boundSyncButtonHeights = () => this.syncReadMoreButtonHeights()
    window.addEventListener("resize", this.boundSyncButtonHeights)
  }

  disconnect() {
    window.removeEventListener("resize", this.boundSyncButtonHeights)
  }

  get currentThread() {
    return this.threads[this.currentThreadId]
  }

  async renderCurrentThread({ animate = false, direction = "forward" } = {}) {
    const thread = this.currentThread
    if (!thread) return

    const html = this.buildThreadBodyHtml(thread)
    const shouldAnimate = animate && !this.prefersReducedMotion

    if (shouldAnimate) {
      this.animating = true
    }

    try {
      await this.renderThreadBody(html, { animate: shouldAnimate, direction })
      this.renderThreadChrome(thread)
      this.syncUrl()
      requestAnimationFrame(() => this.syncReadMoreButtonHeights())
    } finally {
      if (shouldAnimate) {
        this.animating = false
      }
    }
  }

  renderThreadBody(html, { animate = false, direction = "forward" } = {}) {
    if (animate) {
      return this.animateContentSwapAsync(html, direction)
    }

    this.contentPanelTarget.innerHTML = html
    return Promise.resolve()
  }

  renderThreadChrome(thread) {
    this.renderTopNav(thread)
    this.renderToolbar(thread)
    this.renderBottomNav(thread)
    this.renderDrawerList(thread)
  }

  buildThreadBodyHtml(thread) {
    const children = thread.strand_children || []
    if (children.length === 0) {
      return `<div class="public-share-reader-panel-inner"><div class="public-share-reader-body public-share-reader-body--empty"><p class="public-share-reader-empty">No content in this thread.</p></div></div>`
    }

    const sections = children.map((child) => this.buildStrandSectionHtml(child)).join("")
    return `<div class="public-share-reader-panel-inner"><div class="public-share-reader-body">${sections}</div></div>`
  }

  buildStrandSectionHtml(child) {
    const anchorId = `strand-item-${child.position}`

    if (child.kind === "bundle") {
      const inner = (child.sequences || [])
        .map((seq) => {
          const steps = this.buildStepsListHtml(seq.steps)
          const sequencePosition = `${child.position}.${seq.position}`
          return `<section class="public-share-reader-bundle-sequence">
            ${this.buildPositionTitleHtml(sequencePosition, seq.title, "h4", "public-share-reader-bundle-sequence-title")}
            ${steps}
          </section>`
        })
        .join("")

      return `<section class="public-share-reader-strand-item public-share-reader-strand-item--bundle" id="${anchorId}">
        ${this.buildPositionTitleHtml(child.position, child.title, "h3", "public-share-reader-strand-title")}
        <div class="public-share-reader-bundle-sequences">${inner}</div>
      </section>`
    }

    const steps = this.buildStepsListHtml(child.steps)
    return `<section class="public-share-reader-strand-item public-share-reader-strand-item--sequence" id="${anchorId}">
      ${this.buildPositionTitleHtml(child.position, child.title, "h3", "public-share-reader-strand-title")}
      ${steps}
    </section>`
  }

  buildPositionTitleHtml(position, title, tagName, className) {
    return `<${tagName} class="${className}">
      <span class="public-share-reader-position-badge">${position}</span>
      <span class="public-share-reader-item-title-text">${escapeHtml(title)}</span>
    </${tagName}>`
  }

  buildStepsListHtml(steps) {
    if (!steps || steps.length === 0) {
      return `<ol class="public-share-reader-steps public-share-reader-steps--empty"></ol>`
    }

    const items = steps
      .map((step) => {
        const content = normalizeStepContent(step.content)
        return `<li class="public-share-reader-step"><div class="rich-editor public-share-reader-step-content">${content}</div></li>`
      })
      .join("")

    return `<ol class="public-share-reader-steps">${items}</ol>`
  }

  renderTopNav(thread) {
    const nav = this.topNavTarget
    if (!this.showTopNav) {
      nav.hidden = true
      nav.innerHTML = ""
      return
    }

    nav.hidden = false
    const segments = thread.breadcrumb || []
    const parts = segments.map((seg, idx) => {
      const sep = idx === 0 ? "" : `<span class="workspace-thread-panel-title-breadcrumb-sep" aria-hidden="true">/</span>`
      if (seg.current) {
        return `${sep}<span class="workspace-thread-panel-title-breadcrumb-current text-prompt-muted">${escapeHtml(seg.label)}</span>`
      }
      return `${sep}<button type="button" class="workspace-thread-panel-title-breadcrumb-ancestor text-prompt-muted public-share-reader-breadcrumb-btn" data-action="public-share-reader#navigateBreadcrumb" data-public-id="${escapeHtml(seg.public_id)}">${escapeHtml(seg.label)}</button>`
    })

    nav.innerHTML = parts.join("")
  }

  renderToolbar(thread) {
    const children = thread.strand_children || []
    this.toolbarIndexTarget.hidden = children.length <= 1
  }

  restoreContentFontScale() {
    let level = 100
    try {
      const raw = window.localStorage.getItem(CONTENT_FONT_SCALE_STORAGE_KEY)
      if (raw === "80" || raw === "100" || raw === "120") level = Number(raw)
    } catch (_) {
      /* ignore */
    }
    this.applyContentFontScale(level)
  }

  setContentFontSize(event) {
    event.preventDefault()
    const level = Number(event.params.size)
    if (!CONTENT_FONT_SCALES[level]) return

    try {
      window.localStorage.setItem(CONTENT_FONT_SCALE_STORAGE_KEY, String(level))
    } catch (_) {
      /* ignore */
    }
    this.applyContentFontScale(level)
  }

  applyContentFontScale(level) {
    if (!this.hasContentShellTarget) return

    const scale = CONTENT_FONT_SCALES[level] ?? 1
    this.contentShellTarget.style.setProperty("--public-share-reader-content-font-scale", String(scale))
    this.syncContentFontScaleButtons(level)
  }

  syncContentFontScaleButtons(level) {
    if (this.hasTier80Target) this.tier80Target.setAttribute("aria-pressed", level === 80 ? "true" : "false")
    if (this.hasTier100Target) this.tier100Target.setAttribute("aria-pressed", level === 100 ? "true" : "false")
    if (this.hasTier120Target) this.tier120Target.setAttribute("aria-pressed", level === 120 ? "true" : "false")
  }

  renderBottomNav(thread) {
    const nav = this.bottomNavTarget
    const childThreads = thread.child_threads || []

    if (childThreads.length === 0) {
      nav.innerHTML = ""
      nav.hidden = true
      return
    }

    nav.hidden = false
    const buttons = childThreads.map((child) => {
      const disabled = !child.readable
      const icon = disabled ? NO_ENTRANCE_SVG : ARROW_RIGHT_SVG
      const attrs = disabled
        ? `disabled aria-disabled="true"`
        : `data-action="public-share-reader#navigateForward" data-public-id="${escapeHtml(child.public_id)}"`

      return `<button type="button" class="public-share-reader-read-more${disabled ? " public-share-reader-read-more--disabled" : ""}" ${attrs}>
        <span class="public-share-reader-read-more-label">Read more: ${escapeHtml(child.title)}</span>
        <span class="public-share-reader-read-more-icon">${icon}</span>
      </button>`
    })

    nav.innerHTML = `<div class="public-share-reader-read-more-stack">${buttons.join("")}</div>`
    requestAnimationFrame(() => this.syncReadMoreButtonHeights())
  }

  renderDrawerList(thread) {
    const list = this.drawerListTarget
    const children = thread.strand_children || []
    list.innerHTML = children
      .map((child) => {
        const label = `${child.position}. ${escapeHtml(child.title)}`
        return `<li><button type="button" class="public-share-reader-drawer-item" data-action="public-share-reader#scrollToStrand" data-position="${child.position}">${label}</button></li>`
      })
      .join("")
  }

  openDrawer(event) {
    event.preventDefault()
    this.drawerOpen = true
    this.drawerTarget.hidden = false
    this.drawerTarget.setAttribute("aria-hidden", "false")
    requestAnimationFrame(() => {
      this.drawerTarget.classList.add("public-share-reader-drawer--open")
    })
  }

  closeDrawer(event) {
    if (event) event.preventDefault()
    this.drawerOpen = false
    this.drawerTarget.classList.remove("public-share-reader-drawer--open")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    window.setTimeout(() => {
      if (!this.drawerOpen) this.drawerTarget.hidden = true
    }, SLIDE_MS)
  }

  scrollToStrand(event) {
    event.preventDefault()
    const position = event.currentTarget.getAttribute("data-position")
    const anchor = this.contentPanelTarget.querySelector(`#strand-item-${position}`)
    this.closeDrawer()
    if (anchor) {
      anchor.scrollIntoView({ behavior: this.prefersReducedMotion ? "auto" : "smooth", block: "start" })
    }
  }

  async navigateForward(event) {
    event.preventDefault()
    if (this.animating) return

    const publicId = event.currentTarget.getAttribute("data-public-id")?.trim()
    if (!publicId || !this.threads[publicId]) return

    this.currentThreadId = publicId
    await this.renderCurrentThread({ animate: true, direction: "forward" })
  }

  async navigateBreadcrumb(event) {
    event.preventDefault()
    if (this.animating) return

    const targetId = event.currentTarget.getAttribute("data-public-id")?.trim()
    if (!targetId || targetId === this.currentThreadId) return

    const chain = this.ancestorChainToTarget(targetId)
    if (chain.length === 0) return

    if (chain.length === 1) {
      this.currentThreadId = chain[0]
      await this.renderCurrentThread({ animate: true, direction: "back" })
      return
    }

    await this.animateMultiHopBack(chain)
  }

  ancestorChainToTarget(targetId) {
    const current = this.currentThread
    if (!current?.breadcrumb) return [targetId]

    const segments = current.breadcrumb
    const targetIdx = segments.findIndex((s) => s.public_id === targetId)
    if (targetIdx < 0) return [targetId]

    const currentIdx = segments.findIndex((s) => s.current)
    if (currentIdx < 0 || targetIdx >= currentIdx) return []

    return segments.slice(targetIdx, currentIdx).map((s) => s.public_id).reverse()
  }

  async animateMultiHopBack(chain) {
    this.animating = true

    try {
      for (let i = 0; i < chain.length; i += 1) {
        const nextId = chain[i]
        this.currentThreadId = nextId
        const thread = this.currentThread
        const html = this.buildThreadBodyHtml(thread)

        await this.renderThreadBody(html, {
          animate: !this.prefersReducedMotion,
          direction: "back"
        })
        this.renderThreadChrome(thread)
        this.syncUrl()

        if (!this.prefersReducedMotion && i < chain.length - 1) {
          await this.pause(MULTI_HOP_PAUSE_MS)
        }
      }

      this.syncReadMoreButtonHeights()
    } finally {
      this.animating = false
    }
  }

  pause(ms) {
    return new Promise((resolve) => window.setTimeout(resolve, ms))
  }

  nextFrame() {
    return new Promise((resolve) => requestAnimationFrame(resolve))
  }

  animateContentSwapAsync(html, direction) {
    return new Promise((resolve) => {
      const panel = this.contentPanelTarget
      if (this.prefersReducedMotion) {
        panel.innerHTML = html
        resolve()
        return
      }

      const viewport = this.viewportTarget
      const viewportHeight = `${viewport.clientHeight}px`

      const outgoing = document.createElement("div")
      outgoing.className = "public-share-reader-panel public-share-reader-panel--outgoing"
      outgoing.innerHTML = panel.innerHTML
      outgoing.style.height = viewportHeight

      const incoming = document.createElement("div")
      incoming.className = "public-share-reader-panel public-share-reader-panel--incoming"
      incoming.innerHTML = html
      incoming.style.height = viewportHeight

      panel.hidden = true
      viewport.appendChild(outgoing)
      viewport.appendChild(incoming)

      const outClass = direction === "forward" ? "public-share-reader-panel--exit-left" : "public-share-reader-panel--exit-right"
      const inStartClass = direction === "forward" ? "public-share-reader-panel--enter-from-right" : "public-share-reader-panel--enter-from-left"

      incoming.classList.add(inStartClass)

      this.nextFrame()
        .then(() => this.nextFrame())
        .then(() => {
          outgoing.classList.add(outClass)
          incoming.classList.remove(inStartClass)
          incoming.classList.add("public-share-reader-panel--enter-active")
        })

      window.setTimeout(() => {
        outgoing.remove()
        incoming.remove()
        panel.hidden = false
        panel.innerHTML = html
        resolve()
      }, SLIDE_MS)
    })
  }

  syncUrl() {
    const url = new URL(window.location.href)
    if (this.currentThreadId === this.shareRootId) {
      url.searchParams.delete("t")
    } else {
      url.searchParams.set("t", this.currentThreadId)
    }
    window.history.replaceState({}, "", url.toString())
  }

  syncReadMoreButtonHeights() {
    const stack = this.bottomNavTarget.querySelector(".public-share-reader-read-more-stack")
    if (!stack) return

    const buttons = stack.querySelectorAll(".public-share-reader-read-more")
    if (buttons.length === 0) return

    buttons.forEach((btn) => {
      btn.style.minHeight = ""
    })

    let maxHeight = 0
    buttons.forEach((btn) => {
      maxHeight = Math.max(maxHeight, btn.offsetHeight)
    })

    if (maxHeight > 0) {
      buttons.forEach((btn) => {
        btn.style.minHeight = `${maxHeight}px`
      })
    }
  }
}
