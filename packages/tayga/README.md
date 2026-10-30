<!-- SPDX-License-Identifier: MIT -->
# tayga (Omarchy Mobile build)

TAYGA 0.9.6 is a stateless NAT64 translator that runs in user space on a
TUN device. Neither Arch Linux nor Arch Linux ARM packages it.

`omamobile-modem-sit` 0.4.0 and later lists TAYGA as an optional
dependency:

- **With it**, an IPv6-only cellular bearer gets a CLAT (464XLAT,
  RFC 6877). IPv4 addresses and IPv4-only programs then work through the
  carrier's NAT64.
- **Without it**, the bearer is IPv6 only. Hostnames still resolve
  through the carrier's DNS64.

This package enables and configures nothing. `omamobile-sit-data` does
the following itself, for as long as the bearer is up:

1. writes TAYGA's config to `/run/omamobile-sit/clat.conf`;
2. creates the `v4-rmnet0` TUN device with `tayga --mktun`;
3. runs `tayga --nodetach` as its child.

`lib/clat.py` in `omamobile-modem-sit` has the details. MODEM-CLIENT.md
section 1.3 explains why we use TAYGA rather than a ready-made CLAT
daemon.

To build it with the other packages:

```sh
tools/build-packages packages/tayga
```

To build and install it on the phone (only on the maintainer's go):

```sh
tools/phone-install-package packages/tayga
```

The build has not run yet: it waits for the maintainer's container
build.
