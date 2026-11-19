#!/bin/bash
# SPDX-License-Identifier: MIT
# The Qualcomm path (omamobile-gnss-qmi-loc): NMEA from LOC reports, the
# device opt-in, the start script's branch and the Location switch's status.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { echo "not ok - $*"; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' lib/omamobile-gnss-qmi-loc || fail "python: omamobile-gnss-qmi-loc"

python3 -I - lib/omamobile-gnss-qmi-loc "$t" <<'EOF' || fail "NMEA from LOC reports"
import importlib.machinery, importlib.util, struct, sys
sys.dont_write_bytecode = True  # nothing into lib/, which ./install copies whole
loader = importlib.machinery.SourceFileLoader("qmiloc", sys.argv[1])
spec = importlib.util.spec_from_loader("qmiloc", loader)
q = importlib.util.module_from_spec(spec); loader.exec_module(q)

def check(line):
    assert line.endswith(b"\r\n"), line
    body, cs = line[1:-2].split(b"*")
    x = 0
    for b in body: x ^= b
    assert int(cs, 16) == x, line
    return body.decode()

# coordinates: degrees and minutes, hemispheres, zero padding, no 60.0000
assert q.nmea_coord(52.5, False) == ("5230.0000", "N")
assert q.nmea_coord(-13.25, True) == ("01315.0000", "W")
assert q.nmea_coord(-0.5, False) == ("0030.0000", "S")
assert q.nmea_coord(9.999999999, True) == ("01000.0000", "E")
assert q.nmea_time(0) == ("000000.00", "010170")

T = q.tlv
def report(status=0, tech=1, used=(3, 70, 305, 210)):
    b = T(1, struct.pack("<I", status)) + T(2, b"\x01")
    b += T(0x10, struct.pack("<d", 52.5)) + T(0x11, struct.pack("<d", 13.25))
    b += T(0x12, struct.pack("<f", 3.5)) + T(0x18, struct.pack("<f", 10.0))
    b += T(0x1A, struct.pack("<f", 100.0)) + T(0x1B, struct.pack("<f", 60.0))
    b += T(0x20, struct.pack("<f", 90.0)) + T(0x23, struct.pack("<I", tech))
    b += T(0x24, struct.pack("<fff", 1.5, 0.8, 1.2))
    b += T(0x25, struct.pack("<Q", 1700000000123))
    b += T(0x2C, bytes([len(used)]) + struct.pack(f"<{len(used)}H", *used))
    return q.Position(q.parse_tlvs(b))

gga, rmc, gsa = (check(x) for x in q.position_sentences(report()))
assert gga == "GNGGA,221320.12,5230.0000,N,01315.0000,E,1,04,0.8,60.0,M,40.0,M,,", gga
assert rmc == "GNRMC,221320.12,A,5230.0000,N,01315.0000,E,19.4,90.0,141123,,,A", rmc
assert gsa == "GNGSA,A,3,3,70,5,10,,,,,,,,,1.5,0.8,1.2", gsa
# an intermediate report or a cell-ID position is no fix: empty fields only
for p in (report(status=1), report(tech=2)):
    gga, rmc, gsa = (check(x) for x in q.position_sentences(p))
    assert ",0,00," in gga and "5230" not in gga and rmc.split(",")[2] == "V", (gga, rmc)

# satellites: one GSV group per constellation, SNR only while tracked
def sv(system, svid, status, el, az, snr):
    return struct.pack("<IIHBIBfff", 0xFF, system, svid, 0, status, 0, el, az, snr)
svs = [sv(1, 7, 3, 45, 120, 41.6), sv(1, 9, 2, 10, 5, 0), sv(5, 70, 3, 30, 200, 35),
       sv(2, 305, 3, 60, 300, 38), sv(6, 210, 2, 20, 10, 0), sv(3, 133, 3, 25, 180, 30),
       sv(1, 12, 3, 5, 359.6, 20), sv(1, 14, 3, 5, 1, 21), sv(1, 17, 3, 5, 2, 22)]
raw = q.tlv(0x10, bytes([len(svs)]) + b"".join(svs))
parsed = q.parse_svs(q.parse_tlvs(raw))
assert len(parsed) == 9 and parsed[0][:3] == (1, 7, 3)
gsv = [check(x) for x in q.sv_sentences(parsed)]
gp = [g for g in gsv if g.startswith("GPGSV")]
assert gp[0] == "GPGSV,2,1,06,07,45,120,42,09,10,005,,46,25,180,30,12,05,000,20", gp
assert gp[1] == "GPGSV,2,2,06,14,05,001,21,17,05,002,22", gp
assert "GLGSV,1,1,01,70,30,200,35" in gsv and "GAGSV,1,1,01,05,60,300,38" in gsv and "GBGSV,1,1,01,10,20,010," in gsv, gsv

# the device opt-in: only 0 and 1, comments allowed, unknown keys ignored
open(sys.argv[2] + "/c", "w").write('ENGINE_UNLOCK=1 # rmtfs -r\nINJECT_TIME="0"\nBOGUS=1\n')
assert q.read_conf(sys.argv[2] + "/c", {"ENGINE_UNLOCK": False}) == {"ENGINE_UNLOCK": True}
assert q.read_conf(sys.argv[2] + "/c", {"INJECT_TIME": True}) == {"INJECT_TIME": False}
assert q.read_conf(sys.argv[2] + "/missing", {"ENGINE_UNLOCK": False}) == {"ENGINE_UNLOCK": False}
open(sys.argv[2] + "/c", "w").write('ENGINE_UNLOCK=yes\n')
assert q.read_conf(sys.argv[2] + "/c", {"ENGINE_UNLOCK": False}) == {"ENGINE_UNLOCK": False}
print("ok")
EOF
# The daemon never logs a coordinate: no log() call takes the position's fields.
if grep -nE 'log\(.*(\.lat|\.lon|lat,|lon,)' lib/omamobile-gnss-qmi-loc; then fail "a log line carries coordinates"; fi
echo "ok - NMEA (GGA, RMC, GSA, GSV) from LOC reports, no fix without satellites, and the device opt-in"

# ENGINE_UNLOCK=1 asks the modem to change its EFS: the daemon sends
# SET_ENGINE_LOCK only while modemst1, modemst2, fsg and fsc, found by
# PARTNAME in a fake sysfs, all read ro 1. One writable or missing: it reports
# the lock and stops, as with ENGINE_UNLOCK=0. A fake LOC client records what
# would go to the modem.
python3 -I - lib/omamobile-gnss-qmi-loc "$t/sys" <<'EOF' || fail "ENGINE_UNLOCK only with the NV partitions read-only"
import importlib.machinery, importlib.util, io, os, shutil, struct, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("qmiloc", sys.argv[1])
spec = importlib.util.spec_from_loader("qmiloc", loader)
q = importlib.util.module_from_spec(spec); loader.exec_module(q)
root = sys.argv[2]

def sysfs(ro=None, missing=()):
    """sda1.. with the NV partitions and two others; ro: {name: value}, default 1."""
    shutil.rmtree(root, ignore_errors=True)
    parts = ["boot", "modemst1", "modemst2", "fsg", "fsc", "system"]
    for i, name in enumerate(parts, 1):
        if name in missing:
            continue
        d = f"{root}/sda{i}"
        os.makedirs(d)
        open(f"{d}/uevent", "w").write(f"MAJOR=8\nMINOR={i}\nDEVNAME=sda{i}\nDEVTYPE=partition\nPARTN={i}\nPARTNAME={name}\n")
        open(f"{d}/ro", "w").write(f"{(ro or {}).get(name, 1 if name in q.NV_PARTS else 0)}\n")

class FakeLoc:
    def __init__(self):
        self.sent = []
    def call(self, msg, body=b"", ind=None, timeout=5.0):
        self.sent.append(msg)
        ok = q.tlv(2, struct.pack("<HH", 0, 0))
        if msg == q.GET_ENGINE_LOCK:  # locked: type 2 (MI), as stock left it
            return ok, q.parse_tlvs(q.tlv(1, struct.pack("<I", 0)) + q.tlv(0x10, struct.pack("<I", 2)))
        if msg == q.SET_ENGINE_LOCK:
            return q.parse_tlvs(ok), q.parse_tlvs(q.tlv(1, struct.pack("<I", 0)))
        raise AssertionError(f"unexpected LOC message {msg:#x}")

def run(unlock=True):
    loc = FakeLoc()
    err, sys.stderr = sys.stderr, io.StringIO()
    try:
        ok = q.Daemon("/nonexistent", unlock, False, sysblock=root, loc=loc).engine_lock()
        out = sys.stderr.getvalue()
    finally:
        sys.stderr = err
    return ok, loc.sent, out

# all four read-only: the lock is cleared
sysfs()
assert q.nv_not_read_only(root) == [], q.nv_not_read_only(root)
ok, sent, out = run()
assert ok and sent == [q.GET_ENGINE_LOCK, q.SET_ENGINE_LOCK], (ok, sent, out)
assert "cleared" in out, out
# ENGINE_UNLOCK=0: nothing sent but the question, whatever sysfs says
ok, sent, out = run(unlock=False)
assert not ok and sent == [q.GET_ENGINE_LOCK] and "doesn't allow clearing it" in out, (ok, sent, out)
# one writable: refused, the lock reported, no SET_ENGINE_LOCK
for name in q.NV_PARTS:
    sysfs(ro={name: 0})
    ok, sent, out = run()
    assert not ok and sent == [q.GET_ENGINE_LOCK], (name, ok, sent, out)
    assert f"{name} (sda" in out and "not read-only (ro 0)" in out and "engine is locked" in out, (name, out)
# one missing: refused, and the message names it
for name in q.NV_PARTS:
    sysfs(missing=(name,))
    ok, sent, out = run()
    assert not ok and sent == [q.GET_ENGINE_LOCK], (name, ok, sent, out)
    assert f"no {name} partition" in out and "engine is locked" in out, (name, out)
# no sysfs at all, or an ro file that can't be read: refused
shutil.rmtree(root)
ok, sent, _ = run()
assert not ok and sent == [q.GET_ENGINE_LOCK], sent
sysfs(); os.unlink(f"{root}/sda3/ro")
assert q.nv_not_read_only(root) == ["modemst2 (sda3) is not read-only (ro ?)"], q.nv_not_read_only(root)
# a second partition of the same name must be read-only too
sysfs(); os.makedirs(f"{root}/sdb1")
open(f"{root}/sdb1/uevent", "w").write("PARTNAME=fsg\n"); open(f"{root}/sdb1/ro", "w").write("0\n")
assert q.nv_not_read_only(root) == ["fsg (sdb1) is not read-only (ro 0)"], q.nv_not_read_only(root)
print("ok")
EOF
grep -c 'OMAMOBILE_GNSS_SYSBLOCK' lib/omamobile-gnss-qmi-loc >/dev/null &&
  fail "the daemon's read-only check must not take its sysfs from the environment"
grep -c '^    d = Daemon(args.fifo, dev\["ENGINE_UNLOCK"\], user\["INJECT_TIME"\])$' lib/omamobile-gnss-qmi-loc >/dev/null ||
  fail "the daemon reads the real sysfs"
echo "ok - ENGINE_UNLOCK clears the lock only while modemst1, modemst2, fsg and fsc read ro 1"

# The start script: with the device's qmi-loc.conf it execs the daemon, and
# its --stop and --stopped do nothing (SIGTERM ends the session).
printf 'ENGINE_UNLOCK=1\n' > "$t/qmi-loc.conf"
printf '#!/bin/sh\necho "daemon $*" >> "%s/log"\n' "$t" > "$t/daemon"
printf '#!/bin/sh\necho "chroot $*" >> "%s/log"\n' "$t" > "$t/chroot"
chmod +x "$t/daemon" "$t/chroot"
sed -e "s|/usr/lib/omamobile-vendor/omamobile-gnss-qmi-loc|$t/daemon|" \
    -e "s|/usr/lib/omamobile-vendor/omamobile-vendor-chroot|$t/chroot|" \
    -e "s|/var/lib/omamobile/gnss-bringup-started|$t/marker|" lib/omamobile-gnss-start > "$t/start"
: > "$t/log"
OMAMOBILE_GNSS_QMI_LOC_CONF=$t/qmi-loc.conf bash "$t/start" 2>/dev/null
grep -cxF "daemon --conf $t/qmi-loc.conf" "$t/log" >/dev/null || fail "qmi-loc: the start runs the daemon ($(cat "$t/log"))"
OMAMOBILE_GNSS_QMI_LOC_CONF=$t/qmi-loc.conf bash "$t/start" --stop 2>/dev/null
OMAMOBILE_GNSS_QMI_LOC_CONF=$t/qmi-loc.conf bash "$t/start" --stopped 2>/dev/null
[[ $(wc -l < "$t/log") == 1 ]] || fail "qmi-loc: --stop/--stopped must not run anything ($(cat "$t/log"))"
[[ ! -e $t/marker ]] || fail "qmi-loc: no hang marker"
# without the file the Pixel paths are unchanged
: > "$t/log"
OMAMOBILE_GNSS_QMI_LOC_CONF=$t/none OMAMOBILE_DT=$t bash "$t/start" --stop 2>/dev/null || true
grep -c '^daemon' "$t/log" >/dev/null && fail "no qmi-loc.conf: the daemon must not run"
grep -cxF 'chroot gnss stop' "$t/log" >/dev/null || fail "no qmi-loc.conf: the 7 Pro's stop still runs"

# Units and bridge
grep -qx 'ConditionPathExists=|/usr/share/omamobile/gnss/qmi-loc.conf' vendor/systemd/system/omamobile-gnss.service ||
  fail "the service runs on a qmi-loc phone"
grep -c '/run/omamobile-gnss/nmea_out' lib/omamobile-gnss-nmea >/dev/null || fail "the bridge reads the qmi-loc FIFO"
grep -c '/run/omamobile-gnss/nmea_out; do' vendor/systemd/system/omamobile-gnss-nmea.service >/dev/null ||
  fail "the bridge waits for the qmi-loc FIFO"
grep -c '^FIFO = "/run/omamobile-gnss/nmea_out"$' lib/omamobile-gnss-qmi-loc >/dev/null || fail "the daemon writes the FIFO the bridge reads"

# The Location switch: installed with no vendor files, no orbit timer, and
# "powered" is the session. Nothing here reads the machine the test runs on
# (a provisioned Pixel has the vendor files, the orbit file and regulators):
# systemctl is a stub, and the vendor root, the orbit file and the
# regulators point into $t, where none of them exists.
mkdir -p "$t/bin" "$t/machine"
gnss() { # gnss QMI_LOC_CONF ARGS...: run the switch with nothing of the machine
  local conf=$1; shift
  CALLS=$t/calls OMAMOBILE_GNSS_QMI_LOC_CONF=$conf PATH=$t/bin:$PATH \
    OMAMOBILE_GNSS_ROOT=$t/machine/gnss/root OMAMOBILE_GNSS_LTO_FILE=$t/machine/lto2.dat \
    OMAMOBILE_GNSS_REGULATORS=$t/machine/regulator bash bin/omamobile-gnss "$@"
}
cat > "$t/bin/systemctl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$*" in
  "is-enabled omamobile-gnss-nmea.socket") echo enabled ;;
  "is-active omamobile-gnss.service") echo active ;;
  *) echo inactive ;;
esac
STUB
chmod +x "$t/bin/systemctl"
out=$(gnss "$t/qmi-loc.conf" status --json)
grep -c '"installed":true' <<< "$out" >/dev/null || fail "qmi-loc: status must report installed ($out)"
grep -c '"powered":"yes"' <<< "$out" >/dev/null || fail "qmi-loc: powered follows the session ($out)"
out=$(gnss "$t/qmi-loc.conf" status)
grep -c 'vendor files\|LTO' <<< "$out" >/dev/null && fail "qmi-loc: no vendor-file or orbit lines ($out)"
grep -c '\*/gnss/root ]] && ! qmi_loc && systemctl enable --now "\$LTO_TIMER"' bin/omamobile-gnss >/dev/null ||
  fail "qmi-loc: "on" must not enable Broadcom's orbit timer"
out=$(gnss "$t/none" status --json)
grep -c '"installed":false' <<< "$out" >/dev/null || fail "no qmi-loc.conf and no vendor files: not installed ($out)"
echo "ok - the qmi-loc start, units, bridge and Location switch"
