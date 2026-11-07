#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise actual family selector and prove the archived legacy bytes."""
from pathlib import Path
import runpy
pkg=Path(__file__).resolve().parent.parent
m=runpy.run_path(str(pkg/'bin/omamobile-omarchy-patches'))
select=m['default_series']
assert select('/fixture',[('omarchy','4.0.6-2',None)]).endswith('/legacy-4.0.6')
for version in ['4.5.0-3','4.6.0-1']:
 try:select('/fixture',[('omarchy',version,None)])
 except m['Failure']:pass
 else:raise AssertionError('unsupported family accepted: '+version)
for p in (pkg/'patches').glob('*.patch'):assert p.read_bytes()==(pkg/'legacy-4.0.6'/p.name).read_bytes()
print('PASS: actual selector rejects unimplemented families; legacy archive byte-identical')
