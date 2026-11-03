# SPDX-License-Identifier: MIT
"""The internet APN, and the initial-attach APN, for a SIM, chosen from its
home network code, so that a SIM works without anyone typing an APN.

The attach APN is the one the modem registers with (SET_INITIAL_ATTACH_APN).
It comes from an override's attach_apn, else from a database APN typed "ia";
empty means "the internet APN", the usual case. Some carriers register only
with another one: on 2026-11-02 a SIM on Verizon's network never registered
with the internet APN as attach APN and registered within 34 s with the IMS
APN (our capture on the Pixel 7 Pro).

The SIM's home network (MCC and MNC) is the start of its IMSI. It is looked
up first in the project's overrides (apn-overrides.conf: carriers the
database gets wrong, each with the carrier's public APN page), then in the
system's carrier database, mobile-broadband-provider-info's
serviceproviders.xml (GNOME, CC-PDDC public-domain dedication; the same file
NetworkManager and ModemManager use).

Only the MCC and MNC leave home_plmn(): the rest of the IMSI identifies the
subscriber and is dropped there. Nothing here logs; the caller logs where
the APN came from, never the IMSI, the network code or the APN itself.
"""
import configparser
import os
import re
import xml.etree.ElementTree as ElementTree

DATABASE = os.environ.get('OMAMOBILE_SIT_PROVIDERS',
                          '/usr/share/mobile-broadband-provider-info/serviceproviders.xml')
OVERRIDES = os.environ.get('OMAMOBILE_SIT_APN_OVERRIDES',
                           '/usr/share/omamobile/modem-sit/apn-overrides.conf')

# Countries whose MNCs are three digits (ITU-T E.212 lists; North America,
# most of the Caribbean and Latin America, and India's 405 block in part).
# Elsewhere the MNC is two digits. The SIM's EF_AD says which, but reading
# it needs SIM I/O, which the RIL doesn't send; both lengths are tried, the
# country's usual one first.
THREE_DIGIT_MNC = frozenset({
    '302', '310', '311', '312', '313', '314', '315', '316', '334', '338', '342', '344',
    '346', '348', '354', '356', '358', '360', '365', '366', '376', '405', '708', '722',
    '732', '750'})
# Usages that carry the internet in the database's DTD (serviceproviders.2.dtd);
# an APN without a usage element is an internet APN too.
INTERNET_USAGES = ('internet', 'mms-internet-hipri', 'mms-internet-hipri-fota')
APN = re.compile(r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*')


def home_plmn(imsi):
    """(MCC, [MNC candidates, likelier first]) from an IMSI's digits. The
    subscriber part is never returned."""
    if not isinstance(imsi, str) or not imsi.isdigit() or not 6 <= len(imsi) <= 15:
        raise ValueError('not an IMSI')
    mcc = imsi[:3]
    two, three = imsi[3:5], imsi[3:6]
    return mcc, ([three, two] if mcc in THREE_DIGIT_MNC else [two, three])


def plain_apn(value):
    value = (value or '').strip()
    return value if APN.fullmatch(value) and len(value) <= 99 else ''


def from_overrides(mcc, mncs, path=None):
    parser = configparser.ConfigParser(interpolation=None)
    try:
        if not parser.read(path or OVERRIDES):
            return None
    except configparser.Error:
        return None
    for mnc in mncs:
        key = f'{mcc}/{mnc}'
        if parser.has_section(key):
            section = parser[key]
            apn = plain_apn(section.get('apn'))
            if apn:
                return dict(apn=apn, attach_apn=plain_apn(section.get('attach_apn')),
                            ims_apn=plain_apn(section.get('ims_apn')),
                            carrier=section.get('name', '').strip(), source='override')
    return None


def provider_rank(provider, nets):
    """Prefer the network's own operator over the resellers that share its
    code: primary="true", then no attribute, then primary="false"; then the
    provider listing more network codes (the operator lists all of its own,
    a reseller usually one)."""
    primary = {'true': 0, None: 1, 'false': 2}.get(provider.get('primary'), 1)
    return (primary, -len(nets))


def attach_apn(provider):
    """The provider's initial-attach APN: one typed "ia" in the database
    (serviceproviders.2.dtd), or '' (attach with the internet APN, as a
    phone does when a carrier lists no attach APN)."""
    for apn in provider.iter('apn'):
        if any(u.get('type') == 'ia' for u in apn.iter('usage')):
            value = plain_apn(apn.get('value'))
            if value:
                return value
    return ''


def internet_apn(provider):
    for apn in provider.iter('apn'):
        usages = [u.get('type') for u in apn.iter('usage')]
        if usages and not any(u in INTERNET_USAGES for u in usages):
            continue
        value = plain_apn(apn.get('value'))
        # An IMS APN filed as internet (the database lists one for at least
        # one carrier) never carries internet traffic.
        if value and value.lower() != 'ims':
            return value
    return ''


def from_database(mcc, mncs, path=None):
    try:
        root = ElementTree.parse(path or DATABASE).getroot()
    except (OSError, ElementTree.ParseError):
        return None
    for mnc in mncs:
        found = []
        for index, provider in enumerate(root.iter('provider')):
            nets = {(n.get('mcc'), n.get('mnc')) for n in provider.iter('network-id')}
            if (mcc, mnc) not in nets:
                continue
            apn = internet_apn(provider)
            if apn:
                found.append((provider_rank(provider, nets), index, provider, apn))
        if found:
            _, _, provider, apn = min(found, key=lambda f: f[:2])
            return dict(apn=apn, attach_apn=attach_apn(provider), ims_apn='',
                        carrier=(provider.findtext('name') or '').strip(), source='carrier-database')
    return None


def lookup(imsi, database=None, overrides=None):
    """The internet APN, the attach APN ('' for the internet APN) and the
    IMS APN when an override names one, for the SIM with this IMSI, or None.
    The result holds no part of the IMSI."""
    try:
        mcc, mncs = home_plmn(imsi)
    except ValueError:
        return None
    return from_overrides(mcc, mncs, overrides) or from_database(mcc, mncs, database)
