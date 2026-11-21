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

# Pinned, not counted (L-637): a new legacy fix adds a name here instead of
# breaking a literal count that every other PR also bumps.
legacy = {p.name[:4] for p in (package / 'legacy-4.0.6').glob('0*.patch')}
retained = {'0001', '0003', '0005', '0006', '0007', '0008', '0009', '0010',
            '0011', '0012', '0013', '0014', '0015', '0016', '0017', '0018',
            '0019', '0020', '0021', '0022', '0023', '0024', '0025', '0026',
            '0027', '0028', '0029', '0030'}
missing = retained - legacy
assert not missing, 'legacy archive lost %s' % sorted(missing)
assert (package / 'legacy-4.0.6/bridge-4.0.4-menu-first-frame.patch').is_file()
print('PASS: actual selector rejects unsupported families; legacy archive retained')
