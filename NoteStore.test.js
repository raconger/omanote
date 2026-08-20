// Plain-Node test suite for NoteStore.js's pure functions. No framework
// dependency (matches the plugin's own "no deps" constraint) — run with
// `node NoteStore.test.js`.
var assert = require("assert")
var NoteStore = require("./NoteStore.js")

var failures = 0

function test(name, fn) {
  try {
    fn()
    console.log("ok - " + name)
  } catch (e) {
    failures++
    console.log("FAIL - " + name)
    console.log("  " + e.message)
  }
}

test("expandHome expands a bare tilde", function() {
  assert.strictEqual(NoteStore.expandHome("~", "/home/ryan"), "/home/ryan")
})

test("expandHome expands a tilde-prefixed path", function() {
  assert.strictEqual(NoteStore.expandHome("~/notes", "/home/ryan"), "/home/ryan/notes")
})

test("expandHome leaves absolute paths untouched", function() {
  assert.strictEqual(NoteStore.expandHome("/data/notes", "/home/ryan"), "/data/notes")
})

test("titleForFile strips a known extension", function() {
  assert.strictEqual(NoteStore.titleForFile("todo list.md"), "todo list")
  assert.strictEqual(NoteStore.titleForFile("todo.markdown"), "todo")
  assert.strictEqual(NoteStore.titleForFile("todo.txt"), "todo")
})

test("titleForFile leaves unknown extensions alone", function() {
  assert.strictEqual(NoteStore.titleForFile("todo.pdf"), "todo.pdf")
})

test("sanitizeFileName appends the default extension", function() {
  assert.strictEqual(NoteStore.sanitizeFileName("Grocery list"), "Grocery list.md")
})

test("sanitizeFileName strips path separators so it can't escape the notes dir", function() {
  assert.strictEqual(NoteStore.sanitizeFileName("../../etc/passwd"), "-..-etc-passwd.md")
  assert.strictEqual(NoteStore.sanitizeFileName("a/b\\c"), "a-b-c.md")
})

test("sanitizeFileName strips control characters and leading dots", function() {
  assert.strictEqual(NoteStore.sanitizeFileName("..hidden"), "hidden.md")
})

test("sanitizeFileName collapses whitespace and trims", function() {
  assert.strictEqual(NoteStore.sanitizeFileName("  a   b  "), "a b.md")
})

test("sanitizeFileName falls back to Untitled for an empty query", function() {
  assert.strictEqual(NoteStore.sanitizeFileName(""), "Untitled.md")
  assert.strictEqual(NoteStore.sanitizeFileName("   "), "Untitled.md")
})

test("sanitizeFileName truncates very long queries", function() {
  var longQuery = new Array(200).join("x")
  var result = NoteStore.sanitizeFileName(longQuery)
  assert.ok(result.length <= 120 + ".md".length)
})

test("parseListing turns tab-separated rows into note objects", function() {
  var raw = "1700000000\tidea.md\tFirst line\n1690000000\ttodo.txt\tBuy milk\n"
  var notes = NoteStore.parseListing(raw)
  assert.strictEqual(notes.length, 2)
  assert.strictEqual(notes[0].fileName, "idea.md")
  assert.strictEqual(notes[0].title, "idea")
  assert.strictEqual(notes[0].snippet, "First line")
  assert.strictEqual(notes[0].mtimeMs, 1700000000000)
})

test("parseListing skips blank lines and rows missing a filename", function() {
  var raw = "\n1700000000\t\tsnippet\n\t\t\n"
  var notes = NoteStore.parseListing(raw)
  assert.strictEqual(notes.length, 0)
})

test("formatRelativeTime buckets deltas the way nv does", function() {
  var now = 1700000000000
  assert.strictEqual(NoteStore.formatRelativeTime(now - 10 * 1000, now), "just now")
  assert.strictEqual(NoteStore.formatRelativeTime(now - 90 * 1000, now), "1m ago")
  assert.strictEqual(NoteStore.formatRelativeTime(now - 5 * 60 * 1000, now), "5m ago")
  assert.strictEqual(NoteStore.formatRelativeTime(now - 3 * 60 * 60 * 1000, now), "3h ago")
  assert.strictEqual(NoteStore.formatRelativeTime(now - 2 * 24 * 60 * 60 * 1000, now), "2d ago")
  assert.strictEqual(NoteStore.formatRelativeTime(now - 400 * 24 * 60 * 60 * 1000, now), "1y ago")
})

test("isExactMatch is case-insensitive", function() {
  var notes = [{ fileName: "Todo.md" }]
  assert.strictEqual(NoteStore.isExactMatch(notes, "todo.md"), true)
  assert.strictEqual(NoteStore.isExactMatch(notes, "todo-list.md"), false)
})

test("joinPath joins without doubling slashes", function() {
  assert.strictEqual(NoteStore.joinPath("/home/ryan/notes", "todo.md"), "/home/ryan/notes/todo.md")
  assert.strictEqual(NoteStore.joinPath("/home/ryan/notes/", "todo.md"), "/home/ryan/notes/todo.md")
})

test("buildRows appends a create row when the query has no exact match", function() {
  var notes = [{ fileName: "todo.md", title: "todo", snippet: "", mtimeMs: 0 }]
  var rows = NoteStore.buildRows(notes, "todo list")
  assert.strictEqual(rows.length, 2)
  assert.strictEqual(rows[0].rowType, "note")
  assert.strictEqual(rows[1].rowType, "create")
  assert.strictEqual(rows[1].fileName, "todo list.md")
})

test("buildRows omits the create row on an exact match", function() {
  var notes = [{ fileName: "todo.md", title: "todo", snippet: "", mtimeMs: 0 }]
  var rows = NoteStore.buildRows(notes, "todo")
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].rowType, "note")
})

test("buildRows omits the create row when the query is empty", function() {
  var rows = NoteStore.buildRows([], "")
  assert.strictEqual(rows.length, 0)
})

if (failures > 0) {
  console.log("\n" + failures + " test(s) failed")
  process.exit(1)
} else {
  console.log("\nall tests passed")
}
