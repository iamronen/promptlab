/** @typedef {{ id: number, expanded: boolean }} ThreadWorkspacePanel */

/** @typedef {{ version: number, panels: ThreadWorkspacePanel[], focusId?: number }} ThreadWorkspaceState */

export const THREAD_WORKSPACE_STORAGE_VERSION = 1

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
    const id = Number(/** @type {Record<string, unknown>} */ (row).id)
    if (!Number.isInteger(id) || id <= 0 || seen.has(id)) continue
    seen.add(id)
    let expanded = true
    const ex = /** @type {Record<string, unknown>} */ (row).expanded
    if (typeof ex === "boolean") expanded = ex
    panels.push({ id, expanded })
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
 * @param {{ id: number, expanded?: boolean }[]} [fromSaved]
 */
export function mergePanelsFromStorage(openIds, fromSaved) {
  const savedList = Array.isArray(fromSaved) ? fromSaved : []
  /** @type {Map<number, boolean>} */
  const exp = new Map()
  for (const p of savedList) {
    if (!p || typeof p.id !== "number" || p.id <= 0) continue
    exp.set(p.id, typeof p.expanded === "boolean" ? p.expanded : true)
  }
  /** @type {ThreadWorkspacePanel[]} */
  const panels = []
  for (const id of openIds) {
    if (!Number.isInteger(id) || id <= 0) continue
    panels.push({ id, expanded: exp.has(id) ? exp.get(id) : true })
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
