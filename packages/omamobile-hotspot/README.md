# omamobile-hotspot

The root side of the shared Wi-Fi hotspot, for phones whose Wi-Fi can't start an access point on its client interface (brcmfmac on the Pixel 8 Pro and 9a, #523):

- `lib/hotspot-ap`, run as root by `omamobile-hotspot.service`: a second interface (`ap0`) beside the client Wi-Fi, NetworkManager's `Hotspot` profile with PMF required, UFW rules and per-link forwarding while it runs;
- `lib/hotspot-backend`, which the shell's Hotspot tile and page call through `/etc/omamobile/hotspot-backend`;
- `50-omamobile-hotspot.rules`, which lets the active local user start and stop that one unit, nothing else.

It is opt-in per device. omamobile-shell doesn't depend on it, so no phone gets this root surface unless its device package asks for it: the device package depends on this one, ships `/usr/share/omamobile/hotspot.conf` (without it the unit doesn't start) and the link `/etc/omamobile/hotspot-backend` -> `/usr/lib/omamobile-hotspot/hotspot-backend`. On other phones the shell's Hotspot page stays on plain NetworkManager.

Not ready to ship: the hotspot's clients can reach the networks the phone is on (the home LAN as well as the internet), because forwarding isn't limited to the uplink yet. It stays unpublished until client isolation lands.
