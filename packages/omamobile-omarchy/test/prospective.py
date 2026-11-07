#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prospective gate + transaction ordering, using real patches and fake tools."""
from pathlib import Path
import copy,contextlib,io,json,os,runpy,shlex,subprocess,tempfile
PKG=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='omamobile-prospective-test-') as tmp:
 root=Path(tmp);oldenv=dict(os.environ)
 os.environ.update(HOME=str(root/'home'),XDG_RUNTIME_DIR=str(root/'run'),XDG_STATE_HOME=str(root/'state'),OMAMOBILE_REAL_BIN=str(root/'real'),OMAMOBILE_PACMAN_CONF=str(root/'pacman.conf'))
 (root/'real').mkdir();(root/'pacman.conf').write_text('[options]\n[omamobile]\n[omarchy]\n[core]\n')
 fixture=subprocess.run(['python3','-I',str(PKG/'test/prospective-fixture.py'),str(PKG),str(root)],capture_output=True,text=True,check=True)
 for line in fixture.stdout.splitlines():key,value=shlex.split(line)[1].split('=',1);os.environ[key]=value
 os.environ['OMAMOBILE_PACMAN']='fake-pacman'
 module=runpy.run_path(str(PKG/'bin/omamobile-update'),run_name='prospective_tests');gate=module['prospective_check'];g=gate.__globals__
 checksum=(root/'candidate-sha').read_text();policy_path=root/'qualified.json';original_policy=json.loads(policy_path.read_text());calls=[]
 real_run=g['subprocess'].run;real_popen=g['subprocess'].Popen
 class Answer:
  def __init__(self,code=0,out='',err=''):self.returncode=code;self.stdout=out;self.stderr=err
 def fake_run(command,*args,**kwargs):
  if command[0]=='fake-pacman':
   calls.append(command)
   if '-Sp' in command:return Answer(out='omarchy\t4.5.0-3\taarch64\t'+checksum+'\n')
   if '-Sup' in command:return Answer(out='omarchy 4.5.0-3\n')
  if command[0]==str(root/'real/omarchy-update-pacman'):
   calls.append(command);return Answer()
  return real_run(command,*args,**kwargs)
 g['subprocess'].run=fake_run
 def reset():policy_path.write_text(json.dumps(original_policy));policy_path.chmod(0o644)
 def refused(label,change,expected):
  reset();change();answer=gate([('omarchy','4.5.0-3')]);assert not answer['ok'] and expected in answer['problem'],(label,answer);print('PASS:',label)
 try:
  answer=gate([('omarchy','4.5.0-3')]);assert answer['ok'] and answer['rehearsal']['reverse_byte_identical'];print('PASS: actual prospective archive apply/reverse')
  refused('unreviewed candidate stops before update',lambda:policy_path.write_text(json.dumps({'version':1,'candidates':[]})),'no approved')
  refused('writable policy refused',lambda:policy_path.chmod(0o666),'protected regular')
  def signature_false():
   d=copy.deepcopy(original_policy);d['candidates'][0]['signature_verified']=False;policy_path.write_text(json.dumps(d))
  refused('signature qualification required',signature_false,'signature/replay')
  series=Path(os.environ['OMAMOBILE_PROSPECTIVE_SERIES']);patch=series/'0001-version.patch';original_patch=patch.read_text()
  refused('changed series refused',lambda:patch.write_text(original_patch+'\n'),'series_sha256');patch.write_text(original_patch)
  archive=next((root/'cache').glob('*.zst'));original_archive=archive.read_bytes()
  refused('changed cached archive refused',lambda:archive.write_bytes(original_archive+b'changed'),'not cached');archive.write_bytes(original_archive)
  reset();answer=gate([('omarchy','4.6.0-1')]);assert not answer['ok'] and 'no qualified mobile source family' in answer['problem'];print('PASS: unknown future family refuses')
  # A matching series digest alone cannot bless an inapplicable patch.
  reset();patch.write_text(original_patch.replace('-4.5.0','-does-not-match'))
  d=copy.deepcopy(original_policy);d['candidates'][0]['series_sha256']=g['series_digest'](g['prospective_tool'](),str(series));policy_path.write_text(json.dumps(d))
  answer=gate([('omarchy','4.5.0-3')]);assert not answer['ok'] and 'does not apply' in answer['problem'];patch.write_text(original_patch);print('PASS: rehearsal failure blocks even with matching policy digest')
  # The actual named transaction stage refreshes first; refuses before install.
  helper=root/'real/omarchy-update-pacman';helper.write_text('fixture');reset();calls.clear();policy_path.write_text('{"version":1,"candidates":[]}')
  with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):code=module['system_packages']([])
  tx=[x for x in calls if x[0]==str(helper)];assert code==5 and tx==[[str(helper),'-Sy','--noconfirm']],calls;print('PASS: refreshed unknown candidate never reaches package transaction')
  reset();calls.clear()
  with contextlib.redirect_stdout(io.StringIO()):code=module['system_packages']([])
  tx=[x for x in calls if x[0]==str(helper)];assert code==0 and tx[0][1]=='-Sy' and tx[-1][1]=='-Su' and 'omarchy=4.5.0-3' in tx[-1] and all('y' not in arg for arg in tx[-1][1:2]),tx;print('PASS: approved plan transacts without refresh and with exact Omarchy pin')
 finally:
  g['subprocess'].run=real_run;g['subprocess'].Popen=real_popen;os.environ.clear();os.environ.update(oldenv)
