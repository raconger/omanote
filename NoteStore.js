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
    expandHome: expandHome,
    stripExtension: stripExtension,
    titleForFile: titleForFile,
    sanitizeFileName: sanitizeFileName,
    parseListing: parseListing,
    formatRelativeTime: formatRelativeTime,
    isExactMatch: isExactMatch,
    joinPath: joinPath,
    buildRows: buildRows
  }
}
