#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Print a network code (MCC+MNC) and its carrier's name, tab-separated.

The mobile network card (CellularPanel.qml) shows sitd's operator name when
the network sends one; otherwise it asks this, which looks the code up in
mobile-broadband-provider-info as sitd's APN lookup does: the provider marked
primary first, a two-digit MNC also tried as three. Prints only the code when
nothing matches or the file is missing.

Usage: carrier-name.py CODE [SERVICEPROVIDERS.XML]
"""
import sys
import xml.etree.ElementTree as ET

DEFAULT = "/usr/share/mobile-broadband-provider-info/serviceproviders.xml"


def lookup(code, path=DEFAULT):
    if not (code.isdigit() and len(code) in (5, 6)):
        return ""
    wanted = {code, code[:3] + code[3:].zfill(3)}
    try:
        tree = ET.parse(path)
    except (OSError, ET.ParseError):
        return ""
    found = []
    for provider in tree.iter("provider"):
        for net in provider.iter("network-id"):
            mcc, mnc = net.get("mcc") or "", net.get("mnc") or ""
            if mcc + mnc in wanted or mcc + mnc.zfill(3) in wanted:
                found.append((provider.get("primary") != "true", provider.findtext("name") or ""))
                break
    found.sort(key=lambda item: item[0])
    return found[0][1].strip() if found else ""


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    code = sys.argv[1]
    print(code + "\t" + lookup(code, *sys.argv[2:3]))
