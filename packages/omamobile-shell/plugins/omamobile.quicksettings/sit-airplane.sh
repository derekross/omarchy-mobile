#!/bin/sh
# SPDX-License-Identifier: MIT
# The airplane tile's reading of omamobile-sitd, shared by tile-state.sh and
# tile-action.sh so the two can't drift apart: prints "on" while sitd's
# public state says the cellular radio is off, "off" while it is on, and
# nothing where the tile must keep to the rfkill switches (no omamobile-sit,
# no readable state, or an older sitd whose state has no radio_choice under
# "modem": its state goes on reading radio "on" after its own radio off).
sit_state=${OMAMOBILE_SIT_STATE:-/run/omamobile-sit/state.json}
command -v omamobile-sit >/dev/null 2>&1 && [ -r "$sit_state" ] && command -v python3 >/dev/null 2>&1 || exit 0
exec python3 -I -c '
import json, sys
try:
    m = json.load(open(sys.argv[1])).get("modem") or {}
except (OSError, ValueError, AttributeError):
    m = {}
if isinstance(m, dict) and "radio_choice" in m:
    print("on" if m.get("radio") == "off" else "off")
' "$sit_state"
