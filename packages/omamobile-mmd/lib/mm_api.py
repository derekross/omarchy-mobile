# SPDX-License-Identifier: MIT
"""The part of ModemManager's D-Bus API that omamobile-mmd serves.

Matched by hand against ModemManager 1.24.2 (tag 1.24.2, commit
f2b9ab1ad78d, 2025-07-28; GPL-2.0-or-later): introspection/*.xml for the
member names and signatures, include/ModemManager-enums.h for the values,
include/ModemManager-errors.h for the error names, and
data/org.freedesktop.ModemManager1.policy.in.in for the polkit actions.
Nothing is copied from it: these are the interface's names and numbers,
written out again. test/test_api.py compares every interface here with
MM's own XML when that is installed (/usr/share/dbus-1/interfaces, from
the modemmanager package) or named in MM_INTROSPECTION_DIR.

Every property of an interface we export is served (with MM's "unknown"
value where we have nothing), and every method answers: the ones we can't
do yet return MM's Unsupported error.
"""
from xml.sax.saxutils import quoteattr

VERSION = '1.24.2'
SERVICE = 'org.freedesktop.ModemManager1'
PATH = '/org/freedesktop/ModemManager1'
MM = 'org.freedesktop.ModemManager1'
MODEM = MM + '.Modem'
MODEM_3GPP = MODEM + '.Modem3gpp'
SIMPLE = MODEM + '.Simple'
LOCATION = MODEM + '.Location'
MESSAGING = MODEM + '.Messaging'
SIGNAL = MODEM + '.Signal'
VOICE = MODEM + '.Voice'
SIM = MM + '.Sim'
SMS = MM + '.Sms'
CALL = MM + '.Call'
BEARER = MM + '.Bearer'
OBJECT_MANAGER = 'org.freedesktop.DBus.ObjectManager'

# ModemManager-enums.h
STATE_FAILED, STATE_UNKNOWN, STATE_INITIALIZING, STATE_LOCKED, STATE_DISABLED = -1, 0, 1, 2, 3
STATE_DISABLING, STATE_ENABLING, STATE_ENABLED, STATE_SEARCHING, STATE_REGISTERED = 4, 5, 6, 7, 8
STATE_DISCONNECTING, STATE_CONNECTING, STATE_CONNECTED = 9, 10, 11
FAILED_NONE, FAILED_UNKNOWN, FAILED_SIM_MISSING, FAILED_SIM_ERROR = 0, 1, 2, 3
POWER_UNKNOWN, POWER_OFF, POWER_LOW, POWER_ON = 0, 1, 2, 3
CHANGE_UNKNOWN, CHANGE_USER_REQUESTED, CHANGE_SUSPEND, CHANGE_FAILURE = 0, 1, 2, 3
LOCK_UNKNOWN, LOCK_NONE, LOCK_SIM_PIN, LOCK_SIM_PUK, LOCK_PH_NET_PIN = 0, 1, 2, 4, 8
CAP_GSM_UMTS, CAP_LTE, CAP_5GNR = 1 << 2, 1 << 3, 1 << 6
MODE_NONE, MODE_CS, MODE_2G, MODE_3G, MODE_4G, MODE_5G = 0, 1, 2, 4, 8, 16
BAND_UNKNOWN = 0
ACCESS = {'GSM': 1 << 1, 'GPRS': 1 << 3, 'EDGE': 1 << 4, 'UMTS': 1 << 5, 'HSDPA': 1 << 6,
          'HSUPA': 1 << 7, 'HSPA': 1 << 8, 'HSPA+': 1 << 9, 'LTE': 1 << 14, 'LTE-CA': 1 << 14,
          'NR': 1 << 15}
PORT_UNKNOWN, PORT_NET, PORT_AT = 1, 2, 3
IP_V4, IP_V6, IP_V4V6 = 1, 2, 4
REG_IDLE, REG_HOME, REG_SEARCHING, REG_DENIED, REG_UNKNOWN, REG_ROAMING = 0, 1, 2, 3, 4, 5
PACKET_UNKNOWN, PACKET_DETACHED, PACKET_ATTACHED = 0, 1, 2
SUBSCRIPTION_UNKNOWN = 0
EPS_UE_MODE_UNKNOWN = 0
SIM_TYPE_PHYSICAL = 1
ESIM_UNKNOWN = 0
SIM_REMOVABLE = 1
LOCATION_NONE, LOCATION_3GPP_LAC_CI = 0, 1
SMS_UNKNOWN, SMS_STORED, SMS_RECEIVING, SMS_RECEIVED, SMS_SENDING, SMS_SENT = 0, 1, 2, 3, 4, 5
PDU_UNKNOWN, PDU_DELIVER, PDU_SUBMIT = 0, 1, 2
STORAGE_UNKNOWN, STORAGE_ME = 0, 2
DELIVERY_UNKNOWN = 0x100
VALIDITY_UNKNOWN, VALIDITY_RELATIVE = 0, 1
CALL_UNKNOWN, CALL_DIALING, CALL_RINGING_OUT, CALL_RINGING_IN = 0, 1, 2, 3
CALL_ACTIVE, CALL_HELD, CALL_WAITING, CALL_TERMINATED = 4, 5, 6, 7
REASON_UNKNOWN, REASON_OUTGOING_STARTED, REASON_INCOMING_NEW, REASON_ACCEPTED = 0, 1, 2, 3
REASON_TERMINATED, REASON_REFUSED_OR_BUSY, REASON_ERROR = 4, 5, 6
DIRECTION_UNKNOWN, DIRECTION_INCOMING, DIRECTION_OUTGOING = 0, 1, 2
BEARER_DEFAULT = 1
IP_METHOD_UNKNOWN, IP_METHOD_PPP, IP_METHOD_STATIC, IP_METHOD_DHCP = 0, 1, 2, 3

FAILED_REASON_NAMES = {FAILED_NONE: 'none', FAILED_UNKNOWN: 'unknown',
                       FAILED_SIM_MISSING: 'sim-missing', FAILED_SIM_ERROR: 'sim-error'}

# ModemManager-errors.h: MM_DBUS_ERROR_PREFIX ".Core" + the nick.
ERROR_PREFIX = MM + '.Error.Core.'


class MMError(Exception):
    """A ModemManager error as D-Bus returns it. The message must never
    carry a number or message text."""
    def __init__(self, nick, message):
        super().__init__(message)
        self.name = ERROR_PREFIX + nick
        self.message = message


def unsupported(what='This operation'):
    return MMError('Unsupported', what + ' is not supported by omamobile-mmd')


# polkit action per method (data/org.freedesktop.ModemManager1.policy.in.in
# and MM's handlers); methods not listed need none.
DEVICE_CONTROL = MM + '.Device.Control'
ACTIONS = {
    (MM, 'ScanDevices'): MM + '.Control', (MM, 'SetLogging'): MM + '.Control',
    (MM, 'ReportKernelEvent'): MM + '.Control', (MM, 'InhibitDevice'): MM + '.Control',
    **{(MODEM, m): DEVICE_CONTROL for m in (
        'Enable', 'CreateBearer', 'DeleteBearer', 'Reset', 'FactoryReset', 'SetPowerState',
        'SetCurrentCapabilities', 'SetCurrentModes', 'SetCurrentBands', 'SetPrimarySimSlot',
        'GetCellInfo', 'Command')},
    (SIMPLE, 'Connect'): DEVICE_CONTROL, (SIMPLE, 'Disconnect'): DEVICE_CONTROL,
    **{(MODEM_3GPP, m): DEVICE_CONTROL for m in (
        'Register', 'Scan', 'SetEpsUeModeOperation', 'SetInitialEpsBearerSettings',
        'SetNr5gRegistrationSettings', 'DisableFacilityLock', 'SetCarrierLock',
        'SetPacketServiceState')},
    **{(SIM, m): DEVICE_CONTROL for m in ('SendPin', 'SendPuk', 'EnablePin', 'ChangePin',
                                          'SetPreferredNetworks')},
    (BEARER, 'Connect'): DEVICE_CONTROL, (BEARER, 'Disconnect'): DEVICE_CONTROL,
    (SIGNAL, 'Setup'): DEVICE_CONTROL, (SIGNAL, 'SetupThresholds'): DEVICE_CONTROL,
    **{(LOCATION, m): DEVICE_CONTROL for m in ('Setup', 'SetSuplServer', 'InjectAssistanceData',
                                               'SetGpsRefreshRate')},
    (LOCATION, 'GetLocation'): MM + '.Location',
    (MESSAGING, 'Create'): MM + '.Messaging', (MESSAGING, 'Delete'): MM + '.Messaging',
    (MESSAGING, 'SetDefaultStorage'): DEVICE_CONTROL,
    (SMS, 'Send'): MM + '.Messaging', (SMS, 'Store'): MM + '.Messaging',
    **{(VOICE, m): MM + '.Voice' for m in (
        'CreateCall', 'DeleteCall', 'HoldAndAccept', 'HangupAndAccept', 'HangupAll',
        'Transfer', 'CallWaitingSetup', 'CallWaitingQuery')},
    **{(CALL, m): MM + '.Voice' for m in (
        'Start', 'Accept', 'Deflect', 'JoinMultiparty', 'LeaveMultiparty', 'Hangup', 'SendDtmf')},
}


def _m(*ins, out=()):
    return (list(ins), list(out))


# Interface -> methods {name: (in args, out args)}, signals {name: args},
# properties {name: signature} (all read-only in MM 1.24).
INTERFACES = {
    MM: dict(
        methods={'ScanDevices': _m(), 'SetLogging': _m(('level', 's')),
                 'ReportKernelEvent': _m(('properties', 'a{sv}')),
                 'InhibitDevice': _m(('uid', 's'), ('inhibit', 'b'))},
        signals={}, properties={'Version': 's'}),
    OBJECT_MANAGER: dict(
        methods={'GetManagedObjects': _m(out=[('object_paths_interfaces_and_properties', 'a{oa{sa{sv}}}')])},
        signals={'InterfacesAdded': [('object_path', 'o'), ('interfaces_and_properties', 'a{sa{sv}}')],
                 'InterfacesRemoved': [('object_path', 'o'), ('interfaces', 'as')]},
        properties={}),
    MODEM: dict(
        methods={'Enable': _m(('enable', 'b')), 'ListBearers': _m(out=[('bearers', 'ao')]),
                 'CreateBearer': _m(('properties', 'a{sv}'), out=[('path', 'o')]),
                 'DeleteBearer': _m(('bearer', 'o')), 'Reset': _m(), 'FactoryReset': _m(('code', 's')),
                 'SetPowerState': _m(('state', 'u')),
                 'SetCurrentCapabilities': _m(('capabilities', 'u')),
                 'SetCurrentModes': _m(('modes', '(uu)')), 'SetCurrentBands': _m(('bands', 'au')),
                 'SetPrimarySimSlot': _m(('sim_slot', 'u')),
                 'GetCellInfo': _m(out=[('cell_info', 'aa{sv}')]),
                 'Command': _m(('cmd', 's'), ('timeout', 'u'), out=[('response', 's')])},
        signals={'StateChanged': [('old', 'i'), ('new', 'i'), ('reason', 'u')]},
        properties={'Sim': 'o', 'SimSlots': 'ao', 'PrimarySimSlot': 'u', 'Bearers': 'ao',
                    'SupportedCapabilities': 'au', 'CurrentCapabilities': 'u', 'MaxBearers': 'u',
                    'MaxActiveBearers': 'u', 'MaxActiveMultiplexedBearers': 'u',
                    'Manufacturer': 's', 'Model': 's', 'Revision': 's', 'CarrierConfiguration': 's',
                    'CarrierConfigurationRevision': 's', 'HardwareRevision': 's',
                    'DeviceIdentifier': 's', 'Device': 's', 'Physdev': 's', 'Drivers': 'as',
                    'Plugin': 's', 'PrimaryPort': 's', 'Ports': 'a(su)', 'EquipmentIdentifier': 's',
                    'UnlockRequired': 'u', 'UnlockRetries': 'a{uu}', 'State': 'i',
                    'StateFailedReason': 'u', 'AccessTechnologies': 'u', 'SignalQuality': '(ub)',
                    'OwnNumbers': 'as', 'PowerState': 'u', 'SupportedModes': 'a(uu)',
                    'CurrentModes': '(uu)', 'SupportedBands': 'au', 'CurrentBands': 'au',
                    'SupportedIpFamilies': 'u'}),
    MODEM_3GPP: dict(
        methods={'Register': _m(('operator_id', 's')), 'Scan': _m(out=[('results', 'aa{sv}')]),
                 'SetEpsUeModeOperation': _m(('mode', 'u')),
                 'SetInitialEpsBearerSettings': _m(('settings', 'a{sv}')),
                 'SetNr5gRegistrationSettings': _m(('properties', 'a{sv}')),
                 'DisableFacilityLock': _m(('properties', '(us)')),
                 'SetCarrierLock': _m(('data', 'ay')), 'SetPacketServiceState': _m(('state', 'u'))},
        signals={},
        properties={'Imei': 's', 'RegistrationState': 'u', 'NetworkRejection': 'a{sv}',
                    'OperatorCode': 's', 'OperatorName': 's', 'EnabledFacilityLocks': 'u',
                    'SubscriptionState': 'u', 'EpsUeModeOperation': 'u', 'Pco': 'a(ubay)',
                    'InitialEpsBearer': 'o', 'InitialEpsBearerSettings': 'a{sv}',
                    'PacketServiceState': 'u', 'Nr5gRegistrationSettings': 'a{sv}'}),
    SIMPLE: dict(
        methods={'Connect': _m(('properties', 'a{sv}'), out=[('bearer', 'o')]),
                 'Disconnect': _m(('bearer', 'o')),
                 'GetStatus': _m(out=[('properties', 'a{sv}')])},
        signals={}, properties={}),
    LOCATION: dict(
        methods={'Setup': _m(('sources', 'u'), ('signal_location', 'b')),
                 'GetLocation': _m(out=[('Location', 'a{uv}')]), 'SetSuplServer': _m(('supl', 's')),
                 'InjectAssistanceData': _m(('data', 'ay')), 'SetGpsRefreshRate': _m(('rate', 'u'))},
        signals={},
        properties={'Capabilities': 'u', 'SupportedAssistanceData': 'u', 'Enabled': 'u',
                    'SignalsLocation': 'b', 'Location': 'a{uv}', 'SuplServer': 's',
                    'AssistanceDataServers': 'as', 'GpsRefreshRate': 'u'}),
    MESSAGING: dict(
        methods={'List': _m(out=[('result', 'ao')]), 'SetDefaultStorage': _m(('storage', 'u')),
                 'Delete': _m(('path', 'o')),
                 'Create': _m(('properties', 'a{sv}'), out=[('path', 'o')])},
        signals={'Added': [('path', 'o'), ('received', 'b')], 'Deleted': [('path', 'o')]},
        properties={'Messages': 'ao', 'SupportedStorages': 'au', 'DefaultStorage': 'u'}),
    SIGNAL: dict(
        methods={'Setup': _m(('rate', 'u')), 'SetupThresholds': _m(('settings', 'a{sv}'))},
        signals={},
        properties={'Rate': 'u', 'RssiThreshold': 'u', 'ErrorRateThreshold': 'b', 'Cdma': 'a{sv}',
                    'Evdo': 'a{sv}', 'Gsm': 'a{sv}', 'Umts': 'a{sv}', 'Lte': 'a{sv}', 'Nr5g': 'a{sv}'}),
    VOICE: dict(
        methods={'ListCalls': _m(out=[('result', 'ao')]), 'DeleteCall': _m(('path', 'o')),
                 'CreateCall': _m(('properties', 'a{sv}'), out=[('path', 'o')]),
                 'HoldAndAccept': _m(), 'HangupAndAccept': _m(), 'HangupAll': _m(), 'Transfer': _m(),
                 'CallWaitingSetup': _m(('enable', 'b')),
                 'CallWaitingQuery': _m(out=[('status', 'b')])},
        signals={'CallAdded': [('path', 'o')], 'CallDeleted': [('path', 'o')]},
        properties={'Calls': 'ao', 'EmergencyOnly': 'b'}),
    SIM: dict(
        methods={'SendPin': _m(('pin', 's')), 'SendPuk': _m(('puk', 's'), ('pin', 's')),
                 'EnablePin': _m(('pin', 's'), ('enabled', 'b')),
                 'ChangePin': _m(('old_pin', 's'), ('new_pin', 's')),
                 'SetPreferredNetworks': _m(('preferred_networks', 'a(su)'))},
        signals={},
        properties={'Active': 'b', 'SimIdentifier': 's', 'Imsi': 's', 'Eid': 's',
                    'OperatorIdentifier': 's', 'OperatorName': 's', 'EmergencyNumbers': 'as',
                    'PreferredNetworks': 'a(su)', 'Gid1': 'ay', 'Gid2': 'ay', 'SimType': 'u',
                    'EsimStatus': 'u', 'Removability': 'u'}),
    SMS: dict(
        methods={'Send': _m(), 'Store': _m(('storage', 'u'))},
        signals={},
        properties={'State': 'u', 'PduType': 'u', 'Number': 's', 'Text': 's', 'Data': 'ay',
                    'SMSC': 's', 'Validity': '(uv)', 'Class': 'i', 'TeleserviceId': 'u',
                    'ServiceCategory': 'u', 'DeliveryReportRequest': 'b', 'MessageReference': 'u',
                    'Timestamp': 's', 'DischargeTimestamp': 's', 'DeliveryState': 'u',
                    'Storage': 'u'}),
    CALL: dict(
        methods={'Start': _m(), 'Accept': _m(), 'Deflect': _m(('number', 's')),
                 'JoinMultiparty': _m(), 'LeaveMultiparty': _m(), 'Hangup': _m(),
                 'SendDtmf': _m(('dtmf', 's'))},
        signals={'DtmfReceived': [('dtmf', 's')],
                 'StateChanged': [('old', 'i'), ('new', 'i'), ('reason', 'u')]},
        properties={'State': 'i', 'StateReason': 'i', 'Direction': 'i', 'Number': 's',
                    'Multiparty': 'b', 'AudioPort': 's', 'AudioFormat': 'a{sv}'}),
    BEARER: dict(
        methods={'Connect': _m(), 'Disconnect': _m()},
        signals={},
        properties={'Interface': 's', 'Connected': 'b', 'ConnectionError': '(ss)', 'Suspended': 'b',
                    'Multiplexed': 'b', 'Ip4Config': 'a{sv}', 'Ip6Config': 'a{sv}', 'Stats': 'a{sv}',
                    'ReloadStatsSupported': 'b', 'IpTimeout': 'u', 'BearerType': 'u',
                    'ProfileId': 'i', 'Properties': 'a{sv}'}),
}


def introspection(name):
    """The interface as introspection XML (names and types only)."""
    spec = INTERFACES[name]
    out = [f'<interface name={quoteattr(name)}>']
    for method, (ins, outs) in spec['methods'].items():
        out.append(f'<method name={quoteattr(method)}>')
        out += [f'<arg name={quoteattr(a)} type={quoteattr(t)} direction="in"/>' for a, t in ins]
        out += [f'<arg name={quoteattr(a)} type={quoteattr(t)} direction="out"/>' for a, t in outs]
        out.append('</method>')
    for signal, args in spec['signals'].items():
        out.append(f'<signal name={quoteattr(signal)}>')
        out += [f'<arg name={quoteattr(a)} type={quoteattr(t)}/>' for a, t in args]
        out.append('</signal>')
    for prop, sig in spec['properties'].items():
        out.append(f'<property name={quoteattr(prop)} type={quoteattr(sig)} access="read"/>')
    out.append('</interface>')
    return '\n'.join(out)


def out_signature(interface, method):
    return ''.join(t for _, t in INTERFACES[interface]['methods'][method][1])
