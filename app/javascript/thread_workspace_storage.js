/** @typedef {"index" | "split" | "editor"} ThreadPanelLayoutMode */

/** @typedef {{ id: string, layoutMode: ThreadPanelLayoutMode }} ThreadWorkspacePanel */

/** @typedef {{ version: number, panels: ThreadWorkspacePanel[], focusId?: string }} ThreadWorkspaceState */

export const THREAD_WORKSPACE_STORAGE_VERSION = 2

export const VALID_LAYOUT_MODES = /** @type {const} */ (["index", "split", "editor"])

/**
 * @param {unknown} value
 * @returns {value is ThreadPanelLayoutMode}
 */
export function isValidLayoutMode(value) {
  return typeof value === "string" && VALID_LAYOUT_MODES.includes(/** @type {ThreadPanelLayoutMode} */ (value))
}

/**
 * @param {string | null | undefined} raw
 * @returns {ThreadPanelLayoutMode | null}
 */
export function parseStandaloneLayoutMode(raw) {
  if (raw === "true") return "split"
  if (raw === "false") return "index"
  if (isValidLayoutMode(raw)) return raw
  return null
}

/**
 * @param {{ layoutMode?: unknown, expanded?: unknown }} row
 * @returns {ThreadPanelLayoutMode}
 */
export function parsePanelLayoutMode(row) {
  const lm = row?.layoutMode
  if (isValidLayoutMode(lm)) return lm
  const ex = row?.expanded
  if (typeof ex === "boolean") return ex ? "split" : "index"
  return "split"
}

export function threadWorkspaceStorageKey(projectId) {
  return `promptlab.threadWorkspace.v${THREAD_WORKSPACE_STORAGE_VERSION}:project:${projectId}`
}

/**
 * @param {unknown} raw
 * @returns {string | null}
 */
export function normalizeThreadPublicId(raw) {
  const s = String(raw ?? "").trim()
  return s.length > 0 ? s : null
}

/**
 * @param {unknown} data
 * @returns {ThreadWorkspaceState | null}
 */
export function parseThreadWorkspaceState(data) {
  if (!data || typeof data !== "object") return null
  const o = /** @type {Record<string, unknown>} */ (data)
  if (o.version !== THREAD_WORKSPACE_STORAGE_VERSION) return null
  const panelsRaw = o.panels
  if (!Array.isArray(panelsRaw)) return null

  const panels = []
  const seen = new Set()
  for (const row of panelsRaw) {
    if (!row || typeof row !== "object") continue
    const r = /** @type {Record<string, unknown>} */ (row)
    const id = normalizeThreadPublicId(r.id)
    if (!id || seen.has(id)) continue
    seen.add(id)
    panels.push({ id, layoutMode: parsePanelLayoutMode(r) })
  }

  /** @type {ThreadWorkspaceState} */
  const out = { version: THREAD_WORKSPACE_STORAGE_VERSION, panels }
  const fid = normalizeThreadPublicId(o.focusId)
  if (fid) out.focusId = fid

  return out
}

/**
 * @param {string} projectId
 * @returns {ThreadWorkspaceState | null}
 */
export function loadThreadWorkspaceState(projectId) {
  try {
    const raw = window.localStorage.getItem(threadWorkspaceStorageKey(projectId))
    if (!raw) return null
    return parseThreadWorkspaceState(JSON.parse(raw))
  } catch {
    return null
  }
}

/**
 * @param {string} projectId
 * @param {ThreadWorkspaceState} state
 */
export function saveThreadWorkspaceState(projectId, state) {
  try {
    window.localStorage.setItem(threadWorkspaceStorageKey(projectId), JSON.stringify(state))
  } catch {
    /* ignore quota / privacy mode */
  }
}

/**
 * @param {string[]} openIds authoritative order from URL/DOM
 * @param {{ id: string, layoutMode?: ThreadPanelLayoutMode, expanded?: boolean }[]} [fromSaved]
 */
export function mergePanelsFromStorage(openIds, fromSaved) {
  const savedList = Array.isArray(fromSaved) ? fromSaved : []
  /** @type {Map<string, ThreadPanelLayoutMode>} */
  const modes = new Map()
  for (const p of savedList) {
    const id = normalizeThreadPublicId(p?.id)
    if (!id) continue
    modes.set(id, parsePanelLayoutMode(p))
  }
  /** @type {ThreadWorkspacePanel[]} */
  const panels = []
  for (const rawId of openIds) {
    const id = normalizeThreadPublicId(rawId)
    if (!id) continue
    panels.push({ id, layoutMode: modes.has(id) ? modes.get(id) : "split" })
  }
  return panels
}

/**
 * Validates open thread public ids belong to allowed set (from server).
 * @param {string[]} ids
 * @param {Set<string>} allowed
 * @returns {string[]}
 */
export function sanitizeOpenThreadIds(ids, allowed) {
  return ids.filter((id) => allowed.has(id))
}
