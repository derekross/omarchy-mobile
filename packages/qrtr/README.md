<!-- SPDX-License-Identifier: MIT -->
# qrtr

Provides the userspace QRTR library and tools used by Qualcomm remote
processors. The kernel supplies QRTR name service, so this build disables
`qrtr-ns`. Dipper is the first planned consumer; its device package decides
whether to enable any related service.
