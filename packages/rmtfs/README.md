<!-- SPDX-License-Identifier: MIT -->
# rmtfs

Serves modem remote-filesystem requests. Upstream's `rmtfs.service` runs with
`-r`, keeping modem writes in RAM without writing modem partitions.
`rmtfs-dir.service` instead stores that phone's NV files under
`/var/lib/rmtfs`. The Dipper device package must decide which service, if any,
to enable; Linux must never write modem partitions.
