// SPDX-License-Identifier: MIT
// reboot-to: reboot with a reason the Pixel bootloader understands,
// e.g. "reboot-to bootloader" lands in fastboot.
// The kernel's syscon-reboot-mode driver stores the reason in the PMU
// before the reset; busybox reboot can't pass one.
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

/* From <linux/reboot.h> (stable ABI); musl's sysroot has no kernel headers */
#define LINUX_REBOOT_MAGIC1		0xfee1dead
#define LINUX_REBOOT_MAGIC2		672274793
#define LINUX_REBOOT_CMD_RESTART2	0xA1B2C3D4

/*
 * The modem's start refuses after a boot that ended with the modem up and
 * no clean stop (a hang or a reset). This restart skips systemd's shutdown,
 * so it notes the boot it ends, before rebooting: the next start then knows
 * this boot ended on purpose. Best effort: without /var/lib/omamobile (the
 * initramfs) there is no note, and the start refuses as before.
 */
#define NOTE_DIR "/var/lib/omamobile"
#define NOTE NOTE_DIR "/deliberate-restart"

static void note_deliberate_restart(void)
{
	char id[64];
	FILE *f = fopen("/proc/sys/kernel/random/boot_id", "r");
	int fd, dir;

	if (!f)
		return;
	if (!fgets(id, sizeof(id), f)) {
		fclose(f);
		return;
	}
	fclose(f);
	fd = open(NOTE ".new", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		return;
	if (write(fd, id, strlen(id)) != (ssize_t)strlen(id) || fsync(fd)) {
		close(fd);
		unlink(NOTE ".new");
		return;
	}
	close(fd);
	if (rename(NOTE ".new", NOTE))
		return;
	dir = open(NOTE_DIR, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
	if (dir >= 0) {
		fsync(dir);
		close(dir);
	}
}

int main(int argc, char **argv)
{
	const char *reason = argc > 1 ? argv[1] : "bootloader";

	note_deliberate_restart();
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, reason);
	perror("reboot");
	return 1;
}
