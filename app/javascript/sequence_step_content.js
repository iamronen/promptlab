const TRAILING_WHITESPACE_RE = /[\s\u00a0]+$/

function isTrailingWhitespaceNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    return node.textContent.replace(/[\s\u00a0]/g, "") === ""
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return false

  const tag = node.tagName
  if (tag === "BR") return true
  if (tag === "P" || tag === "DIV") {
    return node.textContent.replace(/[\s\u00a0]/g, "") === ""
  }

  return false
}

function trimTrailingWhitespaceInNode(node) {
  if (node.nodeType === Node.TEXT_NODE) {
    node.textContent = node.textContent.replace(TRAILING_WHITESPACE_RE, "")
    return
  }
  if (node.nodeType !== Node.ELEMENT_NODE) return

  while (node.lastChild && isTrailingWhitespaceNode(node.lastChild)) {
    node.removeChild(node.lastChild)
  }

  if (node.lastChild) {
    trimTrailingWhitespaceInNode(node.lastChild)
  }
}

/** Remove trailing spaces, newlines, and empty block markup from step editor HTML. */
export function trimStepEditorHtml(html) {
  const outer = html.trim()
  if (!outer) return ""

  const root = document.createElement("div")
  root.innerHTML = outer

  while (root.lastChild && isTrailingWhitespaceNode(root.lastChild)) {
    root.removeChild(root.lastChild)
  }

  if (root.lastChild) {
    trimTrailingWhitespaceInNode(root.lastChild)
  }

  const result = root.innerHTML
  return result.trim() === "" ? "" : result
}
