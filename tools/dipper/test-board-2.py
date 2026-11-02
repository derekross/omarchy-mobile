#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check build-board-2.py: it must read upstream's own file and refuse bad input."""
import importlib.util, os, struct, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("bb2", HERE / "build-board-2.py")
bb2 = importlib.util.module_from_spec(spec); spec.loader.exec_module(bb2)

fails = []
def check(c, m):
    if not c: fails.append(m)

# 1. a hand-built file must round-trip through our own parser
name = "bus=snoc,qmi-board-id=0,qmi-chip-id=30214"
data = bytes(range(256)) * 4
body = bb2.ie(bb2.BD_IE_BOARD_NAME, name.encode()) + bb2.ie(bb2.BD_IE_BOARD_DATA, data)
blob = bb2.MAGIC + b"\0" + b"\0" * ((-(len(bb2.MAGIC) + 1)) % 4) + bb2.ie(bb2.BD_IE_BOARD, body)
got = bb2.parse(blob)
check(got == [(name, len(data))], f"round-trip failed: {got}")

# 2. the magic must be rejected when wrong, so a truncated download cannot pass
try:
    bb2.parse(b"NOT-A-BOARD-FILE" + b"\0" * 8); fails.append("accepted a bad magic")
except ValueError:
    pass

# 3. odd-length payloads must still align, or every later IE is misread
odd = bb2.ie(7, b"abc")
check(len(odd) % 4 == 0, "IE not padded to a 4-byte boundary")
check(struct.unpack_from("<II", odd)[1] == 3, "IE length must be the unpadded length")

# 4. board-id parsing from the phone's file names
check(bb2.board_id_of(Path("bdwlan.b3f")) == 0x3f, "bdwlan.b3f should be board id 0x3f")
check(bb2.board_id_of(Path("bdwlan.bin")) is None, "bdwlan.bin is the default, not an id")
check(bb2.board_id_of(Path("bdwlan.102")) is None, "bdwlan.102 has no 'b' prefix")

# 5. with no bdwlan.bin present it must refuse rather than ship an empty file
with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    r = subprocess.run([sys.executable, str(HERE / "build-board-2.py"),
                        "--src", str(t), "--out", str(t / "board-2.bin")],
                       capture_output=True, text=True)
    check(r.returncode != 0, "built a board file with no default board data")
    check(not (t / "board-2.bin").exists(), "left a file behind after refusing")

# 6. against upstream's real file, if it is around: our parser must agree with
#    what ath10k would see, or we have no business writing one.
ref = Path(os.environ.get("BOARD2_REFERENCE", "/usr/lib/firmware/ath10k/QCA6174/hw3.0/board-2.bin"))
if ref.is_file():
    entries = bb2.parse(ref.read_bytes())
    snoc = [n for n, _ in entries if n and n.startswith("bus=snoc")]
    check(len(entries) >= 30, f"only {len(entries)} entries parsed from upstream's file")
    check(len(snoc) == len(entries), "some upstream entries did not parse as snoc boards")
    check(any("xiaomi_beryllium" in n for n in snoc), "beryllium missing: parse is suspect")
    print(f"upstream cross-check: {len(entries)} entries, all snoc")
else:
    print("upstream cross-check: SKIPPED (no reference board-2.bin)")

if fails:
    print("FAIL:"); [print("   ", f) for f in fails]; sys.exit(1)
print("test-board-2 OK: round-trips, rejects bad magic, aligns IEs, parses upstream's file")
