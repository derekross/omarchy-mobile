# SPDX-License-Identifier: MIT
"""Exercise the monitor seed with isolated descriptor and user files."""
from pathlib import Path
import os
import sys
import subprocess
import tempfile
source = Path('bin/omamobile-setup-user').read_text()
start = source.index('if omarchy-done ensure omamobile-monitor-scale; then')
fragment = source[start:source.index('\nfi', start) + 3]
# Exercise the same substitution using BSD sed's explicit backup suffix.
if sys.platform == 'darwin':
    fragment = fragment.replace('sed -i ', "sed -i '' ")
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    monitor = root / '.config/hypr/monitors.lua'
    monitor.parent.mkdir(parents=True)
    descriptor = root / 'device.conf'
    fragment = fragment.replace('/usr/share/omamobile/device.conf', str(descriptor))
    for contents, admit, expected in [('', True, '3'), ('MONITOR_SCALE=2\n', True, '2'),
                                      ('MONITOR_SCALE=2.5\n', True, '2.5'),
                                      ('MONITOR_SCALE=2\n', False, '4')]:
        descriptor.write_text(contents)
        monitor.write_text('local omarchy_monitor_scale = 4\n')
        command = 'omarchy-done() { test "$ADMIT" = yes; };\n' + fragment
        subprocess.run(['bash', '-c', command], check=True,
                       env=dict(os.environ, HOME=tmp, ADMIT='yes' if admit else 'no'))
        assert monitor.read_text() == f'local omarchy_monitor_scale = {expected}\n'
print('ok - monitor seed uses device scale, fallback and existing-user marker')
