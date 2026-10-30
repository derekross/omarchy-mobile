// SPDX-License-Identifier: MIT
// A recent-apps card's name: the app's own name from its desktop entry, as
// the app drawer shows it, rather than the window's class and title
// ("org.omamobile.Phone  Phone", "chrome-cinhimbnkkaeohfgghhklpknlkffjgod-Default").
//
// `entries` are Quickshell DesktopEntry objects (or anything with id, name,
// startupClass and execString or command). A window's class (Wayland app_id)
// is matched against, in order:
//   1. the entry's id, with or without ".desktop" ("org.omamobile.Phone");
//   2. the entry's StartupWMClass ("foot");
//   3. a Chromium app installed from the browser: its window is
//      "chrome-<32-letter id>-<profile>", its entry is
//      "chrome-<id>-<profile>.desktop" with StartupWMClass "crx_<id>" or
//      "--app-id=<id>" in Exec;
//   4. an Omarchy web app (omarchy-launch-webapp URL, or a browser started
//      with --app=URL): Chromium names its window
//      "chrome-<host>_<path, '/' as '_'>-<profile>", so
//      https://messages.google.com/web is "chrome-messages.google.com__web-Default"
//      (then by host alone, as omamobile-launch matches it);
//   5. the id's last reverse-DNS part, then the program Exec starts, as
//      omamobile-launch matches an open window to an entry.
// Case is ignored throughout. Without a match: the window's title, then its
// class, then "App".

var CRX_ID = /^[a-z]+-([a-p]{32})-[^-]+$/
var URL_APP = /^[a-z]+-(.+)-[^-]+$/

function lower(v) { return String(v === undefined || v === null ? "" : v).toLowerCase() }

function execOf(entry) {
  if (!entry) return ""
  if (entry.execString) return String(entry.execString)
  try {
    if (entry.command && typeof entry.command.join === "function") return entry.command.join(" ")
  } catch (e) {
  }
  return ""
}

// Chromium's window name for a URL app: host, "_", then the path with each
// "/" as "_" (no query or fragment). "https://maps.google.com" -> "maps.google.com__".
function webAppKey(url) {
  var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)([^?#]*)/i.exec(String(url || ""))
  if (!m) return ""
  var host = m[1].replace(/^[^@]*@/, "").toLowerCase()
  var path = m[2] || "/"
  return host + "_" + path.replace(/\//g, "_")
}

// The URL an entry opens as a web app, if it is one.
function webAppUrl(entry) {
  var exec = execOf(entry)
  var m = /--app=("?)([^"\s]+)\1/.exec(exec) || /omarchy-launch-webapp\s+("?)([^"\s]+)\1/.exec(exec)
  return m ? m[2] : ""
}

function stripDesktop(id) { return lower(id).replace(/\.desktop$/, "") }

function entryFor(appId, entries) {
  var cls = lower(appId)
  if (!cls || !entries) return null
  var list = []
  for (var i = 0; i < entries.length; i++) if (entries[i]) list.push(entries[i])

  for (var a = 0; a < list.length; a++)
    if (stripDesktop(list[a].id) === cls) return list[a]
  for (var b = 0; b < list.length; b++)
    if (list[b].startupClass && lower(list[b].startupClass) === cls) return list[b]

  var crx = CRX_ID.exec(cls)
  if (crx) {
    for (var c = 0; c < list.length; c++) {
      if (lower(list[c].startupClass) === "crx_" + crx[1]) return list[c]
      if (execOf(list[c]).indexOf("--app-id=" + crx[1]) >= 0) return list[c]
    }
  }

  var web = URL_APP.exec(cls)
  if (web) {
    var want = web[1].replace(/_+$/, "")
    for (var d = 0; d < list.length; d++) {
      var key = webAppKey(webAppUrl(list[d]))
      if (key && key.replace(/_+$/, "") === want) return list[d]
    }
    // Then by host alone, as omamobile-launch finds a web app's window.
    for (var e = 0; e < list.length; e++) {
      var k = webAppKey(webAppUrl(list[e]))
      if (k && want.indexOf(k.split("_")[0] + "_") === 0) return list[e]
    }
  }

  // As omamobile-launch matches a window to an entry: the id's last
  // reverse-DNS part, then the program its Exec starts.
  for (var f = 0; f < list.length; f++) {
    var id = stripDesktop(list[f].id)
    var last = id.indexOf(".") >= 0 ? id.slice(id.lastIndexOf(".") + 1) : ""
    if (last.length > 2 && GENERIC.indexOf(last) < 0 && last === cls) return list[f]
  }
  for (var g = 0; g < list.length; g++) {
    var program = programOf(list[g])
    if (program && program === cls) return list[g]
  }
  return null
}

// Wrappers in an Exec that say nothing about the window's class.
var WRAPPERS = ["env", "sh", "bash", "setsid", "nohup", "uwsm-app", "uwsm", "systemd-run", "gtk-launch",
                "python", "python3", "flatpak", "xdg-terminal-exec", "omarchy-launch-tui",
                "omarchy-launch-or-focus", "omarchy-launch-or-focus-tui", "omarchy-launch-webapp"]
var GENERIC = ["desktop", "app", "application", "client", "gui", "main", "launcher"]

function programOf(entry) {
  var words = execOf(entry).split(/\s+/).filter(function(w) { return w.length > 0 })
  while (words.length && (words[0] === "env" || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[0]))) words.shift()
  if (!words.length) return ""
  var program = lower(words[0].replace(/^"|"$/g, "").replace(/^.*\//, ""))
  return WRAPPERS.indexOf(program) >= 0 ? "" : program
}

function appName(appId, title, entries) {
  var entry = entryFor(appId, entries)
  var name = entry ? String(entry.name || "").trim() : ""
  if (name) return name
  var t = String(title || "").trim()
  if (t) return t
  var c = String(appId || "").trim()
  return c || "App"
}

if (typeof module !== "undefined") {
  module.exports = { entryFor: entryFor, appName: appName, webAppKey: webAppKey, webAppUrl: webAppUrl }
}
