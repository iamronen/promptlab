import { sanitizeOpenThreadIds, normalizeThreadPublicId } from "thread_workspace_storage"

/** Node contract mirror: test/javascript/thread_workspace_reconcile_contract_test.mjs */

function uniqOrder(ids) {
  const out = []
  const seen = new Set()
  for (const id of ids) {
    if (seen.has(id)) continue
    seen.add(id)
    out.push(id)
  }
  return out
}

/**
 * Build the canonical strip open order during reconcile.
 * When `open_threads` is present in the URL, its order wins (matches SSR strip order); localStorage
 * only adds ids missing from the URL (cold sessions). `focusUrl` (`weave_thread`) is always included.
 *
 * @param {{ id: string }[]} savedPanels from localStorage
 * @param {string[]} urlOpenIds from `?open_threads=`
 * @param {string | null} focusUrl from `?weave_thread=`
 * @param {Set<string>} allowedSet
 * @returns {string[]}
 */
export function buildReconcileWantOrder(savedPanels, urlOpenIds, focusUrl, allowedSet) {
  let wantRaw = sanitizeOpenThreadIds(
    savedPanels.map((p) => p.id),
    allowedSet
  )
  let wantOrder = [...wantRaw]
  if (!wantOrder.length) return []

  if (focusUrl && !wantOrder.includes(focusUrl)) wantOrder.push(focusUrl)

  wantOrder = sanitizeOpenThreadIds(wantOrder, allowedSet)
  wantOrder = uniqOrder(wantOrder)

  if (urlOpenIds.length) {
    wantOrder = uniqOrder([
      ...urlOpenIds,
      ...wantOrder.filter((id) => !urlOpenIds.includes(id))
    ])
    wantOrder = sanitizeOpenThreadIds(wantOrder, allowedSet)
  }

  return wantOrder
}
