<!-- SPDX-License-Identifier: MIT -->
# Modem link modules

The default link remains `modprobe pcie-gs201-cp allow_hw=1` when no device
configuration exists. The Pixel 9 Pro XL needs a separate PHY before its PCIe
host; its device package may supply the ordered list as
`/usr/lib/omamobile-modem/link.conf`. This directory is staged by this package
and is separate from extracted vendor files. This package does not install
link.conf or enable another device's drivers. The device package owns its file.

The file is data, never a shell fragment. Each nonempty, noncomment line is:

```
module key=value key=value
```

A module starts with an ASCII letter and contains only letters, digits,
underscores and hyphens. Parameter names start with a letter or underscore;
remaining characters are letters, digits or underscores. Values are nonempty
and contain only letters, digits, underscore, period, comma, colon, plus,
slash or hyphen. Arguments are separated by spaces or tabs; a module without
parameters is valid. Blank lines and whole-line comments are allowed. Shell
quotes, substitutions, assignments, functions, options and inline comments
are refused, as are empty configurations, symlinks and unreadable/nonregular
files. A raw ASCII-text check rejects NUL and other non-text bytes before
Bash reads lines; both passes use the same opened file. A missing file preserves the default; a present invalid file refuses.

All entries are validated before checking already-loaded parameters, checking
the sleep inhibitor, creating the bring-up latch or loading modules. Missing
or mismatched parameters on loaded modules still require a reboot; the
configuration cannot reassign MARK/HOLD or redefine refuse. The normal marker,
unclean-stop and hold decisions remain unchanged. Device-specific configuration
does not authorize starting a modem or replace its watchdog/backup/recovery
qualification. The maintainer allocates the package version at merge.
