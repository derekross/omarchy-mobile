# SPDX-License-Identifier: MIT
"""Actual4.5package rehearsal; hooks/scripts are never executed."""
import glob
import json
import os
import shutil
import subprocess


def actual(t, ex, version, make_root, run, ok, read, series, package, parse_qml):
    root, _ = make_root('real45', os.path.join(ex,'.MTREE'))
    for folder in ('patches','legacy-4.0.6'):
        shutil.copytree(os.path.join(package,folder),os.path.join(root,'usr/share/omamobile/omarchy',folder))
    private=os.path.join(root,'home/fixture/.local/share/omarchy/plugins/pixel.lock/Service.qml')
    os.makedirs(os.path.dirname(private));open(private,'w').write('synthetic private policy sentinel\n')
    auth='usr/share/omarchy/shell/services/AuthServiceStore.js'
    auth_before=read(root,auth)
    rc,out=run(root,'apply')  # actual version-selected production default
    ok(rc==0,'real4.5: version-selected shipped runtime series applies to signed aarch64 package')
    if rc: print(out);return
    state='var/lib/omamobile/omarchy-patches'
    status=json.load(open(os.path.join(root,state,'status.json')))
    ok(len(status['applied'])==len(glob.glob(os.path.join(series,'*.patch'))) and not status['upstream'], 'real4.5: all shipped runtime patches applied, not a source-only test')
    ok(status['series'].endswith('/patches'),'real4.5: selects4.5series rather than legacy')
    ok(open(private).read()=='synthetic private policy sentinel\n','real4.5: private clone untouched')
    ok('omamobile-update' in read(root,'usr/bin/omarchy-update'),'real4.5: packaged absolute bin symlink routes updater handoff correctly')
    notif='usr/share/omarchy/shell/plugins/notifications/'
    ok('inlineReplySupported: true' in read(root,notif+'Service.qml'),'real4.5: live-only reply server capability present')
    ok('card.replyOpen' in read(root,notif+'Toast.qml') and 'PointerDevice.TouchScreen' in read(root,notif+'Toast.qml'),'real4.5: scene toast touch/reply controls present')
    ok(os.path.isfile(os.path.join(root,notif+'components/NotificationCard.qml')) and os.path.isfile(os.path.join(root,notif+'NotificationLogic.js')),'real4.5: privateglance legacy presentational import/API restored')
    lock='usr/share/omarchy/shell/plugins/lock/'
    ok('notifications/quiet.json' in read(root,lock+'LockGlance.qml'),'real4.5: DND follows newquietstore')
    ok('Preserving existing mobile lock PAM' in read(root,'usr/bin/omarchy-apply-lock'),'real4.5: setup preserves existingmobilePAM/recoveryhooks')
    ok('OverlayWindow {' in read(root,'usr/share/omarchy/shell/plugins/menu/Menu.qml') and 'contentReady' in read(root,'usr/share/omarchy/shell/Ui/OverlayWindow.qml'),'real4.5: obsolete first-framebridge replaced by actualupstream geometry/scale guard')
    parse_qml(root, series)
    rc,out=run(root,'verify');ok(rc==0,'real4.5: verify patched package state')
    rc,out=run(root,'apply');ok(rc==0 and 'already applied' in out,'real4.5: apply idempotent')
    # The full adapted upstream actual-function fixture exercises4.5's store,
    # private address/markup policy, live ownership, reply and forget semantics.
    env=dict(os.environ);env['OMARCHY_SHELL_DIR']=os.path.join(root,'usr/share/omarchy/shell')
    node=shutil.which('node');r=subprocess.run([node,os.path.join(package,'test/upstream45/notifications/logic.cjs')],env=env,capture_output=True,text=True)
    ok(r.returncode==0,'real4.5: upstream+mobile actualnotificationfunctions pass against packagedpatched files')
    if r.returncode:print(r.stdout+r.stderr)
    r=subprocess.run([node,os.path.join(package,'test/notification-store45.cjs'),env['OMARCHY_SHELL_DIR']],capture_output=True,text=True)
    ok(r.returncode==0,'real4.5: keyed stores feed legacyglance with privacy/malformedrow/oldrecord coverage')
    if r.returncode:print(r.stdout+r.stderr)
    # Refuse a user-changed public target, never overwrite it on another apply.
    p=os.path.join(root,lock+'Service.qml');patched=open(p).read();open(p,'a').write('\n// synthetic external edit\n')
    rc,out=run(root,'apply');ok(rc!=0 and open(p).read().endswith('// synthetic external edit\n'),'real4.5: external publiclock edits cause refusal, preserved')
    open(p,'w').write(patched)
    rc,out=run(root,'restore');ok(rc==0,'real4.5: restore original packagedfiles')
    ok(read(root,auth)==auth_before and open(private).read()=='synthetic private policy sentinel\n','real4.5: restore leaves authstore and privateclone unchanged')
    # Unknown future families must not borrow4.5/legacy patch contexts.
    root2,db=make_root('real-unknown',os.path.join(ex,'.MTREE'))
    d=os.path.join(db,'desc');s=open(d).read().replace(version,'4.6.0-1');open(d,'w').write(s)
    rc,out=run(root2,'apply');ok(rc!=0 and 'no qualified mobile patch series' in out,'unknown Omarchy family refuses before patch writes')
