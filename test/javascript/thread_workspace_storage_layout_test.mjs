/**
 * Contract tests for thread workspace panel layoutMode parsing (Node / CI).
 * MUST stay in sync with app/javascript/thread_workspace_storage.js
 */

import {
  parsePanelLayoutMode,
  parseStandaloneLayoutMode,
  parseThreadWorkspaceState,
  mergePanelsFromStorage
} from "../../app/javascript/thread_workspace_storage.js"

function assertEq(actual, expected, label) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) throw new Error(`${label}: expected ${e}, got ${a}`)
}

assertEq(parseStandaloneLayoutMode("true"), "split", "legacy true → split")
assertEq(parseStandaloneLayoutMode("false"), "index", "legacy false → index")
assertEq(parseStandaloneLayoutMode("editor"), "editor", "editor enum")
assertEq(parseStandaloneLayoutMode(null), null, "null → null")

assertEq(parsePanelLayoutMode({ expanded: true }), "split", "panel expanded true → split")
assertEq(parsePanelLayoutMode({ expanded: false }), "index", "panel expanded false → index")
assertEq(parsePanelLayoutMode({ layoutMode: "editor" }), "editor", "layoutMode wins")
assertEq(parsePanelLayoutMode({ layoutMode: "editor", expanded: false }), "editor", "layoutMode over expanded")

const parsed = parseThreadWorkspaceState({
  version: 1,
  panels: [{ id: 1, expanded: false }, { id: 2, layoutMode: "editor" }]
})
assertEq(parsed?.panels, [{ id: 1, layoutMode: "index" }, { id: 2, layoutMode: "editor" }], "parseThreadWorkspaceState migration")

assertEq(
  mergePanelsFromStorage([3, 1], [{ id: 1, expanded: false }, { id: 3, layoutMode: "editor" }]),
  [{ id: 3, layoutMode: "editor" }, { id: 1, layoutMode: "index" }],
  "mergePanelsFromStorage preserves layoutMode"
)

console.log("thread_workspace_storage_layout_test.mjs: ok")
