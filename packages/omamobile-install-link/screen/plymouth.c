/* SPDX-License-Identifier: MIT */
/*
 * The third output: Plymouth's message line, while Plymouth still holds
 * the screen. Spoken to plymouthd directly on its socket rather than by
 * running `plymouth display-message --text=...`, which would put the code
 * on a command line (readable in /proc by every user, §9). The requests
 * are Plymouth's own (ply-boot-protocol.h): a command letter, then for one
 * with an argument \002, the argument's length with its NUL, the argument
 * and a NUL; the answer is one byte, ACK (\006) or NAK (\025). The socket
 * is abstract, "\0/org/freedesktop/plymouthd", unpadded.
 *
 * Omarchy's Plymouth theme draws messages (omarchy.script,
 * Plymouth.SetDisplayMessageFunction): small, top left.
 *
 * OMAMOBILE_SCREEN_PLYMOUTH_SOCKET names another abstract socket (tests).
 */
#define _GNU_SOURCE
#include <poll.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include "screen.h"

static int request(char cmd, const char *arg)
{
	const char *name = getenv("OMAMOBILE_SCREEN_PLYMOUTH_SOCKET");
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	char msg[300];
	size_t n = 0;
	int fd, ok = -1;

	if (!name || !*name)
		name = "/org/freedesktop/plymouthd";
	size_t nl = strlen(name);
	if (nl + 1 > sizeof(a.sun_path))
		return -1;
	memcpy(a.sun_path + 1, name, nl);
	msg[n++] = cmd;
	if (arg) {
		size_t al = strlen(arg);
		if (al > 250)
			al = 250;
		msg[n++] = '\002';
		msg[n++] = (char)(al + 1);
		memcpy(msg + n, arg, al);
		n += al;
	}
	msg[n++] = 0;
	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	if (connect(fd, (struct sockaddr *)&a, (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + nl)) == 0 &&
	    send(fd, msg, n, MSG_NOSIGNAL) == (ssize_t)n) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		char reply;
		if (poll(&p, 1, 1000) > 0 && recv(fd, &reply, 1, 0) == 1 && reply == '\006')
			ok = 0;
	}
	explicit_bzero(msg, sizeof(msg));
	close(fd);
	return ok;
}

int plymouth_ping(void)
{
	return request('P', NULL);
}

int plymouth_show(struct output *o, const char *text)
{
	if (!strcmp(o->shown, text))
		return 0;
	if (o->shown[0])
		request('m', o->shown);
	explicit_bzero(o->shown, sizeof(o->shown));
	if (!*text)
		return 0;
	if (request('M', text) < 0)
		return -1;
	strncpy(o->shown, text, sizeof(o->shown) - 1);
	return 0;
}

void plymouth_close(struct output *o)
{
	plymouth_show(o, "");
	o->kind = OUT_NONE;
}
