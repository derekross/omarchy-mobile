# SPDX-License-Identifier: MIT
# omamobile-hotdog-sar's messages, without a phone: the requests ask for
# non-wakeup delivery, and the Sensor Core's replies (shaped as captured on
# the phone, 2026-11-28) decode to the SUID and to a near/far sample.
import importlib.machinery
import importlib.util
import pathlib
import struct

path = pathlib.Path(__file__).resolve().parent.parent / "libexec" / "omamobile-hotdog-sar"
loader = importlib.machinery.SourceFileLoader("sar", str(path))
spec = importlib.util.spec_from_loader("sar", loader)
sar = importlib.util.module_from_spec(spec)
loader.exec_module(sar)
f = sar.field

# A request carries the UID, the message ID and a config asking for the
# application processor with non-wakeup delivery
req = dict((n, v) for n, _, v in sar.parse(sar.client_request((1, 2), sar.MSG_ENABLE_ON_CHANGE)))
assert struct.unpack("<I", req[2])[0] == 514
config = dict((n, v) for n, _, v in sar.parse(req[3]))
assert config == {1: sar.PROCESSOR_APSS, 2: sar.SUSPEND_NO_WAKEUP}, config
assert dict((n, v) for n, _, v in sar.parse(req[1])) == {1: 1, 2: 2}

# The SUID lookup's answer
uid = f(1, 1, 0x8867456bc70a6c70ca & ((1 << 64) - 1)) + f(2, 1, 0x7335663959f56988)
suid_resp = f(1, 2, b"sars") + f(2, 2, uid)
body = f(1, 5, sar.MSG_SUID_RESPONSE) + f(2, 1, 0) + f(3, 2, suid_resp)
msg = f(1, 2, f(1, 1, sar.SUID_UID[0]) + f(2, 1, sar.SUID_UID[1])) + f(2, 2, body)
[(u, mid, payload)] = list(sar.responses(msg))
assert u == sar.SUID_UID and mid == sar.MSG_SUID_RESPONSE
got = {n: v for n, _, v in sar.parse(payload)}
assert got[1] == b"sars"

# A grip around the bottom edge: [near, diff, offset, 0, 0], status 3
event = f(1, 2, struct.pack("<5f", 1, 24381, 11863, 0, 0)) + f(2, 0, 3)
values, status = sar.sensor_event(event)
assert values[:3] == [1.0, 24381.0, 11863.0] and status == 3, (values, status)
# The modem's QMI SAR RF state request: message 0x0001, TLV 0x01 a u32
assert sar.sar_rf_request(5, 8) == bytes.fromhex("0005000100070001040008000000")

# The Wi-Fi limit, in 0.25 dBm for both of ath10k's ranges; 0 is none
assert sar.wifi_command("phy0", 14) == ["iw", "phy", "phy0", "set", "sar_specs", "power", "0:56", "1:56"]
assert sar.wifi_command("phy0", 0)[-2:] == ["0:0", "1:0"]

# Near sends the backoff once, far gives it back, a new phy while near gets
# the limit, and the exit clears it
sent = []
b = object.__new__(sar.Backoff)
b.near, b.phys, b.modem = None, set(), None
b.send_modem = lambda: sent.append(("modem", b.near))
b.send_wifi = lambda phys: sent.append(("wifi", b.near, tuple(sorted(phys))))
b.list_phys = lambda: {"phy0"}
b.apply(True); b.apply(True)
assert sent == [("modem", True), ("wifi", True, ("phy0",))], sent
b.list_phys = lambda: {"phy0", "phy1"}
b.watch_wifi()
assert sent[-1] == ("wifi", True, ("phy1",)), sent
b.apply(False)
assert sent[-2:] == [("modem", False), ("wifi", False, ("phy0", "phy1"))], sent
del sent[:]; b.clear()
assert sent == [], sent
b.apply(True); del sent[:]; b.clear()
assert sent == [("modem", False), ("wifi", False, ("phy0", "phy1"))], sent
print("ok - SAR requests ask for non-wakeup delivery; replies decode; near lowers the modem and Wi-Fi, far and exit give it back")
