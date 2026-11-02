<!-- SPDX-License-Identifier: MIT -->
# omamobile-owl-widgets

The OWL widget store ([Simon Schubert's omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets),
MIT) at the commit pinned in `PKGBUILD`, for the home screen's built-ins and its Store tab: only
the widgets that pass our conformance suite (`status.json`), with an index built by our own
compiler (`update-index.js`, committed as `index.json`). `install` copies each file and checks it
against the index's sha256.

## Our copies diverge from the store (`overrides/`)

A widget with a file in `overrides/<author>/<name>/widget.owl` ships that file instead of the
store's. `update-index.js` indexes it, and `install` checks it the same way. These copies are ours
and differ from the store's:

| Widget | Store version | Ours | What changed |
| --- | --- | --- | --- |
| `simonschubert/today` | 1.1 | 1.1.1 | Weather from Open-Meteo instead of wttr.in: current conditions, the next 24 hours, 3 days, wind, humidity, rain, UV, pressure, visibility, sunrise and sunset. The moon phase is worked out from the date (Open-Meteo has none). Credits "weather: open-meteo.com (cc by 4.0)" on its screen |
| `simonschubert/forecast` | 1.2 | 1.2.1 | The same, through `http()` instead of `curl` and `jq` in a command, so it no longer runs commands or needs those packages |
| `simonschubert/sun-and-moon` | 1.2 | 1.2.1 | Sunrise and sunset from Open-Meteo through `http()` (no commands); the moon from the date |
| `simonschubert/air-and-pollen` | 1.1 | 1.1.1 | Already used Open-Meteo's air-quality API; the place now comes from Open-Meteo's geocoding or the phone's location instead of wttr.in |
| `simonschubert/planes-overhead` | 1.1 | 1.1.1 | The place from Open-Meteo's geocoding or the phone's location instead of wttr.in |
| `ssalentin/red-panda` | 1.1 | 1.1.1 | Rain from the phone's own weather reading (`~/.local/state/omamobile/weather.json`, written by `omamobile-weather` from Open-Meteo) instead of wttr.in by IP; `file()` with `optional` needs `owl: 5` |
| `setiapam/omaprayer` | 1.2 | 1.2.1 | No location by IP (it asked wttr.in): "auto" uses the widget's own default city, Jakarta, as it already did when that lookup failed |

Why: wttr.in stopped answering (2026-11-02, refused from the laptop and the phone, so the Today
widget showed only the date), and the phone's own weather service (`omamobile-weather` in
omamobile-shell) already uses Open-Meteo. All weather now comes from Open-Meteo
(`api.open-meteo.com`, `geocoding-api.open-meteo.com`, `air-quality-api.open-meteo.com`; free, no
key, [CC BY 4.0](https://open-meteo.com/en/license), which asks for the credit each copy shows).

How the weather copies find the place, the same in each:

* `city` is "lat,lon" (the home screen puts the phone's position there, rounded to about 1 km,
  when "Use my location" is on): it goes straight to Open-Meteo, with no lookup;
* `city` is a name ("Town" or "Town, Region"): Open-Meteo's geocoding looks the town up, and the
  first result whose region, country or country code matches what follows the comma wins, else
  the first result;
* neither: Open-Meteo has no IP location, so the widget says "set a city or turn on Location".

Units: a `phoneUnit` state ("C" or "F") that the home screen fills from the phone's locale
(`HomeModel.localeUnit`, °F in the US, as `omamobile-weather`), else the found place's country
(°F in the US, Liberia and Myanmar), else °C. WMO weather codes become the words
`omamobile-weather` uses and the glyphs `weatherIcon()` draws.

Versions are bumped one step past the store's (1.1 to 1.1.1), so the Store tab doesn't offer the
store's same version as an update over ours, while a newer store release still shows as one.
**Their hosts changed, so an approval given before asks again** (an approval holds for one exact
list of commands, URLs and files).

These changes are meant to go upstream: once the store takes them (or its own fix for wttr.in), pin
that commit and delete the copies here.

## Changing the package

* a copy: edit it under `overrides/`, bump its `version` in `meta`, then rebuild the index from a
  checkout of the store at the pinned commit:
  `node update-index.js <store checkout> > index.json`;
* `test/all` checks the index against `status.json` and every copy, stages the package from a
  made-up store, and (beside omamobile-shell) runs `test/open-meteo.js`, which drives each copy
  with made-up Open-Meteo answers through our OWL runtime.
