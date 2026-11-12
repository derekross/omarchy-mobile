#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the real wrapper against inert migrations; no package manager is run."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PACKAGE = Path(__file__).resolve().parent.parent
NAMED = ['1789764927', '1791367434', '1791125650', '1791403310', '1790042972']
# Reviewed and released: Omarchy's own file, so a change of its text that
# would match a hold pattern shows here
RELEASED = ['1792648436']
SEMANTIC = ['9999999999', '9999999997']

with tempfile.TemporaryDirectory(prefix='omamobile-migration-holds-') as tmp:
    root = Path(tmp)
    home = root / 'home'
    real = root / 'real'
    real.mkdir()
    tree = root / 'omarchy'
    migrations = tree / 'migrations'
    migrations.mkdir(parents=True)
    for name in NAMED:
        (migrations / f'{name}.sh').write_text('echo "Named migration"\ntrue\n')
    for name in RELEASED:
        shutil.copy(PACKAGE / f'test/upstream45/migrations/{name}.sh', migrations / f'{name}.sh')
    (migrations / '9999999999.sh').write_text('omarchy-apply-lock\n')
    (migrations / '9999999997.sh').write_text('omarchy-pkg-add omarchy-hyprland-titlebars\n')
    (migrations / '9999999998.sh').write_text('echo "Harmless fixture"\ntrue\n')
    (migrations / '9999999996.sh').write_text('mkinitcpio -P\n')

    marker = root / 'real-called'
    runner = real / 'omarchy-migrate'
    runner.write_text(
        '#!/bin/bash\nset -eu\n'
        f'touch "{marker}"\n'
        'for name in ' + ' '.join(NAMED + SEMANTIC) + '; do\n'
        '  test -f "$HOME/.local/state/omarchy/migrations/$name.sh" || '
        '{ echo "UNHELD:$name" >&2; exit 90; }\n'
        'done\n'
    )
    runner.chmod(0o755)
    conf = root / 'pacman.conf'
    conf.write_text('[options]\n[omamobile]\n[omarchy]\n[core]\n')
    pam = root / 'pam'
    pam.mkdir()
    password = pam / 'omarchy-lock-password'
    fingerprint = pam / 'omarchy-lock-fingerprint'
    password.write_text('custom PIN stack unchanged\n')
    fingerprint.write_text('auth required pam_fprintd.so max-tries=1\n')
    before = (password.read_bytes(), fingerprint.read_bytes())

    for flag in ['1', '0', '', '2', 'false', 'unexpected']:
        shutil.rmtree(home, ignore_errors=True)
        marker.unlink(missing_ok=True)
        env = dict(
            os.environ,
            HOME=str(home),
            OMARCHY_PATH=str(tree),
            OMAMOBILE_REAL_BIN=str(real),
            OMAMOBILE_PACMAN_CONF=str(conf),
            OMAMOBILE_HOLD_MIGRATIONS=flag,
        )
        result = subprocess.run(
            ['bash', str(PACKAGE / 'lib/update-bin/omarchy-migrate')],
            env=env, capture_output=True, text=True, check=True,
        )
        state = home / '.local/state/omarchy/migrations'
        held = home / '.local/state/omamobile/update/held-migrations'
        text = held.read_text()
        for name in NAMED + SEMANTIC:
            assert (state / f'{name}.sh').is_file(), name
            assert f'{name}.sh\t' in text, name
        assert marker.exists()
        assert (password.read_bytes(), fingerprint.read_bytes()) == before
        assert not (state / '9999999998.sh').exists()
        for name in RELEASED:
            assert not (state / f'{name}.sh').exists(), name
            assert f'{name}.sh\t' not in text, name
        assert (state / '9999999996.sh').exists() == (flag != '0')
        assert 'it mentions starts' not in result.stdout
        assert 'installs titlebars pinned to a different Hyprland build.' in result.stdout
        print(f'PASS: named/semantic holds and safe flag normalization ({flag!r})')
