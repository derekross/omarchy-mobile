# SPDX-License-Identifier: MIT
"""Rehearse the actual 4.5 package without executing its hooks or scripts."""
import glob
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def actual(t, ex, version, make_root, run, ok, read, series, package, parse_qml):
    root, _ = make_root('real45', os.path.join(ex, '.MTREE'))
    for folder in ('patches', 'legacy-4.0.6'):
        shutil.copytree(
            os.path.join(package, folder),
            os.path.join(root, 'usr/share/omamobile/omarchy', folder),
        )

    policy_fixture = Path(root) / 'home/fixture/.config/omarchy/plugins/custom-lock/Policy.qml'
    policy_fixture.parent.mkdir(parents=True)
    sentinel = 'synthetic external policy fixture\n'
    policy_fixture.write_text(sentinel)
    auth = 'usr/share/omarchy/shell/services/AuthServiceStore.js'
    auth_before = read(root, auth)

    rc, output = run(root, 'apply')
    ok(rc == 0, 'real4.5: version-selected runtime series applies to signed aarch64 package')
    if rc:
        print(output)
        return

    pam = subprocess.run(
        [sys.executable, os.path.join(package, 'test', 'mobile-pam-preserve.py'),
         os.path.join(root, 'usr/bin/omarchy-apply-lock')],
        capture_output=True, text=True,
    )
    ok(pam.returncode == 0, 'real4.5: actual PAM preservation guard passes isolated behavioral tests')
    if pam.returncode:
        print(pam.stdout + pam.stderr)

    status_path = Path(root) / 'var/lib/omamobile/omarchy-patches/status.json'
    status = json.loads(status_path.read_text())
    count = len(glob.glob(os.path.join(series, '*.patch')))
    ok(len(status['applied']) == count and not status['upstream'],
       'real4.5: every shipped runtime patch applied')
    ok(status['series'].endswith('/patches'), 'real4.5: selects the 4.5 family')
    ok(policy_fixture.read_text() == sentinel, 'real4.5: external policy fixture untouched')
    ok('omamobile-update' in read(root, 'usr/bin/omarchy-update'),
       'real4.5: packaged absolute bin symlink routes updater handoff correctly')

    notifications = 'usr/share/omarchy/shell/plugins/notifications/'
    ok('inlineReplySupported: true' in read(root, notifications + 'Service.qml'),
       'real4.5: live-only reply capability present')
    toast = read(root, notifications + 'Toast.qml')
    ok('card.replyOpen' in toast and 'PointerDevice.TouchScreen' in toast,
       'real4.5: scene toast touch/reply controls present')
    ok(os.path.isfile(os.path.join(root, notifications + 'components/NotificationCard.qml'))
       and os.path.isfile(os.path.join(root, notifications + 'NotificationLogic.js')),
       'real4.5: lock-glance presentation imports remain compatible')

    lock = 'usr/share/omarchy/shell/plugins/lock/'
    ok('notifications/quiet.json' in read(root, lock + 'LockGlance.qml'),
       'real4.5: DND follows the keyed quiet store')
    ok('Preserving existing mobile lock PAM' in read(root, 'usr/bin/omarchy-apply-lock'),
       'real4.5: setup preserves existing mobile PAM and recovery hooks')
    ok('OverlayWindow {' in read(root, 'usr/share/omarchy/shell/plugins/menu/Menu.qml')
       and 'contentReady' in read(root, 'usr/share/omarchy/shell/Ui/OverlayWindow.qml'),
       'real4.5: first-frame bridge replaced by upstream geometry/scale guard')
    parse_qml(root, series)

    rc, _ = run(root, 'verify')
    ok(rc == 0, 'real4.5: verify patched package state')
    rc, output = run(root, 'apply')
    ok(rc == 0 and 'already applied' in output, 'real4.5: apply is idempotent')

    env = dict(os.environ)
    env['OMARCHY_SHELL_DIR'] = os.path.join(root, 'usr/share/omarchy/shell')
    node = shutil.which('node')
    node_tests = [
        ('upstream45/notifications/logic.cjs', [], 'actual notification functions'),
        ('notification-store45.cjs', [env['OMARCHY_SHELL_DIR']], 'keyed store and lock-glance compatibility'),
        ('notification-snapshot.cjs', [
            os.path.join(env['OMARCHY_SHELL_DIR'], 'plugins/notifications/Service.qml'),
            os.path.join(env['OMARCHY_SHELL_DIR'], 'plugins/notifications'),
        ], 'startup-safe snapshot notification deletion'),
    ]
    for script, arguments, label in node_tests:
        if not node:
            print(f'ok - real4.5: {label} # SKIP no node')
            continue
        result = subprocess.run(
            [node, os.path.join(package, 'test', script), *arguments],
            env=env, capture_output=True, text=True,
        )
        ok(result.returncode == 0, f'real4.5: {label}')
        if result.returncode:
            print(result.stdout + result.stderr)

    # Refuse externally changed package files instead of overwriting them.
    lock_service = Path(root) / (lock + 'Service.qml')
    patched = lock_service.read_text()
    lock_service.write_text(patched + '\n// synthetic external edit\n')
    rc, _ = run(root, 'apply')
    ok(rc != 0 and lock_service.read_text().endswith('// synthetic external edit\n'),
       'real4.5: external lock edits cause refusal and remain unchanged')
    lock_service.write_text(patched)
    rc, _ = run(root, 'restore')
    ok(rc == 0, 'real4.5: restore original packaged files')
    ok(read(root, auth) == auth_before and policy_fixture.read_text() == sentinel,
       'real4.5: restore leaves authentication store and external fixture unchanged')

    # An unsupported future version must not borrow either family's contexts.
    future_root, database = make_root('real-unknown', os.path.join(ex, '.MTREE'))
    description = Path(database) / 'desc'
    description.write_text(description.read_text().replace(version, '4.6.0-1'))
    rc, output = run(future_root, 'apply')
    ok(rc != 0 and 'no qualified mobile patch series' in output,
       'unknown Omarchy family refuses before patch writes')
