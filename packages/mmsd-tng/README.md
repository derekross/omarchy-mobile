<!-- SPDX-License-Identifier: MIT -->
# mmsd-tng

An opt-in, per-user MMS daemon using ModemManager's D-Bus API. It never
starts the modem or sitd. This package alone does not enable picture
messages in Messages: omatel-agent and omamessages need their T3 changes
in their own repositories. See `docs/TELEPHONY-APPS-PLAN.md` section 1.7b.

The AUR has `mmsd-tng-git`, advertising 2.5.0.r0.g6529119-1 in its cached
package metadata while building upstream HEAD. Neither Arch's exact-name
search nor Arch Linux ARM's aarch64 core/extra indexes contained mmsd-tng
when checked on 2026-11-03. This recipe uses upstream's stable 2.6.4 tag
and the AUR runtime dependency set, with a checked source checksum and a
single Meson build directory. Modern libphonenumber headers additionally
need explicit protobuf and Abseil linkage.

Sources: [AUR recipe](https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=mmsd-tng-git),
[upstream 2.6.4](https://gitlab.com/kop316/mmsd/-/tree/2.6.4),
[Arch Linux ARM package indexes](https://de3.mirror.archlinuxarm.org/aarch64/extra/).
Upstream is GPL-2.0; its LGPL components retain their notices. Patches use
the corresponding upstream file's license.

The patches apply the configured own number when MM's OwnNumbers array is
empty, including E.164 parsing without an IMSI-derived region; close HTTP
sockets on interface-binding failure; and link the dependencies required by
current libphonenumber.

mmsd-tng fetches MMS over a connected bearer whose APN is its `MMS_APN`,
bound to that bearer's device and resolving through the DNS in its
`Ip4Config`. On the 9a that's the internet bearer, where the carrier's MMS
APN is the internet APN: omamobile-mmd gives it the device sitd's data
network found and the carrier's DNS (see docs/TELEPHONY-APPS-PLAN.md 1.7).
Nothing is set up just for MMS, and the system's routes and DNS aren't
touched. A carrier with a separate MMS APN isn't supported yet.

Owner configuration, before the first start: copy
`/usr/share/mmsd-tng/mms.example` to `~/.mms/modemmanager/mms` (mode 0600)
as the same session user as omatel-agent, and replace `<MMSC>`, `<APN>` (the
internet APN) and `<OWN_NUMBER>`. Keep `ForceCAres=true` so DNS goes to the
bearer's servers. Set the MMS proxy to the carrier's `host:port`, or `NULL`
when there's none. Then `systemctl --user start mmsd-tng.service`.

No unit is enabled or D-Bus activated by this package. No carrier settings
are shipped. Do not enable upstream debug logging on the phone: it can
print numbers, message URLs, settings and message content. Never publish
its journal, settings, message store, WAP bytes or attachments.

IPv4 only for now (including an IPv4v6 bearer's IPv4 address and DNS);
IPv6-only MMS, modem suspend and carrier acceptance need attended runs.
