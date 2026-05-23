/** Plain text from HTML (rich step content, etc.). */
export function htmlToPlainText(html) {
  const fragment = document.createElement("div")
  fragment.innerHTML = html == null ? "" : String(html)
  return fragment.innerText.replace(/\n{3,}/g, "\n\n")
}

/** Build clipboard text: title, intent, numbered steps. */
export function buildSequenceCopyText({ title, intent, steps }) {
  const lines = [
    htmlToPlainText(title).trim(),
    "",
    htmlToPlainText(intent).trim(),
    ""
  ]
  steps.forEach((content, i) => {
    const plain = htmlToPlainText(content).trim()
    if (plain) lines.push(`${i + 1}. ${plain}`)
  })
  return `${lines.join("\n").trim()}\n`
}

const SEQUENCE_STEP_ROW_SELECTOR = '[data-editor-kind="sequence_step"]'

/** Read live sequence editor form state (title, intent, steps). */
export function buildSequenceCopyTextFromEditorRoot(root) {
  if (!root) return null

  const title =
    root.querySelector('[data-sequence-editor-target="titleInput"]')?.value ?? ""
  const intent =
    root.querySelector('[data-sequence-editor-target="intentInput"]')?.value ?? ""

  const steps = []
  root.querySelectorAll(SEQUENCE_STEP_ROW_SELECTOR).forEach((card) => {
    const destroyed =
      card.querySelector('[data-sequence-editor-target="destroyInput"]')?.value === "true"
    if (destroyed) return

    const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
    const editor = card.querySelector('[data-sequence-editor-target="editor"]')
    steps.push(contentInput?.value ?? editor?.innerHTML ?? "")
  })

  return buildSequenceCopyText({ title, intent, steps })
}

/** Parse copy text from a data-copy-text attribute (JSON-encoded server string). */
export function parseCopyTextDataset(raw) {
  if (raw == null || raw === "") return null
  try {
    return JSON.parse(raw)
  } catch (_err) {
    return raw
  }
}
