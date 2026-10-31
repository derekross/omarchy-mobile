// SPDX-License-Identifier: Apache-2.0
/*
 * omamobile-bootctl: read and (carefully) update the A/B slot metadata that
 * the Pixel bootloader (ABL) keeps in the "devinfo" partition on gs101/gs201.
 *
 * This file is a port of Google's Pixel boot-control HAL and is therefore
 * licensed under Apache-2.0, not MIT like the rest of Omarchy Mobile's tools.
 * The devinfo layout and the slot update rules come from:
 *
 *   https://android.googlesource.com/device/google/gs-common
 *   tag android-14.0.0_r75 (commit ddbc3a43bcad1db516c114aca87df90d1780e728)
 *   bootctrl/aidl/DevInfo.h       Copyright (C) 2021 The Android Open Source Project
 *   bootctrl/aidl/BootControl.cpp Copyright (C) 2023 The Android Open Source Project
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 *
 * Modifications (Omarchy Mobile, 2026): rewritten from C++/AIDL into a standalone C
 * command-line tool. Only the devinfo path is kept (no GPT-attribute fallback,
 * no virtual A/B misc message, no anti-rollback OTP blowing, no UFS
 * bBootLunEn write). Bitfields are replaced by explicit byte/bit offsets.
 * Writes are gated behind --i-understand, touch only the slot bytes, and are
 * verified by re-reading the whole partition afterwards.
 *
 * Usage:
 *   omamobile-bootctl dump <devinfo>
 *   omamobile-bootctl mark-successful <devinfo> <slot> [--i-understand]
 *   omamobile-bootctl set-active      <devinfo> <slot> [--i-understand]
 * <devinfo> is a file or block device (on the phone: the "devinfo" partition).
 * <slot> is a, b, _a, _b, 0 or 1.
 */
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* From DevInfo.h ("definitions taken from ABL code") */
#define DEVINFO_MAGIC		0x49564544u	/* "DEVI" little-endian */
#define DEVINFO_AB_SLOT_COUNT	2
#define DEVINFO_SIZE		128		/* sizeof(devinfo_t), what the HAL reads/writes */

/*
 * devinfo_t, as in DevInfo.h:
 *   0x00 u32 magic
 *   0x04 u16 ver_major
 *   0x06 u16 ver_minor
 *   0x08 u8  unused[40]
 *   0x30 devinfo_ab_slot_data_t slots[2], 4 bytes each:
 *          +0 u8 retry_count
 *          +1 u8 unbootable:1, successful:1, active:1, fastboot_ok:1, :4
 *                (LSB-first bitfield allocation, as clang/gcc do on arm64)
 *          +2 u8 unused[2]
 *   0x38 u8  unused1[72]
 */
#define OFF_MAGIC		0x00
#define OFF_VER_MAJOR		0x04
#define OFF_VER_MINOR		0x06
#define OFF_SLOTS		0x30
#define SLOT_SIZE		4
#define SLOT_RETRY		0
#define SLOT_FLAGS		1
#define FLAG_UNBOOTABLE		0x01
#define FLAG_SUCCESSFUL		0x02
#define FLAG_ACTIVE		0x04
#define FLAG_FASTBOOT_OK	0x08
#define FLAG_KNOWN		0x0f

/* From BootControl.cpp */
#define AB_ATTR_MAX_RETRY_COUNT	3
#define DEVINFO_MIN_VERSION	0x00030003u	/* "only version 3.3+ supports A/B data" */

/*
 * The only layout version this port has been checked against (Pixel 7 Pro,
 * cheetah, stock CP2A bootloader, devinfo 3.15). Writes refuse anything else.
 */
#define VERIFIED_VER_MAJOR	3
#define VERIFIED_VER_MINOR	15

/* devinfo is 8 KiB on cheetah; refuse anything absurdly large */
#define MAX_REGION		(1024 * 1024)

static const char *argv0 = "omamobile-bootctl";

static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return p[0] | p[1] << 8; }

static int usage(void)
{
	fprintf(stderr,
		"usage: %s dump <devinfo>\n"
		"       %s mark-successful <devinfo> <slot> [--i-understand]\n"
		"       %s set-active <devinfo> <slot> [--i-understand]\n"
		"<slot>: a, b, _a, _b, 0 or 1\n",
		argv0, argv0, argv0);
	return 2;
}

/* Read the whole file/device (up to MAX_REGION) into a malloc'd buffer. */
static uint8_t *read_region(const char *path, size_t *len)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "%s: open %s: %s\n", argv0, path, strerror(errno));
		return NULL;
	}
	uint8_t *buf = malloc(MAX_REGION + 1);
	size_t n = 0;
	while (buf && n <= MAX_REGION) {
		ssize_t r = pread(fd, buf + n, MAX_REGION + 1 - n, n);
		if (r < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "%s: read %s: %s\n", argv0, path, strerror(errno));
			free(buf);
			buf = NULL;
			break;
		}
		if (r == 0)
			break;
		n += r;
	}
	close(fd);
	if (!buf)
		return NULL;
	if (n > MAX_REGION) {
		fprintf(stderr, "%s: %s is larger than %d bytes; is this really devinfo?\n",
			argv0, path, MAX_REGION);
		free(buf);
		return NULL;
	}
	if (n < DEVINFO_SIZE) {
		fprintf(stderr, "%s: %s: only %zu bytes, need %d\n", argv0, path, n, DEVINFO_SIZE);
		free(buf);
		return NULL;
	}
	*len = n;
	return buf;
}

static int check_header(const uint8_t *d, int for_write)
{
	uint32_t magic = rd32(d + OFF_MAGIC);
	uint16_t maj = rd16(d + OFF_VER_MAJOR), min = rd16(d + OFF_VER_MINOR);
	if (magic != DEVINFO_MAGIC) {
		fprintf(stderr, "%s: bad magic 0x%08x (want 0x%08x \"DEVI\")\n", argv0, magic, DEVINFO_MAGIC);
		return -1;
	}
	if (((uint32_t)maj << 16 | min) < DEVINFO_MIN_VERSION) {
		fprintf(stderr, "%s: devinfo version %u.%u has no A/B data (need 3.3+)\n", argv0, maj, min);
		return -1;
	}
	if (for_write && (maj != VERIFIED_VER_MAJOR || min != VERIFIED_VER_MINOR)) {
		fprintf(stderr, "%s: devinfo version %u.%u is not the verified %u.%u layout; refusing to write\n",
			argv0, maj, min, VERIFIED_VER_MAJOR, VERIFIED_VER_MINOR);
		return -1;
	}
	return 0;
}

static int parse_slot(const char *s)
{
	if (!strcmp(s, "a") || !strcmp(s, "_a") || !strcmp(s, "0"))
		return 0;
	if (!strcmp(s, "b") || !strcmp(s, "_b") || !strcmp(s, "1"))
		return 1;
	return -1;
}

static void print_slot(const uint8_t *d, int i)
{
	const uint8_t *s = d + OFF_SLOTS + i * SLOT_SIZE;
	uint8_t f = s[SLOT_FLAGS];
	printf("slot %c (bytes 0x%02x-0x%02x: %02x %02x %02x %02x)\n", 'a' + i,
	       OFF_SLOTS + i * SLOT_SIZE, OFF_SLOTS + i * SLOT_SIZE + 3, s[0], s[1], s[2], s[3]);
	printf("  active:      %s\n", f & FLAG_ACTIVE ? "yes" : "no");
	printf("  successful:  %s\n", f & FLAG_SUCCESSFUL ? "yes" : "no");
	printf("  unbootable:  %s\n", f & FLAG_UNBOOTABLE ? "yes" : "no");
	printf("  fastboot-ok: %s\n", f & FLAG_FASTBOOT_OK ? "yes" : "no");
	printf("  retry-count: %u\n", s[SLOT_RETRY]);
	if (f & ~FLAG_KNOWN || s[2] || s[3])
		printf("  reserved:    flags-high=0x%x unused=%02x %02x\n", f >> 4, s[2], s[3]);
}

static void hexdump(const uint8_t *d, size_t n)
{
	for (size_t i = 0; i < n; i += 16) {
		printf("  %04zx:", i);
		for (size_t j = i; j < i + 16 && j < n; j++)
			printf(" %02x", d[j]);
		printf("\n");
	}
}

static int cmd_dump(const char *path)
{
	size_t len;
	uint8_t *d = read_region(path, &len);
	if (!d)
		return 1;
	if (check_header(d, 0)) {
		free(d);
		return 1;
	}
	printf("devinfo: %s (%zu bytes)\n", path, len);
	printf("magic:   0x%08x \"DEVI\"\n", rd32(d + OFF_MAGIC));
	printf("version: %u.%u%s\n", rd16(d + OFF_VER_MAJOR), rd16(d + OFF_VER_MINOR),
	       rd16(d + OFF_VER_MAJOR) == VERIFIED_VER_MAJOR && rd16(d + OFF_VER_MINOR) == VERIFIED_VER_MINOR
	       ? " (verified layout)" : " (NOT the verified layout: read-only)");
	for (int i = 0; i < DEVINFO_AB_SLOT_COUNT; i++)
		print_slot(d, i);
	printf("active slot (HAL rule: slot b if its active bit is set, else a): %c\n",
	       d[OFF_SLOTS + SLOT_SIZE + SLOT_FLAGS] & FLAG_ACTIVE ? 'b' : 'a');
	/*
	 * Everything else in the 128-byte header is "unused" in Google's
	 * definition but is not zero: ABL keeps its own state there (likely
	 * including lock/unlock state). We print it raw and never modify it.
	 */
	printf("opaque ABL-owned header bytes (never modified), 0x00-0x7f:\n");
	hexdump(d, DEVINFO_SIZE);
	printf("bytes 0x80-0x%zx: not decoded (factory/ABL records), never written\n", len - 1);
	free(d);
	return 0;
}

/* Apply the HAL's update rules to a copy of the 128-byte header. */
static void apply_mark_successful(uint8_t *h, int slot)
{
	/* markBootSuccessful(): devinfo.ab_data.slots[slot].successful = 1 */
	h[OFF_SLOTS + slot * SLOT_SIZE + SLOT_FLAGS] |= FLAG_SUCCESSFUL;
}

static void apply_set_active(uint8_t *h, int slot)
{
	/* setActiveBootSlot(): inactive.active = 0; DevInfoInitSlot(active) */
	uint8_t *act = h + OFF_SLOTS + slot * SLOT_SIZE;
	uint8_t *ina = h + OFF_SLOTS + !slot * SLOT_SIZE;
	ina[SLOT_FLAGS] &= ~FLAG_ACTIVE;
	act[SLOT_RETRY] = AB_ATTR_MAX_RETRY_COUNT;
	act[SLOT_FLAGS] &= ~(FLAG_UNBOOTABLE | FLAG_SUCCESSFUL | FLAG_FASTBOOT_OK);
	act[SLOT_FLAGS] |= FLAG_ACTIVE;
	/* reserved flag bits and unused[2] are left as they were, as with the bitfields */
}

static int cmd_write(const char *path, int slot, int set_active, int confirmed)
{
	size_t len;
	uint8_t *orig = read_region(path, &len);
	if (!orig)
		return 1;
	if (check_header(orig, 1)) {
		free(orig);
		return 1;
	}

	uint8_t want[DEVINFO_SIZE];
	memcpy(want, orig, DEVINFO_SIZE);
	if (set_active)
		apply_set_active(want, slot);
	else
		apply_mark_successful(want, slot);

	printf("before:\n");
	for (int i = 0; i < DEVINFO_AB_SLOT_COUNT; i++)
		print_slot(orig, i);

	if (!set_active && orig[OFF_SLOTS + slot * SLOT_SIZE + SLOT_FLAGS] & FLAG_UNBOOTABLE)
		printf("warning: slot %c is marked unbootable; marking it successful does not clear that\n",
		       'a' + slot);

	/* Every changed byte must lie inside the slot array, 0x30-0x37. */
	int changes = 0;
	for (int i = 0; i < DEVINFO_SIZE; i++) {
		if (want[i] == orig[i])
			continue;
		if (i < OFF_SLOTS || i >= OFF_SLOTS + DEVINFO_AB_SLOT_COUNT * SLOT_SIZE) {
			fprintf(stderr, "%s: internal error: would change byte 0x%02x outside the slot data\n",
				argv0, i);
			free(orig);
			return 1;
		}
		if (!changes++)
			printf("bytes to change (offset: old -> new):\n");
		printf("  0x%02x: %02x -> %02x\n", i, orig[i], want[i]);
	}
	if (!changes) {
		printf("nothing to change; not writing\n");
		free(orig);
		return 0;
	}
	if (set_active)
		printf("note: Google's HAL also writes the UFS bBootLunEn attribute (boot LU %c);"
		       " this tool does not\n", slot ? 'B' : 'A');
	if (!confirmed) {
		printf("dry run: pass --i-understand to write these %d byte(s)\n", changes);
		free(orig);
		return 1;
	}

	/* Re-read right before writing and make sure nothing moved underneath us. */
	size_t len2;
	uint8_t *again = read_region(path, &len2);
	if (!again || len2 != len || memcmp(again, orig, len)) {
		fprintf(stderr, "%s: %s changed since it was read; refusing to write\n", argv0, path);
		free(again);
		free(orig);
		return 1;
	}
	free(again);

	/* Like DevInfoSync(): write the 128-byte header at offset 0, O_DSYNC. */
	int fd = open(path, O_WRONLY | O_DSYNC);
	if (fd < 0) {
		fprintf(stderr, "%s: open %s for writing: %s\n", argv0, path, strerror(errno));
		free(orig);
		return 1;
	}
	ssize_t w = pwrite(fd, want, DEVINFO_SIZE, 0);
	if (w != DEVINFO_SIZE || fsync(fd)) {
		fprintf(stderr, "%s: write %s: %s\n", argv0, path, w < 0 ? strerror(errno) : "short write");
		close(fd);
		free(orig);
		return 1;
	}
	close(fd);

	/* Verify: the whole region must equal the original with only our bytes changed. */
	memcpy(orig, want, DEVINFO_SIZE);
	uint8_t *after = read_region(path, &len2);
	if (!after || len2 != len || memcmp(after, orig, len)) {
		fprintf(stderr, "%s: VERIFY FAILED: %s does not read back as written\n", argv0, path);
		free(after);
		free(orig);
		return 1;
	}
	printf("written and verified (%zu bytes compared)\nafter:\n", len);
	for (int i = 0; i < DEVINFO_AB_SLOT_COUNT; i++)
		print_slot(after, i);
	free(after);
	free(orig);
	return 0;
}

int main(int argc, char **argv)
{
	int confirmed = 0, n = 0;
	char *args[4];
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--i-understand"))
			confirmed = 1;
		else if (n < 4)
			args[n++] = argv[i];
		else
			return usage();
	}
	if (n == 2 && !strcmp(args[0], "dump"))
		return cmd_dump(args[1]);
	if (n == 3 && (!strcmp(args[0], "mark-successful") || !strcmp(args[0], "set-active"))) {
		int slot = parse_slot(args[2]);
		if (slot < 0)
			return usage();
		return cmd_write(args[1], slot, !strcmp(args[0], "set-active"), confirmed);
	}
	return usage();
}
