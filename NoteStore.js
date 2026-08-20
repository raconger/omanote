// Pure logic for Omanote: parsing list.sh output, filenames, and note
// display. Kept dependency-free so it loads both as a QML JS import and as
// a plain Node module for tests.

var NOTE_EXTENSIONS = [".md", ".markdown", ".txt"]
var DEFAULT_EXTENSION = ".md"
var MAX_TITLE_LENGTH = 120

function expandHome(path, home) {
  var value = String(path || "").trim()
  var homeDir = String(home || "")
  if (!value) return value
  if (value === "~") return homeDir
  if (value.indexOf("~/") === 0) return homeDir + value.slice(1)
  return value
}

function stripExtension(fileName) {
  var name = String(fileName || "")
  for (var i = 0; i < NOTE_EXTENSIONS.length; i++) {
    var ext = NOTE_EXTENSIONS[i]
    if (name.length > ext.length && name.slice(-ext.length).toLowerCase() === ext) {
      return name.slice(0, name.length - ext.length)
    }
  }
  return name
}

function titleForFile(fileName) {
  return stripExtension(fileName)
}

// Turns free-typed query text into a safe, flat filename. Strips control
// characters and path separators so a query can never escape the notes
// directory or create a hidden/dotfile note by accident.
function sanitizeFileName(query, extension) {
  var ext = extension || DEFAULT_EXTENSION
  var controlChars = new RegExp("[\\x00-\\x1f\\x7f]", "g")

  var value = String(query || "")
    .replace(controlChars, "")
    .replace(/[\/\\]/g, "-")
    .trim()
    .replace(/\s+/g, " ")
    .replace(/^\.+/, "")

  if (value.length > MAX_TITLE_LENGTH) value = value.slice(0, MAX_TITLE_LENGTH).trim()
  if (!value) value = "Untitled"

  return value + ext
}

// list.sh emits tab-separated rows: mtimeEpochSeconds \t fileName \t snippet
function parseListing(raw) {
  var lines = String(raw || "").split("\n")
  var out = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue

    var columns = line.split("\t")
    var fileName = columns[1]
    if (!fileName) continue

    var mtimeSeconds = parseInt(columns[0], 10)
    out.push({
      fileName: fileName,
      title: titleForFile(fileName),
      snippet: columns[2] || "",
      mtimeMs: isNaN(mtimeSeconds) ? 0 : mtimeSeconds * 1000
    })
  }

  return out
}

function formatRelativeTime(mtimeMs, nowMs) {
  var now = nowMs === undefined ? Date.now() : nowMs
  var deltaSeconds = Math.max(0, Math.floor((now - mtimeMs) / 1000))

  if (deltaSeconds < 45) return "just now"
  if (deltaSeconds < 90) return "1m ago"
  var minutes = Math.floor(deltaSeconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d ago"
  var weeks = Math.floor(days / 7)
  if (weeks < 5) return weeks + "w ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  var years = Math.floor(days / 365)
  return years + "y ago"
}

// True when no existing note's filename is an exact (case-insensitive)
// match for the sanitized query — i.e. "create new" should be offered
// instead of just opening the top search hit.
function isExactMatch(notes, fileName) {
  var needle = String(fileName || "").toLowerCase()
  var values = Array.isArray(notes) ? notes : []
  for (var i = 0; i < values.length; i++) {
    if (String(values[i].fileName || "").toLowerCase() === needle) return true
  }
  return false
}

function joinPath(dir, fileName) {
  var base = String(dir || "").replace(/\/+$/, "")
  return base + "/" + String(fileName || "")
}

var SORT_MODES = ["modified", "title"]

function sortNotes(notes, mode) {
  var values = Array.isArray(notes) ? notes.slice() : []
  if (mode === "title") {
    values.sort(function(a, b) {
      return String(a.title || "").localeCompare(String(b.title || ""), undefined, { sensitivity: "base" })
    })
  } else {
    // "modified" (default): most recently modified first. list.sh already
    // emits rows in this order, but sorting here too keeps behavior correct
    // if that ever changes, and makes the ordering independently testable.
    values.sort(function(a, b) { return b.mtimeMs - a.mtimeMs })
  }
  return values
}

// Two-digit zero-padding without relying on Number.prototype.padStart, so
// this keeps working under whatever JS engine QtQml embeds.
function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function isoDateString(date) {
  var d = date || new Date()
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// Enter-to-continue-list behavior for the note editor: given the full text
// and the cursor offset where Return was pressed, decides whether the
// current line is a markdown bullet/task/numbered item and, if so, how to
// edit the text to continue (or, on an empty item, end) the list. Returns
// null when the current line isn't a list item at all, so the caller can
// fall through to inserting a plain newline.
function listContinuation(text, pos) {
  var s = String(text || "")
  var cursor = Math.max(0, Math.min(pos || 0, s.length))
  var lineStart = s.lastIndexOf("\n", cursor - 1) + 1
  var line = s.slice(lineStart, cursor)

  var bulletMatch = line.match(/^(\s*)([-*+])((?:\s+\[[ xX]\])?)\s+(.*)$/)
  if (bulletMatch) {
    var indent = bulletMatch[1], marker = bulletMatch[2], checkbox = bulletMatch[3], rest = bulletMatch[4]
    if (rest.trim() === "") {
      return { removeStart: lineStart, removeEnd: cursor, insertText: "", cursorAt: lineStart }
    }
    var checkboxOut = checkbox ? " [ ]" : ""
    var insertion = "\n" + indent + marker + checkboxOut + " "
    return { removeStart: cursor, removeEnd: cursor, insertText: insertion, cursorAt: cursor + insertion.length }
  }

  var numberedMatch = line.match(/^(\s*)(\d+)([.)])\s+(.*)$/)
  if (numberedMatch) {
    var numIndent = numberedMatch[1], num = parseInt(numberedMatch[2], 10), sep = numberedMatch[3], numRest = numberedMatch[4]
    if (numRest.trim() === "") {
      return { removeStart: lineStart, removeEnd: cursor, insertText: "", cursorAt: lineStart }
    }
    var numInsertion = "\n" + numIndent + (num + 1) + sep + " "
    return { removeStart: cursor, removeEnd: cursor, insertText: numInsertion, cursorAt: cursor + numInsertion.length }
  }

  return null
}

// Builds the rows for the results list: every matching note, plus (when the
// query doesn't exactly match an existing note) a trailing synthetic
// "create" row. This is the one function the QML view drives directly, so
// the exact-match/create-on-miss policy lives in one tested place.
function buildRows(notes, query) {
  var values = Array.isArray(notes) ? notes : []
  var rows = values.map(function(note) {
    return {
      rowType: "note",
      fileName: note.fileName,
      title: note.title,
      snippet: note.snippet,
      mtimeMs: note.mtimeMs
    }
  })

  var trimmedQuery = String(query || "").trim()
  if (trimmedQuery) {
    var candidateFileName = sanitizeFileName(trimmedQuery)
    if (!isExactMatch(values, candidateFileName)) {
      rows.push({
        rowType: "create",
        fileName: candidateFileName,
        title: "Create “" + trimmedQuery + "”",
        snippet: "",
        mtimeMs: 0
      })
    }
  }

  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    NOTE_EXTENSIONS: NOTE_EXTENSIONS,
    DEFAULT_EXTENSION: DEFAULT_EXTENSION,
    SORT_MODES: SORT_MODES,
    expandHome: expandHome,
    stripExtension: stripExtension,
    titleForFile: titleForFile,
    sanitizeFileName: sanitizeFileName,
    parseListing: parseListing,
    formatRelativeTime: formatRelativeTime,
    isExactMatch: isExactMatch,
    joinPath: joinPath,
    sortNotes: sortNotes,
    isoDateString: isoDateString,
    listContinuation: listContinuation,
    buildRows: buildRows
  }
}
