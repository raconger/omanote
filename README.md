# Omanote

A fast, keyboard-only note launcher for [Omarchy](https://omarchyplugins.com),
in the spirit of [Notational Velocity](https://github.com/scrod/nv) / nvALT:
type to search a flat folder of notes, see the match live, and edit it right
there in the overlay. No exact match? Press Return and it's created.

This is a fresh QML/JS reimplementation of nv's UX for Omarchy's Quickshell
plugin system — none of nv's Objective-C source carries over, since Omarchy
plugins run as QML + JS inside its `omarchy-shell` (Quickshell) host, not as
native macOS apps.

## Features (v1)

- Live filter-as-you-type across note filenames and content
- Instant inline preview/edit of the top match — no separate "open" step
- Create-on-miss: type a title that doesn't exist, hit Return, start typing
- Flat-folder storage (`.md`, `.markdown`, `.txt`)
- Sortable list — most-recently-modified (default) or alphabetical by title
- Markdown list continuation: `Enter` on a bullet, task checkbox, or numbered
  item continues it; `Enter` on an empty one ends the list instead
- Sidebar (the results list) is collapsible, can sit on the left or the top,
  and its size is drag- or keyboard-adjustable
- Full-screen toggle (`Ctrl+F`) for a bigger canvas when you want it
- `Ctrl+/` shows a full keyboard-shortcut cheat sheet in place of the search
  view; press it (or Escape) again to return
- Keyboard nav (arrows, Page Up/Down, Home/End) and mouse both work

Not in v1 (nvALT has these; flagging as candidate follow-ups, not built):
tags, Markdown rendering/preview-in-browser, note locking/encryption,
external sync (Simplenote/Supernote).

## Using it

- Type to filter notes by title or content; the top match previews live.
- `↑`/`↓`/`PageUp`/`PageDown`/`Home`/`End` move the selection, mouse hover
  works too.
- `Enter` on the synthetic "Create …" row makes a new note; on a note row it
  hands focus to the note body so typing edits it.
- Just start typing in the note body — it autosaves (debounced). `Escape`
  returns focus to search.
  - `Enter` on a list line (`- `, `* `, `1. `, `- [ ] `/`- [x] `, or an
    indented variant) continues that list on the next line; press `Enter`
    again on an empty list item to end the list.
- `Escape` on an empty search closes Omanote; with text in the box, it
  clears the search first.
- The side not currently focused (the list while editing, the editor while
  browsing) dims slightly so it's clear where typing will land.
- `Ctrl+,` opens the "change notes folder" prompt.
- `Ctrl+B` collapses/expands the sidebar.
- `Ctrl+L` moves the sidebar between the left side and the top.
- `Ctrl+[` / `Ctrl+]` shrinks/grows the sidebar by keyboard; it's also
  drag-resizable from the divider between it and the editor.
- `Ctrl+.` cycles the sort order between most-recently-modified (default)
  and alphabetical by title.
- `Ctrl+F` toggles full-screen.
- `Ctrl+D` inserts today's date (`YYYY-MM-DD`) into the search/create field.
- `Ctrl+/` shows/hides the keyboard-shortcut cheat sheet.
- `Ctrl+B`/`Ctrl+L`/`Ctrl+[`/`Ctrl+]`/`Ctrl+.`/`Ctrl+F`/`Ctrl+/` all work
  whether the search field or the note body currently has focus.

## Install

Clone into your Omarchy plugins directory (or use `omarchy plugin add` once
this is pushed to a repo Omarchy can reach):

```bash
git clone <this-repo> ~/.config/omarchy/plugins/io.github.raconger.omanote
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.raconger.omanote
```

### Configure your notes folder

The first time you summon Omanote it asks where to keep your notes
(defaulting to `~/notes`) right there in the overlay, and remembers your
answer in `~/.local/state/omarchy/omanote.json`. Change it later with
`Ctrl+,` from the search view.

Two escape hatches for scripted setups, both optional:

- Set `OMANOTE_NOTES_DIR` in your session environment to change the default
  the first-run prompt offers.
- Pass an explicit folder per-summon, which always wins over the saved
  setting for that call:

  ```bash
  omarchy-shell shell summon io.github.raconger.omanote '{"notesDir": "~/Documents/notes"}'
  ```

### Bind a hotkey

Add a Hyprland bind that calls `toggle` (opens it, and closes it again on a
second press):

```
bind = SUPER, N, exec, omarchy-shell shell toggle io.github.raconger.omanote '{}'
```

## How it works

- `manifest.json` — plugin metadata, declares the `overlay` entry point
- `Omanote.qml` — the overlay: search field, results list, preview/edit pane
- `NoteStore.js` — pure, dependency-free logic (filename sanitizing, listing
  parsing, relative-time formatting, create-on-miss row building, sort
  ordering, markdown list continuation). Loads both as a QML JS module and
  as a plain Node module, so it's unit-testable without Quickshell.
- `list.sh` — lists (and filters) the notes folder; run as a subprocess so
  the QML side never touches the filesystem directly for search. Filename
  matching happens in pure bash (no fork per file); content matching,
  mtimes, and snippets are each one batched process across every candidate
  file instead of one process per file, so search stays fast even in a
  vault with thousands of notes.
- `~/.local/state/omarchy/omanote.json` — settings Omanote persists: your
  chosen notes folder, sidebar position/collapsed/size, sort order, and
  full-screen state. Written by the in-overlay settings prompt and by the
  layout/sort keybindings below.

## Testing

Pure logic has a Node test suite (no framework, no deps):

```bash
node NoteStore.test.js
```

The QML can only be checked on an actual Omarchy machine, since it depends
on the Quickshell/Quattro runtime:

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/io.github.raconger.omanote"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" "$PLUGIN_DIR/Omanote.qml"
```

After installing, smoke-test manually:

1. Summon it for the first time — it should prompt for a notes folder
2. Save that prompt, confirm the folder gets created and the list loads
3. Type a query that matches an existing note — content should appear in the
   right pane immediately, editable
4. Type a title that doesn't exist, press Return, type some content, then
   close and reopen — the note should be there
5. Create a note, type nothing, close it — no empty file should be left in
   the notes folder
6. Arrow through results, Escape to clear/close, mouse-click a row
7. `Ctrl+,` from the search view reopens the notes-folder prompt
