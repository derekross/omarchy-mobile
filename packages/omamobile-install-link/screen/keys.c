/* SPDX-License-Identifier: MIT */
/*
 * The two volume keys, from evdev (§2.5: a press is an act at the phone).
 * Every /dev/input/event* that reports KEY_VOLUMEUP or KEY_VOLUMEDOWN is
 * read, never grabbed (no EVIOCGRAB): logind keeps the power key on the
 * same device (the 7 Pro's gpio-keys) and the shell reads the keys later.
 * A press is a value of 1 (2 is autorepeat, 0 the release); presses closer
 * than 200 ms by the events' own times count once (a bounce).
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include "screen.h"

#define BITS(n) (((n) + 8 * sizeof(long) - 1) / (8 * sizeof(long)))
#define TEST_BIT(b, n) (((b)[(n) / (8 * sizeof(long))] >> ((n) % (8 * sizeof(long)))) & 1)

void keys_init(struct keys *k)
{
	memset(k, 0, sizeof(*k));
	k->last_press = -1;
}

static int add_fd(struct keys *k, int fd)
{
	if (k->n >= KEYS_MAX) {
		close(fd);
		return -1;
	}
	k->fd[k->n++] = fd;
	return 0;
}

int keys_add_path(struct keys *k, const char *path)
{
	int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);

	if (fd < 0)
		return -1;
	k->fixed = 1;
	return add_fd(k, fd);
}

static int has_volume(int fd)
{
	unsigned long bits[BITS(KEY_MAX + 1)];

	memset(bits, 0, sizeof(bits));
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) < 0)
		return 0;
	return TEST_BIT(bits, KEY_VOLUMEUP) || TEST_BIT(bits, KEY_VOLUMEDOWN);
}

int keys_scan(struct keys *k, const char *dir)
{
	DIR *d = opendir(dir);
	struct dirent *e;
	int found = 0;

	if (!d)
		return 0;
	while ((e = readdir(d)) && k->n < KEYS_MAX) {
		char path[PATH_MAX];
		if (strncmp(e->d_name, "event", 5) != 0)
			continue;
		snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
		int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		if (!has_volume(fd)) {
			close(fd);
			continue;
		}
		char name[64] = "";
		ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
		say("keys: %s (%s)", path, name);
		add_fd(k, fd);
		found++;
	}
	closedir(d);
	return found;
}

static void drop(struct keys *k, int i)
{
	close(k->fd[i]);
	k->fd[i] = k->fd[--k->n];
}

int keys_read(struct keys *k, int i)
{
	struct input_event ev[32];
	int presses = 0;

	for (;;) {
		ssize_t r = read(k->fd[i], ev, sizeof(ev));
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0 && errno == EAGAIN)
			return presses;
		if (r <= 0) {
			say("keys: an input device went away");
			drop(k, i);
			return presses ? presses : -1;
		}
		for (size_t j = 0; j < (size_t)r / sizeof(ev[0]); j++) {
			if (ev[j].type != EV_KEY || ev[j].value != 1)
				continue;
			if (ev[j].code != KEY_VOLUMEUP && ev[j].code != KEY_VOLUMEDOWN)
				continue;
			double t = (double)ev[j].input_event_sec + ev[j].input_event_usec / 1e6;
			if (k->last_press >= 0 && t >= k->last_press && t - k->last_press < 0.2)
				continue;
			k->last_press = t;
			presses++;
		}
		/* A short read: a part of an event is never left behind on a
		 * device; on a pipe it would be a broken writer */
		if ((size_t)r % sizeof(ev[0]))
			return presses;
	}
}

void keys_close(struct keys *k)
{
	while (k->n)
		drop(k, 0);
}
