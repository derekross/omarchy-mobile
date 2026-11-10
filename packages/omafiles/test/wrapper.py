#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native wrapper activation only against owned stubs, never a real window."""
from pathlib import Path
from unittest.mock import patch
import os,runpy,subprocess,sys,tempfile
PKG=Path(__file__).resolve().parent.parent
wrapper=PKG/'bin/omamobile-files'
if not wrapper.is_file():raise SystemExit('Frontend wrapper has not been staged yet.')
module=runpy.run_path(str(wrapper),run_name='omafiles_wrapper_fixture')
location=module['location'];main=module['main'];g=main.__globals__
assert location('file:///tmp/Folder%20%E2%80%93%20Stra%C3%9Fe%20%25%23')=='/tmp/Folder – Straße %#'
for invalid in ['https://example.invalid/dir','file://remote-host/a','file:///tmp/a#fragment','/a\nfile','/a\0file']:
 try:location(invalid)
 except ValueError:pass
 else:raise AssertionError('nonlocal/malformed path accepted')
with tempfile.TemporaryDirectory(prefix='omafiles-wrapper-fixture-') as tmp:
 app=Path(tmp)/'app';app.mkdir();(app/'shell.qml').write_text('fixture');(app/'Commons').symlink_to('/usr/share/omarchy/shell/Commons',target_is_directory=True)
 target=str(Path(tmp)/"Folder ' $(no shell) Straße % #")
 original_is_dir=Path.is_dir
 def is_dir(p):return True if str(p)=='/usr/share/omarchy/shell/Commons' else original_is_dir(p)
 calls=[]
 class Result:
  def __init__(self,rc=0,text='ok\n'):self.returncode=rc;self.stdout=text;self.stderr=''
 def existing(command,**kwargs):
  assert kwargs.get('shell') is not True;calls.append(command)
  assert command==['quickshell','ipc','--path',str(app/'shell.qml'),'call','files','activate',target]
  return Result()
 with patch.dict(os.environ,{'OMAMOBILE_FILES_DIR':str(app)}),patch.object(Path,'is_dir',is_dir),patch.object(sys,'argv',['omamobile-files',target]),patch.object(g['subprocess'],'run',side_effect=existing):
  assert main()==0
 assert len(calls)==1,'an existing app is activated without a second window'
 calls.clear();ipc_count=[0]
 def fresh(command,**kwargs):
  assert kwargs.get('shell') is not True;calls.append(command)
  if command[:2]==['quickshell','ipc']:
   ipc_count[0]+=1;return Result(1,'') if ipc_count[0]==1 else Result()
  assert command==['quickshell','--no-duplicate','--daemonize','--path',str(app/'shell.qml')]
  return Result()
 with patch.dict(os.environ,{'OMAMOBILE_FILES_DIR':str(app)}),patch.object(Path,'is_dir',is_dir),patch.object(sys,'argv',['omamobile-files',target]),patch.object(g['subprocess'],'run',side_effect=fresh):
  assert main()==0
 assert len([c for c in calls if '--daemonize' in c])==1
 assert all('kill' not in c and 'restart' not in c for c in calls)
 calls.clear()
 with patch.dict(os.environ,{'OMAMOBILE_FILES_DIR':str(app)}),patch.object(g['os'],'geteuid',return_value=0),patch.object(sys,'argv',['omamobile-files']),patch.object(g['subprocess'],'run',side_effect=existing):
  try:result=main()
  except (ValueError,RuntimeError):pass
  else:assert result!=0,'root must be refused'
 assert not calls,'root refusal must precede all native app operations'
print('PASS: exact local-URI/Unicode/space/metacharacter argv, existing-instance activate, unique daemon startup, no main-shell restart/kill, root refusal')
