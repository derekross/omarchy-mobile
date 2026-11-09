<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo)

This first-light target describes the Tensor G4 boot layout, bootloader DT
selectors and slot-B storage allowlist. It uses the existing Android-v4 image
builder, including all five AVB hash footers. The board selector overlay leaves
hardware description to the corresponding kernel board DTS.

The boot-image geometry and footer metadata were checked against the retained
working image set. USB SSH and the storage guard have run on development
hardware. The minimal descriptor in this change still needs its own complete
image-build and boot qualification against the public kernel prerequisites.

This is a development port target rather than an installer release. The device
package and individual peripheral enablement belong in follow-up changes.
Read [the first-light runbook and dated metadata evidence](FIRST-LIGHT.md)
and the project's contributing safety model before any hardware operation.
The runbook names the required kernel patch series; it is not yet a published
kernel dependency or a qualification of this minimal target.
