#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Synthetic signed-policy inputs for updater tests; never a production approval."""
from pathlib import Path
import io,json,os,runpy,shlex,subprocess,sys,tarfile
pkg=Path(sys.argv[1]).resolve();root=Path(sys.argv[2]).resolve();series=root/'prospective-series';series.mkdir(exist_ok=True)
(series/'0001-version.patch').write_text('--- a/version\n+++ b/version\n@@ -1 +1 @@\n-4.5.0\n+4.5.0-mobile\n')
cache=root/'cache';cache.mkdir(exist_ok=True);archive=cache/'omarchy-4.5.0-3-aarch64.pkg.tar.zst'
raw=io.BytesIO()
with tarfile.open(fileobj=raw,mode='w') as tar:
 for name,data in {'.PKGINFO':b'pkgname = omarchy\npkgver = 4.5.0-3\narch = aarch64\n','usr/share/omarchy/version':b'4.5.0\n'}.items():
  info=tarfile.TarInfo(name);info.size=len(data);tar.addfile(info,io.BytesIO(data))
archive.write_bytes(subprocess.run(['zstd','-q','-c'],input=raw.getvalue(),capture_output=True,check=True).stdout)
env={'OMAMOBILE_PROSPECTIVE_SERIES':str(series),'OMAMOBILE_PATCH_TOOL':str(pkg/'bin/omamobile-omarchy-patches'),'OMAMOBILE_PROSPECTIVE_QUALIFICATIONS':str(root/'qualified.json'),'OMAMOBILE_PACMAN_CACHE':str(cache),'OMAMOBILE_OMARCHY_LIB':str(pkg/'lib')};os.environ.update(env);tool=runpy.run_path(str(pkg/'bin/omamobile-update'),run_name='fixture');patcher=tool['prospective_tool']();checksum=tool['file_sha256'](archive)
record={'name':'omarchy','version':'4.5.0-3','arch':'aarch64','package_sha256':checksum,'approved':True,'signature_verified':True,'rehearsal':{'reverse_byte_identical':True},**tool['prospective_inputs'](patcher,str(series))};(root/'qualified.json').write_text(json.dumps({'version':1,'candidates':[record]}));(root/'candidate-sha').write_text(checksum)
for key,value in env.items():print('export '+key+'='+shlex.quote(value))
