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
print("ok - SAR requests ask for non-wakeup delivery; replies decode")
