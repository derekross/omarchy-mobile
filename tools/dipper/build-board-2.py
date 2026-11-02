#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build an ath10k board-2.bin for dipper from the phone's own board data.

Why this exists: upstream linux-firmware's WCN3990 board-2.bin has entries only
for qmi-board-id=ff, and this phone's WLAN firmware reports board id 0 (the
stock kernel logs "wma_rx_service_ready_event: Board id: 0"). If ath10k finds no
matching entry it does not load board data at all and Wi-Fi stays down. So we
build a file keyed by the ids this phone can actually report, carrying its own
factory calibration instead of generic data.

Name format comes from ath10k_core_create_board_name():
    bus=snoc,qmi-board-id=%x,qmi-chip-id=%x[,variant=%s]
Both ids are hex. WCN3990 on SDM845 reports chip id 0x30214.

File format: the 16-byte magic, then length-prefixed IEs. Each ATH10K_BD_IE_BOARD
holds a NAME sub-IE and a DATA sub-IE.
"""
import argparse, re, struct, sys
from pathlib import Path

MAGIC = b"QCA-ATH10K-BOARD"
BD_IE_BOARD = 0
BD_IE_BOARD_NAME = 0
BD_IE_BOARD_DATA = 1
CHIP_ID = 0x30214          # WCN3990 as it appears in upstream's own names


def ie(id_: int, payload: bytes) -> bytes:
    """One IE: id, length, payload padded to a 4-byte boundary."""
    pad = (-len(payload)) % 4
    return struct.pack("<II", id_, len(payload)) + payload + b"\0" * pad


def parse(blob: bytes):
    """Read a board-2.bin back out, so what we write can be checked."""
    if blob[:len(MAGIC)] != MAGIC:
        raise ValueError("not a board-2.bin: bad magic")
    # The magic carries a trailing NUL and the whole thing is padded to 4.
    off = (len(MAGIC) + 1 + 3) & ~3
    out = []
    while off + 8 <= len(blob):
        id_, length = struct.unpack_from("<II", blob, off)
        body = blob[off + 8:off + 8 + length]
        off += 8 + length + ((-length) % 4)
        if id_ != BD_IE_BOARD:
            continue
        name, data, p = None, None, 0
        while p + 8 <= len(body):
            sid, slen = struct.unpack_from("<II", body, p)
            sbody = body[p + 8:p + 8 + slen]
            p += 8 + slen + ((-slen) % 4)
            if sid == BD_IE_BOARD_NAME:
                name = sbody.decode(errors="replace")
            elif sid == BD_IE_BOARD_DATA:
                data = sbody
        out.append((name, len(data) if data is not None else 0))
    return out


def board_id_of(path: Path):
    """bdwlan.bNN -> 0xNN. bdwlan.bin is the default used when no id matches."""
    m = re.fullmatch(r"bdwlan\.b([0-9a-fA-F]{1,4})", path.name)
    return int(m.group(1), 16) if m else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, required=True, help="directory of bdwlan.* files")
    ap.add_argument("--out", type=Path, required=True, help="board-2.bin to write")
    ap.add_argument("--verify", type=Path, help="also parse this reference file first")
    a = ap.parse_args()

    if a.verify:
        ref = parse(a.verify.read_bytes())
        snoc = [n for n, _ in ref if n and n.startswith("bus=snoc")]
        if not snoc:
            raise SystemExit(f"{a.verify}: parsed {len(ref)} entries but none look like snoc "
                             "boards -- the parser is wrong, refusing to build")
        print(f"parser check: read {len(ref)} entries from {a.verify.name}, "
              f"{len(snoc)} of them snoc")

    default = a.src / "bdwlan.bin"
    if not default.is_file():
        raise SystemExit(f"no {default}: that is the phone's default board data")
    data_default = default.read_bytes()

    entries = []
    # The ids this phone can report. 0 is what its stock firmware logs; ff is
    # ath10k's fallback and what upstream's own file uses. Both get the default
    # calibration blob, which is the one the phone itself ships.
    for bid in (0x0, 0xff):
        entries.append((f"bus=snoc,qmi-board-id={bid:x},qmi-chip-id={CHIP_ID:x}", data_default))
    # Every per-board-id blob the phone carries, under its own id, so a unit that
    # reports something else still finds its own calibration.
    for f in sorted(a.src.glob("bdwlan.b*")):
        bid = board_id_of(f)
        if bid is None or bid in (0x0, 0xff):
            continue
        entries.append((f"bus=snoc,qmi-board-id={bid:x},qmi-chip-id={CHIP_ID:x}", f.read_bytes()))

    blob = bytearray(MAGIC + b"\0")
    blob += b"\0" * ((-len(blob)) % 4)
    for name, data in entries:
        body = ie(BD_IE_BOARD_NAME, name.encode()) + ie(BD_IE_BOARD_DATA, data)
        blob += ie(BD_IE_BOARD, body)

    got = parse(bytes(blob))
    if len(got) != len(entries):
        raise SystemExit(f"wrote {len(entries)} entries but read back {len(got)}")
    for (wn, wd), (gn, gl) in zip(entries, got):
        if gn != wn or gl != len(wd):
            raise SystemExit(f"entry did not round-trip: wrote {wn!r}/{len(wd)}, read {gn!r}/{gl}")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(bytes(blob))
    print(f"wrote {a.out} ({len(blob)} bytes, {len(entries)} entries), verified by re-parsing:")
    for n, l in got:
        print(f"    {n}  ({l} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
