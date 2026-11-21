# SPDX-License-Identifier: MIT
# What the root image settles for its first boot, so that nothing on the
# phone has to ask for it. Sourced by rootfs/build-inside; tests/rootfs-first-boot
# runs it on a stand-in root.
#
# systemd-firstboot.service runs once, on a first boot (/etc/machine-id reads
# "uninitialized"), and asks on the console for whatever of these the image
# lacks: locale, keymap, time zone, root password. A phone has no console
# (the bootloader appends console=null), so the unit failed once on every
# install (status 208/STDIN) and left the first boot "degraded"
# (docs/INSTALL-EXPERIENCE-PLAN.md G3). The image answers instead:
#   locale       /etc/locale.conf, LANG=C.UTF-8 (glibc has it built in, so it
#                works before any locale is generated). A device package's
#                omamobile-setup-system replaces it at first boot
#   time zone    /etc/localtime, UTC, until omamobile-firstboot links the
#                owner's TIMEZONE from firstboot.conf (default UTC)
#   root         stays locked (build-inside); the owner's account comes from
#                firstboot.conf
#   machine id   stays "uninitialized" (build-inside): systemd makes this
#                phone's own id on the first boot and commits it; that needs
#                no unit that asks
#   keymap       none: systemd-firstboot only asks for one on a local virtual
#                console, and a KEYMAP= in /etc/vconsole.conf would make
#                systemd-vconsole-setup load a keymap where today it loads
#                nothing
# and masks the unit, as omamobile-device-dodge does. A locale.conf or
# localtime a package already put in the image is kept.

# first_boot_defaults ROOT
first_boot_defaults() {
  local root=$1
  [[ -f $root/usr/share/zoneinfo/UTC ]] || { echo "first_boot_defaults: no $root/usr/share/zoneinfo/UTC (tzdata)" >&2; return 1; }
  install -d "$root/etc/systemd/system"
  ln -sfn /dev/null "$root/etc/systemd/system/systemd-firstboot.service"
  [[ -e $root/etc/locale.conf ]] || printf 'LANG=C.UTF-8\n' > "$root/etc/locale.conf"
  [[ -e $root/etc/localtime || -L $root/etc/localtime ]] || ln -s /usr/share/zoneinfo/UTC "$root/etc/localtime"
}

# first_boot_manifest ROOT: the MANIFEST's line for the above, from what the
# root holds (tests/rootfs-smoke checks an image that carries the line)
first_boot_manifest() {
  local root=$1 zone
  zone=$(readlink "$root/etc/localtime")
  printf 'first boot: systemd-firstboot.service masked; %s; time zone %s until firstboot.conf\n' \
    "$(grep -m1 '^LANG=' "$root/etc/locale.conf")" "${zone#/usr/share/zoneinfo/}"
}
