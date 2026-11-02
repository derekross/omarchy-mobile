// SPDX-License-Identifier: MIT
// Our copies of the store's weather widgets (overrides/) against made-up
// Open-Meteo answers, with omamobile-shell's OWL runtime: each compiles,
// talks only to Open-Meteo's hosts (and its own extra services), builds the
// URLs we expect from a typed city or the phone's "lat,lon", maps the JSON
// to what it draws (WMO codes to words, units, the place), and says
// "set a city or turn on Location" with neither. Nothing reaches the network.
//
//   node test/open-meteo.js <omamobile-shell's test dir>
"use strict"
const fs = require("fs"), path = require("path")
const { load } = require(path.resolve(process.argv[2], "owl-load.js"))
const V = load("values.js"), C = load("compiler.js"), R = load("runtime.js"), P = load("phone.js"), B = load("builtins.js")
const here = path.resolve(__dirname, "..")

let failures = 0
function check(ok, what) {
  if (ok) console.log("ok - " + what)
  else { console.log("not ok - " + what); failures++ }
}

const T = 1793620800   // 2026-11-02 12:00 UTC, made up
process.env.TZ = "UTC"

// A widget with state and source values set as the phone would: the texts
// it shows (tile and screen) and the URLs its sources would fetch now.
function run(id, state, sources) {
  B.setFirstDayOfWeek(0)
  const program = C.compile(fs.readFileSync(path.join(here, "overrides", id, "widget.owl"), "utf8"))
  const host = { theme: () => 0xff808080, tile: (n) => ({ cols: 4, rows: 4, tileWidth: 300, tileHeight: 300, screenWidth: 480, screenHeight: 1000 })[n] ?? null,
                 act() {}, runInto() {}, report() {}, changed() {} }
  const inst = new R.Instance(program, host, {})
  inst.time = 0
  program.globals.forEach((g, slot) => {
    if (g.type === "source" && g.kind === "clock") inst.values[slot] = T
    if (g.type === "state" && state && g.name in state) inst.values[slot] = V.fromPlain(state[g.name])
    if (g.type === "source" && sources && g.name in sources) inst.values[slot] = V.fromPlain(sources[g.name])
  })
  inst.invalidate()
  const texts = []
  const walk = (items, env) => items.forEach((n) => {
    if (n.t === "lets") return walk(n.children, env.withLets(n.values))
    if (n.t === "if") { let c = false; try { c = V.truthy(C.evaluate(n.cond, env)) } catch (e) {} return walk(c ? n.then : n.otherwise, env) }
    if (n.t === "for") { let l = []; try { l = V.listOf(C.evaluate(n.list, env)) } catch (e) {} return l.forEach((it, i) => walk(n.body, env.inner([it, i]))) }
    if (n.t === "use") {
      const args = n.args.map((a) => { try { return C.evaluate(a, env) } catch (e) { return null } })
      return walk(n.body, new C.Env(env.ctx, new C.Env(env.ctx, null, []), args))
    }
    if (n.t === "el") {
      if (n.kind === "Text" && n.props.text) { try { texts.push(V.display(C.evaluate(n.props.text, env))) } catch (e) { texts.push("ERROR " + C.messageOf(e)) } }
      if (n.kind !== "Canvas") walk(n.children || [], env)
    }
  })
  walk(program.root, inst.env)
  if (program.screen) walk(program.screen, inst.env)
  const urls = {}
  inst.sources().forEach((s) => { if (s.kind === "http") urls[s.name] = s.arg() })
  const value = (name) => V.toPlain(inst.read(program.globals.findIndex((g) => g && g.name === name)))
  return { texts, all: texts.join(" | "), urls, caps: P.capabilities(program), program, value }
}

const ok = (out) => ({ ok: true, code: 200, out, err: "" })

// Made-up answers, in Open-Meteo's shapes.
const geocode = { results: [
  { name: "Sample Town", latitude: 40.123456, longitude: -77.654321, country: "United States", country_code: "US", admin1: "Pennsylvania" },
  { name: "Sample Town", latitude: 51.5, longitude: -0.12, country: "United Kingdom", country_code: "GB", admin1: "England" }] }
const hours = Array.from({ length: 72 }, (_, i) => T - 12 * 3600 + i * 3600)
const forecast = {
  current: { time: T, temperature_2m: 14.4, apparent_temperature: 12.2, relative_humidity_2m: 70, is_day: 1, weather_code: 2,
             precipitation: 0.2, pressure_msl: 1016.3, wind_speed_10m: 11.2, wind_direction_10m: 270 },
  hourly: { time: hours, temperature_2m: hours.map((t, i) => 9 + (i % 24) / 3), precipitation_probability: hours.map(() => 10),
            weather_code: hours.map((t, i) => i % 2 ? 61 : 0), is_day: hours.map((t, i) => (i % 24) >= 7 && (i % 24) < 18 ? 1 : 0),
            uv_index: hours.map(() => 3.4), visibility: hours.map(() => 24140) },
  daily: { time: [T - 12 * 3600, T + 12 * 3600, T + 36 * 3600], weather_code: [2, 61, 71], temperature_2m_max: [16.2, 15, 14], temperature_2m_min: [8.6, 8, 7],
           sunrise: [T - 5 * 3600, T + 19 * 3600, T + 43 * 3600], sunset: [T + 5 * 3600, T + 29 * 3600, T + 53 * 3600],
           precipitation_probability_max: [20, 80, 60], precipitation_sum: [0.2, 6, 3] }
}
const air = { current: { european_aqi: 32, us_aqi: 41, pm2_5: 6.1, pm10: 11, ozone: 60, nitrogen_dioxide: 9, uv_index: 2 },
              hourly: { time: hours, european_aqi: hours.map(() => 30), us_aqi: hours.map(() => 40), birch_pollen: hours.map(() => 0),
                        alder_pollen: hours.map(() => 0), grass_pollen: hours.map(() => 25), mugwort_pollen: hours.map(() => 0),
                        olive_pollen: hours.map(() => 0), ragweed_pollen: hours.map(() => 0) } }

// The hosts each copy may name: Open-Meteo's, and the services the widget is about.
const OM_HOSTS = ["geocoding-api.open-meteo.com", "api.open-meteo.com", "air-quality-api.open-meteo.com", "opensky-network.org"]
const widgets = fs.readdirSync(path.join(here, "overrides")).flatMap((a) => fs.readdirSync(path.join(here, "overrides", a)).map((n) => a + "/" + n))
for (const id of widgets) {
  const r = run(id, {}, {})
  const text = fs.readFileSync(path.join(here, "overrides", id, "widget.owl"), "utf8")
  check(!/wttr\.in/.test(text) && r.caps.hosts.every((h) => OM_HOSTS.includes(h)), id + " doesn't use wttr.in: " + r.caps.hosts.join(", "))
}

// today: a typed city, the US result picked by its region, °F.
{
  const id = "simonschubert/today"
  let r = run(id, { city: "Sample Town, Pennsylvania" }, {})
  check(/geocoding-api\.open-meteo\.com\/v1\/search\?count=10&format=json&name=Sample%20Town$/.test(r.urls.geo), "today looks the town up: " + r.urls.geo)
  check(!/latitude=-?[0-9]/.test(r.urls.wx), "today's forecast waits for the place: " + r.urls.wx.slice(0, 80))
  r = run(id, { city: "Sample Town, Pennsylvania" }, { geo: ok(geocode), wx: ok(forecast) })
  check(/^https:\/\/api\.open-meteo\.com\/v1\/forecast\?latitude=40\.12&longitude=-77\.65&/.test(r.urls.wx) && /temperature_unit=fahrenheit/.test(r.urls.wx)
        && /wind_speed_unit=mph/.test(r.urls.wx), "today asks for the found place, rounded, in °F: " + r.urls.wx)
  check(r.texts.includes("14°") && r.texts.includes("partly cloudy") && r.all.includes("sample town, united states"), "today shows the reading, the words and the place")
  check(r.all.includes("wind w") && r.all.includes("70%") && r.all.includes("1016 hPa") === false && r.all.includes("30.01 inHg"), "today maps wind, humidity and pressure in imperial units")
  check(r.all.includes("80%") && r.all.includes("60%"), "today's days get their rain chances")
  check(r.all.includes("open-meteo.com (cc by 4.0)"), "today credits Open-Meteo")
  check(/% lit/.test(r.all) && !/ERROR/.test(r.all), "today works out the moon from the date, without errors")
  // The same city in Britain, and the phone's own unit winning.
  r = run(id, { city: "Sample Town, England" }, { geo: ok(geocode), wx: ok(forecast) })
  check(/latitude=51\.5&longitude=-0\.12/.test(r.urls.wx) && /temperature_unit=celsius/.test(r.urls.wx), "today picks the result by region, in °C")
  r = run(id, { city: "Sample Town, England", phoneUnit: "F" }, { geo: ok(geocode), wx: ok(forecast) })
  check(/temperature_unit=fahrenheit/.test(r.urls.wx), "today follows the phone's unit")
  // The phone's location: straight in, no lookup.
  r = run(id, { city: "40.79,-77.86", phoneUnit: "C" }, { wx: ok(forecast) })
  check(/name=$/.test(r.urls.geo) && /latitude=40\.79&longitude=-77\.86&/.test(r.urls.wx), "today takes the phone's lat,lon straight in")
  check(r.all.includes("your location"), "today names the phone's location")
  // Nothing to go on.
  r = run(id, { city: "" }, {})
  check(r.all.includes("set a city or turn on Location"), "today asks for a city or Location without either")
  r = run(id, { city: "Nowhere" }, { geo: ok({}) })
  check(r.all.includes("city not found"), "today says a city wasn't found")
}

// forecast: the curve and the days, from the same answers.
{
  const id = "simonschubert/forecast"
  let r = run(id, { city: "Sample Town" }, { geo: ok(geocode), w: ok(forecast) })
  check(/latitude=40\.12&longitude=-77\.65&/.test(r.urls.w), "forecast asks for the first result: " + r.urls.w)
  check(r.texts.includes("14°") && r.all.includes("partly cloudy") && r.all.includes("Sample Town"), "forecast shows now and the place")
  check(r.all.includes("16° / 9°") || r.all.includes("16° / 8°"), "forecast shows the days' highs and lows: " + r.all)
  check(r.all.includes("open-meteo.com (cc by 4.0)") && !/ERROR/.test(r.all), "forecast credits Open-Meteo, without errors")
  r = run(id, { city: "" }, {})
  check(r.all.includes("set a city or turn on Location"), "forecast asks for a city or Location without either")
}

// sun and moon: Open-Meteo's sunrise and sunset, the moon from the date.
{
  const id = "simonschubert/sun-and-moon"
  let r = run(id, { city: "40.79,-77.86" }, { sun: ok(forecast) })
  check(/^https:\/\/api\.open-meteo\.com\/v1\/forecast\?latitude=40\.79&longitude=-77\.86&daily=sunrise,sunset/.test(r.urls.sun), "sun and moon asks for sunrise and sunset: " + r.urls.sun)
  check(r.all.includes("↑ 07:00") && r.all.includes("↓ 17:00") && r.all.includes("of daylight left"), "sun and moon shows the day: " + r.all)
  check(/\d+%/.test(r.all) && /(moon|crescent|quarter|gibbous)/.test(r.all) && !/ERROR/.test(r.all), "sun and moon shows the moon's phase")
  r = run(id, { city: "" }, {})
  check(r.all.includes("set a city or turn on Location"), "sun and moon asks for a city or Location without either")
}

// planes overhead: the place only, then OpenSky.
{
  const id = "simonschubert/planes-overhead"
  let r = run(id, { city: "Sample Town" }, { geo: ok(geocode), sky: ok({ states: [] }) })
  check(/opensky-network\.org\/api\/states\/all\?lamin=39\.623&/.test(r.urls.sky), "planes overhead centres OpenSky on the place: " + r.urls.sky)
  check(r.all.includes("0 flights within 30 mi of sample town"), "planes overhead counts in miles in the US: " + r.all)
  r = run(id, { city: "" }, {})
  check(r.all.includes("set a city or turn on Location"), "planes overhead asks for a city or Location without either")
}

// air and pollen: the place, then the air-quality API.
{
  const id = "simonschubert/air-and-pollen"
  let r = run(id, { city: "52.52,13.40", phoneUnit: "C" }, { air: ok(air) })
  check(/^https:\/\/air-quality-api\.open-meteo\.com\/v1\/air-quality\?latitude=52\.52&longitude=13\.4&/.test(r.urls.air), "air and pollen asks at the phone's location: " + r.urls.air)
  check(r.all.includes("32") && r.all.includes("your location") && !/ERROR/.test(r.all), "air and pollen shows Europe's index there")
  r = run(id, { city: "" }, {})
  check(r.all.includes("set a city or turn on Location"), "air and pollen asks for a city or Location without either")
}

// red panda: no internet now; it reads the phone's own weather reading (omamobile-weather).
{
  const id = "ssalentin/red-panda"
  let r = run(id, {}, {})
  check(r.caps.hosts.length === 0 && !r.caps.network && r.caps.files.join() === "~/.local/state/omamobile/weather.json", "red panda reads the phone's weather reading, not the internet")
  r = run(id, { lastTap: T }, { wx: { at: T * 1000, temperature: 9, unit: "°C", text: "Rain", source: "location" } })
  check(r.value("raining") === true, "red panda shelters when the reading says rain")
  r = run(id, { lastTap: T }, { wx: { at: (T - 4 * 3600) * 1000, temperature: 9, unit: "°C", text: "Rain", source: "location" } })
  check(r.value("raining") === false, "red panda ignores a reading over 3 hours old")
}

// omaprayer: no IP location; "auto" uses its own default city.
{
  const r = run("setiapam/omaprayer", { city: "auto" }, {})
  check(r.all.includes("JAKARTA") && !/ERROR/.test(r.all), "omaprayer's auto is its default city: " + r.texts.slice(0, 3).join(" | "))
}

if (failures) { console.log(failures + " failed"); process.exit(1) }
