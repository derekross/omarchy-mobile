# SPDX-License-Identifier: MIT
"""The start-up sequence for a freshly booted CP, using the service's IPC0
owner. This order registered on LTE with IMS voice and SMS on this phone:

  1. wait for the USIM application to be READY (type 2, state 5); a PIN,
     PUK or network lock ends start-up at once (no PIN entry here);
  2. read the radio state (AT+CFUN?); then, with the radio as found, the
     initial attach APN ([network] attach_apn, else apn; none: not sent, the
     modem attaches with its carrier profile, as stock's RIL did on a
     Verizon network), every data
     profile (profile 0 from apn unless [profiles] has its own, then the
     rest of [profiles]) and NR mode 0 ([network] nr = off: stay on LTE; NR
     registered but carried no traffic on this phone);
  3. radio on (AT+CFUN=1) once, unless it was already on: stock's order,
     with no radio cycle (device/cheetah/MODEM-PROVIDER-PROFILES.md
     section 2). An unreadable radio state falls back to 0.3.14's cycle
     (AT+CFUN=0 first). Then wait for packet registration (on LTE with
     nr = off) and log how long it took;
     With attach_apn = none, wait up to ATTACH_BEARER_WAIT s for the modem's
     own attach bearer (listed with its P-CSCF; every bearer listed then is
     recorded as modem-owned and never released);
  4. the internet bearer (CID 1; its rmnet device is found by omamobile-sit-data);
  5. IMS: stack start, then ADD_PDN_INFO for the modem's attach bearer when
     one with a P-CSCF is listed (no IMS setup of our own, as stock); else
     the IMS bearer (CID 2; IPv6, or the IMS profile's
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
from data_call import APN_TYPES, activate, attach_bearer, configured_profiles, entries, initial_attach
from data_call import owned_ids, provision_profiles, record_modem_owned, summary
import data_call
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


def ims_apn_types(profiles, ims_apn):
    """The IMS setup's APN-type bitmask (request offset 0xf1): the whole
    bitmask of the [profiles] entry with the ims type for ims_apn, as stock's
    builder copies the APN's supported types (Verizon's IMS APN: ims|ia,
    0x140), else None (IMS alone, 0x40, unchanged from 0.3.22)."""
    for profile in profiles:
        if profile.types & APN_TYPES['ims'] and profile.apn.lower() == ims_apn.lower():
            return profile.types
    return None


def resolve_default_network(name):
    """AAAA as stock's IMS service resolves an ISIM P-CSCF name
    (InetAddress.getByName on the default network: the internet bearer
    without Wi-Fi): the internet bearer's own DNS servers from its setup
    response, then the host resolver, which may be another link."""
    found = []
    response = bearer_paths(data_call.INTERNET_CID)[1]
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


# With attach_apn = none, how long after packet registration start-up waits
# for the modem's own attach bearer to be listed with a P-CSCF. On stock
# (Verizon network, 2026-11-02) it arrived unsolicited with the attach.
ATTACH_BEARER_WAIT = 20


def find_attach_bearer(service, deadline, stopped, *, adopt_unknown):
    """The data-call item of an IMS-capable bearer the modem brought up on
    its own (data_call.attach_bearer: active, IPv6 or IPv4v6, with a P-CSCF,
    not one sitd owns), from GET_DATA_CALL_LIST and the latest
    IND_DATA_CALL_LIST_CHANGED, polled until deadline (monotonic); or None.
    Each list is logged when it changes, as CID, type, active, P-CSCF and
    DNS counts: never an address. The bearer found is recorded as
    modem-owned. adopt_unknown: also record every other listed bearer sitd
    doesn't own (only before sitd has set up any of its own)."""
    client = service.client
    logged = {}
    found = None

    def check():
        nonlocal found
        for source, payload in (('list', client.request(0x0602)),
                                ('indication', service.data_call_list)):
            if payload is None:
                continue
            try:
                items = entries(payload)
            except RuntimeError as error:
                line = f'not decoded ({error}, {len(payload)} bytes)'
                items = []
            else:
                line = f'{len(items)} item(s)' + ''.join(f'; {summary(i)}' for i in items)
            if logged.get(source) != line:
                print(f'data-call {source}: {line}', flush=True)
                logged[source] = line
            owned = owned_ids()
            if adopt_unknown:
                unknown = {i[2] for i in items} - owned
                if unknown:
                    record_modem_owned(unknown)
            found = attach_bearer(items, owned)
            if found is not None:
                return True
        return False

    try:
        if not check() and deadline > time.monotonic():
            wait_for(service, check, deadline - time.monotonic(), stopped)
    except TimeoutError:
        pass
    if found is None:
        print('no modem-owned attach bearer with a P-CSCF listed', flush=True)
        return None
    record_modem_owned({found[2]})
    print(f'modem-owned attach bearer for IMS: {summary(found)}', flush=True)
    return found


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
    cid = net.getint('internet_cid', 1)
    if not 1 <= cid <= 15 or cid == data_call.IMS_CID:
        raise ValueError('[network] internet_cid must be 1..15 and not 2 (IMS)')
    data_call.INTERNET_CID = cid
    apn, ip_type = net.get('apn', ''), net.get('ip_type', 'ipv4v6')
    if not apn:
        raise RuntimeError('No APN configured: set [network] apn in /etc/omamobile/modem-sit.conf')
    # Some networks attach only on their IMS APN (2026-11-02, cheetah: with
    # the internet APN as the attach APN the modem searched for 13 minutes
    # with no reject; with the IMS APN it registered on LTE in 34 s). The
    # data profile and the internet bearer keep apn. Empty: the same as apn.
    attach_apn = net.get('attach_apn', '').strip() or apn
    # none: no SET_INITIAL_ATTACH_APN at all, as stock's RIL on a Verizon
    # network (2026-11-02): the modem attaches with its carrier profile's
    # settings, and its attach bearer (with the P-CSCF) carries IMS.
    attach_none = attach_apn.lower() == 'none'
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
    if attach_none:
        print('initial attach APN not sent (attach_apn = none): the modem attaches '
              'with its carrier profile', flush=True)
    else:
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
    registered_at = time.monotonic()
    data_snapshot(client, 'at registration')
    attach = None
    if attach_none:
        # Before sitd sets up anything: every bearer listed now is the
        # modem's own and is recorded so (never released). With IMS on, wait
        # for the attach bearer with its P-CSCF.
        wait = ATTACH_BEARER_WAIT if net.getboolean('ims', True) else 0
        attach = find_attach_bearer(service, registered_at + wait, stopped, adopt_unknown=True)
    ims_first = net.getboolean('ims', True) and net.getboolean('ims_first', False)
    if not ims_first:
        service.stage('data')
        activate(client, apn, ip_type=ip_type, on_event=service.event)
        service.pump()
    if not net.getboolean('ims', True):
        service.ims_state = 'off'
        print('Startup: registered with data; IMS off ([network] ims = no)', flush=True)
        return
    service.ims_state = 'pending'
    service.stage('ims')
    internet_up = not ims_first

    def internet():
        # With ims_first (stock's order: IMS bearer and ADD_PDN before any
        # other bearer), the internet comes up after the IMS setup, whether
        # that succeeded or not.
        nonlocal internet_up
        if internet_up:
            return
        service.stage('data')
        activate(client, apn, ip_type=ip_type, on_event=service.event)
        service.pump()
        internet_up = True
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
        if attach is None:
            # One more look (no wait): an attach bearer listed by now with
            # its P-CSCF is used as stock uses it; only that one is recorded.
            attach = find_attach_bearer(service, 0, stopped, adopt_unknown=False)
        fallback = None
        # With the modem's attach bearer, no IMS setup of our own: it carries
        # IMS. Otherwise sitd's own IMS bearer on CID 2, as before.
        if attach is None:
            ims_apn = net.get('ims_apn', 'ims')
            ims_ip = ims_ip_type(profiles, ims_apn)
            print('IMS bearer PDP type', ims_ip, '(from the IMS profile)' if ims_ip != 'ipv6' else '', flush=True)
            activate(client, ims_apn, ims=True, ip_type=ims_ip,
                     apn_types=ims_apn_types(profiles, ims_apn), on_event=service.event)
        if attach is None and net.getboolean('ims_pcscf_from_isim', True):
            # The ISIM's EF_PCSCF when the PCO has none (one read-only file).
            def fallback(bearer):
                return ipv6_pcscf(client, client.request(0x0200), bearer,
                                  resolve_host=resolve_default_network)
        register(client, pcscf_required=net.getboolean('ims_pcscf_required', True),
                 pcscf_fallback=fallback, attach=attach)
        internet()
        print('Startup: waiting for IMS voice and SMS registration', flush=True)
        wait_for(service, lambda: service.registration().get('state') == 2 and
                 service.registration().get('features', 0) & 3 == 3,
                 net.getint('ims_timeout', 120), stopped)
    except (RuntimeError, TimeoutError, ValueError) as error:
        if not internet_up:
            # IMS failed before the internet: bring the internet up first,
            # so data is served whatever happens to IMS (its own failure
            # ends start-up as before).
            internet()
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
