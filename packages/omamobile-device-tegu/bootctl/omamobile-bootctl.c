// SPDX-License-Identifier: Apache-2.0
/*
 * omamobile-bootctl (Pixel 8 Pro and Pixel 9a): mark slot B successful in
 * the bootloader's "devinfo" partition, by hand and attended (#252).
 *
 * The same file is in omamobile-device-husky and omamobile-device-tegu; the
 * only per-phone values are in bootctl/bootctl-device.h (codename, board
 * compatible, and the devinfo layout version recorded for that phone). The
 * 7 Pro's omamobile-bootctl (omamobile-device-cheetah) is a different file
 * and is not changed by this one.
 *
 * The devinfo layout comes from Google's Pixel boot-control HAL:
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
 * Modifications (Omarchy Mobile, 2026): a standalone C tool with one write,
 * markBootSuccessful() for slot B (successful = 1), nothing else. It finds
 * devinfo itself by PARTNAME, checks the storage guard and the phone, and
 * opens and closes the read-write window itself:
 *
 *   The kernel lets a partition be written only if its whole disk is
 *   writable too: bdev_read_only() is the partition's own BD_READ_ONLY flag
 *   OR the disk's (part0's) flag (include/linux/blkdev.h), and both
 *   blkdev_write_iter() and the BLKROGET ioctl and sysfs "ro" use it. So
 *   devinfo can't be written while its disk (the boot LUN, sdd) is read-only,
 *   and no ioctl makes the partition alone writable. Clearing the disk flag
 *   makes the whole-disk node writable, and through it every byte of the LUN,
 *   the other partitions (pinfo, blenv, mfg_data on husky) included, for as
 *   long as the window lasts: their own flags guard only their own nodes.
 *   The tool keeps that window to the one byte: disk rw (checked), the
 *   siblings' own flags checked (the only moment they can be read), devinfo
 *   rw, one byte written and read back, devinfo ro, disk ro, both checked.
 *   The job-control and termination signals are blocked, and a relock child
 *   sets both flags back the moment this process dies, and every 10 s from
 *   the moment the window opens for as long as it stays open (a stopped or
 *   hung process), until this process has closed the window itself.
 *
 * The source sits in bootctl/, not src/: bin/omamobile's initramfs builder
 * compiles a device package's src/omamobile-bootctl.c into the boot image,
 * and this tool belongs in the installed package only.
 *
 * Usage:
 *   omamobile-bootctl status
 *   omamobile-bootctl mark-b-successful                      (dry run)
 *   omamobile-bootctl mark-b-successful --write --expect "<8 bytes>" [--codename <name>]
 * Never run from a unit, a hook or an installer.
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/mount.h>	/* BLKROSET, BLKROGET (musl and glibc) */

#include "bootctl-device.h"

#if !defined(BOOTCTL_CODENAME) || !defined(BOOTCTL_COMPATIBLE) || \
    !defined(BOOTCTL_VER_MAJOR) || !defined(BOOTCTL_VER_MINOR)
#error "bootctl-device.h must define the codename, compatible and devinfo version"
#endif

/* From DevInfo.h ("definitions taken from ABL code") */
#define DEVINFO_MAGIC		0x49564544u	/* "DEVI" little-endian */
#define DEVINFO_HDR		128		/* sizeof(devinfo_t) */
#define OFF_MAGIC		0x00
#define OFF_VER_MAJOR		0x04
#define OFF_VER_MINOR		0x06
#define OFF_SLOTS		0x30		/* slots[2], 4 bytes each, to 0x37 */
#define SLOT_BYTES		8
#define SLOT_RETRY		0
#define SLOT_FLAGS		1
#define FLAG_UNBOOTABLE		0x01
#define FLAG_SUCCESSFUL		0x02
#define FLAG_ACTIVE		0x04
#define FLAG_FASTBOOT_OK	0x08
/* The one byte this tool writes: slot B's flags. */
#define OFF_B_FLAGS		(OFF_SLOTS + 4 + SLOT_FLAGS)

#define MAX_REGION		(1024 * 1024)
#define ALIGN			4096
#define RELOCK_TIMEOUT_MS	10000

/* The storage guard's allowlist (initramfs/init accepts no other names). */
static const char *const allowlist[] = {
	"boot_b", "init_boot_b", "vendor_boot_b", "vendor_kernel_boot_b", "dtbo_b", "userdata", NULL
};

static const char *argv0 = "omamobile-bootctl";

/*
 * Test build (-DBOOTCTL_TEST, test/bootctl only): paths are read under
 * $BOOTCTL_TEST_ROOT, block devices are files, and the read-only flags are
 * files next to them that follow the kernel's rule (a partition is read-only
 * if its own flag or its disk's flag is set). The production build has none
 * of this: fixed paths, real ioctls, O_DIRECT reads.
 */
#ifdef BOOTCTL_TEST
static const char *root = "";
static const char *fault = "";	/* comma-separated test faults */
static int relock_timeout_ms = RELOCK_TIMEOUT_MS;
#define DIRECT 0
#else
static const char *const root = "";
static const int relock_timeout_ms = RELOCK_TIMEOUT_MS;
#define DIRECT O_DIRECT
#endif

struct node {
	char name[32];		/* sdd1 */
	char path[PATH_MAX];	/* /dev/sdd1 (under root in tests) */
	char sys[PATH_MAX];	/* /sys/block/sdd/sdd1 */
	dev_t rdev;
};

struct target {
	struct node part;	/* devinfo */
	struct node disk;	/* its whole disk */
	struct node sib[64];	/* the disk's other partitions */
	int nsib;
	char main_disk[32];	/* the disk that holds userdata */
};

static void err(const char *fmt, ...)
{
	va_list ap;
	fprintf(stderr, "%s: ", argv0);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

/*
 * snprintf that never truncates silently: a cut-off path could name another
 * file, so the tool stops instead (inside the read-write window the relock
 * child then sets both flags back, as for any other exit).
 */
static void xfmt(char *out, size_t n, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int r = vsnprintf(out, n, fmt, ap);
	va_end(ap);
	if (r < 0 || (size_t)r >= n) {
		err("internal error: a path or name is too long");
		exit(1);
	}
}

static void rp(char *out, size_t n, const char *fmt, ...)
{
	char tmp[PATH_MAX];
	va_list ap;
	va_start(ap, fmt);
	int r = vsnprintf(tmp, sizeof(tmp), fmt, ap);
	va_end(ap);
	if (r < 0 || (size_t)r >= sizeof(tmp)) {
		err("internal error: a path is too long");
		exit(1);
	}
	xfmt(out, n, "%s%s", root, tmp);
}

/* Read a small text file into buf (NUL-terminated); returns length or -1. */
static ssize_t slurp(const char *path, char *buf, size_t n)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ssize_t r = read(fd, buf, n - 1);
	close(fd);
	if (r < 0)
		return -1;
	buf[r] = 0;
	return r;
}

#ifdef BOOTCTL_TEST
static int has_fault(const char *name)
{
	size_t n = strlen(name);
	for (const char *p = fault; *p; ) {
		const char *e = strchr(p, ',');
		size_t l = e ? (size_t)(e - p) : strlen(p);
		if (l == n && !strncmp(p, name, n))
			return 1;
		p += l + (e ? 1 : 0);
	}
	return 0;
}
#endif

/* ---- read-only flags ---------------------------------------------------- */

#ifdef BOOTCTL_TEST
static int own_flag(const char *path)
{
	char f[PATH_MAX + 4], b[8];
	xfmt(f, sizeof(f), "%s.ro", path);
	if (slurp(f, b, sizeof(b)) < 0)
		return -1;
	return b[0] == '1';
}

/* The kernel's bdev_read_only(): own flag OR the disk's flag. */
static int ro_get(const struct node *n, const struct node *disk)
{
	/* fault: a sibling whose node can't be opened once the window is open */
	if (has_fault("sdd3-unreadable-in-window") && disk && !strcmp(n->name, "sdd3") &&
	    own_flag(disk->path) == 0)
		return -1;
	int o = own_flag(n->path);
	if (o < 0)
		return -1;
	if (o || !disk || disk == n)
		return o;
	return own_flag(disk->path) != 0;
}

static int ro_set(const struct node *n, int v)
{
	char f[PATH_MAX + 4];
	size_t pl = strlen(n->path);
	int is_disk = pl && !isdigit((unsigned char)n->path[pl - 1]);
	/* faults: a flag that silently doesn't change, as a stuck or lying device would */
	if ((v == 1 && !is_disk && has_fault("part-relock-ignored")) ||
	    (v == 0 && is_disk && has_fault("disk-stays-ro")))
		return 0;
	xfmt(f, sizeof(f), "%s/ro.log", root);
	FILE *log = fopen(f, "a");
	if (log) {
		fprintf(log, "%s %d\n", n->name, v);
		fclose(log);
	}
	xfmt(f, sizeof(f), "%s.ro", n->path);
	FILE *fp = fopen(f, "w");
	if (!fp)
		return -1;
	fprintf(fp, "%d\n", v);
	return fclose(fp) ? -1 : 0;
}
#else
static int ro_get(const struct node *n, const struct node *disk)
{
	(void)disk;
	int fd = open(n->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	int v = 0;
	int r = ioctl(fd, BLKROGET, &v);
	close(fd);
	return r ? -1 : v != 0;
}

static int ro_set(const struct node *n, int v)
{
	int fd = open(n->path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	int r = ioctl(fd, BLKROSET, &v);
	close(fd);
	return r;
}
#endif

/* ---- finding devinfo ---------------------------------------------------- */

static int partname(const char *sys, char *out, size_t n)
{
	char f[PATH_MAX + 8], buf[4096];
	xfmt(f, sizeof(f), "%s/uevent", sys);
	if (slurp(f, buf, sizeof(buf)) < 0)
		return -1;
	for (char *l = strtok(buf, "\n"); l; l = strtok(NULL, "\n"))
		if (!strncmp(l, "PARTNAME=", 9)) {
			xfmt(out, n, "%s", l + 9);
			return 0;
		}
	out[0] = 0;
	return 0;
}

static int fill_node(struct node *nd, const char *name, const char *sys)
{
	xfmt(nd->name, sizeof(nd->name), "%s", name);
	xfmt(nd->sys, sizeof(nd->sys), "%s", sys);
	rp(nd->path, sizeof(nd->path), "/dev/%s", name);
	nd->rdev = 0;
#ifndef BOOTCTL_TEST
	char f[PATH_MAX + 8], buf[32];
	unsigned ma, mi;
	struct stat st;
	xfmt(f, sizeof(f), "%s/dev", sys);
	if (slurp(f, buf, sizeof(buf)) < 0 || sscanf(buf, "%u:%u", &ma, &mi) != 2) {
		err("%s: no device number in sysfs", name);
		return -1;
	}
	nd->rdev = makedev(ma, mi);
	if (stat(nd->path, &st) || !S_ISBLK(st.st_mode) || st.st_rdev != nd->rdev) {
		err("%s is not the block device sysfs names (%u:%u)", nd->path, ma, mi);
		return -1;
	}
#endif
	return 0;
}

static int is_part_dir(const char *sys)
{
	char f[PATH_MAX + 16];
	xfmt(f, sizeof(f), "%s/partition", sys);
	return access(f, F_OK) == 0;
}

static int find_devinfo(struct target *t)
{
	char sysblock[PATH_MAX], dsys[PATH_MAX * 2], psys[PATH_MAX * 3], pn[64];
	char devinfo_disk[32] = "";
	int found = 0, userdata = 0;
	memset(t, 0, sizeof(*t));
	rp(sysblock, sizeof(sysblock), "/sys/block");
	DIR *d = opendir(sysblock);
	if (!d) {
		err("can't list %s: %s", sysblock, strerror(errno));
		return -1;
	}
	struct dirent *e;
	while ((e = readdir(d))) {
		if (strncmp(e->d_name, "sd", 2))
			continue;
		xfmt(dsys, sizeof(dsys), "%s/%s", sysblock, e->d_name);
		DIR *dd = opendir(dsys);
		if (!dd)
			continue;
		struct dirent *p;
		while ((p = readdir(dd))) {
			if (strncmp(p->d_name, e->d_name, strlen(e->d_name)) || !p->d_name[strlen(e->d_name)])
				continue;
			xfmt(psys, sizeof(psys), "%s/%s", dsys, p->d_name);
			if (!is_part_dir(psys) || partname(psys, pn, sizeof(pn)))
				continue;
			if (!strcmp(pn, "devinfo")) {
				if (found++ == 0) {
					xfmt(devinfo_disk, sizeof(devinfo_disk), "%s", e->d_name);
					if (fill_node(&t->part, p->d_name, psys) ||
					    fill_node(&t->disk, e->d_name, dsys)) {
						closedir(dd);
						closedir(d);
						return -1;
					}
				}
			} else if (!strcmp(pn, "userdata")) {
				userdata++;
				xfmt(t->main_disk, sizeof(t->main_disk), "%s", e->d_name);
			}
		}
		closedir(dd);
	}
	closedir(d);
	if (found != 1) {
		err(found ? "%d partitions are named devinfo; refusing" : "no partition is named devinfo", found);
		return -1;
	}
	if (userdata != 1) {
		err("expected one userdata partition, found %d; is the storage layout this phone's?", userdata);
		return -1;
	}
	if (!strcmp(devinfo_disk, t->main_disk)) {
		err("devinfo is on the main LUN (%s); this tool knows only devinfo on a boot LUN", devinfo_disk);
		return -1;
	}
	/* The disk's other partitions, whose own flags are checked in the window. */
	xfmt(dsys, sizeof(dsys), "%s/%s", sysblock, t->disk.name);
	DIR *dd = opendir(dsys);
	if (!dd)
		return -1;
	while ((e = readdir(dd))) {
		if (strncmp(e->d_name, t->disk.name, strlen(t->disk.name)) || !e->d_name[strlen(t->disk.name)] ||
		    !strcmp(e->d_name, t->part.name))
			continue;
		xfmt(psys, sizeof(psys), "%s/%s", dsys, e->d_name);
		if (!is_part_dir(psys))
			continue;
		if (t->nsib == (int)(sizeof(t->sib) / sizeof(t->sib[0])) ||
		    fill_node(&t->sib[t->nsib++], e->d_name, psys)) {
			closedir(dd);
			err("can't list the partitions of %s", t->disk.name);
			return -1;
		}
	}
	closedir(dd);
	return 0;
}

/* ---- checks ------------------------------------------------------------- */

static int check_phone(void)
{
	char f[PATH_MAX], buf[512];
#ifndef BOOTCTL_TEST
	if (geteuid() != 0) {
		err("run as root");
		return -1;
	}
#endif
	rp(f, sizeof(f), "/sys/firmware/devicetree/base/compatible");
	if (slurp(f, buf, sizeof(buf)) < 0) {
		err("can't read the board's compatible string");
		return -1;
	}
	if (strcmp(buf, BOOTCTL_COMPATIBLE)) {	/* the first string, up to its NUL */
		err("this board is \"%s\", not %s (\"%s\"); this build is for %s only",
		    buf, BOOTCTL_CODENAME, BOOTCTL_COMPATIBLE, BOOTCTL_CODENAME);
		return -1;
	}
	return 0;
}

static char booted_slot(void)
{
	char f[PATH_MAX], buf[16384];
	rp(f, sizeof(f), "/proc/bootconfig");
	if (slurp(f, buf, sizeof(buf)) < 0)
		return 0;
	for (char *l = strtok(buf, "\n"); l; l = strtok(NULL, "\n")) {
		if (!strcmp(l, "androidboot.slot_suffix = \"_a\""))
			return 'a';
		if (!strcmp(l, "androidboot.slot_suffix = \"_b\""))
			return 'b';
	}
	return 0;
}

static int same_file(const struct stat *st, const struct node *n)
{
#ifdef BOOTCTL_TEST
	struct stat ns;
	return !stat(n->path, &ns) && ns.st_dev == st->st_dev && ns.st_ino == st->st_ino;
#else
	return S_ISBLK(st->st_mode) && st->st_rdev == n->rdev;
#endif
}

/* devinfo not mounted, held, or open for writing by anyone else. */
static int check_unused(const struct target *t)
{
	char f[PATH_MAX], line[4096], src[PATH_MAX];
	int bad = 0;

	rp(f, sizeof(f), "/proc/self/mountinfo");
	FILE *fp = fopen(f, "r");
	if (!fp) {
		err("can't read %s", f);
		return -1;
	}
	xfmt(src, sizeof(src), "/dev/%s", t->part.name);
	while (fgets(line, sizeof(line), fp)) {
		unsigned ma = 0, mi = 0;
		char *sep = strstr(line, " - ");
		char fstype[64] = "", source[PATH_MAX] = "";
		if (sscanf(line, "%*s %*s %u:%u", &ma, &mi) != 2 || !sep)
			continue;
		sscanf(sep + 3, "%63s %4095s", fstype, source);
		if (!strcmp(source, src) || (t->part.rdev && makedev(ma, mi) == t->part.rdev)) {
			err("devinfo (%s) is mounted; refusing", src);
			bad = 1;
		}
	}
	fclose(fp);

	/* Nothing stacked on the disk, devinfo or a sibling (dm, md, loop...). */
	const struct node *held[2 + (int)(sizeof(t->sib) / sizeof(t->sib[0]))];
	int nh = 0;
	held[nh++] = &t->disk;
	held[nh++] = &t->part;
	for (int i = 0; i < t->nsib; i++)
		held[nh++] = &t->sib[i];
	for (int i = 0; i < nh; i++) {
		xfmt(f, sizeof(f), "%s/holders", held[i]->sys);
		DIR *d = opendir(f);
		if (!d)
			continue;
		struct dirent *e;
		while ((e = readdir(d)))
			if (e->d_name[0] != '.') {
				err("%s is held by %s; refusing", held[i]->name, e->d_name);
				bad = 1;
			}
		closedir(d);
	}

	/* Any process with the disk or one of its partitions open for writing. */
	DIR *d = opendir("/proc");
	if (!d)
		return -1;
	struct dirent *pe;
	pid_t self = getpid();
	while ((pe = readdir(d))) {
		if (!isdigit((unsigned char)pe->d_name[0]) || atoi(pe->d_name) == self)
			continue;
		char fdd[PATH_MAX];
		xfmt(fdd, sizeof(fdd), "/proc/%s/fd", pe->d_name);
		DIR *fds = opendir(fdd);
		if (!fds)
			continue;
		struct dirent *fe;
		while ((fe = readdir(fds))) {
			if (fe->d_name[0] == '.')
				continue;
			char lp[PATH_MAX * 2], info[PATH_MAX * 2], buf[1024];
			struct stat st;
			xfmt(lp, sizeof(lp), "%s/%s", fdd, fe->d_name);
			if (stat(lp, &st))
				continue;
			int hit = same_file(&st, &t->part) || same_file(&st, &t->disk);
			for (int i = 0; !hit && i < t->nsib; i++)
				hit = same_file(&st, &t->sib[i]);
			if (!hit)
				continue;
			xfmt(info, sizeof(info), "/proc/%s/fdinfo/%s", pe->d_name, fe->d_name);
			char *fl;
			unsigned long flags = 0;
			if (slurp(info, buf, sizeof(buf)) >= 0 && (fl = strstr(buf, "flags:")))
				flags = strtoul(fl + 6, NULL, 8);
			if ((flags & O_ACCMODE) != O_RDONLY) {
				err("process %s has %s or one of its partitions open for writing; refusing",
				    pe->d_name, t->disk.name);
				bad = 1;
			}
		}
		closedir(fds);
	}
	closedir(d);
	return bad ? -1 : 0;
}

static int in_allowlist(const char *name)
{
	for (int i = 0; allowlist[i]; i++)
		if (!strcmp(name, allowlist[i]))
			return 1;
	return 0;
}

/*
 * The storage guard as the initramfs leaves it: the main LUN's whole-disk
 * node gone (or mode 0000), every other disk and every partition outside the
 * allowlist read-only, devinfo and its disk among them.
 */
static int check_guard(const struct target *t)
{
	char f[PATH_MAX], dsys[PATH_MAX * 2], psys[PATH_MAX * 3], pn[64];
	struct stat st;
	int bad = 0;

	rp(f, sizeof(f), "/dev/%s", t->main_disk);
	if (!stat(f, &st) && (st.st_mode & 07777)) {
		err("the main LUN's whole-disk node %s is usable (mode %o); the storage guard is not holding",
		    f, st.st_mode & 07777);
		bad = 1;
	}
	rp(f, sizeof(f), "/sys/block");
	DIR *d = opendir(f);
	if (!d)
		return -1;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (strncmp(e->d_name, "sd", 2))
			continue;
		struct node disk;
		xfmt(dsys, sizeof(dsys), "%s/%s", f, e->d_name);
		xfmt(disk.name, sizeof(disk.name), "%s", e->d_name);
		rp(disk.path, sizeof(disk.path), "/dev/%s", e->d_name);
		int main_disk = !strcmp(e->d_name, t->main_disk);
		if (!main_disk && ro_get(&disk, NULL) != 1) {
			err("%s is not read-only; the storage guard is not holding", e->d_name);
			bad = 1;
		}
		DIR *dd = opendir(dsys);
		if (!dd)
			continue;
		struct dirent *p;
		while ((p = readdir(dd))) {
			if (strncmp(p->d_name, e->d_name, strlen(e->d_name)) || !p->d_name[strlen(e->d_name)])
				continue;
			xfmt(psys, sizeof(psys), "%s/%s", dsys, p->d_name);
			if (!is_part_dir(psys) || partname(psys, pn, sizeof(pn)))
				continue;
			if (main_disk && in_allowlist(pn))
				continue;
			struct node part;
			xfmt(part.name, sizeof(part.name), "%s", p->d_name);
			rp(part.path, sizeof(part.path), "/dev/%s", p->d_name);
			if (ro_get(&part, &disk) != 1) {
				err("%s (%s) is not read-only; the storage guard is not holding", p->d_name, pn);
				bad = 1;
			}
		}
		closedir(dd);
	}
	closedir(d);
	return bad ? -1 : 0;
}

/* ---- devinfo contents --------------------------------------------------- */

static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return p[0] | p[1] << 8; }

/* The whole partition, read past the page cache (O_DIRECT) on the phone. */
static uint8_t *read_image(const struct node *n, size_t *len)
{
	uint8_t *buf = NULL;
	int fd = open(n->path, O_RDONLY | O_CLOEXEC | DIRECT);
	if (fd < 0) {
		err("open %s: %s", n->path, strerror(errno));
		return NULL;
	}
	if (posix_memalign((void **)&buf, ALIGN, MAX_REGION + ALIGN)) {
		close(fd);
		return NULL;
	}
	size_t got = 0;
	for (;;) {
		ssize_t r = pread(fd, buf + got, MAX_REGION + ALIGN - got, got);
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0) {
			err("read %s: %s", n->path, strerror(errno));
			goto fail;
		}
		if (r == 0)
			break;
		got += r;
		if (got > MAX_REGION) {
			err("%s is larger than %d bytes; is this really devinfo?", n->path, MAX_REGION);
			goto fail;
		}
	}
	close(fd);
	if (got < DEVINFO_HDR) {
		err("%s: only %zu bytes", n->path, got);
		free(buf);
		return NULL;
	}
	*len = got;
	return buf;
fail:
	close(fd);
	free(buf);
	return NULL;
}

static int check_layout(const uint8_t *d)
{
	uint32_t magic = rd32(d + OFF_MAGIC);
	unsigned maj = rd16(d + OFF_VER_MAJOR), min = rd16(d + OFF_VER_MINOR);
	if (magic != DEVINFO_MAGIC) {
		err("bad magic 0x%08x (want 0x%08x \"DEVI\"); refusing", magic, DEVINFO_MAGIC);
		return -1;
	}
	if (maj != BOOTCTL_VER_MAJOR || min != BOOTCTL_VER_MINOR) {
		err("devinfo version %u.%u is not the %u.%u recorded for %s; refusing",
		    maj, min, BOOTCTL_VER_MAJOR, BOOTCTL_VER_MINOR, BOOTCTL_CODENAME);
		return -1;
	}
	return 0;
}

static void print_bytes(const char *label, const uint8_t *d)
{
	printf("%s 0x30-0x37:", label);
	for (int i = 0; i < SLOT_BYTES; i++)
		printf(" %02x", d[OFF_SLOTS + i]);
	printf("\n");
}

static void print_slots(const uint8_t *d)
{
	for (int i = 0; i < 2; i++) {
		const uint8_t *s = d + OFF_SLOTS + 4 * i;
		uint8_t f = s[SLOT_FLAGS];
		printf("slot %c: retry-count %u, active %s, successful %s, unbootable %s, fastboot-ok %s\n",
		       'a' + i, s[SLOT_RETRY], f & FLAG_ACTIVE ? "yes" : "no",
		       f & FLAG_SUCCESSFUL ? "yes" : "no", f & FLAG_UNBOOTABLE ? "yes" : "no",
		       f & FLAG_FASTBOOT_OK ? "yes" : "no");
	}
}

/* ---- the read-write window ---------------------------------------------- */

static int relock(const struct target *t)
{
	int ok = 1;
	/* devinfo first: while its disk is still writable its own flag reads back */
	if (ro_set(&t->part, 1) || ro_get(&t->part, &t->disk) != 1)
		ok = 0;
	if (ro_set(&t->disk, 1) || ro_get(&t->disk, NULL) != 1)
		ok = 0;
	return ok ? 0 : -1;
}

/*
 * The relock child. It holds the read end of a pipe whose write end only the
 * parent has. Before the window opens it waits without a timeout (nothing is
 * writable yet). The parent writes 'O' just before it clears the first flag;
 * from then on the child sets devinfo and its disk read-only every
 * RELOCK_TIMEOUT_MS for as long as the pipe stays open (a stopped or hung
 * parent: its later steps then fail closed), and once more when the pipe
 * closes, whether the parent finished, crashed or was killed. It ignores the
 * terminal's signals (blocked before the fork), so ^C on the process group
 * can't take it with the parent.
 */
static int child_relock(const struct target *t)
{
#ifdef BOOTCTL_TEST
	if (has_fault("no-child-relock"))	/* the parent must relock alone */
		return 0;
#endif
	return relock(t);
}

static void relocker(const struct target *t, int rfd)
{
	int armed = 0, ok = 1;
	for (;;) {
		struct pollfd pf = { .fd = rfd, .events = POLLIN };
		int r = poll(&pf, 1, armed ? relock_timeout_ms : -1);
		if (r < 0 && errno == EINTR)
			continue;
		if (r == 0) {			/* window open too long: close it, re-arm */
			if (child_relock(t))
				ok = 0;
			continue;
		}
		char c;
		ssize_t n = read(rfd, &c, 1);
		if (n < 0 && errno == EINTR)
			continue;
		if (n == 1 && c == 'O') {
			armed = 1;
			continue;
		}
		break;				/* EOF: the parent is done or gone */
	}
	if (child_relock(t))
		ok = 0;
#ifdef BOOTCTL_TEST
	if (has_fault("child-fails"))
		ok = 0;
#endif
	_exit(ok ? 0 : 1);
}

static pid_t start_relocker(const struct target *t, int *wfd)
{
	int p[2];
#ifdef BOOTCTL_TEST
	if (has_fault("fork-fails"))
		return -1;
#endif
	if (pipe2(p, O_CLOEXEC))
		return -1;
	pid_t pid = fork();
	if (pid < 0) {
		close(p[0]);
		close(p[1]);
		return -1;
	}
	if (pid == 0) {
		close(p[1]);
		relocker(t, p[0]);
	}
	close(p[0]);
	*wfd = p[1];
	return pid;
}

/* The child must be alive before every step that opens anything further. */
static int child_alive(pid_t child, int *reaped, int *st)
{
	if (*reaped)
		return 0;
	pid_t r = waitpid(child, st, WNOHANG);
	if (r == child) {
		*reaped = 1;
		return 0;
	}
	return r == 0;
}

static int write_at(const struct target *t, const uint8_t *buf, size_t len, off_t off)
{
#ifdef BOOTCTL_TEST
	/* the kernel refuses a write to a read-only partition (blkdev_write_iter) */
	if (ro_get(&t->part, &t->disk) != 0) {
		errno = EPERM;
		return -1;
	}
	if (has_fault("write-fails")) {
		errno = EIO;
		return -1;
	}
	if (has_fault("restore-noop") && off == 0 && len > 2)
		return 0;			/* the restore "succeeds" without landing */
#endif
	int fd = open(t->part.path, O_WRONLY | O_DSYNC | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ssize_t w = pwrite(fd, buf, len, off);
	int e = errno;
	if (w == (ssize_t)len && fdatasync(fd) == 0) {
		close(fd);
		return 0;
	}
	close(fd);
	errno = w < 0 ? e : EIO;
	return -1;
}

#ifdef BOOTCTL_TEST
static void test_fault(const char *where)
{
	if (has_fault(where))
		raise(SIGKILL);
	if (!strcmp(where, "kill-before-write") && has_fault("hang-in-window"))
		sleep(60);
}

/* Someone else changes devinfo inside the window (test only). */
static void test_change_under(const struct target *t)
{
	if (!has_fault("change-under"))
		return;
	int fd = open(t->part.path, O_WRONLY);
	uint8_t x = 0x5a;
	if (fd >= 0) {
		if (pwrite(fd, &x, 1, 0x100) != 1)
			err("test: change-under failed");
		close(fd);
	}
}
#else
#define test_fault(x) ((void)0)
#define test_change_under(t) ((void)0)
#endif

/*
 * Returns 0 written and verified, 3 failed with devinfo as it was before,
 * 4 failed and devinfo may differ, 5 the read-only flags could not be
 * restored (the loudest failure: the guard has a hole until a reboot).
 */
static int window(const struct target *t, const uint8_t *orig, size_t len, uint8_t newval)
{
	int rc = 3, wfd = -1, reaped = 0, st = 0;
	uint8_t *after = NULL, *want = NULL, *again = NULL, byte = newval;
	size_t alen;
	sigset_t block, old;
#ifdef BOOTCTL_TEST
	uint8_t bad[2] = { (uint8_t)(orig[OFF_B_FLAGS - 1] ^ 0x01), newval };
#endif

	sigemptyset(&block);
	sigaddset(&block, SIGINT);
	sigaddset(&block, SIGTERM);
	sigaddset(&block, SIGHUP);
	sigaddset(&block, SIGQUIT);
	sigaddset(&block, SIGTSTP);
	sigaddset(&block, SIGPIPE);
	sigprocmask(SIG_BLOCK, &block, &old);

	pid_t child = start_relocker(t, &wfd);
	if (child < 0) {
		err("can't start the relock child; nothing written");
		sigprocmask(SIG_SETMASK, &old, NULL);
		return 3;
	}
#ifdef BOOTCTL_TEST
	if (has_fault("stop-before-open"))
		raise(SIGSTOP);
#endif
	/* The child's timer runs from here, as long as the window stays open. */
	if (write(wfd, "O", 1) != 1 || !child_alive(child, &reaped, &st)) {
		err("the relock child is not running; nothing written");
		goto close_window;
	}
#ifdef BOOTCTL_TEST
	if (has_fault("stop-after-open"))
		raise(SIGSTOP);
#endif

	/* 1. The disk: the kernel won't write a partition of a read-only disk. */
	if (ro_set(&t->disk, 0) || ro_get(&t->disk, NULL) != 0) {
		err("%s did not become writable; nothing written", t->disk.name);
		goto close_window;
	}
	/* 2. With the disk flag clear, each partition reads its own flag: all set. */
	for (int i = 0; i < t->nsib; i++)
		if (ro_get(&t->sib[i], &t->disk) != 1) {
			err("%s's own read-only flag is clear or unreadable: clearing %s's would expose it; refusing",
			    t->sib[i].name, t->disk.name);
			goto close_window;
		}
	if (ro_get(&t->part, &t->disk) != 1) {
		err("devinfo's own read-only flag was already clear; the guard did not set it; refusing");
		goto close_window;
	}
	/* 3. devinfo itself. */
	if (!child_alive(child, &reaped, &st)) {
		err("the relock child is gone; nothing written");
		goto close_window;
	}
	if (ro_set(&t->part, 0) || ro_get(&t->part, &t->disk) != 0) {
		err("can't make devinfo writable: %s", strerror(errno));
		goto close_window;
	}
	test_change_under(t);
	/* 4. Nothing moved since the checks. */
	again = read_image(&t->part, &alen);
	if (!again || alen != len || memcmp(again, orig, len)) {
		err("devinfo changed since it was checked; nothing written");
		free(again);
		goto close_window;
	}
	free(again);
	test_fault("kill-before-write");

	/* 5. The one byte (the kernel writes the 4 KiB block that holds it). */
	want = malloc(len);
	if (!want)
		goto close_window;
	memcpy(want, orig, len);
	want[OFF_B_FLAGS] = newval;
	if (!child_alive(child, &reaped, &st)) {
		err("the relock child is gone; nothing written");
		goto close_window;
	}
#ifdef BOOTCTL_TEST
	if (has_fault("corrupt-write")) {	/* a stray change next to ours */
		if (write_at(t, bad, 2, OFF_B_FLAGS - 1))
			goto write_failed;
	} else
#endif
	if (write_at(t, &byte, 1, OFF_B_FLAGS)) {
		goto write_failed;
	}
	test_fault("kill-after-write");

	/* 6. Read back past the cache: everything as before but that byte. */
	after = read_image(&t->part, &alen);
	if (after && alen == len && !memcmp(after, want, len)) {
		rc = 0;
		goto close_window;
	}
	err("VERIFY FAILED: devinfo does not read back as written; restoring the original");
	free(after);
	after = NULL;
	if (write_at(t, orig, len, 0)) {
		err("RESTORE FAILED: %s; devinfo may differ from the backup", strerror(errno));
		rc = 4;
		goto close_window;
	}
	after = read_image(&t->part, &alen);
	if (after && alen == len && !memcmp(after, orig, len)) {
		err("restored: devinfo reads back as it was before");
		rc = 3;
	} else {
		err("RESTORE FAILED: devinfo does not read back as before; restore it from the backup");
		rc = 4;
	}
	goto close_window;

write_failed:
	err("write failed: %s", strerror(errno));
	after = read_image(&t->part, &alen);
	rc = (after && alen == len && !memcmp(after, orig, len)) ? 3 : 4;
	if (rc == 4)
		err("devinfo no longer reads as before; restore it from the backup");

close_window:
	/* 7. Read-only again, devinfo then the disk, each read back; then the child. */
	if (relock(t)) {
		err("FAILED to set devinfo or %s read-only again; reboot to restore the guard", t->disk.name);
		rc = 5;
	}
	close(wfd);
	if (!reaped)
		while (waitpid(child, &st, 0) < 0 && errno == EINTR)
			;
	if (!WIFEXITED(st) || WEXITSTATUS(st)) {
		err("the relock child failed; reboot to restore the guard");
		rc = 5;
	}
	sigprocmask(SIG_SETMASK, &old, NULL);
	free(after);
	free(want);
	return rc;
}

/* ---- commands ----------------------------------------------------------- */

static int parse_expect(const char *s, uint8_t out[SLOT_BYTES])
{
	int n = 0, half = -1;
	for (; *s; s++) {
		if (*s == ' ' || *s == ':' || *s == '\t')
			continue;
		if (!isxdigit((unsigned char)*s) || n == SLOT_BYTES)
			return -1;
		int v = isdigit((unsigned char)*s) ? *s - '0' : (tolower((unsigned char)*s) - 'a' + 10);
		if (half < 0) {
			half = v;
		} else {
			out[n++] = half << 4 | v;
			half = -1;
		}
	}
	return n == SLOT_BYTES && half < 0 ? 0 : -1;
}

static int read_codename(char *out, size_t n)
{
	FILE *tty = fopen("/dev/tty", "r+");
	if (!tty)
		return -1;
	fprintf(tty, "This writes devinfo on this phone. Type its codename (%s) to go on: ", BOOTCTL_CODENAME);
	fflush(tty);
	if (!fgets(out, n, tty)) {
		fclose(tty);
		return -1;
	}
	fclose(tty);
	out[strcspn(out, "\r\n")] = 0;
	return 0;
}

static int prepare(struct target *t, uint8_t **img, size_t *len)
{
	if (check_phone() || find_devinfo(t))
		return -1;
	printf("omamobile-bootctl for %s: devinfo is %s on %s\n", BOOTCTL_CODENAME, t->part.name, t->disk.name);
	*img = read_image(&t->part, len);
	if (!*img || check_layout(*img))
		return -1;
	printf("devinfo version %u.%u (the layout recorded for %s)\n",
	       BOOTCTL_VER_MAJOR, BOOTCTL_VER_MINOR, BOOTCTL_CODENAME);
	return 0;
}

static int cmd_status(void)
{
	struct target t;
	uint8_t *img = NULL;
	size_t len;
	if (prepare(&t, &img, &len)) {
		free(img);
		return 1;
	}
	char s = booted_slot();
	printf("booted from slot %c\n", s ? s : '?');
	print_bytes("bytes", img);
	print_slots(img);
	int g = check_guard(&t);
	printf("storage guard: %s\n", g ? "NOT as expected (see above)" : "holding");
	free(img);
	return 0;
}

static int cmd_mark(int do_write, const char *expect, const char *codename)
{
	struct target t;
	uint8_t *img = NULL, *after = NULL, exp[SLOT_BYTES], fb, nv;
	size_t len, alen;
	int rc = 1;
	char typed[64] = "";

	if (do_write && (!expect || parse_expect(expect, exp))) {
		err("--write needs --expect with the eight bytes the dry run printed");
		return 2;
	}
	if (prepare(&t, &img, &len))
		goto out;
	if (booted_slot() != 'b') {
		err("this boot is not from slot b; mark slot b only from a boot of slot b");
		goto out;
	}
	if (check_guard(&t) || check_unused(&t))
		goto out;

	fb = img[OFF_B_FLAGS];
	print_bytes("before", img);
	print_slots(img);
	if (!(fb & FLAG_ACTIVE)) {
		err("slot b is not the active slot; refusing");
		goto out;
	}
	if (fb & FLAG_UNBOOTABLE) {
		err("slot b is marked unbootable; refusing");
		goto out;
	}
	if (fb & FLAG_SUCCESSFUL) {
		printf("slot b is already marked successful; nothing to write\n");
		rc = 0;
		goto out;
	}
	nv = fb | FLAG_SUCCESSFUL;
	printf("planned: byte 0x%02x %02x -> %02x (slot b successful), nothing else\n", OFF_B_FLAGS, fb, nv);

	if (!do_write) {
		printf("dry run: nothing written. To write, after the runbook's backup:\n"
		       "  omamobile-bootctl mark-b-successful --write --codename %s --expect \"", BOOTCTL_CODENAME);
		for (int i = 0; i < SLOT_BYTES; i++)
			printf("%s%02x", i ? " " : "", img[OFF_SLOTS + i]);
		printf("\"\n");
		rc = 0;
		goto out;
	}
	if (memcmp(exp, img + OFF_SLOTS, SLOT_BYTES)) {
		err("the slot bytes are not the ones given with --expect; run the dry run again");
		goto out;
	}
	if (codename)
		xfmt(typed, sizeof(typed), "%s", codename);
	else if (read_codename(typed, sizeof(typed)))
		typed[0] = 0;
	if (strcmp(typed, BOOTCTL_CODENAME)) {
		err("codename \"%s\" is not %s; nothing written", typed, BOOTCTL_CODENAME);
		goto out;
	}
#ifdef BOOTCTL_TEST
	if (has_fault("hold-after-codename")) {	/* stands in for a slow prompt */
		char f[PATH_MAX];
		rp(f, sizeof(f), "/at-prompt");
		close(open(f, O_CREAT | O_WRONLY, 0644));
		rp(f, sizeof(f), "/go");
		for (int i = 0; i < 200 && access(f, F_OK); i++)
			usleep(50000);
	}
#endif
	/* The checks again, right before the window: the prompt can take minutes. */
	if (check_guard(&t) || check_unused(&t)) {
		err("the storage guard or a user of the LUN changed since the checks; nothing written");
		goto out;
	}

	rc = window(&t, img, len, nv);
	after = read_image(&t.part, &alen);
	if (after)
		print_bytes("after ", after);
	if (rc == 0) {
		printf("slot b marked successful: written, read back, devinfo and %s read-only again\n", t.disk.name);
	}
out:
	free(after);
	free(img);
	return rc;
}

static int usage(void)
{
	fprintf(stderr,
		"usage: %s status\n"
		"       %s mark-b-successful                (dry run, writes nothing)\n"
		"       %s mark-b-successful --write --expect \"<the dry run's 8 bytes>\" [--codename %s]\n"
		"Build for %s, devinfo %u.%u. Attended use only, from the device plan's runbook.\n",
		argv0, argv0, argv0, BOOTCTL_CODENAME, BOOTCTL_CODENAME, BOOTCTL_VER_MAJOR, BOOTCTL_VER_MINOR);
	return 2;
}

int main(int argc, char **argv)
{
	int do_write = 0;
	const char *expect = NULL, *codename = NULL, *cmd = NULL;

#ifdef BOOTCTL_TEST
	if (getenv("BOOTCTL_TEST_ROOT"))
		root = getenv("BOOTCTL_TEST_ROOT");
	if (getenv("BOOTCTL_TEST_FAULT"))
		fault = getenv("BOOTCTL_TEST_FAULT");
	if (getenv("BOOTCTL_TEST_RELOCK_MS"))
		relock_timeout_ms = atoi(getenv("BOOTCTL_TEST_RELOCK_MS"));
#endif
	setvbuf(stdout, NULL, _IOLBF, 0);
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--write"))
			do_write = 1;
		else if (!strcmp(argv[i], "--expect") && i + 1 < argc)
			expect = argv[++i];
		else if (!strcmp(argv[i], "--codename") && i + 1 < argc)
			codename = argv[++i];
		else if (!cmd && argv[i][0] != '-')
			cmd = argv[i];
		else
			return usage();
	}
	if (!cmd)
		return usage();
	if (!strcmp(cmd, "status") && !do_write && !expect && !codename)
		return cmd_status();
	if (!strcmp(cmd, "mark-b-successful"))
		return cmd_mark(do_write, expect, codename);
	return usage();
}
