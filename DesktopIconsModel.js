// Desktop icons model helpers: default settings, icon-name mapping, sorting.

function defaultSettings() {
  return {
    sortBy: "name",
    sortDesc: false,
    iconSize: "medium",
    iconScale: 1.0,
    showLabels: true,
    align: "left",
    autoHide: true,
    showDesktopFiles: true,
    showDrives: true,
    showNetworkMounts: true,
    showHome: true,
    showTrash: true
  }
}

function iconSizePx(size) {
  switch (size) {
    case "small": return 32
    case "large": return 64
    case "medium":
    default: return 48
  }
}

function _extOf(name) {
  var i = name.lastIndexOf(".")
  if (i <= 0) return ""
  return name.slice(i + 1).toLowerCase()
}

function iconFor(kind, label) {
  var ext = _extOf(label || "")
  switch (kind) {
    case "folder": return "folder"
    case "home": return "user-home"
    case "trash": return "user-trash"
    case "drive": return "drive-harddisk"
    case "netmount": return "folder-remote"
    case "file":
      if (ext === "desktop") return "application-x-executable"
      if (/^(png|jpg|jpeg|gif|svg|bmp|webp|tiff|heic|avif)$/.test(ext)) return "image-x-generic"
      if (/^(mp4|mkv|avi|mov|webm|flv|wmv|mpg|mpeg)$/.test(ext)) return "video-x-generic"
      if (/^(mp3|flac|ogg|opus|wav|m4a|aac)$/.test(ext)) return "audio-x-generic"
      if (ext === "pdf") return "application-pdf"
      if (/^(zip|tar|gz|bz2|xz|7z|rar|zst)$/.test(ext)) return "package-x-generic"
      if (/^(iso|img)$/.test(ext)) return "media-optical"
      if (/^(txt|md|log|json|xml|yaml|yml|toml|ini|conf|sh|py|js|ts|c|cpp|h|rs|go|html|css|lua|sql|cfg)$/.test(ext)) return "text-x-generic"
      return "application-x-generic"
  }
  return "application-x-generic"
}

function sortRows(rows, by, desc) {
  var arr = rows.slice()
  arr.sort(function(a, b) {
    var c
    if (by === "type") {
      c = a.sortType === b.sortType ? 0 : (a.sortType < b.sortType ? -1 : 1)
    } else if (by === "size") {
      c = a.sortSize === b.sortSize ? 0 : (a.sortSize < b.sortSize ? -1 : 1)
    } else {
      var la = a.label.toLowerCase()
      var lb = b.label.toLowerCase()
      c = la === lb ? 0 : (la < lb ? -1 : 1)
    }
    if (by === "type") {
      if (c === 0) c = a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1
    }
    if (desc) c = -c
    return c
  })
  return arr
}

function gather(settings, desktopEntries, drives, netMounts, home) {
  var rows = []
  var seen = {}
  function push(r) {
    if (seen[r.key]) return
    seen[r.key] = true
    rows.push(r)
  }

  if (settings.showHome) {
    push({
      key: "home", kind: "home", label: "Home", path: home,
      iconName: iconFor("home"), sortType: "place-home", sortSize: -3
    })
  }
  if (settings.showTrash) {
    push({
      key: "trash", kind: "trash", label: "Trash", path: "trash:///",
      iconName: iconFor("trash"), sortType: "place-trash", sortSize: -3
    })
  }
  var driveTargets = {}
  if (settings.showDrives) {
    for (var d = 0; d < drives.length; d++) {
      var drive = drives[d]
      driveTargets[drive.target] = true
      push({
        key: "drive-" + drive.target, kind: "drive", label: drive.label, path: drive.target,
        iconName: iconFor("drive"), sortType: "drive", sortSize: -2
      })
    }
  }
  if (settings.showNetworkMounts) {
    for (var n = 0; n < netMounts.length; n++) {
      var net = netMounts[n]
      if (driveTargets[net.target]) continue
      push({
        key: "net-" + net.target, kind: "netmount", label: net.label, path: net.target,
        iconName: iconFor("netmount"), sortType: "net", sortSize: -2
      })
    }
  }
  if (settings.showDesktopFiles) {
    for (var i = 0; i < desktopEntries.length; i++) {
      var e = desktopEntries[i]
      var icon = iconFor(e.isDir ? "folder" : "file", e.name)
      push({
        key: "file-" + e.path, kind: e.isDir ? "folder" : "file", label: e.name, path: e.path,
        iconName: icon, sortType: e.isDir ? "folder" : ("file-" + _extOf(e.name)), sortSize: e.isDir ? -1 : e.size
      })
    }
  }
  return sortRows(rows, settings.sortBy, settings.sortDesc)
}