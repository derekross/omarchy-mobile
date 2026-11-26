// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>

int main(void)
{
	static const char message[] = "<6>grizzly: warm restart requested [systemd-ram-root]\n";
	struct timespec deadline;
	int log, ready;

	if (setsid() < 0 || signal(SIGTERM, SIG_IGN) == SIG_ERR ||
	    clock_gettime(CLOCK_BOOTTIME, &deadline) < 0)
		return 1;
	deadline.tv_sec = 600;
	deadline.tv_nsec = 0;
	log = open("/dev/kmsg", O_WRONLY);
	if (log < 0)
		return 1;
	ready = open("/run/grizzly-systemd-armed", O_CREAT | O_EXCL | O_WRONLY, 0600);
	if (ready < 0)
		return 1;
	close(ready);
	if (clock_nanosleep(CLOCK_BOOTTIME, TIMER_ABSTIME, &deadline, 0) != 0)
		return 1;
	(void)write(log, message, sizeof(message) - 1);
	sleep(1);
	return reboot(RB_AUTOBOOT) < 0;
}
