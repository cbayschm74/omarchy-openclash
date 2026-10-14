// Bounded single-line editing; no native text input or clipboard access.
function insert(text, cursor, anchor, value, limit) {
  value = String(value || "")
  if (/[\x00-\x1f\x7f]/.test(value)) return null
  var start = Math.min(cursor, anchor), end = Math.max(cursor, anchor)
  if (text.length - (end - start) + value.length > limit) return null
  return { text: text.slice(0, start) + value + text.slice(end),
           cursor: start + value.length, anchor: start + value.length }
}
function remove(text, cursor, anchor, backwards) {
  if (cursor === anchor) {
    if (backwards && cursor > 0) anchor = previous(text, cursor)
    else if (!backwards && cursor < text.length) anchor = next(text, cursor)
  }
  return insert(text, cursor, anchor, "", text.length)
}
function previous(text, index) {
  if (index > 1 && text.charCodeAt(index - 1) >= 0xdc00 && text.charCodeAt(index - 1) <= 0xdfff &&
      text.charCodeAt(index - 2) >= 0xd800 && text.charCodeAt(index - 2) <= 0xdbff) return index - 2
  return Math.max(0, index - 1)
}
function next(text, index) {
  if (index + 1 < text.length && text.charCodeAt(index) >= 0xd800 && text.charCodeAt(index) <= 0xdbff &&
      text.charCodeAt(index + 1) >= 0xdc00 && text.charCodeAt(index + 1) <= 0xdfff) return index + 2
  return Math.min(text.length, index + 1)
}
if (typeof module !== "undefined") module.exports = { insert: insert, remove: remove, previous: previous, next: next }
