/* SPDX-License-Identifier: MIT */
/*
 * omamobile-bootctl's values for the Pixel 8 Pro (husky). The tool refuses a
 * board or a devinfo layout other than these. The version is the one read on
 * husky phones (device/husky/BATTERY-NOTES.md, "The cure exists": magic DEVI,
 * version 3.15, three backups; issue #252: two owners' phones). test/all
 * checks the codename and compatible against device.conf.
 */
#define BOOTCTL_CODENAME	"husky"
#define BOOTCTL_COMPATIBLE	"google,zuma-husky"
#define BOOTCTL_VER_MAJOR	3
#define BOOTCTL_VER_MINOR	15
