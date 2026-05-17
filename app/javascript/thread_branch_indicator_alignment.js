const alignmentObservers = new WeakMap()

function applyWorkspaceStrandBridgeAlignment(row) {
  const band = row.querySelector(".thread-branch-strand-bridge-band--strand-row")
  const handle = row.querySelector(".thread-strand-child__handle")
  const stepRail = row.querySelector(".workspace-thread-editor-step-rail")
  if (!band || !handle || !stepRail) return false

  const handleWidth = handle.getBoundingClientRect().width
  const stepRailWidth = stepRail.getBoundingClientRect().width
  if (handleWidth <= 0 || stepRailWidth <= 0) return false

  band.style.setProperty("--thread-branch-handle-gutter", `${handleWidth}px`)
  band.style.setProperty("--thread-branch-timeline-col", `${stepRailWidth}px`)
  return true
}

function applyAllWorkspaceStrandBridgeAlignments(root) {
  root
    .querySelectorAll(".workspace-thread-editor-child--has-thread-branch-band")
    .forEach((row) => applyWorkspaceStrandBridgeAlignment(row))
}

/** Match bridge-band grid columns to the strand row handle + step-rail above. */
export function syncThreadBranchStrandBridgeAlignment(root) {
  const scope = root ?? document
  const run = () => applyAllWorkspaceStrandBridgeAlignments(scope)

  run()
  requestAnimationFrame(() => requestAnimationFrame(run))

  let observer = alignmentObservers.get(scope)
  if (!observer) {
    observer = new ResizeObserver(run)
    observer.observe(scope)
    alignmentObservers.set(scope, observer)
  }
}

export function disconnectThreadBranchStrandBridgeAlignment(root) {
  const observer = alignmentObservers.get(root)
  if (!observer) return
  observer.disconnect()
  alignmentObservers.delete(root)
}
