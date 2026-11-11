#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Real Emu with a synthetic ELF and own ADDVL/RDVL code; no HAL or phone."""
import gc
import importlib.machinery
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile

try:
    import unicorn
    from unicorn import arm64_const as A
    import elftools.elf.elffile
except ImportError:
    print('ok - extractor SVE execution # SKIP requires unicorn and pyelftools')
    raise SystemExit(0)

source = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / 'tools/extract-camera-data'
loader = importlib.machinery.SourceFileLoader('camera_sve_test', str(source))
tool = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(tool)


def fixture(path):
    # Minimal ELF64/AArch64: one load segment, empty relocation/symbol tables.
    # Own assembly: addvl x0, x0, #1; rdvl x1, #1; ret.
    data = bytearray(1024)
    ident = b'\x7fELF\x02\x01\x01' + bytes(9)
    struct.pack_into('<16sHHIQQQIHHHHHH', data, 0, ident, 3, 183, 1,
                     0x100, 64, 0x300, 0, 64, 56, 1, 64, 4, 1)
    struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, 0, 0, 0, len(data), 4096, 4096)
    struct.pack_into('<III', data, 0x100, 0x04205020, 0x04bf5021, 0xd65f03c0)
    names = b'\0.shstrtab\0.rela.plt\0.dynsym\0'
    data[0x200:0x200 + len(names)] = names
    for index, fields in enumerate([
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        (1, 3, 0, 0, 0x200, len(names), 0, 0, 1, 0),
        (11, 4, 0, 0, 0x240, 0, 3, 0, 8, 24),
        (21, 11, 0, 0, 0x240, 24, 1, 0, 8, 24),
    ]):
        struct.pack_into('<IIQQQQIIQQ', data, 0x300 + index * 64, *fields)
    path.write_bytes(data)


def execute(path):
    emu = tool.Emu(str(path))  # Exercise the production constructor unmodified.
    try:
        value = emu.call(0x100, 100)
        vector_bytes = emu.uc.reg_read(A.UC_ARM64_REG_X1)
        assert vector_bytes >= 16 and vector_bytes % 16 == 0
        assert value == 100 + vector_bytes
    finally:
        emu.elf.stream.close()
        del emu
        gc.collect()


def gates(missing):
    # Independent instruction fixture: distinguish integer SVE from FP access.
    uc = unicorn.Uc(unicorn.UC_ARCH_ARM64, unicorn.UC_MODE_ARM)
    uc.ctl_set_cpu_model(A.UC_CPU_ARM64_MAX)
    uc.mem_map(0x10000, 4096)
    uc.mem_write(0x10000, struct.pack('<III', 0x04205020, 0x04bf5021, 0xd65f03c0))
    uc.reg_write(A.UC_ARM64_REG_X0, 100)
    uc.reg_write(A.UC_ARM64_REG_LR, 0x10100)
    before = uc.reg_read(A.UC_ARM64_REG_CPACR_EL1)
    el3 = uc.cpr_read(3, 6, 1, 1, 2)
    zcr, el2 = uc.cpr_read(3, 0, 1, 2, 0), uc.cpr_read(3, 4, 1, 1, 2)
    mask = (3 << 16) | (3 << 20)
    desired = before | mask
    if missing == 'ZEN':
        desired &= ~(3 << 16)
    elif missing == 'FPEN':
        desired &= ~(3 << 20)
    desired_el3 = el3 & ~(1 << 8) if missing == 'EL3' else el3 | (1 << 8)
    uc.reg_write(A.UC_ARM64_REG_CPACR_EL1, desired)
    uc.cpr_write(3, 6, 1, 1, 2, desired_el3)
    assert uc.reg_read(A.UC_ARM64_REG_CPACR_EL1) == desired
    assert desired & ~mask == before & ~mask
    assert uc.cpr_read(3, 6, 1, 1, 2) == desired_el3
    assert desired_el3 & ~(1 << 8) == el3 & ~(1 << 8)
    assert uc.cpr_read(3, 0, 1, 2, 0) == zcr
    assert uc.cpr_read(3, 4, 1, 1, 2) == el2
    try:
        uc.emu_start(0x10000, 0x10100, count=10)
    except unicorn.UcError as error:
        assert missing in ('ZEN', 'EL3') and error.errno == unicorn.UC_ERR_EXCEPTION
    else:
        assert missing in (None, 'FPEN'), f'Missing {missing} did not trap'
        vector_bytes = uc.reg_read(A.UC_ARM64_REG_X1)
        assert vector_bytes >= 16 and vector_bytes % 16 == 0
        assert uc.reg_read(A.UC_ARM64_REG_X0) == 100 + vector_bytes


with tempfile.TemporaryDirectory(prefix='camera-sve-') as root:
    path = Path(root) / 'fixture.so'
    fixture(path)
    execute(path)
    print('ok - actual Emu executes synthetic ELF ADDVL/RDVL')
    for gate in (None, 'ZEN', 'EL3', 'FPEN'):
        gates(gate)
        print(f'ok - independent integer SVE gate {gate}')
