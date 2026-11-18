#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The private Unicorn copy under DIR, loaded and run; no phone, no HAL.

    sve-check.py DIR                    our own checks (below)
    sve-check.py DIR TEST TOOL          the repository's
                                        tests/extract-camera-sve.py on TOOL

Run it with python3 -I -B: DIR is put first on the module path here, as
omamobile-provision does for the camera step. Either way it then checks
that the unicorn module and the libunicorn.so.2 this process has mapped are
the ones under DIR, so a copy that silently fell back to the system's
library fails.

Our own checks: the binding and the library are 2.1.4 and emulate AArch64;
with the "max" CPU and the SVE gates open as tools/extract-camera-data
opens them, our own three instructions (addvl x0, x0, #1; rdvl x1, #1; ret)
run and agree on a vector length. In Unicorn 2.1.4 built with assert() left
in, that first SVE instruction ends the process (SIGABRT) in
sve_zcr_get_valid_len: test/all reports that exit as the abort.
"""
import os
import runpy
import struct
import sys

private = os.path.realpath(sys.argv[1])
sys.path.insert(0, private)
import unicorn  # noqa: E402
from unicorn import arm64_const as A  # noqa: E402


def provenance():
    module = os.path.realpath(unicorn.__file__)
    assert module.startswith(private + os.sep), f"the unicorn module is {module}, not under {private}"
    with open("/proc/self/maps") as maps:
        libs = sorted({line.split()[-1] for line in maps if "libunicorn" in line})
    assert libs, "no libunicorn is mapped"
    for lib in libs:
        assert os.path.realpath(lib).startswith(private + os.sep), f"the mapped library is {lib}, not under {private}"
    return libs[0]


if len(sys.argv) == 4:
    test, tool = sys.argv[2], sys.argv[3]
    sys.argv = [test, tool]
    runpy.run_path(test, run_name="__main__")
    provenance()
    raise SystemExit(0)

assert unicorn.__version__ == "2.1.4", unicorn.__version__
assert unicorn.uc_version()[2] >> 8 == 0x020104, unicorn.uc_version()  # the library's own
assert unicorn.uc_arch_supported(unicorn.UC_ARCH_ARM64)
print(f"ok - the binding and the library are 2.1.4, with the AArch64 target ({provenance()})")

uc = unicorn.Uc(unicorn.UC_ARCH_ARM64, unicorn.UC_MODE_ARM)
uc.ctl_set_cpu_model(A.UC_CPU_ARM64_MAX)
uc.mem_map(0x10000, 4096)
uc.mem_write(0x10000, struct.pack("<III", 0x04205020, 0x04BF5021, 0xD65F03C0))
uc.reg_write(A.UC_ARM64_REG_X0, 100)
uc.reg_write(A.UC_ARM64_REG_LR, 0x10100)
uc.reg_write(A.UC_ARM64_REG_CPACR_EL1, uc.reg_read(A.UC_ARM64_REG_CPACR_EL1) | (3 << 16) | (3 << 20))
uc.cpr_write(3, 6, 1, 1, 2, uc.cpr_read(3, 6, 1, 1, 2) | (1 << 8))  # CPTR_EL3.EZ
uc.emu_start(0x10000, 0x10100, count=10)
vector_bytes = uc.reg_read(A.UC_ARM64_REG_X1)
assert vector_bytes >= 16 and vector_bytes % 16 == 0, vector_bytes
assert uc.reg_read(A.UC_ARM64_REG_X0) == 100 + vector_bytes
print(f"ok - ADDVL and RDVL run on the max CPU and agree ({vector_bytes} bytes per vector)")
