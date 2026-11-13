<!-- SPDX-License-Identifier: MIT -->
# tqftpserv

Serves firmware files to Qualcomm processors over TFTP on AF_QIPCRTR. Its
read-only firmware path maps into `/lib/firmware`; writable files stay under
`/var/lib/tqftpserv` for that phone. They are never copied to another phone or
committed. Dipper is the first planned consumer; its device package decides
whether to enable the service.
