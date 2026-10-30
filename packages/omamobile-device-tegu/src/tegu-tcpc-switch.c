// SPDX-License-Identifier: MIT
/* Fixed MAX77779 observations and one guarded USB data-switch restoration. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define TCPC_ADDR 0x25

static void fail(const char *message)
{
	perror(message);
	exit(EXIT_FAILURE);
}

static uint8_t read_byte(int fd, uint8_t reg)
{
	uint8_t value;
	struct i2c_msg messages[] = {
		{ .addr = TCPC_ADDR, .len = 1, .buf = &reg },
		{ .addr = TCPC_ADDR, .flags = I2C_M_RD, .len = 1, .buf = &value },
	};
	struct i2c_rdwr_ioctl_data transfer = {
		.msgs = messages,
		.nmsgs = 2,
	};
	int ret;

	ret = ioctl(fd, I2C_RDWR, &transfer);
	if (ret != 2) {
		if (ret >= 0)
			errno = EIO;
		fail("one-byte TCPC read");
	}
	return value;
}

static void connect_data(int fd)
{
	uint8_t bytes[] = { 0x93, 0x09 };
	struct i2c_msg message = {
		.addr = TCPC_ADDR, .len = sizeof(bytes), .buf = bytes,
	};
	struct i2c_rdwr_ioctl_data transfer = {
		.msgs = &message, .nmsgs = 1,
	};
	uint8_t value;
	int ret;

	if (read_byte(fd, 0x02) != 0x79 || read_byte(fd, 0x00) != 0x56 ||
	    read_byte(fd, 0x01) != 0x04 || !(read_byte(fd, 0x1e) & 4)) {
		fputs("MAX77779 identity or present VBUS not confirmed; no write\n", stderr);
		exit(EXIT_FAILURE);
	}
	value = read_byte(fd, 0x93);
	if (value == 0x09)
		return;
	if (value != 0x00) {
		fputs("Unexpected USB switch state; no write\n", stderr);
		exit(EXIT_FAILURE);
	}
	if (!(read_byte(fd, 0x1e) & 4)) {
		fputs("VBUS disappeared; no write\n", stderr);
		exit(EXIT_FAILURE);
	}
	fputs("Fixed USB data-switch restoration: register 0x93 <- 0x09\n", stderr);
	ret = ioctl(fd, I2C_RDWR, &transfer);
	if (ret != 1) {
		if (ret >= 0)
			errno = EIO;
		fail("fixed TCPC data-switch write");
	}
	if (read_byte(fd, 0x93) != 0x09) {
		fputs("USB data-switch readback failed\n", stderr);
		exit(EXIT_FAILURE);
	}
}

int main(int argc, char **argv)
{
	static const struct {
		const char *name;
		uint8_t reg;
	} reads[] = {
		{ "vendor-low", 0x00 },
		{ "vendor-high", 0x01 },
		{ "product", 0x02 },
		{ "power", 0x1e },
		{ "switch", 0x93 },
	};
	char path[PATH_MAX], compatible[128] = { 0 };
	FILE *file;
	unsigned long functions;
	size_t i;
	int fd, selected = -1;
	int connect = argc == 2 && !strcmp(argv[1], "connect");

	if (argc == 2) {
		for (i = 0; i < sizeof(reads) / sizeof(reads[0]); i++) {
			if (!strcmp(argv[1], reads[i].name))
				selected = (int)i;
		}
	}
	if (selected < 0 && !connect) {
		fputs("Usage: tegu-tcpc-switch vendor-low|vendor-high|product|power|switch|connect\n",
		      stderr);
		return 64;
	}
	file = fopen("/proc/device-tree/compatible", "rb");
	if (!file)
		fail("machine compatible");
	if (!fread(compatible, 1, sizeof(compatible) - 1, file) ||
	    strcmp(compatible, "google,zumapro-tegu")) {
		fputs("Expected Pixel 9a compatible\n", stderr);
		return EXIT_FAILURE;
	}
	fclose(file);
	/*
	 * The USI6 adapter's number depends on probe order (it was i2c-0 on
	 * the curated boots and is not after the integration DT): find the
	 * adapter whose device is 108d0000.i2c instead of assuming i2c-0.
	 */
	{
		char dev[64] = { 0 };
		int n;

		for (n = 0; n < 64 && !dev[0]; n++) {
			char link[64];

			snprintf(link, sizeof(link), "/sys/bus/i2c/devices/i2c-%d", n);
			if (realpath(link, path) && strstr(path, "/108d0000.i2c/i2c-"))
				snprintf(dev, sizeof(dev), "/dev/i2c-%d", n);
		}
		if (!dev[0]) {
			fputs("Expected USI6 I2C adapter (108d0000.i2c)\n", stderr);
			return EXIT_FAILURE;
		}
		fd = open(dev, O_RDWR | O_CLOEXEC);
	}
	if (fd < 0)
		fail("open qualified I2C adapter");
	/* I2C_SLAVE, never I2C_SLAVE_FORCE: refuse an address owned by a driver. */
	if (ioctl(fd, I2C_SLAVE, TCPC_ADDR) < 0)
		fail("claim unbound TCPC address");
	if (ioctl(fd, I2C_FUNCS, &functions) < 0)
		fail("I2C adapter functionality");
	if (!(functions & I2C_FUNC_I2C)) {
		fputs("I2C combined transfers unavailable\n", stderr);
		return EXIT_FAILURE;
	}
	if (connect) {
		connect_data(fd);
		puts("0x09");
	} else {
		printf("0x%02x\n", read_byte(fd, reads[selected].reg));
	}
	close(fd);
	return EXIT_SUCCESS;
}
