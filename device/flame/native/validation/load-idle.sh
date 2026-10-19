#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import hashlib,json,multiprocessing as mp,subprocess,time

assert Path('/usr/share/omamobile/flame-root').is_file(),'Not a native flame root'
assert Path('/proc/device-tree/model').read_bytes().rstrip(b'\0')==b'Google Pixel 4','Wrong model'
subprocess.run(['sha256sum','-c','/etc/omamobile/flame-calibration.sha256'],check=True,stdout=subprocess.DEVNULL)
held=False
for fd in Path('/proc/1/fd').iterdir():
 try:held=held or fd.resolve().as_posix()=='/dev/watchdog0'
 except FileNotFoundError:pass
assert held,'PID 1 must hold the watchdog'
boot_path=Path('/proc/sys/kernel/random/boot_id')
boot=boot_path.read_text().strip()
started=time.monotonic()
zones=[]
for p in sorted(Path('/sys/class/thermal').glob('thermal_zone*')):
 try:
  label=(p/'type').read_text().strip()
  temperature=int((p/'temp').read_text())
 except (OSError,ValueError):
  continue
 if -20000 <= temperature <= 150000:
  zones.append((p,label))
assert zones,'No thermal readings available'
maxima={}
context=mp.get_context('fork')
stop=context.Event()

def worker(queue):
 try:
  block=bytes(range(256))*(256*1024) # 64 MiB per worker, 128 MiB total.
  expected=hashlib.sha256(block).digest()
  count=0
  while not stop.is_set():
   before=time.monotonic()
   assert hashlib.sha256(block).digest()==expected,'Memory checksum changed'
   count+=1
   stop.wait(max(.02,time.monotonic()-before)) # About 50% duty per worker.
  queue.put(('pass',count))
 except BaseException as error:
  queue.put(('error',repr(error)))

def check(phase):
 assert boot_path.read_text().strip()==boot,'Unexpected restart'
 assert not Path('/dev/sda').exists(),'Whole-disk node appeared'
 values={}
 for p,label in zones:
  value=int((p/'temp').read_text())
  key=p.name+':'+label
  maxima[key]=max(value,maxima.get(key,value))
  values[key]=value
  ceiling=45000 if 'batt' in label.lower() else 70000
  assert value < ceiling, f'Thermal stop: {label}={value}'
 subprocess.run(['systemctl','is-active','--quiet','flame-storage-guard','flame-wifi','sddm'],check=True,timeout=10)
 print(json.dumps({'phase':phase,'elapsed_s':round(time.monotonic()-started),'boot':boot,'temperatures_mC':values}),flush=True)

queue=context.Queue()
workers=[context.Process(target=worker,args=(queue,)) for _ in range(2)]
check('preflight')
print('BOUNDED_LOAD: two CPU workers at about 50% duty, 128 MiB total, 120 seconds; then 180 seconds idle',flush=True)
try:
 for process in workers:process.start()
 deadline=time.monotonic()+120
 while time.monotonic()<deadline:
  time.sleep(min(10,max(0,deadline-time.monotonic())))
  assert all(process.is_alive() for process in workers),'Worker ended early'
  check('load')
finally:
 stop.set()
 for process in workers:
  if process.pid:
   process.join(timeout=5)
   if process.is_alive():
    process.terminate();process.join(timeout=5)
results=[queue.get(timeout=5) for _ in workers]
assert all(result[0]=='pass' and result[1]>0 for result in results),results
print('WORKERS_VERIFIED',results,flush=True)
deadline=time.monotonic()+180
while time.monotonic()<deadline:
 time.sleep(min(15,max(0,deadline-time.monotonic())))
 check('idle')
subprocess.run(['sha256sum','-c','/etc/omamobile/flame-calibration.sha256'],check=True,stdout=subprocess.DEVNULL,timeout=30)
subprocess.run(['curl','--interface','wld0','--connect-timeout','10','--max-time','20','-fsSL','-o','/dev/null','-w','HTTPS %{http_code}\n','https://github.com/derekross/omarchy-mobile'],check=True,timeout=25)
print('STABILITY_SOAK_PASS',json.dumps({'boot':boot,'elapsed_s':round(time.monotonic()-started),'maximum_temperatures_mC':maxima}),flush=True)
PY
