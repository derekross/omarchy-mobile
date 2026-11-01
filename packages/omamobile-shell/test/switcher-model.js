// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.switcher/SwitcherModel.js: the app names
// on recent apps' cards. Run by test/all. The entries stand in for
// Quickshell's DesktopEntry objects.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.switcher/SwitcherModel.js"))

const ENTRIES = [
  { id: "org.omamobile.Phone", name: "Phone", startupClass: "", execString: "omatel" },
  { id: "org.omamobile.Messages", name: "Messages", startupClass: "", execString: "omatel --messages" },
  // Installed from Chromium: the window is chrome-<id>-Default.
  { id: "chrome-cinhimbnkkaeohfgghhklpknlkffjgod-Default", name: "YouTube Music",
    startupClass: "crx_cinhimbnkkaeohfgghhklpknlkffjgod",
    execString: "/usr/bin/chromium --profile-directory=Default --app-id=cinhimbnkkaeohfgghhklpknlkffjgod" },
  // The same kind, but only its Exec names the app id.
  { id: "Some Store App", name: "Store App", startupClass: "",
    command: ["/usr/bin/chromium", "--profile-directory=Default", "--app-id=hlefccemhleoejnejfpmmdcpnhdmpomj"] },
  // Omarchy's web apps: omarchy-launch-webapp URL.
  { id: "Google Messages", name: "Google Messages", startupClass: "", execString: "omarchy-launch-webapp https://messages.google.com/web/conversations" },
  { id: "Google Maps", name: "Google Maps", startupClass: "", execString: "omarchy-launch-webapp https://maps.google.com" },
  { id: "WhatsApp", name: "WhatsApp", startupClass: "", execString: "chromium --app=\"https://web.whatsapp.com/\"" },
  { id: "foot", name: "Foot", startupClass: "foot", execString: "foot" },
  { id: "com.mitchellh.ghostty", name: "Ghostty", startupClass: "", execString: "ghostty" },
  null
]

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("org.omamobile.Phone is Phone", () => {
  assert.strictEqual(M.appName("org.omamobile.Phone", "Phone", ENTRIES), "Phone")
})

test("org.omamobile.Messages is Messages, not 'org.omamobile.Messages  Messages'", () => {
  assert.strictEqual(M.appName("org.omamobile.Messages", "Messages", ENTRIES), "Messages")
})

test("a Chromium app is its desktop entry's name", () => {
  assert.strictEqual(M.appName("chrome-cinhimbnkkaeohfgghhklpknlkffjgod-Default", "YouTube Music - Song", ENTRIES), "YouTube Music")
  assert.strictEqual(M.appName("chrome-hlefccemhleoejnejfpmmdcpnhdmpomj-Default", "x", ENTRIES), "Store App", "by --app-id in Exec")
})

test("an Omarchy web app by its URL", () => {
  assert.strictEqual(M.webAppKey("https://messages.google.com/web/conversations"), "messages.google.com__web_conversations")
  assert.strictEqual(M.webAppKey("https://maps.google.com"), "maps.google.com__")
  assert.strictEqual(M.webAppKey("https://web.whatsapp.com/?x=1#y"), "web.whatsapp.com__")
  assert.strictEqual(M.appName("chrome-messages.google.com__web_conversations-Default", "Messages", ENTRIES), "Google Messages")
  assert.strictEqual(M.appName("chrome-maps.google.com__-Default", "Google Maps", ENTRIES), "Google Maps")
  assert.strictEqual(M.appName("chrome-web.whatsapp.com__-Default", "(3) WhatsApp", ENTRIES), "WhatsApp", "a quoted --app=")
})

test("by StartupWMClass, ignoring case and .desktop", () => {
  assert.strictEqual(M.appName("Foot", "~", ENTRIES), "Foot")
  assert.strictEqual(M.appName("com.mitchellh.ghostty", "~", [{ id: "com.mitchellh.ghostty.desktop", name: "Ghostty" }]), "Ghostty")
})

test("as omamobile-launch: a web app by host, the id's last part, Exec's program", () => {
  assert.strictEqual(M.appName("chrome-maps.google.com__maps_place-Default", "Maps", ENTRIES), "Google Maps", "by host")
  assert.strictEqual(M.appName("Nautilus", "Home", [{ id: "org.gnome.Nautilus", name: "Files" }]), "Files")
  assert.strictEqual(M.appName("imv", "a.png", [{ id: "imv-viewer", name: "Image viewer", execString: "env A=1 /usr/bin/imv %F" }]), "Image viewer")
  assert.strictEqual(M.appName("app", "Title", [{ id: "com.example.App", name: "Example" }]), "Title", "a generic last part is no match")
  assert.strictEqual(M.appName("uwsm-app", "Title", [{ id: "x", name: "X", execString: "uwsm-app -- foo" }]), "Title", "a wrapper is no match")
})

test("no entry: the title, then the class, then App", () => {
  assert.strictEqual(M.appName("chrome-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-Default", "Unknown app", ENTRIES), "Unknown app")
  assert.strictEqual(M.appName("org.example.Thing", "  ", ENTRIES), "org.example.Thing")
  assert.strictEqual(M.appName("", "", ENTRIES), "App")
  assert.strictEqual(M.appName("org.omamobile.Phone", "Phone", null), "Phone")
  assert.strictEqual(M.appName("x", "t", [{ id: "x", name: "" }]), "t", "an entry with no name")
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - switcher model: " + name) } catch (e) { failed++; console.log("not ok - switcher model: " + name + "\n  " + (e.stack || e)) }
}
process.exit(failed ? 1 : 0)
