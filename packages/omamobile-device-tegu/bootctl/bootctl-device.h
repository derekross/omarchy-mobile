/* SPDX-License-Identifier: MIT */
/*
 * omamobile-bootctl's values for the Pixel 9a (tegu). The tool refuses a
 * board or a devinfo layout other than these. The version is the one read on
 * the 9a (device/tegu/NOTES.md, "devinfo write disclosure and stop" and
 * "Read-only layout evidence after official OTA maintenance": layout 3.15,
 * the slot bytes paired with ABL's getvars across a boot that spent a try).
 * test/all checks the codename and compatible against device.conf.
 */
#define BOOTCTL_CODENAME	"tegu"
#define BOOTCTL_COMPATIBLE	"google,zumapro-tegu"
#define BOOTCTL_VER_MAJOR	3
#define BOOTCTL_VER_MINOR	15
