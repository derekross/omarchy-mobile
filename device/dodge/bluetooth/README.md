<!-- SPDX-License-Identifier: MIT -->
# dodge Bluetooth

`omamobile-bt` brings up the WCN7860 HCI over the board's UART. It looks for
helper modules under `/usr/local/lib/omamobile/bt` and, for some out-of-tree
bits, `/usr/lib/modules/$(uname -r).held/`. A kernel installed only by
`modules-push` has neither path, so the unit fails safely (hci0 stays down)
until those modules are installed next to the running release or the package
ships them. Pairing was verified against another phone; A2DP is untested.
