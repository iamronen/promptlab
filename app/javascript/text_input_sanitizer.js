const TRAILING_WHITESPACE_RE = /[\s\u00a0]+$/

export function trimTrailingWhitespace(value) {
  if (value == null) return ""
  return String(value).replace(TRAILING_WHITESPACE_RE, "")
}

export function trimTrailingWhitespaceInPlace(input) {
  if (!input || typeof input.value !== "string") return ""
  const trimmed = trimTrailingWhitespace(input.value)
  if (input.value !== trimmed) input.value = trimmed
  return trimmed
}
