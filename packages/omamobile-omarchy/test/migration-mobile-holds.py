#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the real migration wrapper; migration inputs are inert fixtures."""
from pathlib import Path
import tempfile,subprocess,os,shutil
pkg=Path(__file__).resolve().parent.parent
ids=['1789764927','1791367434','1792648436','1791125650']
with tempfile.TemporaryDirectory(prefix='omamobile-migration-holds-') as tmp:
 root=Path(tmp);home=root/'home';real=root/'real';real.mkdir();tree=root/'omarchy';(tree/'migrations').mkdir(parents=True)
 for name in ids:(tree/'migrations'/f'{name}.sh').write_text('echo \"Named mobile migration\"\ntrue\n')
 # A renamed PAM rewriter must also be caught by semantics, not only IDs.
 (tree/'migrations/9999999999.sh').write_text('echo "Configure auth"\nomarchy-apply-lock\n')
 (tree/'migrations/9999999998.sh').write_text('echo "Harmless fixture"\ntrue\n')
 marker=root/'real-called';(real/'omarchy-migrate').write_text('#!/bin/bash\nset -eu\ntouch "'+str(marker)+'"\nfor name in 1789764927 1791367434 1792648436 1791125650 9999999999; do\n  test -f "$HOME/.local/state/omarchy/migrations/$name.sh" || { echo "UNHELD:$name" >&2; exit 90; }\ndone\n');(real/'omarchy-migrate').chmod(0o755)
 conf=root/'pacman.conf';conf.write_text('[options]\n[omamobile]\n[omarchy]\n[core]\n')
 pam=root/'pam';pam.mkdir();password=pam/'omarchy-lock-password';fp=pam/'omarchy-lock-fingerprint';password.write_text('custom PIN stack unchanged\n');fp.write_text('auth required pam_fprintd.so max-tries=1\n');before=(password.read_bytes(),fp.read_bytes())
 for generic in ['1','0']:
  shutil.rmtree(home,ignore_errors=True);marker.unlink(missing_ok=True)
  env=dict(os.environ,HOME=str(home),OMARCHY_PATH=str(tree),OMAMOBILE_REAL_BIN=str(real),OMAMOBILE_PACMAN_CONF=str(conf),OMAMOBILE_HOLD_MIGRATIONS=generic)
  result=subprocess.run(['bash',str(pkg/'lib/update-bin/omarchy-migrate')],env=env,capture_output=True,text=True,check=True)
  state=home/'.local/state/omarchy/migrations';held=home/'.local/state/omamobile/update/held-migrations';text=held.read_text()
  for name in ids:assert (state/(name+'.sh')).is_file() and name+'.sh\t' in text
  assert marker.exists();assert (password.read_bytes(),fp.read_bytes())==before
  assert (state/'9999999999.sh').exists(), 'PAM rewrites stay held even with generic desktop matches disabled'
  assert not (state/'9999999998.sh').exists()
  print('PASS: named and semantic mobile holds, harmless migration unaffected; generic holds='+generic)
