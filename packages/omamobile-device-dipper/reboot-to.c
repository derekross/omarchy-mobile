// SPDX-License-Identifier: MIT
// Request a reboot reason understood by the Qualcomm bootloader.
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#define LINUX_REBOOT_MAGIC1 0xfee1dead
#define LINUX_REBOOT_MAGIC2 672274793
#define LINUX_REBOOT_CMD_RESTART2 0xA1B2C3D4

int main(int argc, char **argv)
{
	const char *reason = argc > 1 ? argv[1] : "bootloader";

	if (argc > 2 || reason[0] == '-') {
		fprintf(stderr, "usage: reboot-to [REASON]\n");
		return 2;
	}
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, reason);
	perror("reboot");
	return 1;
}
