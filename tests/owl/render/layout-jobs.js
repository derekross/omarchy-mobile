// SPDX-License-Identifier: MIT
// The before/after pictures of the OWL built-ins: the owner's layout shape
// (owner-layout.json, the same as test/home-model.js's fixture) drawn with
// main's QML ports, and migrated (HomeModel.parse) with the OWL originals,
// approved as the migration would (owl/catalog.js portApproval), with
// made-up data for them.
//   node layout-jobs.js <side: before|after> <out dir> <store widgets dir> <theme>
"use strict"
const fs = require("fs"), path = require("path")
const [side, out, storeDir, theme] = process.argv.slice(2)
const H = require(path.resolve(__dirname, "../../../packages/omamobile-shell/plugins/omamobile.home/HomeModel.js"))
const { load } = require(path.resolve(__dirname, "../../../packages/omamobile-shell/test/owl-load.js"))
const K = load("catalog.js")
const owner = require("./owner-layout.json")
const cases = require("../cases.json")
const T = cases.time

// Open-Meteo geocoding and forecast answers, made up (our copies of today and forecast use them).
const geo = { results: [{ name: "Sample Town", latitude: 52.52, longitude: 13.4, country: "Example", country_code: "EX" }] }
const day0 = T - (T % 86400)
const hourTimes = Array.from({ length: 72 }, (_, i) => day0 + i * 3600)
const meteo = {
  current: { time: T, temperature_2m: 14.2, apparent_temperature: 12.1, relative_humidity_2m: 70, is_day: 1, weather_code: 2, precipitation: 0,
             pressure_msl: 1016, wind_speed_10m: 11, wind_direction_10m: 270 },
  hourly: { time: hourTimes, temperature_2m: hourTimes.map((t, i) => 9 - Math.floor(i / 24) + [0, -1, -1, 2, 5, 6, 3, 1][Math.floor((i % 24) / 3)]),
            precipitation_probability: hourTimes.map(() => 10), weather_code: hourTimes.map(() => 2), is_day: hourTimes.map((t, i) => (i % 24) >= 7 && (i % 24) < 18 ? 1 : 0),
            uv_index: hourTimes.map(() => 2), visibility: hourTimes.map(() => 10000) },
  daily: { time: [0, 1, 2].map((i) => day0 + i * 86400), weather_code: [2, 3, 61], temperature_2m_max: [16, 15, 14], temperature_2m_min: [9, 8, 7],
           sunrise: [0, 1, 2].map((i) => day0 + i * 86400 + 5 * 3600 + 26 * 60), sunset: [0, 1, 2].map((i) => day0 + i * 86400 + 16 * 3600 + 18 * 60),
           precipitation_probability_max: [10, 20, 60], precipitation_sum: [0, 0.4, 3] }
}
const prices = Array.from({ length: 42 }, (_, i) => 61000 + i * 80 + Math.round(Math.sin(i / 3) * 400))
const fixtures = {
  "owl:simonschubert.crypto": { market: { code: 200, text: JSON.stringify([{ id: "bitcoin", symbol: "btc", current_price: 64250, low_24h: 63480, high_24h: 64420,
    price_change_percentage_1h_in_currency: 0.21, price_change_percentage_24h_in_currency: 1.42, price_change_percentage_7d_in_currency: 3.1,
    market_cap: 1265000000000, total_volume: 31200000000, circulating_supply: 19750000, max_supply: 21000000, ath: 73700, ath_date: "2024-03-14T07:10:36Z",
    sparkline_in_7d: { price: prices } }]) } },
  "owl:simonschubert.today": { now: { value: T }, geo: { text: JSON.stringify(geo) }, wx: { text: JSON.stringify(meteo) } },
  "owl:simonschubert.forecast": { geo: { text: JSON.stringify(geo) }, w: { text: JSON.stringify(meteo) } },
  "owl:simonschubert.earthquakes": cases.widgets.find((c) => c.id === "simonschubert/earthquakes").sources,
  "owl:simonschubert.habits": cases.widgets.find((c) => c.id === "simonschubert/habits").sources
}

const layout = side === "after" ? H.parse(JSON.stringify(owner), {}) : owner
const widgets = [], approvals = {}
if (side === "after") {
  for (const p of H.portPlacements(owner)) {
    // What omamobile-owl-widgets ships: our own copy (overrides/) where it keeps one.
    const ours = path.resolve(__dirname, "../../../packages/omamobile-owl-widgets/overrides", H.owlStoreId(p.to), "widget.owl")
    const text = fs.readFileSync(fs.existsSync(ours) ? ours : path.join(storeDir, H.owlStoreId(p.to), "widget.owl"), "utf8")
    widgets.push({ id: p.to, text, fixture: { sources: fixtures[p.to] || {} } })
    const v = K.portApproval(H.portCapabilities(p.from), K.describe(p.to, text, H.GRID, 908 / 6, 480 / 6 / 69), p.internet)
    if (v.approve) approvals[p.to] = v.approve
  }
}
const shots = layout.pages.map((page, i) => ({ png: path.join(out, `${side}-page${i + 1}-${theme}.png`), items: page.items, page: i, pages: layout.pages.length }))
console.log(JSON.stringify({ side, time: T, widgets, approvals, shots }))
