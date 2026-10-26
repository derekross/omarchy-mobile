#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from pathlib import Path
import tempfile,subprocess,os
source=(Path(__file__).resolve().parents[1]/'vendor/bin/flame-storage-guard').read_text()
body='UFS_RW="boot_b userdata"'+source.split('UFS_RW="boot_b userdata"',1)[1].split('\nwhile :; do',1)[0]
with tempfile.TemporaryDirectory() as d:
 p=Path(d); sys=p/'sys';dev=p/'dev';bin=p/'bin'
 for x in (sys,dev,bin):x.mkdir()
 body=body.replace('/sys/class/block/',str(sys)+'/').replace('/dev/',str(dev)+'/').replace('[ -b ','[ -f ')
 (p/'guard').write_text('say() { echo "$*" >&2; }\n'+body+'\nstorage_guard\n')
 (bin/'blockdev').write_text('#!/bin/sh\n[ "$1" = --setro ] || exit 92\n[ "${MODE:-}" != fail ] || exit 1\n[ "${MODE:-}" != lie ] || exit 0\necho 1 > "$SYS/${2##*/}/ro"\n')
 (bin/'blockdev').chmod(0o755)
 def add(n,part='',ro='0'):
  (sys/n).mkdir();(sys/n/'ro').write_text(ro+'\n');(sys/n/'uevent').write_text('PARTNAME='+part+'\n' if part else '');(dev/n).touch()
 def run(mode=''):
  return subprocess.run(['sh',str(p/'guard')],env=dict(os.environ,PATH=str(bin)+':'+os.environ['PATH'],SYS=str(sys),MODE=mode),capture_output=True)
 for n,part in [('sda',''),('sda2','persist'),('sda6','boot_a'),('sda7','boot_b'),('sda15','userdata'),('sdb',''),('sde33','devinfo'),('sdf2','modemst1'),('sdf3','userdata')]:add(n,part)
 assert run().returncode==0
 assert not (dev/'sda').exists()
 for n in ['sda2','sda6','sdb','sde33','sdf2','sdf3']:assert (sys/n/'ro').read_text().strip()=='1',n
 for n in ['sda7','sda15']:assert (sys/n/'ro').read_text().strip()=='0',n
 (sys/'sda7'/'ro').write_text('1\n');(dev/'sda').touch();assert run().returncode==0;assert not (dev/'sda').exists();assert (sys/'sda7'/'ro').read_text().strip()=='1'
 add('sdg');assert run('fail').returncode!=0;assert run('lie').returncode!=0
 print('Root guard: exact sda allowlist, all calibration protected, other-LUN userdata rejected, whole node removed, existing RO preserved, failure closed')
