/** Hidden/context fields copied into meta-only autosave requests. */
const AUTOSAVE_CONTEXT_FIELD_NAMES = [
  "_method",
  "authenticity_token",
  "weave_thread",
  "thread_partner",
  "redirect_to",
  "strand_thread_chip_parent",
  "workspace_mode",
  "open_threads",
  "sidebar"
]

/**
 * @param {FormData} fd
 * @param {HTMLFormElement} form
 */
function appendAutosaveContextFields(fd, form) {
  for (const name of AUTOSAVE_CONTEXT_FIELD_NAMES) {
    const el = form.elements.namedItem(name)
    if (!el) continue
    if (typeof RadioNodeList !== "undefined" && el instanceof RadioNodeList) {
      for (const input of el) fd.append(name, input.value)
    } else if (
      el instanceof HTMLInputElement ||
      el instanceof HTMLTextAreaElement ||
      el instanceof HTMLSelectElement
    ) {
      fd.append(name, el.value)
    }
  }
}

/**
 * @param {string} url
 * @param {FormData} body
 * @returns {Promise<Response>}
 */
function postAutosave(url, body) {
  const token =
    document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  body.set("autosave", "1")

  return fetch(url, {
    method: "POST",
    body,
    headers: {
      Accept: "application/json",
      "X-Requested-With": "XMLHttpRequest",
      ...(token ? { "X-CSRF-Token": token } : {})
    },
    credentials: "same-origin"
  })
}

/**
 * @param {HTMLFormElement} form
 * @param {{ saveSteps?: boolean }} [options]
 * @returns {Promise<Response>}
 */
export async function fetchAutosaveForm(form, { saveSteps = false } = {}) {
  if (!form?.action) return Promise.resolve(new Response(null, { status: 400 }))

  const fd = new FormData(form)
  if (saveSteps) fd.set("save_steps", "1")

  return postAutosave(form.action, fd)
}

/**
 * Title/intent autosave without step fields (thread-modal meta blur).
 * @param {HTMLFormElement} form
 * @returns {Promise<Response>}
 */
export async function fetchAutosaveSequenceMeta(form) {
  if (!form?.action) return Promise.resolve(new Response(null, { status: 400 }))

  const fd = new FormData()
  appendAutosaveContextFields(fd, form)

  const titleEl = form.querySelector('[name="sequence[title]"]')
  const intentEl = form.querySelector('[name="sequence[intent]"]')
  if (titleEl instanceof HTMLInputElement || titleEl instanceof HTMLTextAreaElement) {
    fd.set("sequence[title]", titleEl.value)
  }
  if (intentEl instanceof HTMLInputElement || intentEl instanceof HTMLTextAreaElement) {
    fd.set("sequence[intent]", intentEl.value)
  }

  return postAutosave(form.action, fd)
}

/**
 * Pipeline child title/intent autosave without nested step fields.
 * @param {HTMLFormElement} form
 * @param {HTMLElement} pipelineRow
 * @returns {Promise<Response>}
 */
export async function fetchAutosavePipelineChildMeta(form, pipelineRow) {
  if (!form?.action || !pipelineRow) return Promise.resolve(new Response(null, { status: 400 }))

  const hiddenId = pipelineRow.querySelector('input.bundle-pipeline-sequence-id-field[type="hidden"]')
  const childId = hiddenId?.value
  if (!childId) return Promise.resolve(new Response(null, { status: 400 }))

  const fd = new FormData()
  appendAutosaveContextFields(fd, form)

  const titleInput = pipelineRow.querySelector(".bundle-pipeline-child-title-input")
  const intentInput = pipelineRow.querySelector(".bundle-pipeline-child-intent-input")
  if (titleInput instanceof HTMLInputElement || titleInput instanceof HTMLTextAreaElement) {
    fd.set(`nested_sequences[${childId}][title]`, titleInput.value)
  }
  if (intentInput instanceof HTMLInputElement || intentInput instanceof HTMLTextAreaElement) {
    fd.set(`nested_sequences[${childId}][intent]`, intentInput.value)
  }

  return postAutosave(form.action, fd)
}

/**
 * @param {string} url
 * @param {FormData} body
 * @returns {Promise<Response>}
 */
export async function fetchAutosavePost(url, body) {
  return postAutosave(url, body)
}
