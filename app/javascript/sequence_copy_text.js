/** Plain text from HTML (rich step content, etc.). */
export function htmlToPlainText(html) {
  const fragment = document.createElement("div")
  fragment.innerHTML = html == null ? "" : String(html)
  return fragment.innerText.replace(/\n{3,}/g, "\n\n")
}

export const SEQUENCE_DEFAULT_TITLE = "Untitled sequence"
export const SEQUENCE_DEFAULT_INTENT = "Define one clear sentence for the sequence intent."

function plainCopyField(value) {
  return htmlToPlainText(value).trim()
}

function isDefaultOrBlank(value, defaultValue) {
  const plain = plainCopyField(value)
  return !plain || plain === defaultValue
}

/** True when title, intent, and steps are all empty or still at defaults. */
export function isSequenceEmptyForCopy({
  title,
  intent,
  steps,
  defaultTitle = SEQUENCE_DEFAULT_TITLE,
  defaultIntent = SEQUENCE_DEFAULT_INTENT
}) {
  const hasSteps = steps.some((content) => plainCopyField(content))
  return (
    isDefaultOrBlank(title, defaultTitle) &&
    isDefaultOrBlank(intent, defaultIntent) &&
    !hasSteps
  )
}

/** Build clipboard text: title, intent, numbered steps. */
export function buildSequenceCopyText({
  title,
  intent,
  steps,
  defaultTitle = SEQUENCE_DEFAULT_TITLE,
  defaultIntent = SEQUENCE_DEFAULT_INTENT
}) {
  const lines = []
  const titlePlain = plainCopyField(title)
  const intentPlain = plainCopyField(intent)

  if (titlePlain && titlePlain !== defaultTitle) {
    lines.push(titlePlain, "")
  }
  if (intentPlain && intentPlain !== defaultIntent) {
    lines.push(intentPlain, "")
  }
  steps.forEach((content, i) => {
    const plain = plainCopyField(content)
    if (plain) lines.push(`${i + 1}. ${plain}`)
  })
  return `${lines.join("\n").trim()}\n`
}

const SEQUENCE_STEP_ROW_SELECTOR = '[data-editor-kind="sequence_step"]'

function readStepsFromRoot(root) {
  const steps = []
  root.querySelectorAll(SEQUENCE_STEP_ROW_SELECTOR).forEach((card) => {
    const destroyed =
      card.querySelector('[data-sequence-editor-target="destroyInput"]')?.value === "true"
    if (destroyed) return

    const contentInput = card.querySelector('[data-sequence-editor-target="contentInput"]')
    const editor = card.querySelector('[data-sequence-editor-target="editor"]')
    steps.push(contentInput?.value ?? editor?.innerHTML ?? "")
  })
  return steps
}

function sequenceEditorDefaultsFromRoot(root) {
  const editorRoot = root?.closest("[data-controller~='sequence-editor']") ?? root
  return {
    defaultTitle:
      editorRoot?.getAttribute("data-sequence-editor-default-title-value") ||
      SEQUENCE_DEFAULT_TITLE,
    defaultIntent:
      editorRoot?.getAttribute("data-sequence-editor-default-intent-value") ||
      SEQUENCE_DEFAULT_INTENT
  }
}

/** Read live sequence editor form state (title, intent, steps). */
export function buildSequenceCopyTextFromEditorRoot(root) {
  if (!root) return null

  const title =
    root.querySelector('[data-sequence-editor-target="titleInput"]')?.value ?? ""
  const intent =
    root.querySelector('[data-sequence-editor-target="intentInput"]')?.value ?? ""
  const steps = readStepsFromRoot(root)
  const { defaultTitle, defaultIntent } = sequenceEditorDefaultsFromRoot(root)

  return buildSequenceCopyText({ title, intent, steps, defaultTitle, defaultIntent })
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

/** Read title, intent, and steps from a bundle pipeline child row. */
export function buildBundlePipelineChildCopyTextFromPipelineRow(row) {
  if (!row) return null

  const title = row.querySelector(".bundle-pipeline-child-title-input")?.value ?? ""
  const intent = row.querySelector(".bundle-pipeline-child-intent-input")?.value ?? ""
  const steps = readStepsFromRoot(row)

  if (isSequenceEmptyForCopy({ title, intent, steps })) return null

  return buildSequenceCopyText({ title, intent, steps })
}

/** Read bundle title and each pipeline child from a bundle editor root. */
export function buildBundleCopyTextFromEditorRoot(mainEl) {
  if (!mainEl) return null

  const title =
    mainEl.querySelector(".bundle-pipeline-bundle-title-input")?.value ??
    mainEl.querySelector('[data-sequence-editor-target="titleInput"]')?.value ??
    ""

  const parts = [htmlToPlainText(title).trim()]
  mainEl.querySelectorAll('[data-editor-kind="bundle_pipeline_slot"]').forEach((row) => {
    const destroyed =
      row.querySelector('[data-sequence-editor-target="destroyInput"]')?.value === "true"
    if (destroyed) return

    const childText = buildBundlePipelineChildCopyTextFromPipelineRow(row)
    if (!childText?.trim()) return

    parts.push("")
    parts.push(childText.trim())
  })

  return `${parts.join("\n").trim()}\n`
}
