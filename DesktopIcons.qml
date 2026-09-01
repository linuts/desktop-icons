import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "DesktopIconsModel.js" as DIM

Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/desktop-icons"
  readonly property string configPath: stateDir + "/config.json"
  readonly property string hiddenStatePath: stateDir + "/hidden-windows.json"

  property var settings: DIM.defaultSettings()
  property string desktopDir: home + "/Desktop"
  property var desktopEntries: []
  property var drives: []
  property var netMounts: []
  property string selectedKey: ""

  property bool stateReady: false
  property string pendingConfigText: ""

  property ListModel itemModel: ListModel {}

  property bool keysActive: false
  property var keysPanel: null
  property int kbIndex: -1
  property bool ctxOpen: false

  property var hiddenWindows: []
  property bool hiddenChecked: false
  readonly property string hideWorkspace: "special:desktop-icons"

  readonly property int baseIconPx: DIM.iconSizePx(settings.iconSize)
  readonly property int baseCellW: baseIconPx + Math.round(Style.space(22))
  readonly property int baseCellH: baseIconPx + (settings.showLabels ? Math.round(Style.space(26)) : Math.round(Style.space(14)))
  readonly property int topInset: Math.round(Style.space(52))
  readonly property int sideInset: Math.round(Style.space(18))

  // --------------------------------------------------------------------------
  // Inline menu row components (declared before use).
  // --------------------------------------------------------------------------

  component MenuSectionTitle: Text {
    Layout.fillWidth: true
    height: Math.max(Style.space(20), Style.font.caption + Style.spacing.xs)
    verticalAlignment: Text.AlignVCenter
    color: Color.menu.text
    opacity: 0.6
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
  }

  component MenuSeparator: Item {
    Layout.fillWidth: true
    height: 1
    Rectangle {
      anchors.fill: parent
      color: Color.menu.border
      opacity: 0.4
    }
  }

  component MenuToggleRow: MouseArea {
    id: toggleRow
    Layout.fillWidth: true
    hoverEnabled: true
    height: row.implicitHeight

    property string label: ""
    property bool checked: false
    property bool keyed: false
    readonly property bool menuFocusable: true

    signal toggled()

    Rectangle {
      anchors.fill: parent
      color: (toggleRow.containsMouse || toggleRow.keyed) ? Color.menu.selectedBackground : "transparent"
      radius: Math.max(2, Style.cornerRadius / 2)
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      Text {
        text: toggleRow.label
        Layout.fillWidth: true
        color: (toggleRow.containsMouse || toggleRow.keyed) ? Color.menu.selectedText : Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      ToggleSwitch {
        checked: toggleRow.checked
        interactive: false
        trackHeight: Math.round(Style.spacing.controlHeight * 0.55)
      }
    }

    onClicked: toggled()

    function invoke() { toggled() }
  }

  component MenuRadioRow: MouseArea {
    id: radioRow
    Layout.fillWidth: true
    hoverEnabled: true
    height: row.implicitHeight

    property bool selected: false
    property string label: ""
    property bool keyed: false
    readonly property bool menuFocusable: true

    signal chosen()

    Rectangle {
      anchors.fill: parent
      color: (radioRow.containsMouse || radioRow.keyed) ? Color.menu.selectedBackground : "transparent"
      radius: Math.max(2, Style.cornerRadius / 2)
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(4)

      Text {
        text: radioRow.label
        Layout.fillWidth: true
        color: (radioRow.containsMouse || radioRow.keyed) ? Color.menu.selectedText : Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: Style.space(4)
        border.width: Math.max(1, Style.space(1))
        border.color: radioRow.selected ? Color.accent : Color.menu.text
        color: radioRow.selected ? Color.accent : "transparent"
      }
    }

    onClicked: chosen()

    function invoke() { chosen() }
  }

  component MenuActionRow: MouseArea {
    id: actionRow
    Layout.fillWidth: true
    hoverEnabled: true
    height: row.implicitHeight

    property string label: ""
    property bool keyed: false
    readonly property bool menuFocusable: true

    signal trigger()

    Rectangle {
      anchors.fill: parent
      color: (actionRow.containsMouse || actionRow.keyed) ? Color.menu.selectedBackground : "transparent"
      radius: Math.max(2, Style.cornerRadius / 2)
    }

    Text {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      text: actionRow.label
      color: (actionRow.containsMouse || actionRow.keyed) ? Color.menu.selectedText : Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }

    onClicked: trigger()

    function invoke() { trigger() }
  }

  // --------------------------------------------------------------------------
  // Settings persistence (lives outside the plugin dir to avoid the inotify
  // plugin-reload loop).
  // --------------------------------------------------------------------------

  function setSetting(key, value) {
    var next = JSON.parse(JSON.stringify(root.settings))
    next[key] = value
    root.settings = next
  }

  function loadSettings(text) {
    var parsed = ({})
    try {
      parsed = JSON.parse(text || "{}")
    } catch (e) {
      parsed = ({})
    }
    var merged = DIM.defaultSettings()
    for (var k in parsed) merged[k] = parsed[k]

    var same = true
    var cur = root.settings
    for (var kk in merged) {
      if (cur[kk] !== merged[kk]) { same = false; break }
    }
    if (same) return
    root.settings = merged
  }

  function persistSettings() {
    var json = JSON.stringify(root.settings, null, 2) + "\n"
    if (root.stateReady) configFile.setText(json)
    else root.pendingConfigText = json
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    watchChanges: true
    onTextChanged: root.loadSettings(configFile.text())
  }

  FileView {
    id: hiddenFile
    path: root.hiddenStatePath
    atomicWrites: true
    watchChanges: false
    onTextChanged: root.checkHiddenState(hiddenFile.text())
  }

  Process {
    id: stateDirPrep
    command: ["bash", "-c", "mkdir -p \"$1\"; mkdir -p \"$2\"", "desktop-icons", root.stateDir, root.desktopDir]
    onExited: {
      root.stateReady = true
      if (root.pendingConfigText) {
        configFile.setText(root.pendingConfigText)
        root.pendingConfigText = ""
      }
    }
  }

  // --------------------------------------------------------------------------
  // Desktop directory + listing.
  // --------------------------------------------------------------------------

  Process {
    id: desktopDirProc
    command: ["xdg-user-dir", "DESKTOP"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = String(text || "").trim()
        if (found.length > 0) {
          if (found === root.home || found === root.home + "/") {
            root.desktopDir = root.home + "/Desktop"
          } else {
            root.desktopDir = found
          }
        }
      }
    }
  }

  readonly property string desktopListCmd: [
    "set -u",
    "d=\"$1\"",
    "[[ -d \"$d\" ]] || exit 0",
    "find \"$d\" -maxdepth 1 -mindepth 1 -printf '%y\\t%s\\t%f\\n' | while IFS=$'\\t' read -r type size name; do",
    "  case \"$name\" in .*) continue ;; esac",
    "  if [[ -d \"$d/$name\" ]]; then flag=0; elif [[ -x \"$d/$name\" ]]; then flag=1; else flag=0; fi",
    "  printf '%s\\t%s\\t%s\\t%s\\n' \"$type\" \"$size\" \"$flag\" \"$name\"",
    "done"
  ].join("\n")

  Process {
    id: desktopListProc
    command: ["bash", "-c", root.desktopListCmd, "desktop-icons", root.desktopDir]
    stdout: StdioCollector {
      id: desktopListOut
      waitForEnd: true
    }
    onExited: root.parseDesktopList(desktopListOut.text || "")
  }

  function parseDesktopList(raw) {
    var out = []
    var base = root.desktopDir.replace(/\/+$/, "")
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/\r$/, "")
      if (line.length === 0) continue
      var parts = line.split("\t")
      if (parts.length < 4) continue
      out.push({
        name: parts[3],
        path: base + "/" + parts[3],
        isDir: parts[0] === "d",
        isExec: parts[2] === "1",
        size: parseInt(parts[1], 10) || 0
      })
    }
    root.desktopEntries = out
  }

  // --------------------------------------------------------------------------
  // Desktop watcher (inotify) + drives poll.
  // --------------------------------------------------------------------------

  Process {
    id: desktopWatchProc
    command: ["inotifywait", "-m", "-q", "-e", "create,delete,move,attrib,close_write",
              "--format", "%w%f", root.desktopDir]
    stdout: SplitParser {
      onRead: root.desktopChanged()
    }
    onExited: desktopWatchRestart.restart()
  }

  Timer {
    id: desktopWatchRestart
    interval: 750
    onTriggered: desktopWatchProc.running = true
  }

  Timer {
    id: rescanDebounce
    interval: 200
    onTriggered: root.rescanDesktop()
  }

  function desktopChanged() {
    rescanDebounce.restart()
  }

  function rescanDesktop() {
    if (!desktopListProc.running) desktopListProc.running = true
  }

  readonly property string drivesCmd: [
    "set -u",
    "user=$(id -un)",
    "{ findmnt -rn -o TARGET | grep -E '/run/media/\\$user/|^/mnt/|^/media/' ; } | sort -u"
  ].join("; ")

  Process {
    id: drivesProc
    command: ["bash", "-c", root.drivesCmd, "desktop-icons"]
    stdout: StdioCollector {
      onStreamFinished: root.parseDrives(String(text || ""))
    }
  }

  readonly property string netMountsCmd: [
    "set -u",
    "{ findmnt -rn -o FSTYPE,TARGET | awk '$1 ~ /^(sshfs|nfs[0-9]*|cifs|smbfs|ceph|9p|davfs2?|fuse\\.sshfs|fuse\\.smb[0-9]*|fuse\\.rclone)$/ { sub(/^[^ ]+ /, \"\"); print }' ; } | sort -u"
  ].join("; ")

  Process {
    id: netMountsProc
    command: ["bash", "-c", root.netMountsCmd, "desktop-icons"]
    stdout: StdioCollector {
      onStreamFinished: root.parseNetMounts(String(text || ""))
    }
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.onClientsCensus(String(text || ""))
    }
  }

  function onClientsCensus(raw) {
    var list = []
    try { list = JSON.parse(raw) } catch (e) { return }
    if (!Array.isArray(list)) return
    var hidden = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w || !w["mapped"] || w["hidden"] || w["pinned"]) continue
      var ws = w["workspace"] ? w["workspace"]["id"] : -1
      if (typeof ws !== "number" || ws < 0) continue
      hidden.push({ address: String(w["address"]), workspace: String(ws) })
    }
    root.hiddenWindows = hidden
    hiddenFile.setText(JSON.stringify(hidden))
    console.log("[desktop-icons] census: " + hidden.length + " window(s) to hide")
    root.dispatchWindowMoves(hidden, root.hideWorkspace)
  }

  function checkHiddenState(text) {
    if (root.hiddenChecked) return
    root.hiddenChecked = true
    var list = []
    try { list = JSON.parse(text || "") } catch (e) { return }
    if (!Array.isArray(list) || list.length === 0) return
    root.restoreList(list)
  }

  function restoreList(list) {
    if (!list || list.length === 0) return
    console.log("[desktop-icons] restore: " + list.length + " window(s)")
    var byWorkspace = {}
    for (var i = 0; i < list.length; i++) {
      var ws = list[i].workspace
      if (!byWorkspace[ws]) byWorkspace[ws] = []
      byWorkspace[ws].push(list[i])
    }
    for (var key in byWorkspace) root.dispatchWindowMoves(byWorkspace[key], key)
    if (hiddenFile) hiddenFile.setText("")
  }

  function dispatchWindowMoves(windows, workspace) {
    if (!windows || windows.length === 0) return
    for (var i = 0; i < windows.length; i++) {
      var dispatch = "hl.dsp.window.move({ window = \"address:" + windows[i].address
        + "\", workspace = \"" + workspace + "\", follow = false })"
      Util.execArgv(["hyprctl", "dispatch", dispatch])
    }
  }

  function hideWindowsForDesktop() {
    if (!clientsProc.running) clientsProc.running = true
  }

  function restoreWindows() {
    var list = root.hiddenWindows
    root.hiddenWindows = []
    root.restoreList(list)
  }

  function parseNetMounts(raw) {
    var out = []
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var target = lines[i].replace(/\r$/, "").trim()
      if (target.length === 0 || target === "/") continue
      var name = target.replace(/\/+$/, "")
      var label = name.split("/").pop()
      if (!label) label = name
      if (label.length === 0) continue
      out.push({ label: label, target: target })
    }
    var changed = out.length !== root.netMounts.length
    if (!changed) {
      for (var j = 0; j < out.length; j++) {
        if (out[j].target !== root.netMounts[j].target) { changed = true; break }
      }
    }
    if (changed) root.netMounts = out
  }

  function rescanNetMounts() {
    if (!netMountsProc.running) netMountsProc.running = true
  }

  Timer {
    id: drivesTimer
    interval: 8000
    repeat: true
    running: true
    onTriggered: root.rescanDrives()
  }

  function rescanDrives() {
    if (!drivesProc.running) drivesProc.running = true
  }

  function parseDrives(raw) {
    var out = []
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var target = lines[i].replace(/\r$/, "").trim()
      if (target.length === 0 || target === "/") continue
      var name = target.replace(/\/+$/, "")
      var label = name.split("/").pop()
      if (!label) label = name
      if (label.length === 0) continue
      out.push({ label: label, target: target })
    }
    var changed = out.length !== root.drives.length
    if (!changed) {
      for (var j = 0; j < out.length; j++) {
        if (out[j].target !== root.drives[j].target) { changed = true; break }
      }
    }
    if (changed) root.drives = out
  }

  // --------------------------------------------------------------------------
  // Model.
  // --------------------------------------------------------------------------

  function resolveIcon(name) {
    var url = Quickshell.iconPath(name, true)
    if (!url || url.length === 0) url = Quickshell.iconPath("application-x-generic", true)
    return url
  }

  function rebuild() {
    var rows = DIM.gather(root.settings, root.desktopEntries, root.drives, root.netMounts, root.home)
    itemModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      itemModel.append({
        key: r.key,
        kind: r.kind,
        label: r.label,
        path: r.path,
        resolvedIcon: root.resolveIcon(r.iconName)
      })
    }
  }

  function refreshAll() {
    root.rescanDesktop()
    root.rescanDrives()
    root.rescanNetMounts()
  }

  function openItem(row) {
    if (!row || !row.path) return
    Util.execArgv(["gio", "open", row.path])
  }

  onSettingsChanged: {
    root.rebuild()
    root.persistSettings()
  }

  onDesktopEntriesChanged: root.rebuild()
  onDrivesChanged: root.rebuild()
  onNetMountsChanged: root.rebuild()

  // --------------------------------------------------------------------------
  // IPC + startup.
  // --------------------------------------------------------------------------

  IpcHandler {
    target: "io.github.linuts.desktop-icons"

    function refresh() {
      root.refreshAll()
    }

    function toggleAutoHide() {
      root.setSetting("autoHide", !root.settings.autoHide)
    }

    function focus() {
      root.enterKeys()
    }

    function unfocus() {
      root.leaveKeys()
    }

    function toggle() {
      root.keysActive ? root.leaveKeys() : root.enterKeys()
    }

    function listItems(): string {
      var out = []
      for (var i = 0; i < root.itemModel.count; i++) {
        var row = root.itemModel.get(i)
        out.push({ key: row.key, kind: row.kind, label: row.label, path: row.path })
      }
      var entries = []
      for (var j = 0; j < root.desktopEntries.length; j++) {
        var e = root.desktopEntries[j]
        entries.push({ name: e.name, path: e.path, isDir: e.isDir, size: e.size })
      }
      var driveNames = []
      for (var k = 0; k < root.drives.length; k++) driveNames.push(root.drives[k].target)
      var netNames = []
      for (var m = 0; m < root.netMounts.length; m++) netNames.push(root.netMounts[m].target)
      return JSON.stringify({
        settings: root.settings,
        desktopDir: root.desktopDir,
        desktopEntries: entries,
        drives: driveNames,
        netMounts: netNames,
        items: out,
        keys: {
          active: root.keysActive,
          kbIndex: root.kbIndex,
          monitor: root.keysPanel ? String(root.keysPanel.modelData.name) : ""
        }
      })
    }
  }

  Component.onCompleted: {
    stateDirPrep.running = true
    desktopDirProc.running = true
    drivesProc.running = true
    netMountsProc.running = true
  }

  Connections {
    target: desktopDirProc
    function onExited() {
      desktopWatchProc.running = true
      root.rescanDesktop()
    }
  }

  // --------------------------------------------------------------------------
  // Keyboard navigation.
  // --------------------------------------------------------------------------

  function kbFocusedPanel() {
    return root.keysPanel || null
  }

  function enterKeys() {
    if (root.keysActive) return
    root.hideWindowsForDesktop()
    var target = null
    for (var i = 0; i < panels.instances.length; i++) {
      var p = panels.instances[i]
      if (Hyprland.focusedMonitor && p.hyproMonitor
          && p.hyproMonitor === Hyprland.focusedMonitor) {
        target = p
        break
      }
    }
    if (!target && panels.instances.length > 0) target = panels.instances[0]
    if (!target) return
    root.keysPanel = target
    root.keysActive = true
    if (root.kbIndex < 0 && root.itemModel.count > 0) root.selectKb(0)
  }

  function leaveKeys() {
    root.keysActive = false
    root.keysPanel = null
    root.kbIndex = -1
    root.selectedKey = ""
    root.restoreWindows()
  }

  function selectKb(index) {
    var count = root.itemModel.count
    if (count === 0) {
      root.kbIndex = -1
      root.selectedKey = ""
      return
    }
    root.kbIndex = index
    root.selectedKey = root.itemModel.get(index).key
    var p = root.kbFocusedPanel()
    if (p) p.parkKb()
  }

  function kbStep(delta) {
    var count = root.itemModel.count
    if (count === 0) { root.kbIndex = -1; return }
    var next = root.kbIndex < 0 ? (delta > 0 ? 0 : count - 1) : root.kbIndex + delta
    next = ((next % count) + count) % count
    root.selectKb(next)
  }

  function kbArrow(dx, dy) {
    var p = root.kbFocusedPanel()
    if (!p || root.itemModel.count === 0) return
    if (root.kbIndex < 0) { root.selectKb(0); return }
    var rows = p.rowsAvail
    var cols = p.gridCols
    var col = Math.min(Math.floor(root.kbIndex / rows), cols - 1)
    var row = root.kbIndex % rows
    var t = col + dx
    if (t < 0 || t >= cols) return
    var occupied = Math.min(rows, root.itemModel.count - t * rows)
    var r = row + dy
    if (r < 0 || r >= occupied) return
    root.selectKb(t * rows + r)
  }

  function kbOpen() {
    if (root.kbIndex < 0 || root.kbIndex >= root.itemModel.count) return
    root.openItem(root.itemModel.get(root.kbIndex))
    root.leaveKeys()
  }

  function openContextMenuAtKeys() {
    console.log("[desktop-icons] openContextMenuAtKeys, count=", root.itemModel.count)
    var p = root.kbFocusedPanel()
    if (!p) return
    var x, y
    if (root.itemModel.count === 0) {
      x = Math.round(p.width / 2)
      y = Math.round(p.height / 2)
    } else {
      if (root.kbIndex < 0) root.selectKb(0)
      var rows = p.rowsAvail
      var cols = p.gridCols
      var col = Math.min(Math.floor(root.kbIndex / rows), cols - 1)
      var row = root.kbIndex % rows
      x = Math.round(p.gridX + col * p.panelCellW + p.panelCellW / 2)
      y = Math.round(p.gridY + row * p.panelCellH + p.panelCellH / 2)
    }
    root.openContextMenu(p, x, y, true)
  }

  // --------------------------------------------------------------------------
  // Per-monitor panels (Bottom layer, below windows).
  // --------------------------------------------------------------------------

  Variants {
    id: panels
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      objectName: "desktop-icons-panel"

      screen: modelData
      visible: true
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        window: panel
      }

      color: "transparent"
      updatesEnabled: true
      WlrLayershell.namespace: "omarchy-desktop-icons"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: panel.inKeysMode && !root.ctxOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      readonly property var hyproMonitor: Hyprland.monitorFor(modelData)
      readonly property var activeWs: hyproMonitor ? hyproMonitor.activeWorkspace : null
      readonly property int wsToplevels: activeWs ? activeWs.toplevels.values.length : 0
      readonly property bool busy: root.settings.autoHide && wsToplevels > 0
      readonly property bool showDesktopIcons: !busy

      readonly property real displayScale: Math.max(
        hyproMonitor ? hyproMonitor.scale : 1.0, 0.25) * root.settings.iconScale
      readonly property int panelIconPx: Math.round(root.baseIconPx * displayScale)
      readonly property int panelCellW: panelIconPx + Math.round(Style.space(22) * displayScale)
      readonly property int panelCellH: panelIconPx + (root.settings.showLabels ? Math.round(Style.space(26) * displayScale) : Math.round(Style.space(14) * displayScale))

      readonly property int gridUsable: Math.max(1, Math.floor(panel.width - root.sideInset * 2))
      readonly property int rowsAvail: Math.max(1, Math.floor(panel.height / panelCellH))
      readonly property int colsFit: Math.max(1, Math.floor(gridUsable / panelCellW))
      readonly property int gridCols: Math.max(1, Math.min(colsFit, Math.ceil(root.itemModel.count / rowsAvail)))
      readonly property real gridContentWidth: Math.min(gridUsable, gridCols * panelCellW)
      readonly property real gridContentHeight: Math.ceil(root.itemModel.count / gridCols) * panelCellH
      readonly property real gridX: root.settings.align === "right"
        ? Math.floor(panel.width - root.sideInset - gridContentWidth)
        : (root.settings.align === "center"
          ? Math.floor((panel.width - gridContentWidth) / 2)
          : root.sideInset)
      readonly property real gridY: root.settings.align === "center"
        ? Math.floor((panel.height - gridContentHeight) / 2)
        : root.topInset

      readonly property bool inKeysMode: root.keysActive && root.keysPanel === panel

      function parkKb() {
        keyCatcher.forceActiveFocus()
        if (root.kbIndex >= 0 && root.kbIndex < root.itemModel.count) {
          grid.positionViewAtIndex(root.kbIndex, GridView.Center)
        }
      }

      onInKeysModeChanged: {
        if (inKeysMode) Qt.callLater(parkKb)
      }

      onBusyChanged: {
        if (panel.busy && root.keysActive) root.leaveKeys()
      }

      Item {
        id: desktopSurface
        anchors.fill: parent
        opacity: showDesktopIcons ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        MouseArea {
          id: backdrop
          anchors.fill: parent
          enabled: panel.showDesktopIcons
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              root.openContextMenu(panel, mouse.x, mouse.y)
              mouse.accepted = true
            } else if (mouse.button === Qt.LeftButton) {
              root.enterKeys()
            }
          }
        }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          visible: panel.inKeysMode

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (!panel.inKeysMode) return
            var shift = (event.modifiers & Qt.ShiftModifier) !== 0
            if (event.key === Qt.Key_Escape) {
              root.leaveKeys()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              if (event.key === Qt.Key_Backtab || shift) root.openContextMenuAtKeys()
              else root.kbStep(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.kbOpen()
              event.accepted = true
            } else if (event.key === Qt.Key_Right) {
              root.kbArrow(1, 0)
              event.accepted = true
            } else if (event.key === Qt.Key_Left) {
              root.kbArrow(-1, 0)
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.kbArrow(0, 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.kbArrow(0, -1)
              event.accepted = true
            }
          }
        }

        GridView {
          id: grid
          x: panel.gridX
          y: panel.gridY
          width: panel.gridContentWidth
          height: panel.gridContentHeight
          model: itemModel
          cellWidth: panel.panelCellW
          cellHeight: panel.panelCellH
          interactive: false
          clip: true
          cacheBuffer: 0
          enabled: panel.showDesktopIcons

          property QtObject host: root
          property QtObject hostWindow: panel
          property int iconPx: panel.panelIconPx

        delegate: Component {
          id: itemDelegate

          Item {
            id: cell
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            readonly property bool hovered: cellMouse.containsMouse
            readonly property bool isSelected: cell.host.selectedKey === model.key
            readonly property bool showLabels: cell.host.settings.showLabels
            readonly property int iconPx: GridView.view.iconPx
            readonly property QtObject host: grid.host
            readonly property QtObject hostWindow: grid.hostWindow

            Rectangle {
              id: highlight
              anchors.fill: parent
              anchors.margins: Math.max(1, Style.space(1))
              radius: Math.max(2, Style.cornerRadius / 2)
              color: cell.hovered ? Qt.rgba(1, 1, 1, 0.12)
                                  : (cell.isSelected ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
              visible: cell.hovered || cell.isSelected

              Behavior on color { ColorAnimation { duration: 90 } }
            }

            Image {
              id: iconImg
              width: cell.iconPx
              height: cell.iconPx
              anchors.top: parent.top
              anchors.topMargin: Math.max(2, Style.space(3))
              anchors.horizontalCenter: parent.horizontalCenter
              source: model.resolvedIcon
              fillMode: Image.PreserveAspectFit
              mipmap: true
              smooth: true
            }

            Text {
              id: label
              anchors.top: iconImg.bottom
              anchors.topMargin: Math.max(1, Style.space(1))
              anchors.left: parent.left
              anchors.right: parent.right
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignTop
              text: model.label
              elide: Text.ElideMiddle
              maximumLineCount: 1
              visible: cell.showLabels
              color: Color.foreground
              textFormat: Text.PlainText
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true
              onEntered: cell.host.selectedKey = model.key
              onClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton) {
                  cell.host.openItem(model)
                  cell.host.selectedKey = model.key
                  cell.host.kbIndex = index
                } else if (mouse.button === Qt.RightButton) {
                  var win = cell.hostWindow
                  var p = cell.mapToItem(win.contentItem, cell.width / 2, cell.height / 2)
                  cell.host.openContextMenu(win, p.x, p.y)
                }
              }
            }
          }
        }
      }
      }
    }
  }

  // --------------------------------------------------------------------------
  // Context menu.
  // --------------------------------------------------------------------------

  function openContextMenu(window, x, y, fromKeys) {
    ctxMenu.open = false
    Qt.callLater(function() {
      ctxAnchor.window = window
      ctxAnchor.rect.x = Math.round(x)
      ctxAnchor.rect.y = Math.round(y)
      ctxMenu.kbRow = -1
      ctxMenu.open = true
      root.ctxOpen = true
      if (fromKeys) {
        menuKey.focus = true
        menuKey.forceActiveFocus()
        ctxMenu.stepRow(1)
      }
    })
  }

  PopupWindow {
    id: ctxMenu
    objectName: "desktop-icons-menu"
    color: "transparent"
    property bool open: false
    property int kbRow: -1
    visible: open
    implicitWidth: menuCard.implicitWidth
    implicitHeight: menuCard.implicitHeight

    function menuRows() {
      var out = []
      for (var i = 0; i < rowList.children.length; i++) {
        var c = rowList.children[i]
        if (c.menuFocusable) out.push(c)
      }
      return out
    }

    function paintRows() {
      var rows = ctxMenu.menuRows()
      for (var j = 0; j < rows.length; j++) rows[j].keyed = (j === ctxMenu.kbRow)
    }

    function stepRow(delta) {
      var rows = ctxMenu.menuRows()
      if (!rows.length) return
      var n = rows.length
      ctxMenu.kbRow = ((ctxMenu.kbRow + delta) % n + n) % n
      ctxMenu.paintRows()
    }

    function activateRow() {
      var rows = ctxMenu.menuRows()
      if (ctxMenu.kbRow < 0 || ctxMenu.kbRow >= rows.length) return
      rows[ctxMenu.kbRow].invoke()
    }

    FocusScope {
      id: menuKey
      anchors.fill: parent
      focus: ctxMenu.open
      visible: ctxMenu.open

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
        if (event.key === Qt.Key_Escape) {
          ctxMenu.open = false
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
          var delta = (event.key === Qt.Key_Up) || (event.key === Qt.Key_Backtab) || (event.key === Qt.Key_Tab && shift) ? -1 : 1
          ctxMenu.stepRow(delta)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          ctxMenu.activateRow()
          event.accepted = true
        }
      }
    }

    HyprlandFocusGrab {
      active: ctxMenu.open
      windows: [ctxMenu]
      onCleared: {
        ctxMenu.open = false
        root.leaveKeys()
      }
    }

    onOpenChanged: {
      if (!open) root.ctxOpen = false
    }

    anchor {
      id: ctxAnchor
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var w = ctxAnchor.window
        var vw = w ? w.width : 0
        var vh = w ? w.height : 0
        var pad = Style.space(8)
        if (vw > 0) ctxAnchor.rect.x = Math.max(pad, Math.min(ctxAnchor.rect.x, vw - ctxMenu.implicitWidth - pad))
        if (vh > 0) ctxAnchor.rect.y = Math.max(pad, Math.min(ctxAnchor.rect.y, vh - ctxMenu.implicitHeight - pad))
      }
    }

    BorderSurface {
      id: menuCard
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(1)))
      radius: Style.cornerRadius
      padding: Style.spacing.xs
      implicitWidth: Math.round(Style.space(252))
      implicitHeight: rowList.implicitHeight + contentTopInset + contentBottomInset

      ColumnLayout {
        id: rowList
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: menuCard.contentTopInset
        anchors.bottomMargin: menuCard.contentBottomInset
        anchors.leftMargin: menuCard.contentLeftInset
        anchors.rightMargin: menuCard.contentRightInset
        spacing: Math.max(1, Style.spacing.hairline)

        MenuSectionTitle { text: "Sort By" }
        MenuRadioRow { label: "Name"; selected: root.settings.sortBy === "name"; onChosen: root.setSetting("sortBy", "name") }
        MenuRadioRow { label: "Type"; selected: root.settings.sortBy === "type"; onChosen: root.setSetting("sortBy", "type") }
        MenuRadioRow { label: "Size"; selected: root.settings.sortBy === "size"; onChosen: root.setSetting("sortBy", "size") }
        MenuToggleRow { label: "Reverse order"; checked: root.settings.sortDesc; onToggled: root.setSetting("sortDesc", !root.settings.sortDesc) }

        MenuSeparator {}

        MenuSectionTitle { text: "Appearance" }
        MenuRadioRow { label: "Align left"; selected: root.settings.align === "left"; onChosen: root.setSetting("align", "left") }
        MenuRadioRow { label: "Align center"; selected: root.settings.align === "center"; onChosen: root.setSetting("align", "center") }
        MenuRadioRow { label: "Align right"; selected: root.settings.align === "right"; onChosen: root.setSetting("align", "right") }
        MenuRadioRow { label: "Small icons"; selected: root.settings.iconSize === "small"; onChosen: root.setSetting("iconSize", "small") }
        MenuRadioRow { label: "Medium icons"; selected: root.settings.iconSize === "medium"; onChosen: root.setSetting("iconSize", "medium") }
        MenuRadioRow { label: "Large icons"; selected: root.settings.iconSize === "large"; onChosen: root.setSetting("iconSize", "large") }
        MenuToggleRow { label: "Show labels"; checked: root.settings.showLabels; onToggled: root.setSetting("showLabels", !root.settings.showLabels) }
        MenuToggleRow { label: "Hide while windows open"; checked: root.settings.autoHide; onToggled: root.setSetting("autoHide", !root.settings.autoHide) }

        MenuSeparator {}

        MenuSectionTitle { text: "Show On Desktop" }
        MenuToggleRow { label: "Desktop files"; checked: root.settings.showDesktopFiles; onToggled: root.setSetting("showDesktopFiles", !root.settings.showDesktopFiles) }
        MenuToggleRow { label: "Mounted drives"; checked: root.settings.showDrives; onToggled: root.setSetting("showDrives", !root.settings.showDrives) }
        MenuToggleRow { label: "Network mounts"; checked: root.settings.showNetworkMounts; onToggled: root.setSetting("showNetworkMounts", !root.settings.showNetworkMounts) }
        MenuToggleRow { label: "Home folder"; checked: root.settings.showHome; onToggled: root.setSetting("showHome", !root.settings.showHome) }
        MenuToggleRow { label: "Trash"; checked: root.settings.showTrash; onToggled: root.setSetting("showTrash", !root.settings.showTrash) }

        MenuSeparator {}

        MenuActionRow { label: "Refresh"; onTrigger: root.refreshAll() }
      }
    }
  }
}