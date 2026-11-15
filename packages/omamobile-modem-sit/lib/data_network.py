#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-sit-data: the internet bearer (CID 1) as a fallback behind Wi-Fi.

CPIF's rmnet devices are raw-IP links that NetworkManager doesn't manage
(the package marks rmnet* unmanaged). This owns only the bearer's rmnet
device: its /32 address, a metric-700 default route (Wi-Fi's default is 600,
so Wi-Fi wins while it is up) and the carrier's DNS while it is the only way
out. All state and rollback records stay in RAM; nothing here is logged with
an address.

Which rmnet carries the bearer: stock's RIL names it rmnet<CID - 1>
(PdpContext's "%s%d" with the RIL socket's ifprefix and ifstart), and that is
tried first. On a network that attaches on another APN than the internet one,
the attach bearer held rmnet0 and the CID 1 internet bearer came out on
rmnet1 (cheetah, 2026-11-02), so the rest are tried after it: the device
that answers a ping with the bearer's address is the one kept, and its name
is recorded in RAM (data-interface) for the bearer's release.

The carrier's DNS is used only while the bearer is the only way out. A bearer
that sends but receives nothing, and then answers no ping either, loses its
default route, and gets it back as soon as nothing else is left: otherwise a
dead bearer's route plus its DNS can outlive a short Wi-Fi outage, make
NetworkManager's connectivity check fail through it and keep the phone
offline with Wi-Fi up.

Around a system sleep the default route is taken away (SleepHold): at
logind's announcement NetworkManager takes Wi-Fi down, and a route through
the bearer would carry everything that had been talking over Wi-Fi, bring
the modem's link up and make the kernel refuse the sleep.
"""
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import time

import cp
import paths
from data_call import RESPONSE

RESOLVER = Path('/etc/resolv.conf')
INTERFACE = paths.RUN / 'data-interface'
# rmnet0-rmnet7 are tried; CPIF creates 30, a phone uses a handful.
CANDIDATES = 8


def run(*args):
    p = subprocess.run(args, capture_output=True, timeout=20)
    if p.returncode:
        raise RuntimeError('Cellular network operation failed: ' + args[0])
    return p.stdout


def configuration(data):
    if len(data) < 132:
        raise ValueError('Short internet bearer response')
    status, cid, active, pdp = struct.unpack_from('<HBBB', data)
    if status or cid == 2 or not 1 <= cid <= 15 or active not in (1, 2) or pdp not in (1, 3):
        raise ValueError('An active IPv4 internet bearer is required')
    addr = ipaddress.IPv4Address(data[5:9])
    dns = list(dict.fromkeys(str(ipaddress.IPv4Address(data[i:i+4])) for i in (0x1a, 0x2e) if any(data[i:i+4])))
    if addr.is_unspecified or addr.is_multicast or not dns:
        raise ValueError('Missing internet address or carrier DNS')
    return str(addr), dns


def counters(stats):
    """(received bytes, sent packets) from `ip -j -s link` output for the device."""
    link = stats[0]['stats64']
    return link['rx']['bytes'], link['tx']['packets']


def looks_silent(routed, before, after):
    """The routed bearer sent packets but received nothing since the last
    check. Not proof: a few router solicitations get no answer on a live one."""
    return routed and after[1] > before[1] and after[0] == before[0]


def guarded(step):
    """One pass of the route watch; the error of a failed or stalled `ip`, or
    None. Such a failure is retried: when this service exits the cellular
    fallback is gone until someone restarts it, and one stalled `ip route`
    must not cost hours without cellular."""
    try:
        step()
    except (subprocess.SubprocessError, RuntimeError, ValueError) as error:
        return error
    return None


def answers(dev):
    """Whether the bearer carries anything: a ping out through its device."""
    for target in ('1.1.1.1', '8.8.8.8'):
        p = subprocess.run(['ping', '-n', '-q', '-c', '1', '-W', '3', '-I', dev, target],
                           capture_output=True, timeout=10)
        if p.returncode == 0:
            return True
    return False


class Resolver:
    """The carrier's DNS in /etc/resolv.conf while cellular is the only way
    out; the previous file comes back unless something (NetworkManager) has
    written a newer one meanwhile."""
    def __init__(self, path):
        self.path = path.resolve()
        self.original = None
        self.owned = None

    def update(self, cellular, servers):
        if cellular:
            content = '# Omarchy Mobile cellular fallback (session only)\n' + ''.join('nameserver ' + s + '\n' for s in servers)
            current = self.path.read_text()
            if self.owned is None or current != self.owned:
                self.original = current
            if current != content:
                self.path.write_text(content)
            self.owned = content
        else:
            self.restore()

    def restore(self):
        if self.owned is not None:
            if self.path.read_text() == self.owned:
                self.path.write_text(self.original)
            self.owned = None


class ResolvedLink:
    """The same with systemd-resolved: the device's DNS servers are set once and
    the link is the default DNS route only while cellular is the only way out."""
    def __init__(self, servers, dev):
        self.dev = dev
        run('resolvectl', 'dns', dev, *servers)
        self.cellular = None

    def update(self, cellular, servers):
        if cellular != self.cellular:
            run('resolvectl', 'default-route', self.dev, 'yes' if cellular else 'no')
            self.cellular = cellular

    def restore(self):
        subprocess.run(['resolvectl', 'revert', self.dev], capture_output=True, timeout=20)


def resolver_for(servers, dev):
    target = str(RESOLVER.resolve()) if RESOLVER.exists() else ''
    if target.startswith('/run/systemd/resolve/'):
        return ResolvedLink(servers, dev)
    return Resolver(RESOLVER)


def roaming_blocked(config=None, state=None):
    """Data roaming is off ([data] roaming = no) and the network says the
    phone is roaming: then rmnet0 gets no default route. Read on every pass,
    so the Mobile network page's switch applies without a restart."""
    try:
        if paths.config(config)['data'].getboolean('roaming', True):
            return False
    except (ValueError, OSError):
        return False
    try:
        status = json.loads(Path(state or paths.RUN / 'state.json').read_text())
    except (OSError, ValueError):
        return False
    return (status.get('modem') or {}).get('registration') == 'roaming'


def candidates(cid):
    """rmnet<CID - 1> (stock's name for the bearer) first, then the others."""
    first = cid - 1
    return [f'rmnet{first}'] + [f'rmnet{i}' for i in range(CANDIDATES) if i != first]


def unused(dev):
    """The device exists and nobody has configured it (down, no address)."""
    try:
        info = json.loads(run('ip', '-j', 'address', 'show', 'dev', dev))[0]
    except (RuntimeError, ValueError, IndexError):
        return False
    return 'UP' not in info['flags'] and not info['addr_info']


def put_back(dev, address=None):
    """Undo a candidate's configuration, every step on its own and none
    fatal: whatever was set before a failure or a stop goes. Only devices
    this service records (data-interface) or is probing get here, and rmnet
    devices carry nothing but this service's configuration."""
    steps = [('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')]
    steps.append(('ip', 'addr', 'del', address + '/32', 'dev', dev) if address
                 else ('ip', 'addr', 'flush', 'dev', dev))
    steps.append(('ip', 'link', 'set', 'dev', dev, 'down'))
    for step in steps:
        try:
            subprocess.run(step, capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            pass


def clear_stale():
    """A device recorded by a run that ended without its cleanup (killed, or
    stopped before 0.3.12 while probing): put it back before anything else."""
    try:
        dev = INTERFACE.read_text().strip()
    except OSError:
        return
    if dev.startswith('rmnet') and dev[5:].isdigit():
        put_back(dev)
        print('Removed a configuration left on', dev, 'by an earlier run', flush=True)
    INTERFACE.unlink(missing_ok=True)


def find_device(address, cid, probe=None, stopped=lambda: False):
    """Bring each unused candidate up with the bearer's /32 and the metric-700
    default route until one carries it (ping -I binds to the device, so the
    route through it is used even with Wi-Fi's better one present); that one
    keeps its address and route. Every other one is put back as it was, also
    when a step fails or the service is stopped in the middle (the record in
    data-interface is written before the device is touched, so a run that is
    killed outright is cleaned up by the next start)."""
    probe = probe or answers
    for dev in candidates(cid):
        if stopped():
            break
        if not unused(dev):
            continue
        paths.run_dir()
        INTERFACE.write_text(dev + '\n')
        kept = False
        try:
            run('ip', 'link', 'set', 'dev', dev, 'up')
            run('ip', 'addr', 'add', address + '/32', 'dev', dev)
            run('ip', 'route', 'add', 'default', 'dev', dev, 'src', address, 'metric', '700')
            try:
                kept = probe(dev) and not stopped()
            except subprocess.SubprocessError:
                kept = False
        except RuntimeError:
            kept = False
        finally:
            if not kept:
                put_back(dev, address)
                INTERFACE.unlink(missing_ok=True)
        if kept:
            print('Bearer CID', cid, 'carried by', dev, flush=True)
            return dev
    if stopped():
        raise InterruptedError('Stopped while looking for the bearer device')
    raise RuntimeError('No rmnet device carries the internet bearer (no ping answered)')


def wait_for_bearer(seconds):
    deadline = time.monotonic() + seconds
    while not RESPONSE.exists():
        if time.monotonic() >= deadline:
            raise RuntimeError('No internet bearer: omamobile-sitd has not set one up')
        time.sleep(1)


# How long after a sleep the cellular default route waits for Wi-Fi.
RETURN_GRACE = 10
SLEEP_MATCH = ("type='signal',interface='org.freedesktop.login1.Manager',"
               "member='PrepareForSleep'")


def sleep_signal(line):
    """True or False for a logind PrepareForSleep line of busctl's JSON
    monitor (a sleep is starting, or is over), None for anything else."""
    try:
        message = json.loads(line)
    except ValueError:
        return None
    if not isinstance(message, dict) or message.get('member') != 'PrepareForSleep':
        return None
    data = (message.get('payload') or {}).get('data')
    if isinstance(data, list) and len(data) == 1 and isinstance(data[0], bool):
        return data[0]
    return None


class SleepWatch:
    """logind's sleep announcements, read without blocking. Without busctl
    nothing is heard, and the route simply stays as it was."""

    def __init__(self):
        self.buffer = b''
        try:
            self.process = subprocess.Popen(
                ['busctl', 'monitor', '--system', '--json=short', '--match', SLEEP_MATCH],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            os.set_blocking(self.process.stdout.fileno(), False)
        except OSError:
            self.process = None

    def wait(self, seconds):
        """Sleep up to seconds; return the announcements heard, in order."""
        if not self.process:
            time.sleep(seconds)
            return []
        heard = []
        ready, _, _ = select.select([self.process.stdout], [], [], seconds)
        if ready:
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:   # the monitor ended: go on without it
                self.close()
                return heard
            self.buffer += chunk
            *lines, self.buffer = self.buffer.split(b'\n')
            for line in lines:
                state = sleep_signal(line.decode(errors='replace'))
                if state is not None:
                    heard.append(state)
        return heard

    def close(self):
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None


class SleepHold:
    """The cellular default route around a system sleep.

    When the system goes to sleep NetworkManager takes Wi-Fi down first, and
    the bearer's default route is then the only one: whatever was talking
    over Wi-Fi sends through the bearer in that moment, the modem's link
    comes up, and the kernel refuses the sleep because of it. So the route
    goes at logind's announcement. After the sleep it waits for something
    else to lead out again, or for RETURN_GRACE without that: put back at
    once, it carried a few seconds of traffic at every wake, and the answers
    to that traffic ended the next sleeps early.
    """

    def __init__(self, grace=RETURN_GRACE):
        self.grace = grace
        self.sleeping = False
        self.held = False       # the route is ours to bring back
        self.back_at = None     # when it returns if nothing else leads out

    @property
    def active(self):
        """True while the route's presence is this class's business."""
        return self.sleeping or self.back_at is not None

    def announced(self, routed):
        """A sleep is starting. True when the route has to go now."""
        if self.sleeping:
            return False
        self.sleeping = True
        # Still waiting to return after the last sleep counts as held.
        self.held = routed or self.back_at is not None
        self.back_at = None
        return routed

    def over(self, now, allowed=True):
        """The sleep is over; allowed is False when roaming forbids data."""
        if not self.sleeping:
            return
        self.sleeping = False
        if self.held and allowed:
            self.back_at = now + self.grace
        self.held = False

    def returns(self, others, now):
        """True once: the route comes back now (others: another default
        route exists)."""
        if self.sleeping or self.back_at is None:
            return False
        if others or now >= self.back_at:
            self.back_at = None
            return True
        return False

    def cancel(self):
        """Roaming took the route away for good: nothing to bring back."""
        self.held = False
        self.back_at = None


def main():
    os.umask(0o077)
    lock = os.open(paths.RUN / 'data-network.lock', os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    clear_stale()
    wait_for_bearer(60)
    data = RESPONSE.read_bytes()
    address, dns = configuration(data)
    stopping = False
    addressed = False
    dev = None

    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    resolver = None
    sleeps = None
    try:
        dev = find_device(address, data[2], stopped=lambda: stopping)
        addressed = True
        resolver = resolver_for(dns, dev)
        if roaming_blocked():
            run('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')
            print('Roaming with data roaming off; the cellular default route is not set', flush=True)
        print('Cellular fallback ready; Wi-Fi remains preferred', flush=True)
        last = None
        seen = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', dev)))
        check_at = time.monotonic() + 30
        hold = SleepHold()

        def watch():
            nonlocal last, seen, check_at
            routes = json.loads(run('ip', '-j', 'route', 'show', 'default'))
            routed = any(r.get('dev') == dev for r in routes)
            others = [r for r in routes if r.get('dev') != dev]
            if roaming_blocked():
                if routed:
                    run('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')
                    print('Roaming with data roaming off; the cellular default route is removed', flush=True)
                resolver.update(False, dns)
                hold.cancel()
                last = None
                return
            # With Wi-Fi up but rated limited, the carrier's DNS would keep
            # NetworkManager's own check failing and Wi-Fi penalised.
            cellular = routed and not others
            resolver.update(cellular, dns)
            if cellular != last:
                print('Default internet path', 'cellular' if cellular else 'Wi-Fi/other', flush=True)
                last = cellular
            if hold.active:
                if hold.returns(bool(others), time.monotonic()):
                    if not routed:
                        run('ip', 'route', 'add', 'default', 'dev', dev, 'src', address, 'metric', '700')
                    print('The cellular default route is back', 'behind Wi-Fi' if others else 'as the only way out', flush=True)
                    last = None
                return
            if not routed and not others:
                run('ip', 'route', 'add', 'default', 'dev', dev, 'src', address, 'metric', '700')
                print('Nothing else leads out; the cellular default route is back', flush=True)
            elif time.monotonic() >= check_at:
                now = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', dev)))
                if looks_silent(routed, seen, now) and not answers(dev):
                    run('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')
                    print('Cellular bearer carries nothing; its default route is removed', flush=True)
                    now = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', dev)))
                seen = now
                check_at = time.monotonic() + 30
        def announced(state):
            if not state:
                hold.over(time.monotonic(), not roaming_blocked())
                return
            routes = json.loads(run('ip', '-j', 'route', 'show', 'default'))
            routed = any(r.get('dev') == dev and r.get('metric') == 700 for r in routes)
            if hold.announced(routed):
                run('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')
                print('Sleep announced; the cellular default route is away until it is over', flush=True)
        sleeps = SleepWatch()
        failing = None
        while not stopping and cp.online() and RESPONSE.exists():
            error = guarded(watch)
            if error and not failing:
                print('Network check failed, retrying:', type(error).__name__, flush=True)
            elif failing and not error:
                print('Network checks work again', flush=True)
            failing = error
            for state in sleeps.wait(2 if error else .5):
                guarded(lambda state=state: announced(state))
    except InterruptedError:
        # Stopped while probing: find_device has put the candidate back.
        pass
    finally:
        if sleeps:
            sleeps.close()
        if resolver:
            resolver.restore()
        if dev:
            routes = json.loads(run('ip', '-j', 'route', 'show', 'default'))
            if any(r.get('dev') == dev and r.get('metric') == 700 for r in routes):
                run('ip', 'route', 'del', 'default', 'dev', dev, 'metric', '700')
            if addressed:
                run('ip', 'addr', 'del', address + '/32', 'dev', dev)
            run('ip', 'link', 'set', 'dev', dev, 'down')
            INTERFACE.unlink(missing_ok=True)
        os.close(lock)
        print('Cellular fallback configuration removed', flush=True)


if __name__ == '__main__':
    main()
