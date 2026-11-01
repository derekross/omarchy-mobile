#!/usr/bin/env python3
"""Generate device/husky/overlays/gauge-model.dtso from Google's stock husky devicetree.

Usage: gen-gauge-overlay.py STOCK.dts NODE OUT.dtso
  STOCK.dts  the stock husky overlay source (dtc -I dtb -O dts of the factory image's dtbo), the one
             with the "maxim,<NODE> { maxim,fg-model ... maxim,fg-params ... }" nodes
  NODE       the model node, e.g. default-a1-0k (Google's fallback for an unknown pack),
             atl-a1-1k, cos-a1-2k, lsn-a1-3k, default-fake-batt

Writes maxim,fg-model (48 u16 from the 24 stock u32 cells, high halfword first) and
maxim,fg-params (u16 from the stock big-endian byte pairs, in the order of
struct max77759_fg_params). Nothing is typed by hand."""
import re, sys
src, node, out = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src).read()
m = re.search(r'maxim,' + re.escape(node) + r' \{(.*?)\n\t*\};', text, re.S)
body = m.group(1)
cells = re.search(r'maxim,fg-model = <([^>]*)>', body).group(1).split()
params = re.search(r'maxim,fg-params = \[([^\]]*)\]', body).group(1).split()
model = []
for c in cells:
    v = int(c, 16)
    model += [(v >> 16) & 0xffff, v & 0xffff]
pw = [(int(params[i], 16) << 8) | int(params[i + 1], 16) for i in range(0, len(params), 2)]
assert len(model) == 48, len(model)
assert len(pw) in (27, 28), len(pw)
def fmt(ws): return "\n".join("\t\t\t" + " ".join("0x%04x" % w for w in ws[i:i + 8]) for i in range(0, len(ws), 8))
open(out, "w").write(f"""// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up overlay, never default (BATTERY-NOTES.md M4c): load Google's ModelGauge m5 model for an
 * unknown pack into the husky fuel gauge (Google falls back to the {node} node when the
 * battery ID is unknown). Generated from the stock DT by tools/gen-gauge-overlay.py:
 * maxim,fg-model = the 24 stock u32 cells split into 48 u16 (high half first),
 * maxim,fg-params = the stock byte list as big-endian u16 words, in the order of
 * struct max77759_fg_params. The driver loads it only while the gauge reports power-on
 * reset (Status bit 1), then clears that bit.
 */
/dts-v1/;
/plugin/;

&hsi2c_11 {{
	fuel-gauge@36 {{
	maxim,fg-model = /bits/ 16 <
{fmt(model)}
	>;
	maxim,fg-params = /bits/ 16 <
{fmt(pw)}
	>;
	}};
}};
""")
print("model words", len(model), "param words", len(pw), "design cap word", hex(pw[7]), "config", hex(pw[3]), "tgain/toff", hex(pw[19]), hex(pw[20]))
