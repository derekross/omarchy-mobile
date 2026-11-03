# SPDX-License-Identifier: MIT
"""The start-up sequence for a freshly booted CP, using the service's IPC0
owner. This order registered on LTE with IMS voice and SMS on this phone:

  1. wait for the USIM application to be READY (type 2, state 5); a PIN,
     PUK or network lock ends start-up at once (no PIN entry here);
  2. read the radio state (AT+CFUN?); then, with the radio as found, the
     initial attach APN ([network] attach_apn, else apn), every data
     profile (profile 0 from apn unless [profiles] has its own, then the
     rest of [profiles]) and NR mode 0 ([network] nr = off: stay on LTE; NR
     registered but carried no traffic on this phone);
  3. radio on (AT+CFUN=1) once, unless it was already on: stock's order,
     with no radio cycle (device/cheetah/MODEM-PROVIDER-PROFILES.md
     section 2). An unreadable radio state falls back to 0.3.14's cycle
     (AT+CFUN=0 first). Then wait for packet registration (on LTE with
     nr = off) and log how long it took;
  4. the internet bearer (CID 1; its rmnet device is found by omamobile-sit-data);
  5. IMS: stack start, the IMS bearer (CID 2; IPv6, or the IMS profile's
     home IP type, as stock takes it from the IMS APN), the hidden menu and
     the OMA-DM menu, ADD_PDN_INFO (its P-CSCF from the bearer's PCO, else
     from the ISIM's EF_PCSCF with [network] ims_pcscf_from_isim = yes, a
     name resolved over the IMS bearer, the internet bearer's DNS or the
     host resolver), then wait for an IMS registration with voice and SMS.
     The stock IMS service and its requests: device/cheetah/IMS-SHANNON.md.

No retransmission of SMS/calls and no warm CP restart. A failed or uncertain
step up to the internet bearer ends start-up; the service exits and the
modem stays up for diagnosis. An IMS step that fails leaves the service
running with data only, unless [network] ims_required = yes.
"""
import time

from at import radio, radio_state
from data_call import APN_TYPES, activate, configured_profiles, initial_attach, provision_profiles
from data_call import paths as bearer_paths
from ims import register, start_stack
from isim import bearer_dns, ipv6_pcscf, resolve_on_bearer, resolve_system
from radio_settings import SAVED_NR, nr_mode
from sit import ModemError


def ims_ip_type(profiles, ims_apn):
    """The IMS bearer's PDP type: the home protocol of the [profiles] entry
    with the ims type for ims_apn, as stock takes it from the IMS APN
    (Verizon's IMS APN is IPv4v6 at home), else IPv6 (unchanged from 0.3.19)."""
    for profile in profiles:
        if profile.types & APN_TYPES['ims'] and profile.apn.lower() == ims_apn.lower():
            return profile.ip
    return 'ipv6'


def resolve_default_network(name):
    """AAAA as stock's IMS service resolves an ISIM P-CSCF name
    (InetAddress.getByName on the default network: the internet bearer
    without Wi-Fi): the internet bearer's own DNS servers from its setup
    response, then the host resolver, which may be another link."""
    found = []
    response = bearer_paths(1)[1]
    if response.exists():
        bearer = response.read_bytes()
        if len(bearer) >= 132 and any(bearer[9:25]):
            source, servers = bearer_dns(bearer)
            try:
                found = resolve_on_bearer(name, source, servers) if servers else []
            except (OSError, ValueError):
                found = []
            if found:
                print(f'P-CSCF from ISIM: {name} resolved through the internet bearer\'s DNS', flush=True)
    return found or resolve_system(name)


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



def data_snapshot(client, label):
    """Registration and the data-call list, as the modem reports them at
    registration: whether a bearer is ever listed before the setup. States,
    codes and counts only."""
    try:
        reg = client.request(0x0701)
        calls = client.request(0x0602)
    except (TimeoutError, RuntimeError) as error:
        print(f'{label}: snapshot unavailable: {error}', flush=True)
        return
    state = (reg[0], reg[1], reg[3]) if len(reg) >= 4 else tuple(reg[:4])
    print(f'{label}: PS state, reject, RAT {state}; data calls listed {calls[0] if calls else "none"}',
          flush=True)


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
    # Some networks attach only on their IMS APN (2026-11-02, cheetah: with
    # the internet APN as the attach APN the modem searched for 13 minutes
    # with no reject; with the IMS APN it registered on LTE in 34 s). The
    # data profile and the internet bearer keep apn. Empty: the same as apn.
    attach_apn = net.get('attach_apn', '').strip() or apn
    try:
        profiles = configured_profiles(settings)
    except ValueError as error:
        raise RuntimeError(f'Bad data profile in /etc/omamobile/modem-sit.conf: {error}') from None
    began = time.monotonic()
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
    level = radio_state()
    if level is None:
        # Unknown: 0.3.14's known-good cycle rather than a guess.
        print('Startup: radio state unreadable; switching it off before the attach settings', flush=True)
        radio(False)
        already_on = False
    else:
        already_on = level == 1
        print(f'Startup: radio state {level} ({"on: no radio cycle" if already_on else "off"})', flush=True)
    # Attaching on the IMS APN: ask for the P-CSCF in the attach, as stock does
    # for an IMS APN, since that bearer is the one IMS then uses.
    ims_attach = (attach_apn != apn and net.getboolean('ims', True)
                  and attach_apn == net.get('ims_apn', 'ims'))
    if attach_apn != apn:
        print('initial attach on attach_apn, not the internet APN'
              + (' (the IMS APN: P-CSCF requested)' if ims_attach else ''), flush=True)
    initial_attach(client, attach_apn, ip_type, ims=ims_attach)
    if profiles[0].ident == 0 and profiles[0].apn != apn:
        print('data profile 0 from [profiles], with another APN than [network] apn '
              '(the internet bearer uses apn)', flush=True)
    provision_profiles(client, profiles)
    lte = net.get('nr', 'off') == 'off'
    nr_after_radio = False
    if lte:
        # Before radio on, as stock sets its network type: changed after
        # registration it made the CP register again. This modem refuses
        # SET_NR_MODE with the radio off (error 2, 2026-11-02), so then it is
        # set right after radio on, still before registration.
        try:
            nr_mode(client)
        except ModemError as error:
            if already_on:
                raise
            SAVED_NR.unlink(missing_ok=True)
            nr_after_radio = True
            print(f'NR mode refused with the radio off ({error}); setting it after radio on', flush=True)
    service.pump()
    if not already_on and net.get('carrier_manifest', '').strip():
        # Stock applies the carrier profile before the radio comes on; with
        # the radio switched on first (2026-11-02) the modem confirmed the
        # profile 11 s later and then stopped searching. Wait for its status
        # here, so registration starts with the profile in place.
        limit = net.getint('carrier_manifest_timeout', 60)
        try:
            wait_for(service, lambda: service.carrier_status is not None, limit, stopped)
            print('Radio on after carrier config: status', service.carrier_status[0],
                  'cause', service.carrier_status[1], flush=True)
        except TimeoutError:
            print('Radio on without carrier config status after', limit, 's;',
                  'manifest sent' if service.manifest_sent else 'no request from the modem seen', flush=True)
    if not already_on:
        radio(True)
        began = time.monotonic()
        if nr_after_radio:
            nr_mode(client)
    service.stage('registering')
    print('Startup: waiting for packet registration' + (' on LTE' if lte else ''), flush=True)
    timeout = net.getint('register_timeout', 180)
    first = None

    def registered():
        nonlocal first
        state = client.request(0x0701)
        if first is None and packet_registered(state):
            first = time.monotonic()
            print(f'Registration: packet registered {first - began:.1f} s after '
                  + ('start-up began (the radio was already on)' if already_on else 'radio on')
                  + f', RAT {state[3]}', flush=True)
        return packet_registered(state, lte=lte)
    wait_for(service, registered, timeout, stopped)
    data_snapshot(client, 'at registration')
    service.stage('data')
    activate(client, apn, ip_type=ip_type, on_event=service.event)
    service.pump()
    if not net.getboolean('ims', True):
        service.ims_state = 'off'
        print('Startup: registered with data; IMS off ([network] ims = no)', flush=True)
        return
    service.ims_state = 'pending'
    service.stage('ims')
    try:
        if net.get('carrier_manifest', '').strip():
            # As stock's IMS service: no stack start while the modem applies
            # its carrier profile. The modem's 0x4602 arrives on its own after
            # the SIM loads; service.event answers it and records the 0x4601.
            limit = net.getint('carrier_manifest_timeout', 60)
            try:
                wait_for(service, lambda: service.carrier_status is not None, limit, stopped)
                print('IMS stack start released (after carrier config: status',
                      service.carrier_status[0], 'cause', service.carrier_status[1], ')', flush=True)
            except TimeoutError:
                print('IMS stack start released (timeout: no carrier config status in', limit, 's;',
                      'manifest sent' if service.manifest_sent else 'no request from the modem seen', ')',
                      flush=True)
        start_stack(client)
        ims_apn = net.get('ims_apn', 'ims')
        ims_ip = ims_ip_type(profiles, ims_apn)
        print('IMS bearer PDP type', ims_ip, '(from the IMS profile)' if ims_ip != 'ipv6' else '', flush=True)
        activate(client, ims_apn, ims=True, ip_type=ims_ip, on_event=service.event)
        fallback = None
        if net.getboolean('ims_pcscf_from_isim', True):
            # The ISIM's EF_PCSCF when the PCO has none (one read-only file).
            def fallback(bearer):
                return ipv6_pcscf(client, client.request(0x0200), bearer,
                                  resolve_host=resolve_default_network)
        register(client, pcscf_required=net.getboolean('ims_pcscf_required', True),
                 pcscf_fallback=fallback)
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
