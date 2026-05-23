/** @typedef {"index" | "split" | "editor"} ThreadPanelLayoutMode */

/** @typedef {{ id: number, layoutMode: ThreadPanelLayoutMode }} ThreadWorkspacePanel */

/** @typedef {{ version: number, panels: ThreadWorkspacePanel[], focusId?: number }} ThreadWorkspaceState */

export const THREAD_WORKSPACE_STORAGE_VERSION = 1

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
    const id = Number(r.id)
    if (!Number.isInteger(id) || id <= 0 || seen.has(id)) continue
    seen.add(id)
    panels.push({ id, layoutMode: parsePanelLayoutMode(r) })
  }

  /** @type {ThreadWorkspaceState} */
  const out = { version: THREAD_WORKSPACE_STORAGE_VERSION, panels }
  const fid = o.focusId
  if (typeof fid === "number" && Number.isInteger(fid) && fid > 0) out.focusId = fid

  return out
}

/** @returns {ThreadWorkspaceState | null} */
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
 * @param {number} projectId
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
 * @param {number[]} openIds authoritative order from URL/DOM
 * @param {{ id: number, layoutMode?: ThreadPanelLayoutMode, expanded?: boolean }[]} [fromSaved]
 */
export function mergePanelsFromStorage(openIds, fromSaved) {
  const savedList = Array.isArray(fromSaved) ? fromSaved : []
  /** @type {Map<number, ThreadPanelLayoutMode>} */
  const modes = new Map()
  for (const p of savedList) {
    if (!p || typeof p.id !== "number" || p.id <= 0) continue
    modes.set(p.id, parsePanelLayoutMode(p))
  }
  /** @type {ThreadWorkspacePanel[]} */
  const panels = []
  for (const id of openIds) {
    if (!Number.isInteger(id) || id <= 0) continue
    panels.push({ id, layoutMode: modes.has(id) ? modes.get(id) : "split" })
  }
  return panels
}

/**
 * Validates open thread ids belong to allowed set (from server).
 * @param {number[]} ids
 * @param {Set<number>} allowed
 * @returns {number[]}
 */
export function sanitizeOpenThreadIds(ids, allowed) {
  return ids.filter((id) => allowed.has(id))
}
