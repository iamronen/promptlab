const STORAGE_KEY = "promptlab.sequenceEditorReadonly"

export function getSequenceEditorReadonlyPreference() {
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY)
    if (stored === "true") return true
    if (stored === "false") return false
    return null
  } catch (_e) {
    return null
  }
}

export function setSequenceEditorReadonlyPreference(readonly) {
  try {
    window.localStorage.setItem(STORAGE_KEY, readonly ? "true" : "false")
  } catch (_e) {
    /* ignore quota / private mode */
  }
}
