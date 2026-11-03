// SPDX-License-Identifier: MIT
// The media card at the top of the notification shade: which MPRIS player
// it shows, what it says and which art it may load. Pure functions over
// plain objects with MprisPlayer's property names (Quickshell.Services.Mpris),
// so MediaSource.qml and MediaCard.qml can use them and Node can test them
// in test/media-model.js through module.exports.
//
// The rule follows Omarchy's own media service (shell/plugins/services/
// media: MediaModel.js, Service.qml): playerctld is a proxy that repeats
// another player, so it comes last; a player with neither a title nor an
// identity is not shown. On top of that, a phone's media card: only a player
// that is playing or paused (not stopped) and has a title; a playing one
// before a paused one, and among those the one that started or changed
// track most recently (MediaSource.qml keeps that order).

// MprisPlaybackState.Enum: Stopped, Playing, Paused
var PLAYING = 1
var PAUSED = 2

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

function isProxy(player) {
  var dbus = str(player && player.dbusName).toLowerCase()
  var entry = str(player && player.desktopEntry).toLowerCase()
  return dbus.indexOf("playerctld") !== -1 || entry === "playerctld"
}

function key(player) {
  if (!player) return ""
  return str(player.dbusName || player.desktopEntry || player.identity)
}

function playing(player) {
  return !!player && (!!player.isPlaying || player.playbackState === PLAYING)
}

// Playing or paused with a title: what the card is for. A stopped player,
// or one that has published nothing to show, is left out.
function showable(player) {
  if (!player || !str(player.trackTitle)) return false
  return playing(player) || player.playbackState === PAUSED
}

// The player the card shows, or null. `order` maps key(player) to a number
// that grows each time a player starts playing or changes track
// (MediaSource.qml); a player never seen doing either counts as 0.
function pick(players, order) {
  var list = []
  var all = players || []
  for (var i = 0; i < all.length; i++) if (showable(all[i])) list.push(all[i])
  if (list.length === 0) return null
  var real = list.filter(function(p) { return !isProxy(p) })
  if (real.length > 0) list = real
  var rank = order || {}
  list.sort(function(a, b) {
    if (playing(a) !== playing(b)) return playing(a) ? -1 : 1
    return (rank[key(b)] || 0) - (rank[key(a)] || 0)
  })
  return list[0]
}

// The app's name, as Omarchy's media service names a player: its MPRIS
// identity ("Firefox", "Chromium", "mpv"), else its desktop entry, else the
// bus name without the MPRIS prefix and instance suffix.
function appName(player) {
  if (!player) return ""
  var identity = str(player.identity)
  if (identity) return identity
  var entry = str(player.desktopEntry)
  if (entry) return entry
  return str(player.dbusName).replace(/^org\.mpris\.MediaPlayer2\./, "").replace(/\.instance[0-9_]+$/, "")
}

function artist(player) {
  if (!player) return ""
  var a = str(player.trackArtist)
  if (a) return a
  var list = player.trackArtists
  if (list && list.length) {
    var out = []
    for (var i = 0; i < list.length; i++) if (str(list[i])) out.push(str(list[i]))
    return out.join(", ")
  }
  return ""
}

// The art the card may load, or "" for the app's icon instead. Local art
// (a file the player wrote, or a data: image) always; art on the network
// only where the caller allows it (the shade does, the lock does not), and
// never another scheme (qrc:, image:// providers, ftp:).
function artSource(url, allowRemote) {
  var u = str(url).trim()
  if (!u) return ""
  if (u.charAt(0) === "/") return "file://" + u.split("/").map(encodeURIComponent).join("/")
  var lower = u.toLowerCase()
  if (lower.indexOf("file:///") === 0) return u
  if (lower.indexOf("data:image/") === 0) return u
  if (allowRemote && (lower.indexOf("https://") === 0 || lower.indexOf("http://") === 0)) return u
  return ""
}

// Whether the card shows a seek bar: the player reports where it is and how
// long the track is.
function hasTimeline(player) {
  return !!player && !!player.positionSupported && !!player.lengthSupported
    && Number(player.length) > 0 && isFinite(Number(player.length))
}

// m:ss, or h:mm:ss from an hour; seconds as Quickshell reports them.
function timeText(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var ss = (r < 10 ? "0" : "") + r
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

function fraction(position, length) {
  var l = Number(length)
  if (!(l > 0) || !isFinite(l)) return 0
  return Math.max(0, Math.min(1, (Number(position) || 0) / l))
}

function canPlayPause(player) {
  return !!player && (!!player.canTogglePlaying || !!player.canPlay || !!player.canPause)
}

// The label the play/pause button reads out (and its glyph's meaning).
function playPauseName(player) {
  return playing(player) ? "Pause" : "Play"
}

// What a screen reader hears for the card.
function accessibleName(player) {
  if (!player) return ""
  var parts = [str(player.trackTitle), artist(player), appName(player)].filter(function(p) { return !!p })
  return (playing(player) ? "Playing: " : "Paused: ") + parts.join(", ")
}

// A pattern for omarchy-hyprland-focus-app, which matches window classes
// with jq's test(): the name taken literally, case aside.
function focusPattern(name) {
  var n = str(name)
  if (!n) return ""
  return n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// The names to try, in order, when the card is tapped: the desktop entry
// (a window's class is usually that), then the identity.
function focusNames(player) {
  if (!player) return []
  var out = []
  var entry = str(player.desktopEntry)
  var identity = str(player.identity)
  if (entry) out.push(focusPattern(entry))
  if (identity && identity.toLowerCase() !== entry.toLowerCase()) out.push(focusPattern(identity))
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    PLAYING: PLAYING,
    PAUSED: PAUSED,
    isProxy: isProxy,
    key: key,
    playing: playing,
    showable: showable,
    pick: pick,
    appName: appName,
    artist: artist,
    artSource: artSource,
    hasTimeline: hasTimeline,
    timeText: timeText,
    fraction: fraction,
    canPlayPause: canPlayPause,
    playPauseName: playPauseName,
    accessibleName: accessibleName,
    focusPattern: focusPattern,
    focusNames: focusNames
  }
}
