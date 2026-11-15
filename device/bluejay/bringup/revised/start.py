#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Opt-in, exact-build Bluejay startup. No installer, boot writer or recovery.

The private profile supplies handset identity, DT and protected hashes. The
public manifest pins code modules. No previous trial launcher is imported.
"""
from collections import Counter
from pathlib import Path
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time

RELEASE = '7.3.0-rc6-omamobile-bluejay-review-20261111'
SOURCE = '720a495233734e4328a09c33c095d72a8291e1c4'
HISTORICAL = '7.3.0-rc6-omamobile-bluejay-input-gated0'
LIBDIR = Path('/usr/local/lib/omamobile/bluejay-revised')
PROFILE = Path('/etc/omamobile/bluejay-revised.json')
STATE = Path('/var/lib/omamobile/bluejay-revised')
RUN = Path('/run/omamobile-bluejay-revised')
LOG = Path('/var/log/omamobile/bluejay-revised')
STAGES = ('root', 'gpu', 'touch', 'pcie', 'wifi', 'gauge')
REQUIRED_MASKS = {'omamobile-bluejay-hardware.service', 'omamobile-bluejay-wifi.service',
                  'omamobile-bluejay-gpu.service', 'omamobile-bluejay-boot-ready.service',
                  'omamobile-boot-success.service', 'sddm.service',
                  'omamobile-modem-boot.target', 'omamobile-modem.service',
                  'sleep.target', 'suspend.target', 'hibernate.target',
                  'hybrid-sleep.target', 'suspend-then-hibernate.target'}
HELD_MODULES = {'clk_acpm', 'panfrost', 'salixp', 'spi_s3c64xx', 'phy_gs201_pcie',
                'pcie_gs201', 'brcmfmac', 'brcmfmac_wcc', 'max17042_battery',
                'leds_lm3644', 'cpufreq_dt'}
FAULT = re.compile(r'Kernel panic|Oops:|SError|BUG:|Unable to handle kernel|'
                   r'Call trace:|MMU fault|job timed out|GPU fault|'
                   r'touch poll read failed|AP bus not acknowledged|'
                   r'system info would repair|cx poll would repair|'
                   r'crc status nonzero|link training failed|'
                   r'refusing unconfined restricted DMA|'
                   r'I/O error|ufshcd_err_handler|EXT4-fs error', re.I)
TOUCH_PROOFS = ('ALIX AP bus acknowledged', 'chip id 36 48', 'crc status 00',
                'cx poll ready yes config-crc no cx-crc no panel-crc no',
                'sense echo yes')


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def cmd(*args, timeout=10, env=None):
    return subprocess.check_output(args, text=True, timeout=timeout, env=env).strip()


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def secure(path, directory=False):
    s = path.lstat()
    need((stat.S_ISDIR(s.st_mode) if directory else stat.S_ISREG(s.st_mode))
         and s.st_uid == 0 and not s.st_mode & 0o022, 'unsafe path: ' + str(path))


def syncdir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def save(path, data):
    """Exclusive creation: an ambiguous attempt is never silently replaced."""
    with path.open('x') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    syncdir(path.parent)


def boot():
    value = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    need(re.fullmatch(r'[0-9a-f-]{36}', value), 'invalid boot ID')
    return value


def bootargs_ok(actual, expected):
    """Check the exact observed command line from this frozen image pair.

    Bootloader-added arguments may occur, but must not override any expected
    key. The DT and vendor header each carry the two unused-resource holds;
    the live boot has two copies of each. All other safety arguments retain
    their original multiplicity. Only console=tty0 is rewritten to null.
    """
    want = expected.split()
    got = actual.split()
    need(want.count('console=tty0') == 1, 'expected console contract')
    want[want.index('console=tty0')] = 'console=null'
    for hold in ('clk_ignore_unused', 'pd_ignore_unused'):
        need(want.count(hold) == 1, 'expected DT hold flag contract')
        want.append(hold)
    required = Counter(want)
    seen = Counter(got)
    need(all(seen[k] == v for k, v in required.items()), 'missing/duplicate bootarg')
    keys = {x.split('=', 1)[0] for x in want}
    need(all(x in required for x in got if x.split('=', 1)[0] in keys),
         'conflicting bootarg')
    return True


def validate_profile(c):
    need(c['source'] == SOURCE and c['release'] == RELEASE, 'source/release mismatch')
    need(re.fullmatch(r'[A-Za-z0-9]+', c['serial']), 'invalid private identity')
    need(c['host_logging_required'] is True, 'attended host logging required')
    need(set(c['masked_units']) == REQUIRED_MASKS, 'required mask inventory')
    args = c['bootargs'].split()
    required_args = {'console=tty0', 'panic=10', 'clk_ignore_unused', 'pd_ignore_unused',
                     'rdinit=/init', 'mem_sleep_default=s2idle', 'omamobile.noresize',
                     'systemd.unit=multi-user.target', 'bluejay.gpu_evening=1'}
    required_args |= {'systemd.mask=' + name for name in REQUIRED_MASKS}
    need(required_args <= set(args), 'missing safety bootarg in profile')
    blacklist = [x.split('=', 1)[1] for x in args if x.startswith('modprobe.blacklist=')]
    need(len(blacklist) == 1 and set(blacklist[0].split(',')) == HELD_MODULES,
         'module blacklist contract')
    need(c['root_marker'] == '/var/lib/omamobile/root-boot-pending',
         'root marker must match the qualified initramfs')
    need(set(c['image_hashes']) == {'boot_b', 'vendor_boot_b', 'dtbo_b'}, 'B image set')
    protected = {'efs', 'efs_backup', 'modem_userdata', 'persist', 'modem_a',
                 'modem_b', 'boot_a', 'vendor_boot_a', 'dtbo_a'}
    need(set(c['protected_hashes']) == protected, 'protected partition set')
    need(c['devinfo_hashes'] and all(re.fullmatch(r'[0-9a-f]{64}', h)
         for h in c['devinfo_hashes']), 'full devinfo hashes required')
    need(c['dt_properties'] and c['firmware'], 'DT and firmware provenance required')
    for row in c['dt_properties']:
        need(len(row) == 3 and not Path(row[0]).is_absolute()
             and '..' not in Path(row[0]).parts and '/' not in row[1], 'unsafe DT path')
        bytes.fromhex(row[2])
    for name, digest in c['firmware'].items():
        need(not Path(name).is_absolute() and '..' not in Path(name).parts
             and re.fullmatch(r'[0-9a-f]{64}', digest), 'unsafe firmware entry')
    for digest in [*c['image_hashes'].values(), *c['protected_hashes'].values()]:
        need(re.fullmatch(r'[0-9a-f]{64}', digest), 'invalid partition digest')
    return c


def profile():
    secure(PROFILE)
    c = validate_profile(json.loads(PROFILE.read_text()))
    secure(LIBDIR, directory=True)
    secure(LIBDIR / 'modules.json')
    c['modules'] = json.loads((LIBDIR / 'modules.json').read_text())
    return c


def journal(label):
    """Complete boot journal retained before live-ring rollover can matter."""
    dest = LOG / boot()
    dest.mkdir(mode=0o700, parents=True, exist_ok=True)
    secure(dest, directory=True)
    cmd('journalctl', '--sync', timeout=15)
    text = cmd('journalctl', '-k', '-b', '--no-pager', '-o', 'cat', timeout=20)
    need(text, 'empty current-boot kernel journal')
    target = dest / (label + '.kernel.txt')
    with target.open('x') as f:
        f.write(text + '\n')
        f.flush()
        os.fsync(f.fileno())
    syncdir(dest)
    need(not FAULT.search(text), 'kernel/storage/hardware fault; retain journal and STOP')
    return text


def parts():
    result = {}
    for p in Path('/sys/class/block').iterdir():
        if not (p / 'partition').exists():
            continue
        fields = dict(line.split('=', 1) for line in (p / 'uevent').read_text().splitlines()
                      if '=' in line)
        name = fields.get('PARTNAME')
        need(name and name not in result, 'partition inventory')
        result[name] = p
        expected = '0' if name in ('userdata', 'boot_b', 'vendor_boot_b', 'dtbo_b') else '1'
        need((p / 'ro').read_text().strip() == expected, 'storage guard: ' + name)
    need(len(result) == 49 and not Path('/dev/sda').exists(), '49 guards/raw disk')
    return result


def common(c):
    need(os.uname().release == RELEASE, 'wrong kernel')
    need(Path('/proc/device-tree/compatible').read_bytes().split(b'\0')[0]
         == b'google,gs101-bluejay', 'wrong board')
    bc = Path('/proc/bootconfig').read_text()
    ids = re.findall(r'^androidboot.serialno = "([^"]+)"$', bc, re.M)
    need(ids == [c['serial']] and 'androidboot.slot_suffix = "_b"' in bc,
         'wrong handset/slot')
    need(Path('/proc/1/comm').read_text().strip() == 'systemd', 'wrong PID1')
    p = parts()
    mount = cmd('findmnt', '--task', '1', '-n', '-o', 'SOURCE,FSTYPE,OPTIONS', '/').split()
    need(len(mount) == 3 and mount[0] == '/dev/' + p['userdata'].name
         and mount[1] == 'ext4' and 'rw' in mount[2].split(','), 'wrong root')
    for line in Path('/proc/1/mounts').read_text().splitlines():
        fields = line.split()
        need(not fields[0].startswith('/dev/sd') or fields[1] == '/', 'Android mount')
    data = Path('/dev', p['devinfo'].name).read_bytes()
    need(len(data) == 8192 and hashlib.sha256(data).hexdigest() in c['devinfo_hashes'],
         'unknown full devinfo/retry state')
    need(data[52] in (1, 2), 'qualification requires B1 or B2; no boot from this helper')
    policy = [x for x in Path('/etc/omamobile/boot-update.conf').read_text().splitlines()
              if x and not x.startswith('#')]
    need(policy == ['AUTO_WRITE=no'], 'automatic boot writer')
    for unit in c['masked_units']:
        need(cmd('systemctl', 'show', '-p', 'LoadState', '--value', unit) == 'masked',
             'required mask: ' + unit)
    need(cmd('systemctl', 'show', '-p', 'ActiveState', '--value', 'sshd.service') == 'active',
         'SSH is not active')
    need(' 172.16.42.1/24 ' in ' ' + cmd('ip', '-4', '-o', 'addr', 'show', 'dev', 'usb0') + ' ',
         'USB rescue address')
    need(Path('/sys/class/watchdog/watchdog0/state').read_text().strip() == 'active'
         and Path('/sys/class/watchdog/watchdog0/timeout').read_text().strip() == '20'
         and cmd('systemctl', 'show', '-p', 'RuntimeWatchdogUSec', '--value') == '20s',
         '20-second watchdog policy')
    need(any(x.is_symlink() and os.readlink(x) in ('/dev/watchdog', '/dev/watchdog0')
             for x in Path('/proc/1/fd').iterdir()), 'PID1 does not own watchdog')
    need(not cmd('systemctl', '--failed', '--no-legend'), 'failed system unit')
    bootargs_ok(Path('/proc/cmdline').read_text(), c['bootargs'])
    for node, key, expected in c['dt_properties']:
        need((Path('/proc/device-tree') / node / key).read_bytes().hex() == expected,
             'DT property mismatch: ' + node + '/' + key)
    tree = Path('/usr/lib/modules') / RELEASE
    need((tree / '.omamobile-tarball').read_text().strip() == c['module_archive_sha256'],
         'module archive marker')
    need(Path('/usr/lib/modules/.omamobile-pinned').read_text().strip() == HISTORICAL
         and not Path('/usr/lib/modules/.omamobile-next').exists(), 'historical pin/next')
    for name in ('max77759_charger', 'tcpci_maxim', 'cpif', 'aoc_core', 'trusty_core',
                 'gsa', 'leds_lm3644', 'panthor'):
        need(not Path('/sys/module', name).exists(), 'unqualified module: ' + name)
    return {'boot_id': boot(), 'kernel': RELEASE, 'source': SOURCE, 'guards': 49,
            'B_retries': data[52], 'devinfo_sha256': hashlib.sha256(data).hexdigest()}


def all_hashes(c):
    p = parts()
    for name, digest in {**c['image_hashes'], **c['protected_hashes']}.items():
        need(sha(Path('/dev', p[name].name)) == digest, 'partition hash: ' + name)


def module(c, name):
    m = c['modules'][name]
    path = Path('/usr/lib/modules') / RELEASE / m['path']
    secure(path)
    for parent in path.parents:
        secure(parent, directory=True)
        if parent == Path('/usr/lib/modules'):
            break
    need(sha(path) == m['sha256'], 'module hash: ' + name)
    need(cmd('modinfo', '-F', 'vermagic', str(path)).split()[0] == RELEASE, 'module ABI')
    return path


def load(c, name, *args, dependency=False):
    path = module(c, name)
    if Path('/sys/module', name).exists():
        need(dependency, 'hardware was already loaded: ' + name)
        return
    cmd('insmod', str(path), *args, timeout=25)


def bound(bus, name, driver):
    p = Path('/sys/bus') / bus / 'devices' / name
    need((p / 'driver').is_symlink() and (p / 'driver').resolve().name == driver,
         'binding: ' + name)
    return p


def gpu_post(c):
    bound('platform', 'gs101-acpm-clk', 'acpm-clocks')
    bound('platform', '1c500000.gpu', 'panfrost')
    cpu = Path('/sys/bus/platform/devices/cpufreq-dt')
    need(not (cpu / 'driver').exists()
         and (cpu / 'driver_override').read_text().strip() == 'bluejay-revised-cpu-hold',
         'CPU DVFS hold lost')
    for name in ('available_frequencies', 'cur_freq'):
        need((Path('/sys/class/devfreq/1c500000.gpu') / name).read_text().strip()
             == '151000000', 'GPU OPP changed')
    need(Path('/dev/dri/renderD128').is_char_device(), 'render node missing')


def touch_post(log):
    devices = [p for p in Path('/sys/bus/spi/devices').glob('*')
               if (p / 'of_node/compatible').exists()
               and (p / 'of_node/compatible').read_bytes() == b'st,alix\0']
    need(len(devices) == 1, 'ALIX inventory')
    p = devices[0]
    bound('spi', p.name, 'salixp')
    need([q.read_text().strip() for q in p.glob('input/input*/name')] == ['ALIX Touchscreen'],
         'ALIX input absent')
    for name in ('errors', 'timedout'):
        need((p / 'statistics' / name).read_text().strip() == '0', 'SPI ' + name)
    need(all(x in log for x in TOUCH_PROOFS), 'current-boot touch journal incomplete')


def endpoint():
    devices = [p for p in Path('/sys/bus/pci/devices').glob('*')
               if (p / 'vendor').read_text().strip() == '0x14e4']
    need(len(devices) == 1 and (devices[0] / 'device').read_text().strip() == '0x4441',
         'BCM4389 inventory')
    return devices[0]


def pcie_post(log):
    bound('platform', '14550000.phy', 'gs201-pcie-phy')
    bound('platform', '14520000.pcie', 'gs201-pcie')
    endpoint()
    need('link up on try 1' in log and 'link up on try 2' not in log, 'PCIe link proof')


def wifi_post(log):
    e = endpoint()
    bound('pci', e.name, 'brcmfmac')
    nets = list((e / 'net').glob('*'))
    need(len(nets) == 1 and re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}', nets[0].name),
         'station interface inventory')
    iface = nets[0].name
    need(re.search(r'^\s*type managed\s*$', cmd('iw', 'dev', iface, 'info'), re.M),
         'not a managed station')
    need('restricted DMA attachment verified below 4 GiB' in log, 'restricted DMA proof')
    return iface


def reading():
    supplies = list(Path('/sys/class/power_supply').iterdir())
    need(len(supplies) == 1 and (supplies[0] / 'type').read_text().strip() == 'Battery',
         'battery inventory')
    r = {name: int((supplies[0] / name).read_text().strip()) for name in
         ('capacity', 'temp', 'voltage_now', 'current_now', 'charge_now', 'charge_full')}
    need(0 <= r['capacity'] <= 100 and -100 <= r['temp'] <= 600
         and 2500000 <= r['voltage_now'] <= 4700000
         and abs(r['current_now']) < 10000000, 'implausible provisional readings')
    return r


def receipt(stage):
    p = RUN / (stage + '.json')
    secure(p)
    r = json.loads(p.read_text())
    need(r['boot_id'] == boot() and r['passed'] is True, 'stale readiness receipt')
    return r


def check_host():
    p = RUN / 'host-log.json'
    secure(p)
    r = json.loads(p.read_text())
    need(r['boot_id'] == boot() and r['kernel_stream_proven'] is True,
         'fresh host logging receipt missing')


def run(stage):
    need(stage in STAGES, 'unknown explicit stage')
    c = profile()
    for path in (STATE, RUN, LOG):
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        secure(path, directory=True)
    need(not (RUN / (stage + '.json')).exists(), 'stage already completed this boot')
    pending = STATE / (stage + '.pending')
    need(not pending.exists() and not pending.is_symlink(), 'previous attempt held: ' + stage)
    r = common(c)
    log = journal(stage + '-before')
    groups = {'gpu': {'clk_acpm', 'gpu_sched', 'panfrost'},
              'touch': {'spi_s3c64xx', 'salixp'},
              'pcie': {'phy_gs201_pcie', 'pcie_gs201'},
              'wifi': {'brcmfmac', 'brcmfmac_wcc'}, 'gauge': {'max17042_battery'}}
    allowed = set().union(*(groups.get(s, set()) for s in STAGES[:STAGES.index(stage)]))
    tracked = set().union(*groups.values())
    loaded = {line.split()[0] for line in Path('/proc/modules').read_text().splitlines()}
    need(loaded & tracked == allowed, 'unexpected/missing hardware modules before ' + stage)
    if stage == 'root':
        all_hashes(c)
        for name in c['modules']:
            module(c, name)
        for name, digest in c['firmware'].items():
            need(sha(Path('/usr/lib/firmware') / name) == digest, 'firmware provenance')
        binary = Path('/usr/local/bin/bluejay-gpu-smoke')
        secure(binary)
        need(sha(binary) == c['render_binary_sha256'], 'GPU checker provenance')
        root = Path(c['root_marker'])
        secure(root)
        need(root.read_text() == boot() + '\n', 'root marker boot mismatch')
        # No hardware starts until the host proves logging on this exact boot.
        # The marker is acknowledged only after that proof, not by this gate.
    else:
        receipt(STAGES[STAGES.index(stage) - 1])
        check_host()
        need(not Path(c['root_marker']).exists(), 'root has not been acknowledged')
        for name in ('gpu', 'touch', 'pcie', 'wifi'):
            if STAGES.index(name) >= STAGES.index(stage):
                break
            if name == 'gpu':
                gpu_post(c)
            elif name == 'touch':
                touch_post(log)
            elif name == 'pcie':
                pcie_post(log)
            elif name == 'wifi':
                wifi_post(log)
    save(pending, r)
    if stage == 'gpu':
        cpu = Path('/sys/bus/platform/devices/cpufreq-dt')
        need(not (cpu / 'driver').exists(), 'CPU DVFS already bound')
        for name in ('clk_acpm', 'gpu_sched', 'panfrost'):
            module(c, name)
        (cpu / 'driver_override').write_text('bluejay-revised-cpu-hold\n')
        need((cpu / 'driver_override').read_text().strip() == 'bluejay-revised-cpu-hold',
             'CPU hold failed')
        for name in ('clk_acpm', 'gpu_sched', 'panfrost'):
            load(c, name)
        cmd('udevadm', 'settle', '--timeout=5')
        gpu_post(c)
        binary = Path('/usr/local/bin/bluejay-gpu-smoke')
        secure(binary)
        need(sha(binary) == c['render_binary_sha256'], 'GPU checker provenance')
        env = dict(os.environ)
        env.pop('GALLIUM_DRIVER', None)
        env.pop('LIBGL_ALWAYS_SOFTWARE', None)
        output = cmd(str(binary), '/dev/dri/renderD128', timeout=15, env=env)
        need('PASS: Bluejay headless hardware rendering' in output
             and output.count('all pixels') == 9, 'GPU readbacks incomplete')
        r['render_output'] = output
    elif stage == 'touch':
        for name in ('spi_s3c64xx', 'salixp'):
            load(c, name)
        time.sleep(2)
    elif stage == 'pcie':
        load(c, 'phy_gs201_pcie', 'trace=1', 'trace_delay_ms=20', 'check_tcxo=0')
        load(c, 'pcie_gs201', 'stop_after=5', 'trace=1', 'trace_delay_ms=20',
             'use_ia=1', 'cmu_acg_off=0')
        need(not (endpoint() / 'driver').exists(), 'endpoint bound before firmware stage')
    elif stage == 'wifi':
        e = endpoint()
        need(not (e / 'driver').exists(), 'Wi-Fi already bound')
        for name in ('rfkill', 'cfg80211', 'brcmutil', 'brcmfmac', 'brcmfmac_wcc'):
            module(c, name)
        for name, digest in c['firmware'].items():
            need(sha(Path('/usr/lib/firmware') / name) == digest, 'firmware provenance')
        need((e / 'of_node/brcm,max-dma-buffer-size').read_bytes() == (8192).to_bytes(4, 'big'),
             'DMA size bound changed')
        (e / 'driver_override').write_text('bluejay-revised-wifi-hold\n')
        need((e / 'driver_override').read_text().strip() == 'bluejay-revised-wifi-hold',
             'endpoint hold failed')
        for name in ('rfkill', 'cfg80211', 'brcmutil'):
            load(c, name, dependency=True)
        load(c, 'brcmfmac', 'debug=6', 'feature_disable=16')
        load(c, 'brcmfmac_wcc')
        need(not (e / 'driver').exists(), 'endpoint bound through hold')
        (e / 'driver_override').write_text('\n')
        Path('/sys/bus/pci/drivers/brcmfmac/bind').write_text(e.name + '\n')
        for _ in range(150):
            if list((e / 'net').glob('*')):
                break
            time.sleep(.1)
        cmd('udevadm', 'settle', '--timeout=10')
    elif stage == 'gauge':
        dev = Path('/sys/bus/i2c/devices/1-0036')
        node = dev / 'of_node'
        need((node / 'compatible').read_bytes() == b'maxim,max77759-fg\0'
             and (node / 'shunt-resistor-micro-ohms').read_bytes() == (5000).to_bytes(4, 'big'),
             'gauge identity/sense resistor')
        need(not (dev / 'driver').exists(), 'gauge already bound')
        need(not any((node / name).exists() for name in ('maxim,fg-model', 'maxim,fg-params',
                                                       'maxim,fg-data', 'monitored-battery')),
             'unreviewed battery model properties')
        load(c, 'max17042_battery')
        bound('i2c', dev.name, 'max17042')
        time.sleep(1)
        r.update(battery=reading(), accuracy_qualified=False, charging_qualified=False)
        cmd('systemctl', 'start', 'upower.service', timeout=15)
    log = journal(stage + '-after')
    if stage == 'touch':
        touch_post(log)
    elif stage == 'pcie':
        pcie_post(log)
    elif stage == 'wifi':
        r['station_interface'] = wifi_post(log)
    common(c)
    r['passed'] = True
    save(RUN / (stage + '.json'), r)
    pending.unlink()
    syncdir(STATE)
    return r


def acknowledge():
    """Called only after the host's unique kernel marker reached its log."""
    c = profile()
    r = common(c)
    receipt('root')
    check_host()
    root = Path(c['root_marker'])
    secure(root)
    need(root.read_text() == boot() + '\n', 'root marker mismatch')
    root.unlink()
    syncdir(root.parent)
    save(RUN / 'ack.json', {**r, 'passed': True})


def wait_host():
    """Fail closed if an attended boot lacks host logging; never reboot."""
    receipt('root')
    for _ in range(450):
        if (RUN / 'host-log.json').exists():
            acknowledge()
            return
        time.sleep(.1)
    raise RuntimeError('no fresh host logging receipt within 45 seconds; hardware held')


if __name__ == '__main__':
    try:
        need(len(sys.argv) == 2 and os.geteuid() == 0, 'root and one explicit mode required')
        if sys.argv[1] == 'ack':
            acknowledge()
        elif sys.argv[1] == 'wait-host':
            wait_host()
        else:
            print(json.dumps(run(sys.argv[1]), indent=2))
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        sys.exit('bluejay-revised: STOP: ' + str(exc))
