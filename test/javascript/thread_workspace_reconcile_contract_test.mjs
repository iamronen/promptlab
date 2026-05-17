/**
 * Contract tests for strip reconcile ordering (Node / CI).
 * MUST stay in sync with app/javascript/thread_workspace_reconcile.js
 */

function sanitizeOpenThreadIds(ids, allowed) {
  return ids.filter((id) => allowed.has(id))
}

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

function buildReconcileWantOrder(savedPanels, urlOpenIds, focusUrl, allowedSet) {
  let wantRaw = sanitizeOpenThreadIds(
    savedPanels.map((p) => p.id),
    allowedSet
  )
  let wantOrder = [...wantRaw]
  if (!wantOrder.length) return []

  if (focusUrl > 0 && !wantOrder.includes(focusUrl)) wantOrder.push(focusUrl)

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

function assertEq(actual, expected, label) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) throw new Error(`${label}: expected ${e}, got ${a}`)
}

const allowed = new Set([1, 2, 3, 99])

assertEq(
  buildReconcileWantOrder([{ id: 3 }, { id: 2 }, { id: 1 }], [1, 2, 3], 0, allowed),
  [1, 2, 3],
  "open_threads order wins over localStorage order"
)

assertEq(
  buildReconcileWantOrder([{ id: 99 }, { id: 1 }], [], 1, allowed),
  [99, 1],
  "cold URL: saved ids plus weave_thread focus"
)

assertEq(
  buildReconcileWantOrder([{ id: 1 }], [], 3, allowed),
  [1, 3],
  "weave_thread appended when missing from saved"
)

assertEq(
  buildReconcileWantOrder([{ id: 1 }], [1, 2, 3], 2, allowed),
  [1, 2, 3],
  "URL list preserved when complete"
)

console.log("thread_workspace_reconcile_contract_test.mjs: ok")
