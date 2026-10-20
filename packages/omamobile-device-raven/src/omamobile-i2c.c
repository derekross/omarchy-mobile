// SPDX-License-Identifier: MIT
/*
 * omamobile-i2c: read or write one byte register over /dev/i2c-N, for the
 * USB rescue on a root that has no i2c-tools yet. Static, no dependencies.
 *
 *   omamobile-i2c BUS ADDR REG          prints the value as 0xNN
 *   omamobile-i2c BUS ADDR REG VALUE    writes it
 *
 * Uses I2C_SLAVE_FORCE (as i2cget -f does): the address belongs to a kernel
 * driver (the MAX77759 core binds the chip's other addresses).
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* From the kernel's uapi <linux/i2c-dev.h> and <linux/i2c.h> (stable ABI) */
#define I2C_SLAVE_FORCE		0x0706
#define I2C_SMBUS		0x0720
#define I2C_SMBUS_READ		1
#define I2C_SMBUS_WRITE		0
#define I2C_SMBUS_BYTE_DATA	2

union i2c_smbus_data {
	uint8_t byte;
	uint16_t word;
	uint8_t block[34];
};

struct i2c_smbus_ioctl_data {
	uint8_t read_write;
	uint8_t command;
	uint32_t size;
	union i2c_smbus_data *data;
};

static long num(const char *s)
{
	char *end;
	long v = strtol(s, &end, 0);

	if (*s == '\0' || *end != '\0' || v < 0 || v > 255) {
		fprintf(stderr, "bad number: %s\n", s);
		exit(2);
	}
	return v;
}

int main(int argc, char **argv)
{
	struct i2c_smbus_ioctl_data args;
	union i2c_smbus_data data;
	char path[32];
	int fd;

	if (argc != 4 && argc != 5) {
		fprintf(stderr, "usage: %s BUS ADDR REG [VALUE]\n", argv[0]);
		return 2;
	}
	snprintf(path, sizeof(path), "/dev/i2c-%ld", num(argv[1]));
	fd = open(path, O_RDWR);
	if (fd < 0 || ioctl(fd, I2C_SLAVE_FORCE, num(argv[2])) < 0) {
		perror(path);
		return 1;
	}
	args.command = num(argv[3]);
	args.data = &data;
	args.size = I2C_SMBUS_BYTE_DATA;
	if (argc == 5) {
		data.byte = num(argv[4]);
		args.read_write = I2C_SMBUS_WRITE;
	} else {
		args.read_write = I2C_SMBUS_READ;
	}
	if (ioctl(fd, I2C_SMBUS, &args) < 0) {
		perror("i2c");
		return 1;
	}
	if (argc == 4)
		printf("0x%02x\n", data.byte);
	return 0;
}
