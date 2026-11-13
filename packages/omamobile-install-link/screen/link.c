/* SPDX-License-Identifier: MIT */
/*
 * The daemon's screen socket, /run/omamobile-install-link/screen (root's,
 * 0600; omamobile-linkd sockets.rs): lines from the daemon, `key` back.
 * The daemon takes one screen at a time and closes a second at once. A
 * line longer than the buffer is no line of the daemon's: it is skipped to
 * its newline.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "screen.h"

#define LINE_MAX_LEN 64

void link_init(struct link *l)
{
	memset(l, 0, sizeof(*l));
	l->fd = -1;
}

int link_connect(struct link *l, const char *path)
{
	struct sockaddr_un a = { .sun_family = AF_UNIX };

	if (strlen(path) >= sizeof(a.sun_path))
		return -1;
	strcpy(a.sun_path, path);
	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	if (connect(fd, (struct sockaddr *)&a, sizeof(a)) < 0) {
		close(fd);
		return -1;
	}
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
	l->fd = fd;
	l->len = 0;
	l->discarding = 0;
	return 0;
}

int link_read(struct link *l, void (*fn)(void *, const char *, size_t), void *arg)
{
	char in[512];

	for (;;) {
		ssize_t r = read(l->fd, in, sizeof(in));
		if (r < 0 && errno == EINTR)
			continue;
		if (r < 0 && errno == EAGAIN)
			break;
		if (r <= 0) {
			explicit_bzero(in, sizeof(in));
			link_close(l);
			return -1;
		}
		for (ssize_t i = 0; i < r; i++) {
			char c = in[i];
			if (c == '\n') {
				if (!l->discarding)
					fn(arg, l->buf, l->len);
				l->discarding = 0;
				explicit_bzero(l->buf, l->len);
				l->len = 0;
			} else if (l->discarding) {
				continue;
			} else if (l->len >= LINE_MAX_LEN) {
				l->discarding = 1;
				explicit_bzero(l->buf, l->len);
				l->len = 0;
			} else {
				l->buf[l->len++] = c;
			}
		}
	}
	explicit_bzero(in, sizeof(in));
	return 0;
}

int link_key(struct link *l)
{
	if (l->fd < 0)
		return -1;
	return send(l->fd, "key\n", 4, MSG_NOSIGNAL | MSG_DONTWAIT) == 4 ? 0 : -1;
}

void link_close(struct link *l)
{
	if (l->fd >= 0)
		close(l->fd);
	explicit_bzero(l->buf, sizeof(l->buf));
	l->fd = -1;
	l->len = 0;
	l->discarding = 0;
}
