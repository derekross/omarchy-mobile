// SPDX-License-Identifier: MIT
// Pure logic for omamobile.home: the layout format, the widget registry, grid
// placement and the edits made in edit mode. Node runs it in
// test/home-model.js through the module.exports at the end, so nothing here
// touches QML.
//
// The layout, as stored in ~/.config/omamobile/home.json:
//
//   { "version": 1,
//     "grid": { "columns": 4, "rows": 6 },
//     "home": 0,                       // the page Home returns to
//     "nextId": 7,
//     "pages": [ { "items": [
//       { "id": "w1", "kind": "widget", "type": "clock", "x": 0, "y": 0, "w": 4, "h": 2, "config": {} },
//       { "id": "a2", "kind": "app", "app": "chromium", "x": 0, "y": 5, "w": 1, "h": 1 } ] } ] }
//
// x and y are grid cells from the top-left, w and h spans. Every function
// that changes a layout returns a new one and leaves its argument alone.

var VERSION = 1
var GRID = { columns: 4, rows: 6 }
var LIMITS = { minColumns: 3, maxColumns: 6, minRows: 4, maxRows: 8, maxPages: 12 }

// Widget types. min/max/size are in cells; `network` widgets reach the
// internet and stay off until the user turns them on in their settings.
var REGISTRY = {
  clock:   { name: "Clock",          icon: "󰥔", min: [2, 1], max: [4, 3], size: [4, 2], network: false,
             config: { timeFormat: "", dateFormat: "dddd d MMMM" } },
  weather: { name: "Weather",        icon: "󰖐", min: [2, 1], max: [4, 2], size: [4, 1], network: true,
             config: { enabled: false, useLocation: true, place: "", latitude: null, longitude: null, units: "celsius" } },
  battery: { name: "Battery",        icon: "󰁹", min: [1, 1], max: [4, 2], size: [2, 1], network: false, config: {} },
  media:   { name: "Media",          icon: "󰝚", min: [3, 1], max: [4, 2], size: [4, 1], network: false, config: {} },
  agenda:  { name: "Calendar",       icon: "󰃭", min: [2, 2], max: [4, 4], size: [4, 3], network: false, config: {} },
  notes:   { name: "Note",           icon: "󰎚", min: [1, 1], max: [4, 6], size: [2, 2], network: false, config: { text: "" } },
  toggles: { name: "Quick toggles",  icon: "󰔡", min: [2, 1], max: [4, 2], size: [4, 1], network: false, config: {} },
  command: { name: "Text or command", icon: "󰆍", min: [1, 1], max: [4, 6], size: [2, 1], network: false,
             config: { title: "", text: "", command: "", interval: 300, tap: "" } }
}

var WIDGET_ORDER = ["clock", "weather", "battery", "media", "agenda", "notes", "toggles", "command"]

// Built-ins from Simon Schubert's omarchy-widgets
// (https://github.com/SimonSchubert/omarchy-widgets, widgets/simonschubert/;
// MIT, Copyright (c) 2026 Simon Schubert and contributors). They used to be
// QML ports under ported/; they are now the OWL originals, run by our OWL
// runtime from the omamobile-owl-widgets package (type "owl:<author>.<name>",
// OwlCell.qml). This table, keyed by the old port's type, keeps what the
// home screen knew about each: its name, icon and sizes on our grid, and
// for the migration of old layouts (owlMigrate below) what the port could
// do (`source`, the hosts a network one talked to; PORT_COMMANDS, the ones
// that ran commands) and which of its settings become the OWL widget's
// state. `credit` is the original.
var PORTED = {
  airAndPollen: {"name": "Air and pollen", "icon": "󰵃", "min": [2, 1], "max": [4, 4], "size": [2, 1], "network": true, "config": {"enabled": false, "useLocation": true, "city": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "useLocation", "type": "boolean", "label": "Use my location", "description": "The phone's position (Location), rounded to about 1 km", "defaultValue": true}, {"key": "city", "type": "string", "label": "City when there is no location", "defaultValue": "", "description": "Empty: wttr.in guesses from your address"}], "source": "wttr.in, air-quality-api.open-meteo.com", "credit": "simonschubert/air-and-pollen"},
  analogClock: {"name": "Analog clock", "icon": "󰅐", "min": [1, 1], "max": [4, 4], "size": [2, 2], "network": false, "config": {"seconds": true}, "schema": [{"key": "seconds", "type": "boolean", "label": "Second hand", "defaultValue": true}], "credit": "simonschubert/analog-clock"},
  bundesliga: {"name": "Bundesliga", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/bundesliga"},
  calendar: {"name": "Month", "icon": "󰃭", "min": [2, 2], "max": [4, 4], "size": [2, 2], "network": false, "config": {"firstDay": "Monday"}, "schema": [{"key": "firstDay", "type": "enum", "label": "Weeks start on", "options": ["Monday", "Sunday"], "defaultValue": "Monday"}], "credit": "simonschubert/calendar"},
  championsLeague: {"name": "Champions League", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/champions-league"},
  countdowns: {"name": "Countdowns", "icon": "󰔟", "min": [2, 1], "max": [4, 4], "size": [2, 2], "network": false, "config": {"dates": ""}, "schema": [{"key": "dates", "type": "string", "label": "Dates (2026-12-24 christmas; ...)", "description": "YYYY-MM-DD and a label, separated by ;", "defaultValue": ""}], "credit": "simonschubert/countdown"},
  crypto: {"name": "Bitcoin (CoinGecko)", "icon": "󰠓", "min": [2, 1], "max": [4, 4], "size": [2, 2], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "coingecko.com", "credit": "simonschubert/crypto"},
  departures: {"name": "Departures", "icon": "󰞒", "min": [1, 1], "max": [4, 5], "size": [2, 1], "network": true, "config": {"enabled": false, "stopId": "", "stopName": "", "pickedFor": "", "stop": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "stop", "type": "string", "label": "Stop (a name to search for)", "defaultValue": ""}], "source": "transitous.org", "credit": "simonschubert/departures"},
  earthquakes: {"name": "Earthquakes", "icon": "󰇧", "min": [3, 2], "max": [4, 6], "size": [4, 2], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "earthquake.usgs.gov", "credit": "simonschubert/earthquakes"},
  exchangeRates: {"name": "Exchange rates", "icon": "󰁰", "min": [2, 1], "max": [4, 2], "size": [4, 1], "network": true, "config": {"enabled": false, "base": "USD", "currencies": "EUR, GBP, JPY"}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "base", "type": "string", "label": "Base currency", "defaultValue": "USD"}, {"key": "currencies", "type": "string", "label": "Quoted in (comma-separated)", "defaultValue": "EUR, GBP, JPY"}], "source": "frankfurter.dev", "credit": "simonschubert/exchange-rates"},
  feeds: {"name": "Feeds", "icon": "󰑫", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false, "feeds": "https://archlinux.org/feeds/news/, https://github.com/omacom/omarchy/releases.atom", "interval": 30}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "feeds", "type": "string", "label": "Feeds (URLs, comma-separated)", "defaultValue": "https://archlinux.org/feeds/news/, https://github.com/omacom/omarchy/releases.atom"}, {"key": "interval", "type": "integer", "label": "Refresh every (minutes)", "min": 10, "max": 1440, "defaultValue": 30}], "source": "the feeds you list", "credit": "simonschubert/feeds"},
  fetch: {"name": "Fetch", "icon": "󰣇", "min": [2, 2], "max": [4, 4], "size": [3, 2], "network": false, "config": {}, "credit": "simonschubert/fetch"},
  focus: {"name": "Focus", "icon": "󰔛", "min": [2, 2], "max": [4, 4], "size": [2, 2], "network": false, "config": {"minutes": 25}, "schema": [{"key": "minutes", "type": "integer", "label": "Session length (minutes)", "min": 5, "max": 60, "defaultValue": 25}], "credit": "simonschubert/focus"},
  forecast: {"name": "Forecast", "icon": "󰖕", "min": [3, 2], "max": [4, 4], "size": [4, 2], "network": true, "config": {"enabled": false, "useLocation": true, "city": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "useLocation", "type": "boolean", "label": "Use my location", "description": "The phone's position (Location), rounded to about 1 km", "defaultValue": true}, {"key": "city", "type": "string", "label": "City when there is no location", "defaultValue": "", "description": "Empty: wttr.in guesses from your address"}], "source": "wttr.in", "credit": "simonschubert/forecast"},
  freeGames: {"name": "Free games", "icon": "󰊗", "min": [3, 2], "max": [4, 4], "size": [4, 2], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "store.epicgames.com, store-site-backend-static.ak.epicgames.com", "credit": "simonschubert/free-games"},
  github: {"name": "GitHub", "icon": "", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "github.com", "credit": "simonschubert/github"},
  githubTrending: {"name": "GitHub trending", "icon": "󰊤", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "github.com", "credit": "simonschubert/github-trending"},
  habits: {"name": "Habits", "icon": "󰄴", "min": [2, 2], "max": [4, 6], "size": [4, 2], "network": false, "config": {"done": [], "habits": "exercise, read, drink water"}, "schema": [{"key": "habits", "type": "string", "label": "Habits (comma-separated)", "defaultValue": "exercise, read, drink water"}], "credit": "simonschubert/habits"},
  hackerNews: {"name": "Hacker News", "icon": "󰈙", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false, "interval": 15}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "interval", "type": "integer", "label": "Refresh every (minutes)", "min": 5, "max": 240, "defaultValue": 15}], "source": "news.ycombinator.com, hn.algolia.com", "credit": "simonschubert/hacker-news"},
  homeAssistant: {"name": "Home Assistant", "icon": "󰟐", "min": [2, 2], "max": [4, 6], "size": [4, 2], "network": true, "config": {"enabled": false, "url": "http://homeassistant.local:8123", "token": "", "entities": "sun.sun"}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "url", "type": "string", "label": "Server URL", "defaultValue": "http://homeassistant.local:8123"}, {"key": "token", "type": "string", "label": "Long-lived access token", "description": "Home Assistant: profile, security", "defaultValue": ""}, {"key": "entities", "type": "string", "label": "Entities (comma-separated)", "defaultValue": "sun.sun"}], "source": "your Home Assistant server", "credit": "simonschubert/home-assistant"},
  ifsc: {"name": "IFSC World Cup", "icon": "󰯊", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "ifsc.results.info, d1n1qj9geboqnb.cloudfront.net", "credit": "simonschubert/ifsc"},
  koiPond: {"name": "Koi pond", "icon": "󰈺", "min": [2, 2], "max": [4, 4], "size": [4, 2], "network": false, "config": {}, "credit": "simonschubert/koi-pond"},
  laLiga: {"name": "LaLiga", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/la-liga"},
  launches: {"name": "Rocket launches", "icon": "󱓞", "min": [2, 1], "max": [4, 4], "size": [4, 2], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "spacelaunchnow.me, ll.thespacedevs.com", "credit": "simonschubert/launches"},
  lavaLamp: {"name": "Lava lamp", "icon": "󰛨", "min": [1, 1], "max": [3, 4], "size": [2, 2], "network": false, "config": {"wax": 0}, "credit": "simonschubert/lava-lamp"},
  ligue1: {"name": "Ligue 1", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/ligue-1"},
  lobsters: {"name": "Lobsters", "icon": "󰈙", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false, "interval": 15}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "interval", "type": "integer", "label": "Refresh every (minutes)", "min": 5, "max": 240, "defaultValue": 15}], "source": "lobste.rs", "credit": "simonschubert/lobsters"},
  mlb: {"name": "MLB", "icon": "󰒷", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/mlb"},
  nba: {"name": "NBA", "icon": "󰒶", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/nba"},
  nhl: {"name": "NHL", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/nhl"},
  notifications: {"name": "Notifications", "icon": "󰂚", "min": [2, 2], "max": [4, 6], "size": [2, 3], "network": false, "config": {"hidden": []}, "credit": "simonschubert/notifications"},
  nowPlaying: {"name": "Now playing", "icon": "󰎆", "min": [2, 1], "max": [4, 3], "size": [4, 1], "network": false, "config": {}, "credit": "simonschubert/now-playing"},
  omarchyCommits: {"name": "Omarchy commits", "icon": "󰜘", "min": [3, 2], "max": [4, 6], "size": [3, 3], "network": true, "config": {"enabled": false, "repo": "omacom/omarchy", "branch": "quattro"}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "repo", "type": "string", "label": "Repository (owner/name)", "defaultValue": "omacom/omarchy"}, {"key": "branch", "type": "string", "label": "Branch", "defaultValue": "quattro"}], "source": "github.com", "credit": "simonschubert/omarchy-commits"},
  owl: {"name": "Owl", "icon": "󰈺", "min": [1, 1], "max": [4, 4], "size": [2, 2], "network": false, "config": {"born": 0, "fed": 0, "pets": 0}, "credit": "simonschubert/owl"},
  pictureOfTheDay: {"name": "Picture of the day", "icon": "󰋩", "min": [2, 2], "max": [4, 6], "size": [4, 2], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "wikimedia.org, commons.wikimedia.org", "credit": "simonschubert/picture-of-the-day"},
  planesOverhead: {"name": "Planes overhead", "icon": "󰀝", "min": [1, 1], "max": [4, 5], "size": [2, 2], "network": true, "config": {"enabled": false, "useLocation": true, "city": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "useLocation", "type": "boolean", "label": "Use my location", "description": "The phone's position (Location), rounded to about 1 km", "defaultValue": true}, {"key": "city", "type": "string", "label": "City when there is no location", "defaultValue": "", "description": "Empty: wttr.in guesses from your address"}], "source": "wttr.in, opensky-network.org, globe.adsbexchange.com", "credit": "simonschubert/planes-overhead"},
  premierLeague: {"name": "Premier League", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/premier-league"},
  releases: {"name": "Releases", "icon": "󰏗", "min": [3, 2], "max": [4, 6], "size": [4, 2], "network": true, "config": {"enabled": false, "repos": "omacom/omarchy, neovim/neovim, hyprwm/Hyprland, jesseduffield/lazygit, sxyazi/yazi"}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "repos", "type": "string", "label": "Repositories (owner/name, comma-separated)", "defaultValue": "omacom/omarchy, neovim/neovim, hyprwm/Hyprland, jesseduffield/lazygit, sxyazi/yazi"}], "source": "github.com", "credit": "simonschubert/releases"},
  serieA: {"name": "Serie A", "icon": "󰒸", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "espn.com, espncdn.com", "credit": "simonschubert/serie-a"},
  sunAndMoon: {"name": "Sun and moon", "icon": "󰖜", "min": [2, 2], "max": [4, 3], "size": [2, 2], "network": true, "config": {"enabled": false, "useLocation": true, "city": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "useLocation", "type": "boolean", "label": "Use my location", "description": "The phone's position (Location), rounded to about 1 km", "defaultValue": true}, {"key": "city", "type": "string", "label": "City when there is no location", "defaultValue": "", "description": "Empty: wttr.in guesses from your address"}], "source": "wttr.in", "credit": "simonschubert/sun-and-moon"},
  today: {"name": "Today", "icon": "󰖐", "min": [2, 1], "max": [4, 4], "size": [2, 2], "network": true, "config": {"enabled": false, "useLocation": true, "city": ""}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "useLocation", "type": "boolean", "label": "Use my location", "description": "The phone's position (Location), rounded to about 1 km", "defaultValue": true}, {"key": "city", "type": "string", "label": "City when there is no location", "defaultValue": "", "description": "Empty: wttr.in guesses from your address"}], "source": "wttr.in, yr.no", "credit": "simonschubert/today"},
  todo: {"name": "Todo", "icon": "󰝖", "min": [2, 2], "max": [4, 6], "size": [2, 3], "network": false, "config": {"path": "~/notes/todo.md"}, "schema": [{"key": "path", "type": "path", "label": "Checklist file", "defaultValue": "~/notes/todo.md"}], "credit": "simonschubert/todo"},
  uptime: {"name": "Uptime", "icon": "󰓅", "min": [3, 2], "max": [4, 6], "size": [4, 2], "network": true, "config": {"enabled": false, "sites": "https://archlinux.org, https://github.com", "interval": 5}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}, {"key": "sites", "type": "string", "label": "Sites (URLs, comma-separated)", "defaultValue": "https://archlinux.org, https://github.com"}, {"key": "interval", "type": "integer", "label": "Check every (minutes)", "min": 2, "max": 240, "defaultValue": 5}], "source": "the sites you list", "credit": "simonschubert/uptime"},
  wikipedia: {"name": "Wikipedia", "icon": "󰖬", "min": [3, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "wikimedia.org, en.m.wikipedia.org", "credit": "simonschubert/wikipedia"},
  worldClock: {"name": "World clock", "icon": "󰥔", "min": [2, 1], "max": [4, 4], "size": [4, 1], "network": false, "config": {"clocks": "New York=America/New_York, London=Europe/London, Tokyo=Asia/Tokyo"}, "schema": [{"key": "clocks", "type": "string", "label": "Clocks (Name=Area/City, comma-separated)", "description": "Time zones from the tz database, for example New York=America/New_York, London=Europe/London, Tokyo=Asia/Tokyo", "defaultValue": "New York=America/New_York, London=Europe/London, Tokyo=Asia/Tokyo"}], "credit": "simonschubert/world-clock"},
  xkcd: {"name": "xkcd", "icon": "󰭹", "min": [2, 2], "max": [4, 6], "size": [4, 3], "network": true, "config": {"enabled": false}, "schema": [{"key": "enabled", "type": "boolean", "label": "Use the internet", "description": "Off until you turn it on"}], "source": "xkcd.com", "credit": "simonschubert/xkcd"},
  yearProgress: {"name": "Year progress", "icon": "󰦖", "min": [2, 2], "max": [4, 4], "size": [2, 2], "network": false, "config": {}, "credit": "simonschubert/year-progress"}
}
var PORTED_ORDER = ["airAndPollen", "analogClock", "crypto", "bundesliga", "championsLeague", "countdowns", "departures", "earthquakes", "exchangeRates", "feeds", "fetch", "focus", "forecast", "freeGames", "github", "githubTrending", "habits", "hackerNews", "homeAssistant", "ifsc", "koiPond", "laLiga", "lavaLamp", "ligue1", "lobsters", "mlb", "calendar", "nba", "nhl", "notifications", "nowPlaying", "omarchyCommits", "owl", "pictureOfTheDay", "planesOverhead", "premierLeague", "releases", "launches", "serieA", "sunAndMoon", "today", "todo", "uptime", "wikipedia", "worldClock", "xkcd", "yearProgress"]
// The ports that ran commands of their own (scripts in their folders).
var PORT_COMMANDS = ["feeds", "fetch", "github", "ifsc", "notifications", "todo", "worldClock"]
// The ports that used the phone's position (GeoClue): the OWL originals get it
// as their `city` state (rounded coordinates), OwlCell does that.
var PORT_LOCATION = ["airAndPollen", "forecast", "planesOverhead", "sunAndMoon", "today"]
// Port settings that mean the same as an OWL original's persisted state.
var PORT_STATE = {
  airAndPollen: { city: "city" }, forecast: { city: "city" }, planesOverhead: { city: "city" },
  sunAndMoon: { city: "city" }, today: { city: "city" }, habits: { done: "done" },
  owl: { born: "born", fed: "fed", pets: "pets" }, lavaLamp: { wax: "wax" },
  departures: { stopId: "stopId", stopName: "stopName" }
}
var OWL_PREFIX = "owl:"

// The OWL built-in that replaces a port: "earthquakes" -> "owl:simonschubert.earthquakes".
function owlTypeFor(portType) {
  return has(PORTED, portType) ? OWL_PREFIX + PORTED[portType].credit.replace("/", ".") : ""
}
function isOwlType(type) { return typeof type === "string" && type.indexOf(OWL_PREFIX) === 0 }
// "owl:simonschubert.earthquakes" -> "simonschubert/earthquakes"
function owlStoreId(type) { return isOwlType(type) ? type.slice(OWL_PREFIX.length).replace(".", "/") : "" }

var OWL_BUILTINS = {}
var OWL_ORDER = PORTED_ORDER.map(function(portType) {
  var p = PORTED[portType]
  var location = PORT_LOCATION.indexOf(portType) >= 0
  var type = owlTypeFor(portType)
  OWL_BUILTINS[type] = {
    name: p.name, icon: p.icon, min: p.min, max: p.max, size: p.size, network: p.network,
    // Whether it may use the internet is part of its approval now.
    config: location ? { useLocation: true, locationText: "", owlState: {} } : { owlState: {} },
    schema: location ? [{ key: "useLocation", type: "boolean", label: "Use my location",
                          description: "The phone's position (Location), rounded to about 1 km", defaultValue: true }] : [],
    source: p.source || "", credit: p.credit, owl: p.credit, port: portType, location: location
  }
  return type
})
Object.keys(OWL_BUILTINS).forEach(function(type) { REGISTRY[type] = OWL_BUILTINS[type] })
WIDGET_ORDER = WIDGET_ORDER.concat(OWL_ORDER)

// What the old port could do, for approving its OWL original without asking
// (the home screen approves only what is no more than this):
// { commands, network, hosts (null: any it was given), files, notifications }.
function portCapabilities(portType) {
  var p = PORTED[portType]
  if (!p) return null
  var listed = String(p.source || "")
  var any = /you list|your /.test(listed)
  return {
    commands: PORT_COMMANDS.indexOf(portType) >= 0,
    network: !!p.network,
    hosts: !p.network ? [] : any ? null : listed.split(",").map(function(h) { return h.trim() }).filter(function(h) { return h }),
    files: false,
    notifications: portType === "notifications"
  }
}

// An old port's settings as its OWL original's: `useLocation` stays with the
// placement, settings with the same meaning seed its persisted state, and
// `enabled` (its internet switch) goes into the approval (portApprovals).
function owlConfigFor(portType, config) {
  var c = config && typeof config === "object" ? config : {}
  var out = { owlState: {} }
  if (PORT_LOCATION.indexOf(portType) >= 0) out.useLocation = c.useLocation !== false
  var map = PORT_STATE[portType] || {}
  Object.keys(map).forEach(function(key) {
    var v = c[key]
    if (v === undefined || v === null || v === "" || (Array.isArray(v) && !v.length)) return
    out.owlState[map[key]] = copy(v)
  })
  return out
}

// The ports a stored layout still places: [{ id, from, to, internet }], for
// the home screen to back the file up and approve what it may. `internet`
// is the port's own "Use the internet" switch (its `enabled`), not whether
// the original is approved: owl/catalog.js migrationApprovals decides that.
function portPlacements(raw) {
  var out = []
  ;(raw && Array.isArray(raw.pages) ? raw.pages : []).forEach(function(page) {
    ;(page && Array.isArray(page.items) ? page.items : []).forEach(function(item) {
      if (item && item.kind === "widget" && has(PORTED, item.type))
        out.push({ id: String(item.id || ""), from: item.type, to: owlTypeFor(item.type),
                   internet: !!(item.config && item.config.enabled === true) })
    })
  })
  return out
}

// What a fresh home gets, before the user changes anything: a clock and the
// first of these apps that are installed along the bottom row.
var DEFAULT_APPS = ["chromium", "Alacritty", "org.gnome.Nautilus", "omarchy-menu", "org.omarchy.settings",
                    "foot", "org.gnome.Calculator", "btop", "nvim", "localsend"]

function clampInt(value, lo, hi, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) n = fallback
  return Math.max(lo, Math.min(hi, n))
}

function copy(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value))
}

// The home clock's time format when the user has not typed one: the system's
// 12- or 24-hour choice, read from the bar's clockFormat in shell.json (what
// the bar shows). Quoted literals are ignored; "h" without "H", or an AM/PM
// marker, means 12-hour.
function systemTimeFormat(barFormat) {
  var f = String(barFormat || "").replace(/'[^']*'/g, "")
  var twelve = /a/i.test(f) || (/h/.test(f) && !/H/.test(f))
  return twelve ? "h:mm AP" : "HH:mm"
}

// The user's own widgets (WIDGETS.md) are stored as type "user:<id>". Their
// specs are not here but in a catalog the caller passes in (UserWidgets.js
// builds it from `omamobile-widget scan`), shaped like REGISTRY entries.
// A user widget the catalog doesn't know (not scanned yet, folder gone,
// manifest broken) stays on the layout with its stored size and settings:
// the home screen shows an error card for it, and nothing is lost while
// someone is half-way through an edit.
var USER_PREFIX = "user:"
var USER_ID_RE = /^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$/
var MISSING_SPEC = { name: "Missing widget", icon: "󰀦", min: [1, 1], max: [6, 8], size: [2, 2], network: false, config: {}, user: true }

function isUserType(type) {
  return typeof type === "string" && type.indexOf(USER_PREFIX) === 0
    && USER_ID_RE.test(type.slice(USER_PREFIX.length)) && type.length <= USER_PREFIX.length + 64
}

function has(map, key) {
  return !!map && Object.prototype.hasOwnProperty.call(map, key)
}

function widgetSpec(type, catalog) {
  if (isUserType(type)) {
    var id = type.slice(USER_PREFIX.length)
    return has(catalog, id) ? catalog[id] : null
  }
  return has(REGISTRY, type) ? REGISTRY[type] : null
}

// The spec an item is sized by: its own, or MISSING_SPEC for a user widget
// the catalog doesn't know.
function specFor(type, catalog) {
  return widgetSpec(type, catalog) || (isUserType(type) ? MISSING_SPEC : null)
}

function widgetTypes() {
  return WIDGET_ORDER.map(function(type) {
    var spec = REGISTRY[type]
    return { type: type, name: spec.name, icon: spec.icon, network: spec.network, w: spec.size[0], h: spec.size[1] }
  })
}

// The span limits of an item on a given grid.
function sizeLimits(item, grid, catalog) {
  if (!item || item.kind !== "widget") return { minW: 1, minH: 1, maxW: 1, maxH: 1 }
  var spec = specFor(item.type, catalog)
  if (!spec) return { minW: 1, minH: 1, maxW: 1, maxH: 1 }
  return {
    minW: Math.min(spec.min[0], grid.columns), minH: Math.min(spec.min[1], grid.rows),
    maxW: Math.min(spec.max[0], grid.columns), maxH: Math.min(spec.max[1], grid.rows)
  }
}

// ---------------------------------------------------------------- geometry

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

function fits(grid, rect) {
  return rect.x >= 0 && rect.y >= 0 && rect.w >= 1 && rect.h >= 1
    && rect.x + rect.w <= grid.columns && rect.y + rect.h <= grid.rows
}

// The item that rect would overlap on this list, skipping ignoreId.
function collision(items, rect, ignoreId) {
  for (var i = 0; i < items.length; i++) {
    if (items[i].id === ignoreId) continue
    if (overlaps(items[i], rect)) return items[i]
  }
  return null
}

function isFree(items, grid, rect, ignoreId) {
  return fits(grid, rect) && !collision(items, rect, ignoreId)
}

// The first free w x h spot in reading order, or null.
function freeSpot(items, grid, w, h) {
  for (var y = 0; y + h <= grid.rows; y++)
    for (var x = 0; x + w <= grid.columns; x++)
      if (isFree(items, grid, { x: x, y: y, w: w, h: h }, null)) return { x: x, y: y }
  return null
}

// A free spot as close as possible to (x, y), for a drop that lands on
// another item. Nearest by cell distance, reading order on ties.
function nearestFreeSpot(items, grid, x, y, w, h, ignoreId) {
  var best = null, bestDistance = Infinity
  for (var cy = 0; cy + h <= grid.rows; cy++) {
    for (var cx = 0; cx + w <= grid.columns; cx++) {
      if (!isFree(items, grid, { x: cx, y: cy, w: w, h: h }, ignoreId)) continue
      var d = Math.abs(cx - x) + Math.abs(cy - y)
      if (d < bestDistance) { best = { x: cx, y: cy }; bestDistance = d }
    }
  }
  return best
}

// The top-left cell under an item dragged so its top-left corner sits at
// (px, py) in a page of cellWidth x cellHeight cells: rounded to the nearest
// cell and kept on the grid.
function cellForPoint(px, py, cellWidth, cellHeight, w, h, grid) {
  return {
    x: clampInt(px / cellWidth, 0, grid.columns - w, 0),
    y: clampInt(py / cellHeight, 0, grid.rows - h, 0)
  }
}

// A drag that ends this far past a page edge (in cells) moves the item to
// the neighbouring page: -1 left, +1 right, 0 stay.
function pageShift(px, w, grid) {
  if (px < -0.5) return -1
  if (px + w > grid.columns + 0.5) return 1
  return 0
}

// ---------------------------------------------------------------- the layout

function emptyLayout(grid) {
  return { version: VERSION, grid: { columns: grid.columns, rows: grid.rows }, home: 0, nextId: 1, pages: [{ items: [] }] }
}

function takeId(layout, prefix) {
  var id = prefix + layout.nextId
  layout.nextId += 1
  return id
}

// availableApps: desktop ids that exist now (without ".desktop").
function defaultLayout(availableApps, grid) {
  grid = grid || GRID
  var layout = emptyLayout(grid)
  var have = {}
  ;(availableApps || []).forEach(function(id) { have[normalizeAppId(id)] = true })
  var clock = REGISTRY.clock
  layout.pages[0].items.push({ id: takeId(layout, "w"), kind: "widget", type: "clock",
                               x: 0, y: 0, w: Math.min(clock.size[0], grid.columns), h: clock.size[1],
                               config: copy(clock.config) })
  var x = 0
  for (var i = 0; i < DEFAULT_APPS.length && x < grid.columns; i++) {
    if (!have[DEFAULT_APPS[i]]) continue
    layout.pages[0].items.push({ id: takeId(layout, "a"), kind: "app", app: DEFAULT_APPS[i],
                                 x: x, y: grid.rows - 1, w: 1, h: 1 })
    x += 1
  }
  layout.pages.push({ items: [] })
  var battery = REGISTRY.battery, media = REGISTRY.media
  layout.pages[1].items.push({ id: takeId(layout, "w"), kind: "widget", type: "media", x: 0, y: 0,
                               w: Math.min(media.size[0], grid.columns), h: media.size[1], config: {} })
  layout.pages[1].items.push({ id: takeId(layout, "w"), kind: "widget", type: "battery", x: 0, y: media.size[1],
                               w: battery.size[0], h: battery.size[1], config: {} })
  return layout
}

function normalizeAppId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

// Anything read from disk goes through here: unknown or broken items are
// dropped, sizes are clamped to the widget's limits and the grid, and items
// that no longer fit or overlap move to the first free spot (on a later page
// if need be). Apps that aren't installed stay: they may come back (and the
// user sees them, dimmed, to remove them). Returns null for input that isn't
// a layout at all, so the caller can fall back to the default.
function normalize(raw, catalog) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.pages)) return null
  var rawGrid = raw.grid && typeof raw.grid === "object" ? raw.grid : {}
  var grid = {
    columns: clampInt(rawGrid.columns, LIMITS.minColumns, LIMITS.maxColumns, GRID.columns),
    rows: clampInt(rawGrid.rows, LIMITS.minRows, LIMITS.maxRows, GRID.rows)
  }
  return fitPages(raw, grid, catalog)
}

// raw's pages laid onto grid: every item cleaned and clamped to its limits
// (cleanItem), one that then overlaps another re-placed on the nearest page
// with room (placeOn).
function fitPages(raw, grid, catalog) {
  var layout = emptyLayout(grid)
  layout.pages = []
  layout.nextId = clampInt(raw.nextId, 1, 1e9, 1)
  var seen = {}
  var homeless = []

  var pages = raw.pages.slice(0, LIMITS.maxPages)
  for (var p = 0; p < pages.length; p++) {
    var page = { items: [] }
    layout.pages.push(page)
    var items = pages[p] && Array.isArray(pages[p].items) ? pages[p].items : []
    for (var i = 0; i < items.length; i++) {
      var item = cleanItem(items[i], grid, catalog)
      if (!item) continue
      if (!item.id || seen[item.id]) item.id = takeId(layout, item.kind === "app" ? "a" : "w")
      seen[item.id] = true
      if (isFree(page.items, grid, item, null)) page.items.push(item)
      else homeless.push({ page: p, item: item })
    }
  }
  if (layout.pages.length === 0) layout.pages.push({ items: [] })

  // Keep generated ids clear of the ones on disk.
  Object.keys(seen).forEach(function(id) {
    var n = parseInt(id.slice(1), 10)
    if (isFinite(n) && n >= layout.nextId) layout.nextId = n + 1
  })

  for (var h = 0; h < homeless.length; h++)
    layout = placeOn(layout, homeless[h].page, homeless[h].item)

  layout.home = clampInt(raw.home, 0, layout.pages.length - 1, 0)
  return layout
}

function cleanItem(raw, grid, catalog) {
  if (!raw || typeof raw !== "object") return null
  var item = { id: typeof raw.id === "string" ? raw.id : "", kind: raw.kind }
  if (raw.kind === "app") {
    item.app = normalizeAppId(raw.app)
    if (!item.app) return null
    item.w = 1; item.h = 1
  } else if (raw.kind === "widget") {
    // A port from before the OWL built-ins becomes its OWL original, in the
    // same place and size (portPlacements lists them).
    var portType = has(PORTED, raw.type) ? raw.type : ""
    var type = portType ? owlTypeFor(portType) : raw.type
    var spec = specFor(type, catalog)
    if (!spec) return null
    item.type = type
    var limits = sizeLimits(item, grid, catalog)
    item.w = clampInt(raw.w, limits.minW, limits.maxW, spec.size[0])
    item.h = clampInt(raw.h, limits.minH, limits.maxH, spec.size[1])
    var stored = portType ? owlConfigFor(portType, raw.config) : raw.config
    item.config = spec.user ? mergeUserConfig(spec.config, stored) : mergeConfig(spec.config, stored)
  } else {
    return null
  }
  item.x = clampInt(raw.x, 0, grid.columns - item.w, 0)
  item.y = clampInt(raw.y, 0, grid.rows - item.h, 0)
  return item
}

// The widget's defaults, overlaid with stored values of the same type.
function mergeConfig(defaults, stored) {
  var out = copy(defaults) || {}
  if (!stored || typeof stored !== "object") return out
  Object.keys(out).forEach(function(key) {
    var value = stored[key]
    if (value === undefined) return
    if (out[key] === null) {
      if (value === null || typeof value === "number") out[key] = value
    } else if (typeof value === typeof out[key]) {
      out[key] = value
    }
  })
  return out
}

// A user widget's settings: its manifest's defaults, overlaid with stored
// values (a stored value of another type than the default is dropped).
// Unlike built-ins, stored keys the manifest doesn't name are kept: a
// manifest being rewritten must not cost the user what they set.
function mergeUserConfig(defaults, stored) {
  var out = copy(defaults) || {}
  if (!stored || typeof stored !== "object" || Array.isArray(stored)) return out
  Object.keys(stored).forEach(function(key) {
    var value = stored[key]
    if (value === undefined || typeof value === "function") return
    if (has(out, key) && out[key] !== null && value !== null && typeof value !== typeof out[key]) return
    out[key] = copy(value)
  })
  return out
}

// Only the stored fields: edits leave notes such as `placed` on the
// objects they return, and those don't belong in the file.
function serialize(layout) {
  var out = { version: VERSION, grid: { columns: layout.grid.columns, rows: layout.grid.rows },
              home: layout.home, nextId: layout.nextId, pages: layout.pages.map(function(page) {
                return { items: page.items.map(function(item) {
                  var o = { id: item.id, kind: item.kind }
                  if (item.kind === "app") o.app = item.app
                  else { o.type = item.type }
                  o.x = item.x; o.y = item.y; o.w = item.w; o.h = item.h
                  if (item.kind === "widget") o.config = item.config
                  return o
                }) }
              }) }
  return JSON.stringify(out, null, 2) + "\n"
}

// Parse a file's text; null when it isn't a usable layout.
function parse(text, catalog) {
  var raw
  try { raw = JSON.parse(String(text || "")) } catch (e) { return null }
  return normalize(raw, catalog)
}

// ---------------------------------------------------------------- lookups

function findItem(layout, id) {
  for (var p = 0; p < layout.pages.length; p++) {
    var items = layout.pages[p].items
    for (var i = 0; i < items.length; i++)
      if (items[i].id === id) return { page: p, index: i, item: items[i] }
  }
  return null
}

// Apps on the home screen whose desktop entries are gone.
function missingApps(layout, availableApps) {
  var have = {}
  ;(availableApps || []).forEach(function(id) { have[normalizeAppId(id)] = true })
  var out = []
  layout.pages.forEach(function(page) {
    page.items.forEach(function(item) { if (item.kind === "app" && !have[item.app]) out.push(item.app) })
  })
  return out
}

// ---------------------------------------------------------------- edits

// Put an item (any x/y) on page `pageIndex`: where it says if that's free,
// else the first free spot there, else on the next page with room, else on
// a new page at the end. Returns the new layout; result.placed tells where.
function placeOn(layout, pageIndex, item) {
  var out = copy(layout)
  var it = copy(item)
  var start = clampInt(pageIndex, 0, out.pages.length - 1, 0)
  if (fits(out.grid, it) && isFree(out.pages[start].items, out.grid, it, null)) {
    out.pages[start].items.push(it)
    out.placed = { page: start, x: it.x, y: it.y }
    return out
  }
  for (var n = 0; n < out.pages.length; n++) {
    var p = (start + n) % out.pages.length
    if (n > 0 && p < start) break // only forward, then a new page
    var spot = freeSpot(out.pages[p].items, out.grid, it.w, it.h)
    if (spot) {
      it.x = spot.x; it.y = spot.y
      out.pages[p].items.push(it)
      out.placed = { page: p, x: it.x, y: it.y }
      return out
    }
  }
  if (out.pages.length >= LIMITS.maxPages) { out.placed = null; return out }
  it.x = 0; it.y = 0
  out.pages.push({ items: [it] })
  out.placed = { page: out.pages.length - 1, x: 0, y: 0 }
  return out
}

// A user widget can be added before the catalog knows it (just created,
// not scanned yet): it gets MISSING_SPEC's size until it is.
function addWidget(layout, pageIndex, type, catalog) {
  var spec = specFor(type, catalog)
  if (!spec) return null
  var out = copy(layout)
  var item = { id: takeId(out, "w"), kind: "widget", type: type, x: -1, y: -1,
               w: Math.min(spec.size[0], out.grid.columns), h: Math.min(spec.size[1], out.grid.rows),
               config: copy(spec.config) }
  out = placeOn(out, pageIndex, item)
  if (out.placed) out.placed.id = item.id
  return out
}

function addApp(layout, pageIndex, appId) {
  var app = normalizeAppId(appId)
  if (!app) return null
  var out = copy(layout)
  var item = { id: takeId(out, "a"), kind: "app", app: app, x: -1, y: -1, w: 1, h: 1 }
  out = placeOn(out, pageIndex, item)
  if (out.placed) out.placed.id = item.id
  return out
}

// Every placed copy of a widget type, from every page (a removed user widget).
function removeWidgetType(layout, type) {
  var out = copy(layout)
  out.pages.forEach(function(page) {
    page.items = page.items.filter(function(item) { return !(item.kind === "widget" && item.type === type) })
  })
  return out
}

function removeItem(layout, id) {
  var found = findItem(layout, id)
  if (!found) return layout
  var out = copy(layout)
  out.pages[found.page].items.splice(found.index, 1)
  return out
}

// Put back an item removeItem took out (Undo), given what findItem said
// about it before: on its old page, in its old cell when that is still free,
// else the nearest free cell there, else wherever placeOn finds room. null
// when it is still (or again) in the layout, or no longer fits the grid.
function restoreItem(layout, removed) {
  if (!removed || !removed.item || findItem(layout, removed.item.id)) return null
  var out = copy(layout)
  var it = copy(removed.item)
  if (!fits(out.grid, { x: 0, y: 0, w: it.w, h: it.h })) return null
  var page = clampInt(removed.page, 0, out.pages.length - 1, 0)
  var items = out.pages[page].items
  var spot = isFree(items, out.grid, it, null) ? { x: it.x, y: it.y }
    : nearestFreeSpot(items, out.grid, it.x, it.y, it.w, it.h, null)
  if (spot) {
    it.x = spot.x; it.y = spot.y
    items.splice(clampInt(removed.index, 0, items.length, items.length), 0, it)
    out.placed = { page: page, x: it.x, y: it.y }
    return out
  }
  out = placeOn(out, page, it)
  return out.placed ? out : null
}

// Move to (x, y) on page `pageIndex` (the same page or another). A spot that
// is taken or off the grid snaps to the nearest free one; with none free on
// that page the layout comes back unchanged. result.moved says if it moved.
function moveItem(layout, id, pageIndex, x, y) {
  var found = findItem(layout, id)
  if (!found) return layout
  var out = copy(layout)
  var page = clampInt(pageIndex, 0, out.pages.length - 1, found.page)
  var item = out.pages[found.page].items.splice(found.index, 1)[0]
  var rect = { x: clampInt(x, 0, out.grid.columns - item.w, 0), y: clampInt(y, 0, out.grid.rows - item.h, 0), w: item.w, h: item.h }
  // Dropped squarely onto an item of the same size on the same page: swap
  // the two, as app icons do on Android.
  var other = collision(out.pages[page].items, rect, id)
  if (other && page === found.page && other.w === item.w && other.h === item.h
      && other.x === rect.x && other.y === rect.y) {
    other.x = found.item.x; other.y = found.item.y
    item.x = rect.x; item.y = rect.y
    out.pages[page].items.push(item)
    out.moved = true
    return out
  }
  var spot = !other && fits(out.grid, rect) ? rect
    : nearestFreeSpot(out.pages[page].items, out.grid, rect.x, rect.y, item.w, item.h, id)
  if (!spot) { var same = copy(layout); same.moved = false; return same }
  item.x = spot.x; item.y = spot.y
  out.pages[page].items.push(item)
  out.moved = page !== found.page || spot.x !== found.item.x || spot.y !== found.item.y
  return out
}

// Resize a widget to w x h cells, clamped to its limits and the grid edge.
// A size that would overlap another item is refused (layout unchanged).
function resizeItem(layout, id, w, h, catalog) {
  var found = findItem(layout, id)
  if (!found || found.item.kind !== "widget") return layout
  var limits = sizeLimits(found.item, layout.grid, catalog)
  var rect = { x: found.item.x, y: found.item.y,
               w: clampInt(w, limits.minW, Math.min(limits.maxW, layout.grid.columns - found.item.x), found.item.w),
               h: clampInt(h, limits.minH, Math.min(limits.maxH, layout.grid.rows - found.item.y), found.item.h) }
  if (collision(layout.pages[found.page].items, rect, id)) return layout
  var out = copy(layout)
  out.pages[found.page].items[found.index].w = rect.w
  out.pages[found.page].items[found.index].h = rect.h
  return out
}

function setConfig(layout, id, patch, catalog) {
  var found = findItem(layout, id)
  if (!found || found.item.kind !== "widget") return layout
  var out = copy(layout)
  var target = out.pages[found.page].items[found.index]
  var merged = copy(target.config)
  Object.keys(patch || {}).forEach(function(key) { merged[key] = patch[key] })
  var spec = specFor(target.type, catalog)
  if (!spec) return layout
  target.config = spec.user ? mergeUserConfig(spec.config, merged) : mergeConfig(spec.config, merged)
  return out
}

function addPage(layout, at) {
  if (layout.pages.length >= LIMITS.maxPages) return layout
  var out = copy(layout)
  var index = clampInt(at === undefined ? out.pages.length : at, 0, out.pages.length, out.pages.length)
  out.pages.splice(index, 0, { items: [] })
  if (index <= layout.home) out.home += 1
  return out
}

// Removing a page removes what is on it; the last page stays.
function removePage(layout, index) {
  if (layout.pages.length <= 1 || index < 0 || index >= layout.pages.length) return layout
  var out = copy(layout)
  out.pages.splice(index, 1)
  if (out.home > index) out.home -= 1
  else if (out.home === index) out.home = Math.min(index, out.pages.length - 1)
  return out
}

function movePage(layout, from, to) {
  var n = layout.pages.length
  if (from < 0 || from >= n || to < 0 || to >= n || from === to) return layout
  var out = copy(layout)
  var page = out.pages.splice(from, 1)[0]
  out.pages.splice(to, 0, page)
  // The home page follows its page.
  var order = []
  for (var i = 0; i < n; i++) order.push(i)
  order.splice(to, 0, order.splice(from, 1)[0])
  out.home = order.indexOf(layout.home)
  return out
}

function setHome(layout, index) {
  if (index < 0 || index >= layout.pages.length) return layout
  var out = copy(layout)
  out.home = index
  return out
}

// Change the grid; everything is re-placed through normalize().
function setGrid(layout, columns, rows, catalog) {
  var raw = copy(layout)
  raw.grid = { columns: columns, rows: rows }
  return normalize(raw, catalog)
}

// ---------------------------------------------------------------- landscape

// The layout turned on its side, for a page wider than tall (TOUCH-PLAN
// 2.4, #85): the grid's columns and rows swap, each item's x and y swap,
// and its box is turned with them. `pages` gives the portrait and the
// landscape page in logical px ({ portrait: [w, h], landscape: [w, h] }):
// the landscape grid's cells are wide and short (173x87 against 120x151 on
// the Pixel 7 Pro), so the turned box's spans are scaled by the cells'
// ratio to keep about its size in pixels, which is what a widget's content
// was laid out for; with the spans merely swapped a 2x2 widget lost half
// its height and its rows landed on each other. Without `pages` the spans
// just swap. The result goes through the same clamp and re-placement as a
// loaded file (fitPages), so each widget keeps to its minimum and maximum
// and nothing overlaps; an item with no room on its page moves on. Derived
// for the view only: the file and the layout it came from stay portrait,
// and nothing here is ever saved.
function transposeLayout(layout, catalog, pages) {
  var grid = { columns: layout.grid.rows, rows: layout.grid.columns }
  var scaleW = 1, scaleH = 1
  if (pages && pages.portrait && pages.landscape) {
    var cellW = pages.portrait[0] / layout.grid.columns, cellH = pages.portrait[1] / layout.grid.rows
    var sideW = pages.landscape[0] / grid.columns, sideH = pages.landscape[1] / grid.rows
    if (cellW > 0 && cellH > 0 && sideW > 0 && sideH > 0) { scaleW = cellH / sideW; scaleH = cellW / sideH }
  }
  var raw = { version: VERSION, grid: grid, home: layout.home, nextId: layout.nextId, pages: [] }
  for (var p = 0; p < layout.pages.length; p++) {
    var items = []
    for (var i = 0; i < layout.pages[p].items.length; i++) {
      var item = layout.pages[p].items[i]
      var t = copy(item)
      t.x = item.y; t.y = item.x
      t.w = Math.max(1, Math.round(item.h * scaleW)); t.h = Math.max(1, Math.round(item.w * scaleH))
      items.push(t)
    }
    raw.pages.push({ items: items })
  }
  return fitPages(raw, grid, catalog)
}

// ---------------------------------------------------------------- widgets' pure parts

// Open-Meteo's WMO weather codes -> a glyph and words.
function weatherText(code) {
  var c = Number(code)
  if (c === 0) return { icon: "󰖙", text: "Clear" }
  if (c === 1 || c === 2) return { icon: "󰖕", text: c === 1 ? "Mostly clear" : "Partly cloudy" }
  if (c === 3) return { icon: "󰖐", text: "Overcast" }
  if (c === 45 || c === 48) return { icon: "󰖑", text: "Fog" }
  if (c >= 51 && c <= 57) return { icon: "󰖗", text: "Drizzle" }
  if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return { icon: "󰖖", text: "Rain" }
  if ((c >= 71 && c <= 77) || c === 85 || c === 86) return { icon: "󰖘", text: "Snow" }
  if (c >= 95 && c <= 99) return { icon: "󰖓", text: "Thunderstorm" }
  return { icon: "󰖐", text: "" }
}

// The two requests the weather widget makes, and only once it is turned on.
// Coordinates are rounded to 0.01° (about 1 km), which is all a forecast
// needs and all the service sees.
function geocodeUrl(place) {
  return "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name=" + encodeURIComponent(String(place || "").trim())
}

function forecastUrl(latitude, longitude, units) {
  var lat = Math.round(Number(latitude) * 100) / 100
  var lon = Math.round(Number(longitude) * 100) / 100
  return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
    + "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
    + (units === "fahrenheit" ? "&temperature_unit=fahrenheit" : "")
}

function parseGeocode(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  var r = data && Array.isArray(data.results) ? data.results[0] : null
  if (!r || typeof r.latitude !== "number" || typeof r.longitude !== "number") return null
  return { name: String(r.name || ""), latitude: r.latitude, longitude: r.longitude }
}

function parseForecast(text) {
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  var cur = data && data.current
  if (!cur || typeof cur.temperature_2m !== "number") return null
  var daily = data.daily || {}
  return {
    temperature: Math.round(cur.temperature_2m),
    code: cur.weather_code,
    high: daily.temperature_2m_max ? Math.round(daily.temperature_2m_max[0]) : null,
    low: daily.temperature_2m_min ? Math.round(daily.temperature_2m_min[0]) : null
  }
}

// The agenda widget runs
//   khal list --day-format "" --format "{start-date}\t{start-time}\t{title}" today 7d
// (khal is the local calendar Omarchy users sync with vdirsyncer): one event
// per line, all-day events with an empty time.
var AGENDA_ARGV = ["khal", "list", "--day-format", "", "--format", "{start-date}\t{start-time}\t{title}", "today", "7d"]

function parseAgenda(text, limit) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    if (!line.trim()) return
    var f = line.split("\t")
    if (f.length < 3) return
    out.push({ date: f[0].trim(), time: f[1].trim(), title: f.slice(2).join(" ").trim() })
  })
  return out.slice(0, limit || 8)
}

// A month grid for the calendar widget: 6 weeks of { day, inMonth, today },
// weeks starting on `firstDay` (0 Sunday, 1 Monday).
function monthGrid(year, month, today, firstDay) {
  var first = new Date(year, month, 1)
  var offset = (first.getDay() - (firstDay || 0) + 7) % 7
  var cells = []
  for (var i = 0; i < 42; i++) {
    var d = new Date(year, month, 1 - offset + i)
    cells.push({ day: d.getDate(), inMonth: d.getMonth() === month,
                 today: !!today && d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate() })
  }
  return cells
}

// The text/command widget: what to show from a command's output.
function commandText(output, maxLines) {
  var lines = String(output || "").replace(/\s+$/, "").split("\n")
  return lines.slice(0, Math.max(1, maxLines || 1)).join("\n")
}

// Every launch from the home screen goes through omamobile-launch (bin/):
// one app per screen, as on Android. Apps by desktop id; commands (a
// widget's host.launch, a text widget's tap) and links as argv.
var LAUNCH = "omamobile-launch"

function appLaunchArgv(desktopId) {
  return [LAUNCH, "app", String(desktopId || "")]
}

function commandLaunchArgv(argv) {
  return [LAUNCH, "cmd", "--"].concat((argv || []).map(String))
}

function urlLaunchArgv(url) {
  return [LAUNCH, "url", String(url || "")]
}

if (typeof module !== "undefined") {
  module.exports = {
    LAUNCH: LAUNCH, appLaunchArgv: appLaunchArgv, commandLaunchArgv: commandLaunchArgv, urlLaunchArgv: urlLaunchArgv,
    VERSION: VERSION, GRID: GRID, LIMITS: LIMITS, REGISTRY: REGISTRY, DEFAULT_APPS: DEFAULT_APPS,
    WIDGET_ORDER: WIDGET_ORDER, PORTED: PORTED, PORTED_ORDER: PORTED_ORDER,
    OWL_BUILTINS: OWL_BUILTINS, OWL_ORDER: OWL_ORDER, PORT_COMMANDS: PORT_COMMANDS, PORT_LOCATION: PORT_LOCATION, PORT_STATE: PORT_STATE,
    owlTypeFor: owlTypeFor, isOwlType: isOwlType, owlStoreId: owlStoreId, portCapabilities: portCapabilities,
    owlConfigFor: owlConfigFor, portPlacements: portPlacements,
    USER_PREFIX: USER_PREFIX, USER_ID_RE: USER_ID_RE, MISSING_SPEC: MISSING_SPEC, isUserType: isUserType,
    specFor: specFor, mergeUserConfig: mergeUserConfig, removeWidgetType: removeWidgetType,
    widgetSpec: widgetSpec, widgetTypes: widgetTypes, systemTimeFormat: systemTimeFormat, sizeLimits: sizeLimits,
    overlaps: overlaps, fits: fits, collision: collision, isFree: isFree, freeSpot: freeSpot,
    nearestFreeSpot: nearestFreeSpot, cellForPoint: cellForPoint, pageShift: pageShift,
    emptyLayout: emptyLayout, defaultLayout: defaultLayout, normalizeAppId: normalizeAppId,
    normalize: normalize, serialize: serialize, parse: parse, mergeConfig: mergeConfig,
    findItem: findItem, missingApps: missingApps,
    placeOn: placeOn, addWidget: addWidget, addApp: addApp, removeItem: removeItem, restoreItem: restoreItem,
    moveItem: moveItem, resizeItem: resizeItem, setConfig: setConfig,
    addPage: addPage, removePage: removePage, movePage: movePage, setHome: setHome, setGrid: setGrid, transposeLayout: transposeLayout,
    weatherText: weatherText, geocodeUrl: geocodeUrl, forecastUrl: forecastUrl,
    parseGeocode: parseGeocode, parseForecast: parseForecast, parseAgenda: parseAgenda, AGENDA_ARGV: AGENDA_ARGV,
    monthGrid: monthGrid, commandText: commandText
  }
}
