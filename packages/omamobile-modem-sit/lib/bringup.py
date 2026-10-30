# SPDX-License-Identifier: MIT
"""The start-up sequence for a freshly booted CP, using the service's IPC0
owner. This order registered on LTE with IMS voice and SMS on this phone:

  1. wait for the USIM application to be READY (type 2, state 5); a PIN,
     PUK or network lock ends start-up at once (no PIN entry here);
  2. radio off (AT+CFUN=0), initial attach APN, the default data profile;
  3. radio on (AT+CFUN=1), wait for packet registration;
  4. NR mode 0 ([network] nr = off): stay on LTE (NR registered, but
     carried no traffic on this phone), wait for LTE registration;
  5. the internet bearer (CID 1, rmnet0);
  6. IMS: stack start, the IMS bearer (CID 2, IPv6), ADD_PDN_INFO, then wait
     for an IMS registration with voice and SMS.

No retransmission of SMS/calls and no warm CP restart. A failed or uncertain
step up to the internet bearer ends start-up; the service exits and the
modem stays up for diagnosis. An IMS step that fails leaves the service
running with data only, unless [network] ims_required = yes.
"""
import time

from at import radio
from data_call import activate, initial_attach, provision_default_profile
from ims import register, start_stack, values as ims_values
from radio_settings import nr_mode
from sit import ModemError


def sim_ready(payload):
    if len(payload) < 3 or payload[2] > 8 or len(payload) < 3 + payload[2] * 63:
        raise ValueError('Unexpected SIM status layout')
    return any(
        payload[i:i + 2] == bytes([2, 5])
        for i in range(3, 3 + payload[2] * 63, 63))


# AOSP RIL_AppState values that need the user (the RIL has no PIN entry):
# PIN, PUK and subscription personalisation (a network lock).
LOCKS = {2: 'PIN', 3: 'PUK', 4: 'network'}
LOCK_ADVICE = {
    'PIN': 'the SIM PIN lock is on; the RIL has no PIN entry: turn the lock off in another phone',
    'PUK': 'the SIM is PUK-blocked: unblock it with the carrier\'s PUK in another phone; never guess PUKs',
    'network': 'the SIM is network-locked (subscription lock): ask the carrier, or use another SIM',
}
# A lock must hold this long before start-up gives up (a card that is still
# initialising may report a transient state).
LOCK_GRACE = 10


def sim_lock(payload):
    """The lock of the USIM application (else of the first one), or None.
    Reads only the application type and state bytes."""
    if len(payload) < 3 or payload[2] > 8 or len(payload) < 3 + payload[2] * 63:
        raise ValueError('Unexpected SIM status layout')
    if payload[0] != 1 or not payload[2]:
        return None
    apps = [payload[i:i + 2] for i in range(3, 3 + payload[2] * 63, 63)]
    app = next((a for a in apps if a[0] == 2), apps[0])
    return LOCKS.get(app[1])


def packet_registered(payload, *, lte=False):
    return len(payload) >= 4 and payload[0] in (1, 5) and (not lte or payload[3] == 14)


def wait_for(service, predicate, seconds, stopped):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if stopped():
            raise InterruptedError('Modem startup stopped')
        service.pump()
        try:
            ready = predicate()
        except TimeoutError:
            # CP may briefly stop answering status requests while its SIM
            # application initializes. Only these read-only polls retry.
            ready = False
        if ready:
            service.pump()
            return
        # Receive and durably handle SMS throughout startup. Calls never
        # auto-answer; the same Service retains them for the user.
        until = time.monotonic() + 1
        while time.monotonic() < until:
            if stopped():
                raise InterruptedError('Modem startup stopped')
            packet = service.client.next_indication(.1)
            if packet:
                service.event(packet)
    raise TimeoutError('Modem registration deadline exceeded')


def start(service, settings, stopped=lambda: False):
    client = service.client
    net = settings['network']
    apn, ip_type = net.get('apn', ''), net.get('ip_type', 'ipv4v6')
    if not apn:
        raise RuntimeError('No APN configured: set [network] apn in /etc/omamobile/modem-sit.conf')
    previous = None
    locked = None

    def usim_ready():
        nonlocal previous, locked
        payload = client.request(0x0200)
        ready = sim_ready(payload)
        # Card state and application type/state only: never AIDs or labels.
        state = (payload[0], tuple((payload[i], payload[i + 1])
                 for i in range(3, 3 + payload[2] * 63, 63)))
        if state != previous:
            print('SIM card state and application type/state:', state, flush=True)
            previous = state
        lock = None if ready else sim_lock(payload)
        if lock is None:
            locked = None
        elif locked is None or locked[0] != lock:
            locked = (lock, time.monotonic())
        elif time.monotonic() - locked[1] >= LOCK_GRACE:
            # Nothing is ever sent to unlock it: no PIN or PUK request is on
            # the allow-list, so a wrong guess can't use up a retry.
            raise RuntimeError('SIM not usable: ' + LOCK_ADVICE[lock])
        return ready
    service.stage('sim')
    print('Startup: waiting for physical USIM ready', flush=True)
    timeout = net.getint('sim_timeout', 120)
    try:
        wait_for(service, usim_ready, timeout, stopped)
    except TimeoutError:
        card = {None: 'no answer', 0: 'no SIM card detected', 1: 'card present, USIM not ready',
                2: 'card error'}.get(previous[0] if previous else None, 'unknown card state')
        raise TimeoutError(f'No ready USIM within {timeout} s ({card})') from None
    service.stage('attach')
    radio(False)
    initial_attach(client, apn, ip_type)
    provision_default_profile(client, apn, ip_type)
    service.pump()
    radio(True)
    service.stage('registering')
    print('Startup: waiting for packet registration', flush=True)
    timeout = net.getint('register_timeout', 180)
    wait_for(service, lambda: packet_registered(client.request(0x0701)), timeout, stopped)
    if net.get('nr', 'off') == 'off':
        nr_mode(client)
        wait_for(service, lambda: packet_registered(client.request(0x0701), lte=True), 120, stopped)
    service.stage('data')
    activate(client, apn, ip_type=ip_type)
    service.pump()
    if not net.getboolean('ims', True):
        service.ims_state = 'off'
        print('Startup: registered with data; IMS off ([network] ims = no)', flush=True)
        return
    service.ims_state = 'pending'
    service.stage('ims')
    try:
        # The carrier's IMS values: the config's, or the registered
        # network's own profile on the phone (ims.values). The PLMN is
        # used to pick the file and never printed.
        from service import operator_name
        try:
            plmn = operator_name(client.request(0x0702, timeout=5))['plmn']
        except (ModemError, TimeoutError):
            plmn = ''
        values = ims_values(settings, plmn)
        start_stack(client)
        activate(client, net.get('ims_apn', 'ims'), ims=True)
        register(client, values)
        print('Startup: waiting for IMS voice and SMS registration', flush=True)
        wait_for(service, lambda: service.registration().get('state') == 2 and
                 service.registration().get('features', 0) & 3 == 3,
                 net.getint('ims_timeout', 120), stopped)
    except (RuntimeError, TimeoutError, ValueError) as error:
        # The internet bearer is up and owned: keep serving it. Nothing about
        # IMS is retried (an uncertain IMS bearer or ADD_PDN is never sent
        # twice); a registration the modem completes later still shows up
        # through its indication. ims_required = yes keeps the old rule.
        service.ims_state = 'failed'
        if net.getboolean('ims_required', False):
            raise
        print('Startup: IMS did not register (' + type(error).__name__ + ': ' + str(error) +
              '); serving data only, no SMS or calls', flush=True)
        return
    service.ims_state = 'registered'
    print('Startup: LTE, IMS voice and SMS registered', flush=True)
