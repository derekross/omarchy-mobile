#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the real source-family selector and retained legacy archive."""
from pathlib import Path
import runpy

package = Path(__file__).resolve().parent.parent
module = runpy.run_path(str(package / 'bin/omamobile-omarchy-patches'))
select = module['default_series']

assert select('/fixture', [('omarchy', '4.0.6-2', None)]).endswith('/legacy-4.0.6')
assert select('/fixture', [('omarchy', '4.5.0-3', None)]).endswith('/patches')
try:
    select('/fixture', [('omarchy', '4.6.0-1', None)])
except module['Failure']:
    pass
else:
    raise AssertionError('unsupported source family accepted')

assert len(list((package / 'legacy-4.0.6').glob('*.patch'))) == 28
print('PASS: actual selector rejects unsupported families; legacy archive retained')
