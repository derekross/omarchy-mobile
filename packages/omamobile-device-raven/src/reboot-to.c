// SPDX-License-Identifier: MIT
// reboot-to: reboot with a reason the Pixel bootloader understands,
// e.g. "reboot-to bootloader" lands in fastboot.
// The kernel's syscon-reboot-mode driver stores the reason in the PMU
// before the reset; busybox reboot can't pass one.
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

/* From <linux/reboot.h> (stable ABI); musl's sysroot has no kernel headers */
#define LINUX_REBOOT_MAGIC1		0xfee1dead
#define LINUX_REBOOT_MAGIC2		672274793
#define LINUX_REBOOT_CMD_RESTART2	0xA1B2C3D4

int main(int argc, char **argv)
{
	const char *reason = argc > 1 ? argv[1] : "bootloader";

	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, reason);
	perror("reboot");
	return 1;
}
