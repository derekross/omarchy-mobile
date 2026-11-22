// SPDX-License-Identifier: MIT
// The Mobile network page's pure parts: omamobile-mobile-network's status
// in, the rows the page shows out. No QML here, so test/mobile-network-model.js
// runs it under Node through the module.exports below.

var STATUS_ARGV = ["omamobile-mobile-network", "status"]
var REBOOT_ARGV = ["omamobile-reboot"]
var APN = /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$/

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

function dataArgv(on) { return ["omamobile-mobile-network", "data", on ? "on" : "off"] }
function roamingArgv(on) { return ["omamobile-mobile-network", "roaming", on ? "on" : "off"] }
function apnArgv(value) { return ["omamobile-mobile-network", "apn", value] }
function attachArgv(value) { return ["omamobile-mobile-network", "attach-apn", value] }
function modemArgv(on) { return ["omamobile-mobile-network", "modem", on ? "on" : "off"] }

// The Modem switch (omamobile-modem-switch's status in s.modem, or null when
// it isn't installed): whether the stack starts at boot, and what this boot
// does about it. Shown only where something starts the modem at boot
// (available). Off never stops a running modem (its sleep block lasts until
// the reboot anyway), so off with the modem up says "after a restart", and
// "can't sleep" follows the sleep block itself.
function modemSwitch(m) {
  if (!m || m.available !== true) return { shown: false }
  var on = m.enabled === true
  var note
  if (!m.provisioned) note = "Not set up on this phone yet"
  else if (on && m.running) note = "On"
  else if (on && m.started) note = "On after a restart"
  else if (on) note = "Starting"
  else if (m.sleep_blocked) note = "Off after a restart. Until then the phone can't sleep."
  else if (m.running || m.started) note = "Off after a restart."
  else note = "Off. The phone can sleep; no calls, texts or mobile data."
  return { shown: true, on: on, note: note, restart: m.restart_needed === true }
}

// What the override field accepts: "" or "auto" (from the SIM), or a plain
// carrier APN (the helper checks again as root).
function apnValue(text) {
  var s = String(text || "").trim()
  if (s === "" || s.toLowerCase() === "auto") return "auto"
  return APN.test(s) && s.length <= 99 ? s : null
}

var REGISTRATION = {
  "home": "Connected", "roaming": "Roaming", "searching": "Searching for a network",
  "not-registered": "Not registered", "denied": "Registration refused by the network",
  "unknown": "Starting"
}
var SIM = {
  "ready": "", "absent": "No SIM card", "pin": "The SIM asks for its PIN",
  "puk": "The SIM is PUK-blocked", "network-locked": "The SIM is locked to another network",
  "error": "SIM card error", "detected": "Reading the SIM", "unknown": "Reading the SIM"
}
var SOURCES = {
  "manual": "Typed in settings", "override": "Chosen from your SIM",
  "carrier-database": "Chosen from your SIM", "none": "None found for this SIM"
}

// The page as one object: whether it has a modem at all, a headline, and
// the rows. s: omamobile-mobile-network status (or null while it loads).
function view(s) {
  if (!s) return { state: "loading", title: "Mobile network", body: "Reading the modem..." }
  if (!s.installed)
    return { state: "none", title: "No modem", body: "This phone's modem software isn't installed." }
  var modem = modemSwitch(s.modem)
  // Switched on, and the modem or its phone service still coming up: say
  // so, rather than the off text, until the service reports (about two
  // minutes from the switch, as at boot).
  var m = s.modem || {}
  if (!s.running && modem.shown && modem.on && m.provisioned && (m.running || !m.started))
    return { state: "off", title: "Starting the modem",
             body: "Registering with the network. This takes a minute or two.",
             modem: modem }
  if (!s.running)
    return { state: "off", title: "Mobile network is off",
             body: modem.shown && !modem.on
               ? "The modem is turned off."
               : "The modem service isn't running. It starts with the phone once the modem is set up.",
             modem: modem }
  var sim = s.sim || {}
  var simProblem = SIM[sim.state] !== undefined ? SIM[sim.state] : "Reading the SIM"
  var registered = s.registration === "home" || s.registration === "roaming"
  var title = registered ? (s.carrier || "Mobile network") : (simProblem || REGISTRATION[s.registration] || "Starting")
  var status = registered ? (REGISTRATION[s.registration] + (s.tech ? " · " + s.tech : "")) : ""
  if (s.stage && s.stage !== "running" && !registered) status = "Setting up the modem"
  var apn = s.apn || {}
  var data = s.data || {}
  var dataText
  if (data.available === false) dataText = "Unavailable: no APN for this SIM. Type your carrier's APN below."
  else if (!data.enabled) dataText = "Off"
  else dataText = data.up ? "On" : "Starting"
  return {
    state: "ready",
    title: title,
    body: status,
    signal: signalText(s.signal, registered),
    signalBars: registered && s.signal >= 0 ? Math.min(4, Math.floor(s.signal / 25) + (s.signal > 0 ? 1 : 0)) : -1,
    dataOn: !!data.enabled,
    dataAvailable: data.available !== false,
    dataText: dataText,
    roamingAllowed: !s.roaming || s.roaming.allowed !== false,
    roamingText: s.roaming && s.roaming.now
      ? (s.roaming.allowed === false ? "Roaming now: mobile data paused" : "Roaming now")
      : "Use mobile data when roaming",
    apnInUse: apn.in_use || "",
    apnSource: SOURCES[apn.source] || "",
    apnConfigured: apn.configured && apn.configured !== "auto" ? apn.configured : "",
    attachText: attachText(apn),
    attachConfigured: apn.attach_configured && apn.attach_configured !== "auto" ? apn.attach_configured : "",
    pinText: pinText(sim),
    modem: modem
  }
}

// The attach APN (the one the modem registers with), for the Advanced part.
// "none" (sitd's attach_apn = none): no attach APN is sent, and the modem
// attaches with its carrier profile, as on Verizon's network.
function attachText(apn) {
  if (apn.attach_source === "same" || (!apn.attach_source && apn.attach_in_use && apn.attach_in_use === apn.in_use))
    return "Same as the internet APN"
  if (!apn.attach_in_use) return apn.source === "none" ? "The modem's own" : "Not chosen yet"
  var source = SOURCES[apn.attach_source] ? "  ·  " + SOURCES[apn.attach_source] : ""
  if (String(apn.attach_in_use).toLowerCase() === "none") return "Not sent: the carrier profile's own" + source
  return apn.attach_in_use + source
}

function signalText(signal, registered) {
  if (!registered) return "No signal"
  if (typeof signal !== "number" || signal < 0) return "Not reported yet"
  return signal + "%"
}

function pinText(sim) {
  if (sim.state === "pin" || sim.pin_lock === "on")
    return "On. This phone can't enter a SIM PIN yet: turn the lock off in another phone."
  if (sim.pin_lock === "off") return "Off"
  return "Unknown"
}

// After an APN change: it applies at the next start of the modem service,
// which needs a restart of the phone.
function apnSavedText(value, attach) {
  var what = attach ? "attach APN" : "APN"
  return value === "auto"
    ? "Saved: the " + what + " comes from your SIM after a restart."
    : "Saved: " + value + " is the " + what + " after a restart."
}

if (typeof module !== "undefined") {
  module.exports = { STATUS_ARGV: STATUS_ARGV, REBOOT_ARGV: REBOOT_ARGV, parseJson: parseJson,
                     dataArgv: dataArgv, roamingArgv: roamingArgv, apnArgv: apnArgv, attachArgv: attachArgv, apnValue: apnValue,
                     modemArgv: modemArgv, modemSwitch: modemSwitch,
                     attachText: attachText,
                     view: view, signalText: signalText, pinText: pinText, apnSavedText: apnSavedText }
}
