// SPDX-License-Identifier: MIT
// reboot-to: pass a restart reason through Linux's generic reboot ABI.
// The bootloader outcome must be checked on alioth during hardware bring-up.
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
