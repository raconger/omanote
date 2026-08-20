import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "NoteStore.js" as NoteStore

// Omanote: a Notational-Velocity-style note launcher. Search, live preview,
// and inline editing of a flat folder of plain-text notes, with create-on-miss
// (type a title that doesn't exist yet, press Return, start typing the note).
Item {
  id: root

  property string homeDir: Quickshell.env("HOME")
  // Notes folder, resolved once settings load: a per-summon override via
  // open('{"notesDir": "..."}') wins outright; otherwise the folder chosen
  // in Omanote's own settings prompt (persisted below) is used; the
  // OMANOTE_NOTES_DIR env var is only a fallback default for the first-run
  // prompt or for scripted/dotfiles setups that never touch the UI.
  property string notesDir: ""
  readonly property string expandedNotesDir: NoteStore.expandHome(root.notesDir, root.homeDir)
  readonly property string scriptPath: Qt.resolvedUrl("list.sh").toString().replace("file://", "")

  property string settingsPath: root.homeDir + "/.local/state/omarchy/omanote.json"
  property bool settingsLoaded: false
  property bool editingSettings: false
  property string settingsInput: ""
  // Set whenever the resolved notes folder can't be created/accessed, so the
  // UI can say so instead of silently looking like an empty folder.
  property string dirError: ""

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  // Set while creating a brand-new note, so the editor targets a path that
  // doesn't exist in displayModel (and hasn't been written to disk) yet.
  property string manualOverridePath: ""
  property bool suppressSave: false
  property string loadedNotePath: ""
  // False until the current loadedNotePath is confirmed to exist on disk —
  // lets doSave() skip writing an empty file for a new note nobody typed
  // anything into.
  property bool noteFileExists: false

  // Shares the [menu] surface tokens — themes that style the menu also
  // style Omanote.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property string monoFontFamily: Style.font.monoFamily || Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  readonly property var selectedRow: (root.cursorActive && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count)
    ? displayModel.get(root.selectedIndex) : null
  readonly property bool hasActiveNote: root.manualOverridePath !== "" || (root.selectedRow !== null && root.selectedRow.rowType === "note")
  readonly property string selectedNotePath: root.manualOverridePath !== "" ? root.manualOverridePath
    : (root.selectedRow !== null && root.selectedRow.rowType === "note" ? NoteStore.joinPath(root.expandedNotesDir, root.selectedRow.fileName) : "")
  readonly property string activeNoteTitle: root.manualOverridePath !== "" ? NoteStore.titleForFile(root.manualOverridePath.split("/").pop())
    : (root.selectedRow !== null ? root.selectedRow.title : "")

  function open(payloadJson) {
    var args = {}
    if (payloadJson) {
      try { args = JSON.parse(payloadJson) || {} } catch (e) { args = {} }
    }

    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = false
    root.manualOverridePath = ""
    root.disarmPointer()

    if (args.notesDir) {
      root.notesDir = String(args.notesDir)
      root.editingSettings = false
      root.runList()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (root.settingsLoaded) {
      root.afterSettingsReady()
    }
    // else: settingsFile's onLoaded/onLoadFailed resolves notesDir and
    // calls afterSettingsReady() once the initial read completes.
  }

  function afterSettingsReady() {
    if (!root.notesDir) {
      root.beginSettingsEdit(Quickshell.env("OMANOTE_NOTES_DIR") || (root.homeDir + "/notes"))
    } else {
      root.editingSettings = false
      root.ensureDir(root.expandedNotesDir)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function close() {
    root.flushSave()
    root.opened = false
  }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson)
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.raconger.omanote")
  }

  // ---- settings (notes folder) -----------------------------------------

  function loadSettings(raw) {
    var parsed = {}
    try { parsed = JSON.parse(String(raw || "{}")) || {} } catch (e) { parsed = {} }
    var persisted = String(parsed.notesDir || "")
    root.notesDir = persisted || Quickshell.env("OMANOTE_NOTES_DIR") || ""
    root.settingsLoaded = true
    if (root.notesDir) root.runList()
    if (root.opened) root.afterSettingsReady()
  }

  function saveSettings() {
    root.ensureDir(root.homeDir + "/.local/state/omarchy")
    settingsFile.setText(JSON.stringify({ notesDir: root.notesDir }, null, 2) + "\n")
  }

  function ensureDir(path) {
    if (mkdirProc.running) {
      mkdirProc.queuedPath = path
      return
    }
    mkdirProc.targetPath = path
    mkdirProc.command = ["mkdir", "-p", path]
    mkdirProc.running = true
  }

  function beginSettingsEdit(prefill) {
    root.editingSettings = true
    root.settingsInput = prefill !== undefined ? prefill : (root.notesDir || root.homeDir + "/notes")
    Qt.callLater(function() { settingsCatcher.forceActiveFocus() })
  }

  function commitSettings() {
    var expanded = NoteStore.expandHome(root.settingsInput, root.homeDir)
    if (!expanded) return
    root.notesDir = expanded
    root.editingSettings = false
    root.saveSettings()
    root.ensureDir(expanded)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function cancelSettingsEdit() {
    if (!root.notesDir) { root.dismiss(); return }
    root.editingSettings = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function runList() {
    if (!root.expandedNotesDir) {
      displayModel.clear()
      return
    }
    if (listProc.running) {
      listProc.hasQueued = true
      return
    }
    listProc.command = [root.scriptPath, root.expandedNotesDir, root.filterText]
    listProc.running = true
  }

  function applyListing(raw) {
    var notes = NoteStore.parseListing(raw)
    var rows = NoteStore.buildRows(notes, root.filterText)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) displayModel.append(rows[i])

    if (displayModel.count === 0) {
      root.cursorActive = false
      root.selectedIndex = 0
    } else {
      // Live-follow the top hit, nv-style: the instant a query narrows to
      // one note (or offers a create row), its content is on screen.
      root.cursorActive = true
      root.selectedIndex = Math.min(root.selectedIndex, displayModel.count - 1)
    }
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function setFilter(nextFilter) {
    root.flushSave()
    root.manualOverridePath = ""
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.disarmPointer()
    root.runList()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.manualOverridePath = ""
    root.flushSave()
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.manualOverridePath = ""
    root.flushSave()
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.manualOverridePath = ""
    root.flushSave()
    root.cursorActive = true
    root.selectedIndex = index
  }

  // Enter: create-on-miss when the highlighted row is the synthetic "create"
  // row, otherwise just hands keyboard focus to the note body so typing
  // edits the note instead of continuing to filter.
  function activateSelection() {
    var row = root.selectedRow
    if (row && row.rowType === "create") {
      root.createNote(row.fileName)
    } else if (root.hasActiveNote) {
      Qt.callLater(function() { contentEditor.forceActiveFocus() })
    }
  }

  function createNote(fileName) {
    root.flushSave()
    root.manualOverridePath = NoteStore.joinPath(root.expandedNotesDir, fileName)
    root.cursorActive = false
    Qt.callLater(function() { contentEditor.forceActiveFocus() })
  }

  function loadNoteContent(text, path, existed) {
    root.suppressSave = true
    contentEditor.text = text
    root.suppressSave = false
    root.loadedNotePath = path
    root.noteFileExists = existed
  }

  function flushSave() {
    if (saveTimer.running) saveTimer.stop()
    root.doSave()
  }

  function doSave() {
    if (!root.loadedNotePath) return
    // A brand-new note nobody has typed into yet shouldn't leave an empty
    // file behind just because it was highlighted for a moment.
    if (!root.noteFileExists && contentEditor.text.length === 0) return
    noteFile.setText(contentEditor.text)
    root.noteFileExists = true
  }

  ListModel { id: displayModel }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("{}")
  }

  Process {
    id: mkdirProc
    property string targetPath: ""
    property string queuedPath: ""
    property string stderrText: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: mkdirProc.stderrText = text
    }
    onExited: function(exitCode) {
      var path = mkdirProc.targetPath
      var accessible = exitCode === 0 && path !== ""
      root.dirError = accessible ? "" : ("Can't access notes folder “" + path + "”"
        + (mkdirProc.stderrText ? ": " + mkdirProc.stderrText.trim() : "") + ". Press Ctrl+, to change it.")
      if (path === root.expandedNotesDir) root.runList()
      if (mkdirProc.queuedPath) {
        var next = mkdirProc.queuedPath
        mkdirProc.queuedPath = ""
        root.ensureDir(next)
      }
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: listProc
    property bool hasQueued: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text)
    }
    onExited: {
      if (listProc.hasQueued) {
        listProc.hasQueued = false
        listProc.command = [root.scriptPath, root.expandedNotesDir, root.filterText]
        listProc.running = true
      }
    }
  }

  FileView {
    id: noteFile
    path: root.selectedNotePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadNoteContent(text(), root.selectedNotePath, true)
    onLoadFailed: root.loadNoteContent("", root.selectedNotePath, false)
  }

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: root.doSave()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omanote"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.editingSettings ? Math.min(root.cardHeight, Style.space(170)) : root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing
        visible: root.editingSettings

        Text {
          width: parent.width
          text: "Where should Omanote keep your notes?"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: Util.alpha(root.foreground, 0.08)

          Item {
            id: settingsCatcher
            anchors.fill: parent
            focus: root.editingSettings

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelSettingsEdit()
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitSettings()
                event.accepted = true
              } else if (Util.editsFilter(event, root.settingsInput)) {
                root.settingsInput = Util.editedFilter(event, root.settingsInput)
                event.accepted = true
              } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                root.settingsInput = root.settingsInput + event.text
                event.accepted = true
              }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.spacing.md
            text: root.settingsInput
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
          }
        }

        Text {
          width: parent.width
          text: "A flat folder of .md/.txt files. Enter to save, Escape to cancel."
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: !root.editingSettings
        visible: !root.editingSettings

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_Comma) {
            root.beginSettingsEdit(root.notesDir)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelection()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing
        visible: !root.editingSettings

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search or create a note…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Text {
          id: errorText
          width: parent.width
          visible: root.dirError !== ""
          text: root.dirError
          color: Color.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
            - (root.dirError !== "" ? errorText.height + root.contentSpacing : 0)

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: parent.width * 0.38
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string rowType
                  required property string title
                  required property string snippet
                  required property real mtimeMs

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Column {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(6)
                    anchors.bottomMargin: Style.space(6)
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: row.title
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.italic: row.rowType === "create"
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: row.rowType === "note"
                      text: (row.mtimeMs ? NoteStore.formatRelativeTime(row.mtimeMs) + "  ·  " : "") + row.snippet
                      color: row.hasCursor ? root.selectedText : root.foreground
                      opacity: 0.62
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateSelection()
                    }
                  }
                }
              }
            }

            Item {
              width: parent.width * 0.62
              height: parent.height
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Column {
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                visible: root.hasActiveNote
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  text: root.activeNoteTitle
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Flickable {
                  width: parent.width
                  height: parent.height - Style.space(24)
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  contentWidth: width
                  contentHeight: contentEditor.implicitHeight

                  TextEdit {
                    id: contentEditor
                    width: parent.width
                    color: root.foreground
                    font.family: root.monoFontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    onTextChanged: if (!root.suppressSave) saveTimer.restart()

                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        root.flushSave()
                        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                        event.accepted = true
                      }
                    }
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(8)
                visible: !root.hasActiveNote

                Text {
                  text: displayModel.count === 0 && root.filterText === "" ? "Type to search or create a note" : "No note selected"
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }
              }
            }
          }
        }
      }
    }
  }
}
