#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the actual boot_arch shell with isolated metadata and write spies."""
from pathlib import Path
import subprocess,tempfile,os,json

repo=Path(__file__).resolve().parent.parent
source=(repo/'initramfs/init').read_text()
body='boot_arch() {'+source.split('boot_arch() {',1)[1].split('\n}\n',1)[0]+'\n}\n'
cases=[('f2fs',0,1,False),('android_ext4',0,0,False),('no_label',0,0,False),
       ('our_root',0,0,True),('corrected',1,0,True),('needs_reboot',2,0,False),
       ('uncorrected',4,0,False),('operational_error',8,0,False)]
for name,fsck,header_error,can_mount in cases:
 with tempfile.TemporaryDirectory() as tmp:
  p=Path(tmp);(p/'block/sda48').mkdir(parents=True)
  (p/'block/sda48/uevent').write_text('PARTNAME=userdata\n')
  (p/'block/sda48/ro').write_text('0\n');(p/'cmdline').write_text('rdinit=/init\n');(p/'policy').write_text('omamobile-root\n')
  script=body.replace('/etc/omamobile-root-label',str(p/'policy')).replace('/sys/block/sda',str(p/'block')).replace('/proc/cmdline',str(p/'cmdline'))
  label='userdata' if name=='android_ext4' else '' if name=='no_label' else 'omamobile-root'
  spies=f'''
say() {{ printf 'say %s\n' "$*" >> "$LOG"; }}
dumpe2fs() {{ echo header >> "$LOG"; printf 'Filesystem volume name:   %s\n' '{label}'; return {header_error}; }}
e2fsck() {{ echo fsck >> "$LOG"; return {fsck}; }}
grow_root() {{ echo grow >> "$LOG"; }}
mkdir() {{ echo mkdir >> "$LOG"; }}
mount() {{ echo mount >> "$LOG"; return 1; }}
'''
  f=p/'run.sh';f.write_text(spies+script+'boot_arch\n')
  env=os.environ.copy();env['LOG']=str(p/'calls')
  shell=json.loads(env.get('OMAMOBILE_BOOT_ARCH_TEST_SHELL','["/bin/sh"]'))
  result=subprocess.run(shell+[str(f)],env=env,capture_output=True,text=True,timeout=5)
  assert result.returncode==1,(name,result.stdout,result.stderr)
  calls=(p/'calls').read_text().splitlines()
  assert ('mount' in calls)==can_mount,(name,calls)
  if name in ('f2fs','android_ext4','no_label'):
   assert not any(c in calls for c in ['fsck','grow','mkdir','mount']),(name,calls)
  if fsck>1:assert 'grow' not in calls and 'mount' not in calls,(name,calls)
  if can_mount:assert calls.index('header')<calls.index('fsck')<calls.index('grow')<calls.index('mount')
  print('ok -',name,'refuses unsafe repair/mount' if not can_mount else 'label precedes repair and mount')
