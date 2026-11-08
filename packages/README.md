<!-- SPDX-License-Identifier: MIT -->
# Qualcomm userspace packages

These packages provide userspace pieces used by Qualcomm remote processors over
the kernel's QRTR transport. They do not enable a modem service or write phone
partitions by themselves.

- **qrtr** provides the userspace QRTR library and tools. This build disables
  `qrtr-ns`; the phones use the kernel QRTR name service.
- **pd-mapper** publishes Qualcomm service registry and protection-domain
  mapping data used by clients that request it.
- **tqftpserv** serves firmware files to Qualcomm processors over TFTP on
  AF_QIPCRTR. Upstream's read-only firmware path maps into `/lib/firmware`; its
  temporary read-write path maps into `/tmp/tqftpserv`.
- **rmtfs** serves the modem's remote filesystem requests. Upstream's
  `rmtfs.service` uses `rmtfs -r`, keeping modem writes in RAM. The separate
  `rmtfs-dir.service` persists the phone's NV files under `/var/lib/rmtfs`.
  Choosing whether a Dipper device package may start either service is a later
  modem decision; Linux does not write modem partitions.

The package recipes follow the tagged `linux-msm` source releases and keep each
upstream license and attribution with the package.
