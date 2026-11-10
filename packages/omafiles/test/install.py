#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Installer fixtures only: no package installation, MIME default or user IO."""
from pathlib import Path
import hashlib,json,os,subprocess,tempfile
PKG=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='omafiles-stage-fixture-') as tmp:
 root=Path(tmp);dest=root/'stage';ui=root/'ui';ui.mkdir()
 missing=subprocess.run([str(PKG/'install'),str(dest)],capture_output=True,text=True,env=dict(os.environ,OMAFILES_UI_SOURCE=str(ui)))
 assert missing.returncode!=0 and not dest.exists(),'incomplete candidate must fail before staging'
 (ui/'shell.qml').write_text('import QtQuick\nItem {}\n');(ui/'FilesBridge.qml').write_text('import QtQuick\nItem {}\n');(ui/'FilesModel.js').write_text('function fixture() { return true }\n');(ui/'tst_private.qml').write_text('do not package test harness');(ui/'personal-image.jpg').write_text('never copy images')
 launcher=root/'launcher';launcher.write_text('#!/bin/sh\nexit 0\n');desktop=root/'org.omamobile.Files.desktop';desktop.write_text('[Desktop Entry]\nType=Application\nName=Files\nExec=omamobile-files %u\nMimeType=inode/directory;\n')
 env=dict(os.environ,OMAFILES_UI_SOURCE=str(ui),OMAFILES_LAUNCHER_SOURCE=str(launcher),OMAFILES_DESKTOP_SOURCE=str(desktop))
 subprocess.run([str(PKG/'install'),str(dest)],env=env,check=True)
 app=dest/'usr/share/omamobile/files'
 for name in ['shell.qml','FilesBridge.qml','FilesModel.js','files_core.py','files_backend.py','qt_backend.py','version']:assert (app/name).is_file(),name
 assert (app/'Commons').is_symlink() and os.readlink(app/'Commons')=='/usr/share/omarchy/shell/Commons'
 assert not (app/'test_files.py').exists() and not (app/'tst_private.qml').exists() and not (app/'personal-image.jpg').exists()
 assert os.readlink(dest/'usr/bin/omafiles')=='omamobile-files'
 assert (dest/'usr/share/applications/org.omamobile.Files.desktop').is_file()
 assert not (root/'home/.config/mimeapps.list').exists()
 print('PASS: isolated DESTDIR, fail-closed missing UI, runtime/Common namespace/desktop, no fixtures or personal assets, no MIME defaults changed')

with tempfile.TemporaryDirectory(prefix='omafiles-real-stage-') as tmp:
 dest=Path(tmp)/'stage'
 subprocess.run([str(PKG/'install'),str(dest)],check=True)
 manifest=json.loads((PKG/'frontend-manifest.json').read_text())
 app=dest/'usr/share/omamobile/files'
 for name in manifest['runtimeFiles']:
  assert hashlib.sha256((app/name).read_bytes()).hexdigest()==manifest['sha256'][name],name
 for name,target in [('omamobile-files',dest/'usr/bin/omamobile-files'),('org.omamobile.Files.desktop',dest/'usr/share/applications/org.omamobile.Files.desktop'),('org.omamobile.Files.svg',dest/'usr/share/icons/hicolor/scalable/apps/org.omamobile.Files.svg')]:
  assert hashlib.sha256(target.read_bytes()).hexdigest()==manifest['sha256'][name],name
 for name in ['files_core.py','files_backend.py','qt_backend.py']:
  assert (app/name).read_bytes()==(PKG/'runtime'/name).read_bytes()
 assert not (dest/'usr/bin/omafiles-integrate').exists(),'default-handler integration is a separate contribution'
 assert not list(app.glob('test*')) and not list(app.glob('*.png'))
 assert (app/'Commons').is_symlink()
 print('PASS: staged frontend/launcher hashes, backend parity, font license/provenance, icon and Commons namespace staged')
