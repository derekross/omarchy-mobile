#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise actual family selector and prove the archived legacy bytes."""
from pathlib import Path
import runpy
pkg=Path(__file__).resolve().parent.parent
m=runpy.run_path(str(pkg/'bin/omamobile-omarchy-patches'))
select=m['default_series']
assert select('/fixture',[('omarchy','4.0.6-2',None)]).endswith('/legacy-4.0.6')
assert select('/fixture',[('omarchy','4.5.0-3',None)]).endswith('/patches')
for version in ['4.6.0-1']:
 try:select('/fixture',[('omarchy',version,None)])
 except m['Failure']:pass
 else:raise AssertionError('unsupported family accepted: '+version)
assert len(list((pkg/'legacy-4.0.6').glob('*.patch')))==28
print('PASS: actual selector rejects unimplemented families; legacy archive retained')
