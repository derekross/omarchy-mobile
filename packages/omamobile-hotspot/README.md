# omamobile-hotspot

The root side of the shared Wi-Fi hotspot, for phones whose Wi-Fi can't start an access point on its client interface (brcmfmac on the Pixel 8 Pro and 9a, #523):

- `lib/hotspot-ap`, run as root by `omamobile-hotspot.service`: a second interface (`ap0`) beside the client Wi-Fi, NetworkManager's `Hotspot` profile with PMF required, UFW rules and per-link forwarding while it runs;
- `lib/hotspot-backend`, which the shell's Hotspot tile and page call through `/etc/omamobile/hotspot-backend`;
- `50-omamobile-hotspot.rules`, which lets the active local user start the hotspot unit after asking for their PIN (`auth_admin_keep`, since starting opens DHCP, DNS and forwarding) and stop it without asking, and start or stop the Share VPN switch with the PIN; nothing else.

It is opt-in per device. omamobile-shell doesn't depend on it, so no phone gets this root surface unless its device package asks for it: the device package depends on this one, ships `/usr/share/omamobile/hotspot.conf` (without it the unit doesn't start) and the link `/etc/omamobile/hotspot-backend` -> `/usr/lib/omamobile-hotspot/hotspot-backend`. On other phones the shell's Hotspot page stays on plain NetworkManager.

Client isolation is always on, in its own nftables table (`inet omamobile_hotspot_iso`, so a drop there is final whatever UFW or NetworkManager accept):

- a client gets to the phone only for DHCP and for DNS on the hotspot's own address; ssh or the phone's address on another network are dropped;
- forwarding from the hotspot to private, shared (100.64/10), link-local, loopback, multicast and reserved IPv4 ranges is dropped, so the home LAN is out of reach whether it is the uplink's own subnet or behind its router;
- nothing on the uplink side can open a connection to a client, a client can't reach another one through the phone, and IPv6 from and to the hotspot is dropped (the profile is IPv4 only);
- the profile asks for AP isolation, so clients don't talk to each other inside the radio either (whether the Wi-Fi firmware honours that hasn't been checked on a phone yet).

It goes in before the profile comes up, is refreshed every 5 s, and goes after the access point's interface is deleted. If it can't be applied (no `nft`, or `nft` refuses), the hotspot doesn't start or stops. The phone's own on-link subnets and host routes are dropped as well, so a home LAN on public addresses directly on the uplink is covered; a public-address network behind the uplink's router can't be told from the internet and stays reachable.

Limit: an on-link split default route (`0.0.0.0/1` and `128.0.0.0/1`, as some VPNs add) lands in that drop set too, so with Share VPN off the clients lose the internet while it is there. That fails closed, nothing leaks. With Share VPN on, the routes of the VPN link it uses are left out of the set.

Share VPN (the page's box, `omamobile-hotspot-vpn.service`): with it on, the clients' traffic leaves only through the phone's VPN link (WireGuard or tun), and with no VPN up they get no internet and no DNS. It's a kill switch in a second table (`inet omamobile_hotspot_vpn`) plus a routing rule for the hotspot's interface. The VPN link is exempt from the private-range drop above, so hosts behind the VPN stay reachable. Turning the switch on or off asks for the PIN both ways, like the other privacy and network switches.

Not run on a phone yet: both have run in the CI container only, against stubs and in a real-kernel network namespace test, with no real WireGuard tunnel.
