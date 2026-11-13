<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo)

This first-light target describes the Tensor G4 boot layout, bootloader DT
selectors and slot-B storage allowlist. It uses the existing Android-v4 image
builder, including all five AVB hash footers. The board selector overlay leaves
hardware description to the corresponding kernel board DTS.

The boot-image geometry was checked against the retained working image set.
The descriptor retains the booted all-five-footer/index-`1791158400` policy
for the first public-kernel cohort, following the maintainer's 2026-11-11
decision. Read-only slot-A boot/init_boot captures establish the OS/security
metadata and their different footer index 0; both vbmeta partitions list all
five images as hash descriptors, none chained. [FIRST-LIGHT](FIRST-LIGHT.md)
records the remaining hold on new image builds and boots until the disabled-node
kernel series is merged and its public PR and exact head are cited.
USB SSH and the storage guard have run on development hardware. The minimal descriptor in this change still needs its own complete
image-build and boot qualification against the public kernel prerequisites.

This is a development port target rather than an installer release. The device
package and individual peripheral enablement belong in follow-up changes.
Read [the first-light runbook and dated metadata evidence](FIRST-LIGHT.md)
and the project's contributing safety model before any hardware operation.
The runbook names the required kernel patch series; it is not yet a published
kernel dependency or a qualification of this minimal target.
