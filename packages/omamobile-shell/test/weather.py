#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# omamobile-weather against a fake HOME and a fake network: the reading it
# writes for the lock screen (the shape LockGlance.js weatherLine reads),
# its words for the weather codes against the home screen's
# (HomeModel.weatherText, through node), the settings it reads, the city
# lookup and its cache, and one try per run that leaves the old reading.
import glob
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
home = tempfile.mkdtemp()
os.environ["HOME"] = home
loader = importlib.machinery.SourceFileLoader("omamobile_weather", os.path.join(ROOT, "bin/omamobile-weather"))
spec = importlib.util.spec_from_loader("omamobile_weather", loader)
W = importlib.util.module_from_spec(spec)
loader.exec_module(W)


def ok(cond, name):
    if not cond:
        print("not ok - weather: " + name)
        sys.exit(1)


def write(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(value, f)


def reset():
    for p in (W.CONFIG, W.HOME_LAYOUT, W.READING, W.PLACE):
        if os.path.exists(p):
            os.unlink(p)


# The words agree with the home screen widget's for every code.
js = ("const M = require(process.argv[1]); const out = {};"
      "for (let c = -1; c <= 120; c++) out[c] = M.weatherText(c).text;"
      "out.x = M.weatherText('x').text; out.n = M.weatherText(null).text;"
      "console.log(JSON.stringify(out))")
theirs = json.loads(subprocess.run(["node", "-e", js, os.path.join(ROOT, "plugins/omamobile.home/HomeModel.js")],
                                   check=True, capture_output=True, text=True).stdout)
mine = {str(c): W.weather_text(c) for c in range(-1, 121)}
mine["x"] = W.weather_text("x")
mine["n"] = W.weather_text(None)
diff = {k: (mine[k], theirs[k]) for k in theirs if mine.get(k) != theirs[k]}
ok(not diff, "the words for each code are the home screen widget's %s" % diff)
print("ok - weather: the words for every code are the home screen widget's (HomeModel.weatherText)")

# Settings and where to look
us = {"LANG": "en_US.UTF-8"}
de = {"LANG": "de_DE.UTF-8"}
ok(W.locale_unit(us) == "F" and W.locale_unit(de) == "C" and W.locale_unit({"LANG": "C.UTF-8"}) == "C"
   and W.locale_unit({}) == "C" and W.locale_unit({"LC_ALL": "de_DE.UTF-8", "LANG": "en_US.UTF-8"}) == "C"
   and W.locale_unit({"LC_MEASUREMENT": "en_US.UTF-8", "LANG": "de_DE.UTF-8"}) == "F", "the unit follows the locale")
ok(W.setting_place({"city": " State College, PA ", "unit": "F"}, de) == {"city": "State College, PA", "unit": "F", "fixed": False},
   "a city and a unit")
ok(W.setting_place({"city": "Oslo"}, us)["unit"] == "F" and W.setting_place({"city": "Oslo"}, de)["unit"] == "C", "no unit: the locale's")
ok(W.setting_place({"city": "Oslo", "unit": "°c"}, us)["unit"] == "C"
   and W.setting_place({"city": "Oslo", "unit": "fahrenheit"}, de)["unit"] == "F", "units read loosely")
ok(W.setting_place({"latitude": 59.9, "longitude": 10.7, "city": "ignored", "unit": "C", "location": "fixed"}, us)
   == {"latitude": 59.9, "longitude": 10.7, "unit": "C", "fixed": True}, "coordinates win over a city; fixed")
ok(W.setting_place({"latitude": "59.9", "longitude": 10.7}, us) is None, "coordinates must be numbers")
ok(W.setting_place({}, us) is None and W.setting_place(None, us) is None and W.setting_place({"unit": "F"}, us) is None,
   "no place set")
layout = {"pages": [{"items": [{"type": "clock"}, {"type": "weather", "config": {
    "enabled": True, "useLocation": False, "latitude": 52.52, "longitude": 13.41, "units": "celsius"}}]}]}
here_only = {"pages": [{"items": [{"type": "weather", "config": {"enabled": True, "useLocation": True,
                                                                 "latitude": None, "longitude": None}}]}]}
off = {"pages": [{"items": [{"type": "weather", "config": {"enabled": False, "latitude": 1.0, "longitude": 2.0}}]}]}
ok(W.home_widget_place(layout) == {"latitude": 52.52, "longitude": 13.41, "unit": "C"}, "the weather widget's named place")
ok(W.home_widget_place(here_only) is None and W.home_widget_place(off) is None, "no named place, or off: none")

owl = os.path.join(home, ".local/state/omamobile/owl")
os.makedirs(owl, exist_ok=True)
write(os.path.join(owl, "owl_simonschubert.today_w3.json"), {"city": "old town"})
os.utime(os.path.join(owl, "owl_simonschubert.today_w3.json"), (1000, 1000))
write(os.path.join(owl, "owl_simonschubert.today_w17.json"), {"city": "state college, pa"})
write(os.path.join(owl, "owl_someone.else_w1.json"), {"city": "elsewhere"})
ok(W.today_city() == "state college, pa", "the newest today widget's city")

geo = {"usable": False, "answer": None, "asked": 0}


def usable():
    return geo["usable"]


def where():
    geo["asked"] += 1
    return geo["answer"]


W.geoclue_usable = usable
W.where_am_i = where
T = 1790000000.0
st = {}
r = W.resolve({"city": "Oslo", "unit": "C"}, None, st, T, us)
ok(r["source"] == "setting" and r["city"] == "Oslo" and geo["asked"] == 0, "GeoClue not usable, a setting: the setting, GeoClue never asked")
r = W.resolve(None, None, {}, T, us)
ok(r == {"city": "state college, pa", "unit": "F", "source": "widget"}, "GeoClue not usable, no setting: the today widget's city %s" % r)
r = W.resolve({"unit": "C"}, None, {}, T, us)
ok(r["source"] == "widget" and r["unit"] == "C", "a unit alone still sets the unit")
geo.update(usable=True, answer=(40.79, -77.86))
st = {}
r = W.resolve({"city": "Oslo"}, None, st, T, us)
ok(r == {"latitude": 40.79, "longitude": -77.86, "unit": "F", "source": "location"} and geo["asked"] == 1,
   "with Location on, the phone's position comes first %s" % r)
ok(st["fix"] == {"latitude": 40.79, "longitude": -77.86, "at": int(T)}, "the fix is kept with its time")
r = W.resolve({"city": "Oslo"}, None, st, T + 2 * 3600, us)
ok(r["source"] == "location" and geo["asked"] == 1, "a fix under 3 h old is used again without asking")
r = W.resolve({"city": "Oslo", "location": "fixed"}, None, st, T + 4 * 3600, us)
ok(r["source"] == "setting" and r["city"] == "Oslo" and geo["asked"] == 1, "location fixed: the setting, GeoClue never asked")
geo["answer"] = None
r = W.resolve(None, None, st, T + 4 * 3600, us)
ok(r["source"] == "location" and r["latitude"] == 40.79 and geo["asked"] == 2, "a failed fix: the last one, under a day old")
r = W.resolve(None, None, st, T + 30 * 3600, us)
ok(r["source"] == "widget" and geo["asked"] == 3, "a failed fix and the last over a day old: the widget's city")
geo["usable"] = False
r = W.resolve(None, None, st, T + 3600, us)
ok(r["source"] == "location", "Location off but a fix under 3 h old: still used")
r = W.resolve(None, None, st, T + 5 * 3600, us)
ok(r["source"] == "widget" and geo["asked"] == 3, "Location off and the fix older: GeoClue isn't asked, the widget's city")
for f in glob.glob(os.path.join(owl, "owl_simonschubert.today_*")):
    os.unlink(f)
ok(W.resolve(None, layout, {}, T, us)["source"] == "widget"
   and W.resolve(None, layout, {}, T, us)["latitude"] == 52.52, "no today widget: the weather widget's named place")
ok(W.resolve(None, here_only, {}, T, us) is None, "no place anywhere: none (no IP geolocation)")
print("ok - weather: where, in order: the phone's position (at most every 3 h, never asked with Location off), the setting, the widgets' city")

# Requests
url = W.forecast_url(40.79345, -77.86012, "F")
ok("latitude=40.79&longitude=-77.86" in url and url.endswith("&temperature_unit=fahrenheit")
   and "current=temperature_2m,weather_code" in url, "the forecast asks for a rounded place " + url)
ok("temperature_unit" not in W.forecast_url(1, 2, "C"), "celsius is the default")
ok(W.geocode_url("State College") .endswith("name=State%20College"), "the city is quoted")
results = {"results": [
    {"name": "State College", "latitude": 33.4, "longitude": -88.8, "admin1": "Mississippi", "country_code": "US"},
    {"name": "State College", "latitude": 40.79, "longitude": -77.86, "admin1": "Pennsylvania", "country_code": "US"}]}
ok(W.pick_place("State College, PA", results)["latitude"] == 40.79, "a state abbreviation picks the state")
ok(W.pick_place("State College, Mississippi", results)["latitude"] == 33.4, "a region by name")
ok(W.pick_place("State College", results)["latitude"] == 33.4, "no region: the first")
ok(W.pick_place("Nowhere", {"generationtime_ms": 0.1}) is None, "no results: no place")
print("ok - weather: the requests send a rounded place or the city, and \"Town, ST\" picks the state")

# A run
ok(W.reading({"current": {"temperature_2m": 11.6, "weather_code": 2}}, "C", 1790000000000.4)
   == {"at": 1790000000000, "temperature": 12, "unit": "°C", "text": "Partly cloudy"}, "the reading's shape")
ok(W.reading({"current": {}}, "C", 1) is None, "no temperature: no reading")

calls = []


def fake(answers):
    def fetch(url):
        calls.append(url)
        for key, value in answers.items():
            if key in url:
                if isinstance(value, Exception):
                    raise value
                return value
        raise AssertionError(url)
    return fetch


geo.update(usable=False, answer=None)
net = {"geocoding-api": results, "api.open-meteo.com/v1/forecast": {"current": {"temperature_2m": 47.4, "weather_code": 61}}}
reset(); calls.clear()
ok(W.run(fake(net), lambda: 1790000000.0, us) == 0 and calls == [], "no place: nothing fetched")
ok(not os.path.exists(W.READING), "no place: nothing written")
W.main(["omamobile-weather", "set", "State College, PA", "F"])
ok(json.load(open(W.CONFIG)) == {"city": "State College, PA", "unit": "F"}, "set saves the city and unit")
ok(W.main(["omamobile-weather", "set", "Oslo", "K"]) == 2, "set refuses a unit that isn't F or C")
ok(W.run(fake(net), lambda: 1790000000.0, us) == 0, "a run with a city")
ok(len(calls) == 2 and "name=State" in calls[0] and "latitude=40.79&longitude=-77.86" in calls[1]
   and "temperature_unit=fahrenheit" in calls[1], "the city is looked up, then its weather fetched " + str(calls))
r = json.load(open(W.READING))
ok(r == {"at": 1790000000000, "temperature": 47, "unit": "°F", "text": "Rain", "source": "setting"}, "the reading the lock reads %s" % r)
ok(isinstance(r["temperature"], int), "a whole temperature")
calls.clear()
ok(W.run(fake(net), lambda: 1790001800.0, us) == 0 and len(calls) == 1 and "forecast" in calls[0], "the place is looked up once")
write(W.CONFIG, {"city": "state  college, pa", "unit": "F"})
calls.clear()
W.run(fake(net), lambda: 1790001800.0, us)
ok(len(calls) == 1, "the same city written differently: no new lookup")
write(W.CONFIG, {"city": "Oslo", "unit": "C"})
calls.clear()
W.run(fake({"geocoding-api": {"results": [{"name": "Oslo", "latitude": 59.91, "longitude": 10.75}]},
            "api.open-meteo.com": {"current": {"temperature_2m": 3.2, "weather_code": 71}}}), lambda: 1790003600.0, us)
ok(len(calls) == 2 and "name=Oslo" in calls[0] and "latitude=59.91" in calls[1], "a new city is looked up again")
ok(set(json.load(open(W.PLACE))["cities"]) == {"state college, pa", "oslo"}, "both cities are kept, by name")
before = open(W.READING).read()
ok(json.loads(before)["text"] == "Snow" and json.loads(before)["unit"] == "°C", "the new city's reading")
geo.update(usable=True, answer=(52.52, 13.41))
calls.clear()
W.run(fake({"api.open-meteo.com": {"current": {"temperature_2m": 9.0, "weather_code": 3}}}), lambda: 1790003600.0, us)
ok(len(calls) == 1 and "latitude=52.52&longitude=13.41" in calls[0] and json.load(open(W.READING))["source"] == "location",
   "with Location on, the reading is for the phone's position, and says so")
ok(json.load(open(W.PLACE))["fix"]["latitude"] == 52.52, "the fix is kept in the state file")
geo.update(usable=False, answer=None)
write(W.PLACE, {"cities": json.load(open(W.PLACE))["cities"]})
W.run(fake({"api.open-meteo.com": {"current": {"temperature_2m": 3.2, "weather_code": 71}}}), lambda: 1790003600.0, us)
before = open(W.READING).read()
calls.clear()
ok(W.run(fake({"api.open-meteo.com": OSError("timed out")}), lambda: 1790005400.0, us) == 1 and len(calls) == 1,
   "a failed fetch: one try, and the run fails")
ok(open(W.READING).read() == before, "a failed fetch leaves the old reading")
calls.clear()
ok(W.run(fake({"api.open-meteo.com": {"error": True}}), lambda: 1790005400.0, us) == 1 and open(W.READING).read() == before,
   "an answer without a temperature leaves the old reading")
write(W.CONFIG, {"city": "Atlantis"})
calls.clear()
ok(W.run(fake({"geocoding-api": {"generationtime_ms": 0.1}}), lambda: 1790005400.0, us) == 1 and len(calls) == 1
   and open(W.READING).read() == before, "a city that isn't found: no forecast, the old reading stays")
ok(not [n for n in os.listdir(W.STATE_DIR) if n.startswith(".weather-")], "no temporary files are left behind")
print("ok - weather: a run writes the lock's reading (with its source) atomically, looks a city up once, and keeps the old reading on failure")

# where-am-i's output, as GeoClue's demo prints it
fake_wai = os.path.join(home, "wai")
with open(fake_wai, "w") as f:
    f.write("#!/bin/sh\nprintf 'New location:\\nLatitude:    40.793450\\302\\260\\nLongitude:   -77.860120\\302\\260\\nAccuracy:    25000.000000 meters\\n'\n")
os.chmod(fake_wai, 0o755)
loader.exec_module(W)
W.WHERE_AM_I = fake_wai
ok(W.where_am_i() == (40.79, -77.86), "where-am-i's answer, rounded to about 1 km")
with open(fake_wai, "w") as f:
    f.write("#!/bin/sh\necho 'Failed to connect to GeoClue service'\n")
ok(W.where_am_i() is None, "no answer: none")
W.WHERE_AM_I = os.path.join(home, "missing")
ok(W.geoclue_usable() is False, "no where-am-i: GeoClue isn't usable")
print("ok - weather: GeoClue's where-am-i is read at city accuracy, and missing means not usable")
