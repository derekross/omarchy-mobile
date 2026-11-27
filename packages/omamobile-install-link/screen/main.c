/* SPDX-License-Identifier: MIT */
/*
 * omamobile-install-screen: the install link's first-start screen
 * (docs/INSTALL-LINK-PLAN.md §2.5, §3.3).
 *
 *   omamobile-install-screen [--output auto|drm|fb|plymouth|none]
 *   omamobile-install-screen --demo [--output ...]      (runbook R5)
 *
 * It connects to the daemon's screen socket and shows what each line says
 * (model.c), the pairing code among it, and sends `key` when a volume key
 * is pressed. The output is the first of these that works (--output auto):
 *
 *   1. a DRM device (drm.c): a dumb buffer and a mode set, as Plymouth does
 *   2. /dev/fb0 (fb.c), where the kernel still offers one
 *   3. Plymouth's message line (plymouth.c), while Plymouth runs
 *   4. nothing: the daemon works on, and the installer tells the owner
 *
 * A DRM device that another program holds (Plymouth before it quits) puts
 * Plymouth before fb0, whose writes would not show. Until the output is a
 * DRM device it tries again every 5 s. It ends on the daemon's `off`, or
 * on SIGTERM (its unit is stopped before the login screen comes): it
 * draws the background alone, so no code is left on the panel, gives the
 * device back and puts the VT back as it was.
 *
 * --demo reads the daemon's lines from standard input instead of the
 * socket and writes `key` to standard output for each press: R5 runs it
 * on a phone whose daemon offers nothing, with a made-up code.
 *
 * It never writes the code to standard output, standard error (the
 * journal) or a file. Tests: --output memory:WxH draws into memory only,
 * --trace FILE writes the model after each frame (the code's serial and
 * length, never its digits), --keys PATH reads input events from PATH in
 * place of /dev/input, OMAMOBILE_LINK_ROOT puts the socket under a scratch
 * root.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/signalfd.h>
#include <time.h>
#include <unistd.h>
#include "screen.h"

#ifndef VERSION
#define VERSION "0"
#endif
#define SOCKET_PATH "/run/omamobile-install-link/screen"

void say(const char *fmt, ...)
{
	char line[300];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	fprintf(stderr, "omamobile-install-screen: %s\n", line);
}

static double now_s(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

enum want { W_AUTO, W_DRM, W_FB, W_PLYMOUTH, W_NONE, W_MEMORY };

struct app {
	struct model m;
	struct theme th;
	struct fonts *fonts;
	struct output out;
	enum want want;
	int mem_w, mem_h;
	struct keys keys;
	int scan_keys;
	struct link link;
	char sock[PATH_MAX];
	int demo;
	int trace_fd;
	int dirty;
	double next_connect, next_probe, next_scan;
	int told_absent;
	int drift;
	enum phase last_phase;
	enum pairing last_pairing;
	int last_connected;
};

static const char *kind_name(enum out_kind k)
{
	switch (k) {
	case OUT_DRM:
		return "drm";
	case OUT_FB:
		return "fb";
	case OUT_PLYMOUTH:
		return "plymouth";
	case OUT_MEMORY:
		return "memory";
	default:
		return "none";
	}
}

static int pixels(enum out_kind k)
{
	return k == OUT_DRM || k == OUT_FB || k == OUT_MEMORY;
}

static void close_output(struct app *a)
{
	switch (a->out.kind) {
	case OUT_DRM:
		drm_close(&a->out);
		break;
	case OUT_FB:
		fb_close(&a->out);
		break;
	case OUT_PLYMOUTH:
		plymouth_close(&a->out);
		break;
	case OUT_MEMORY:
		explicit_bzero(a->out.shadow.px, (size_t)a->out.shadow.w * a->out.shadow.h * 4);
		free(a->out.shadow.px);
		memset(&a->out.shadow, 0, sizeof(a->out.shadow));
		a->out.kind = OUT_NONE;
		break;
	default:
		break;
	}
}

static int try_plymouth(struct app *a)
{
	if (plymouth_ping() < 0)
		return -1;
	a->out.kind = OUT_PLYMOUTH;
	say("output: Plymouth's message line");
	return 0;
}

static int try_pixels(struct app *a, int (*open)(struct output *))
{
	if (open(&a->out) < 0)
		return -1;
	if (fonts_ok(a->fonts))
		return 0;
	say("output: no font to draw with (JetBrains Mono, Noto Sans, DejaVu Sans)");
	close_output(a);
	return -1;
}

static void open_output(struct app *a)
{
	int busy = 0;

	switch (a->want) {
	case W_MEMORY:
		a->out.shadow.w = a->mem_w;
		a->out.shadow.h = a->mem_h;
		a->out.shadow.stride = a->mem_w;
		a->out.shadow.px = calloc((size_t)a->mem_w * a->mem_h, 4);
		a->out.kind = a->out.shadow.px ? OUT_MEMORY : OUT_NONE;
		return;
	case W_NONE:
		break;
	case W_DRM:
		try_pixels(a, drm_open);
		break;
	case W_FB:
		try_pixels(a, fb_open);
		break;
	case W_PLYMOUTH:
		try_plymouth(a);
		break;
	case W_AUTO:
		if (try_pixels(a, drm_open) == 0)
			break;
		busy = errno == EBUSY;
		/* Another program holds the DRM device: what fb0 gets would not
		 * show, Plymouth's line would */
		if (busy && try_plymouth(a) == 0)
			break;
		if (try_pixels(a, fb_open) == 0)
			break;
		if (try_plymouth(a) == 0)
			break;
		break;
	}
	if (a->out.kind == OUT_NONE && !a->told_absent) {
		say("output: none%s; the link works on without a screen", busy ? " (the DRM device is held by another program)" : "");
		a->told_absent = 1;
	}
	if (a->out.kind != OUT_NONE)
		a->told_absent = 0;
	a->dirty = 1;
}

/* An output that is not a DRM device: is one free now? */
static void probe_again(struct app *a)
{
	struct output o = { 0 };

	if (a->want != W_AUTO || a->out.kind == OUT_DRM || !fonts_ok(a->fonts))
		return;
	if (drm_open(&o) < 0) {
		if (a->out.kind == OUT_NONE)
			open_output(a);
		return;
	}
	close_output(a);
	a->out = o;
	a->told_absent = 0;
	a->dirty = 1;
}

static void trace(struct app *a)
{
	char line[256];
	int n;

	if (a->trace_fd < 0)
		return;
	n = model_trace(&a->m, line, sizeof(line) - 32);
	n += snprintf(line + n, sizeof(line) - (size_t)n, " output=%s\n", kind_name(a->out.kind));
	if (write(a->trace_fd, line, (size_t)n) < 0)
		a->trace_fd = -1;
}

static void tell_state(struct app *a)
{
	static const char *pairing[] = { "no code yet", "a code shown", "locked for a while", "locked until a key",
					 "paired" };
	static const char *phase[] = { "waiting", "setup", "stopped" };

	if (a->m.connected == a->last_connected && a->m.phase == a->last_phase && a->m.pairing == a->last_pairing)
		return;
	if (a->m.connected)
		say("screen: %s, %s", phase[a->m.phase], pairing[a->m.pairing]);
	a->last_connected = a->m.connected;
	a->last_phase = a->m.phase;
	a->last_pairing = a->m.pairing;
}

static void present(struct app *a, int blank)
{
	double now = now_s();
	int r = 0;

	if (a->out.kind == OUT_DRM && drm_busy(&a->out)) {
		if (!blank)
			return; /* after the flip that is on its way */
		for (int i = 0; i < 20 && drm_busy(&a->out); i++) {
			struct pollfd p = { .fd = drm_fd(&a->out), .events = POLLIN };
			if (poll(&p, 1, 10) > 0)
				drm_event(&a->out);
		}
	}
	a->dirty = 0;
	if (pixels(a->out.kind)) {
		int drift = a->out.kind == OUT_MEMORY ? 0 : a->drift;
		render(&a->out.shadow, a->fonts, &a->th, &a->m, now, drift, blank, NULL);
		if (a->out.kind == OUT_DRM)
			r = drm_present(&a->out);
		else if (a->out.kind == OUT_FB)
			r = fb_present(&a->out);
	} else if (a->out.kind == OUT_PLYMOUTH) {
		char msg[256] = "";
		if (!blank)
			model_message(&a->m, now, msg, sizeof(msg));
		r = plymouth_show(&a->out, msg);
		explicit_bzero(msg, sizeof(msg));
	}
	if (r < 0) {
		say("output: %s stopped working; looking again", kind_name(a->out.kind));
		close_output(a);
		a->next_probe = 0;
		a->dirty = 1;
	}
	if (!blank)
		trace(a);
	else if (a->trace_fd >= 0) {
		char line[64];
		int n = snprintf(line, sizeof(line), "blank output=%s\n", kind_name(a->out.kind));
		if (write(a->trace_fd, line, (size_t)n) < 0)
			a->trace_fd = -1;
	}
}

static void on_line(void *arg, const char *line, size_t len)
{
	struct app *a = arg;

	if (model_line(&a->m, line, len, now_s()) == L_CHANGED)
		a->dirty = 1;
	else
		say("daemon: a line this screen does not know (%zu bytes), ignored", len);
}

static void on_keys(struct app *a, int presses)
{
	if (presses <= 0)
		return;
	if (a->demo) {
		if (write(STDOUT_FILENO, "key\n", 4) < 0)
			return;
		say("keys: a volume key press (demo: written to standard output)");
	} else if (link_key(&a->link) == 0) {
		say("keys: a volume key press, told the daemon");
	} else {
		say("keys: a volume key press, no daemon to tell");
	}
}

static void usage(FILE *f)
{
	fputs("usage: omamobile-install-screen [--output auto|drm|fb|plymouth|none] [--demo]\n"
	      "       [--theme COLORS.TOML] [--font F] [--bold-font F] [--logo-font F]\n"
	      "       [--socket PATH] [--keys PATH]... [--no-keys] [--trace FILE]\n"
	      "The install link's first-start screen (docs/INSTALL-LINK-PLAN.md §3.3).\n",
	      f);
}

int main(int argc, char **argv)
{
	static struct app a;
	const char *theme = NULL, *font = NULL, *bold = NULL, *logo = NULL, *trace_path = NULL, *sock = NULL;
	static const struct option opts[] = {
		{ "output", required_argument, 0, 'o' }, { "demo", no_argument, 0, 'd' },
		{ "theme", required_argument, 0, 't' },  { "font", required_argument, 0, 'f' },
		{ "bold-font", required_argument, 0, 'b' }, { "logo-font", required_argument, 0, 'l' },
		{ "socket", required_argument, 0, 's' }, { "keys", required_argument, 0, 'k' },
		{ "no-keys", no_argument, 0, 'n' },     { "trace", required_argument, 0, 'T' },
		{ "help", no_argument, 0, 'h' },        { "version", no_argument, 0, 'V' },
		{ 0, 0, 0, 0 },
	};
	int c, no_keys = 0;

	model_init(&a.m);
	keys_init(&a.keys);
	link_init(&a.link);
	a.trace_fd = -1;
	a.last_connected = -1;
	while ((c = getopt_long(argc, argv, "", opts, NULL)) != -1) {
		switch (c) {
		case 'o':
			if (!strcmp(optarg, "auto"))
				a.want = W_AUTO;
			else if (!strcmp(optarg, "drm"))
				a.want = W_DRM;
			else if (!strcmp(optarg, "fb"))
				a.want = W_FB;
			else if (!strcmp(optarg, "plymouth"))
				a.want = W_PLYMOUTH;
			else if (!strcmp(optarg, "none"))
				a.want = W_NONE;
			else if (sscanf(optarg, "memory:%dx%d", &a.mem_w, &a.mem_h) == 2 && a.mem_w > 0 && a.mem_h > 0 &&
				 a.mem_w <= 8192 && a.mem_h <= 8192)
				a.want = W_MEMORY;
			else {
				usage(stderr);
				return 2;
			}
			break;
		case 'd':
			a.demo = 1;
			break;
		case 't':
			theme = optarg;
			break;
		case 'f':
			font = optarg;
			break;
		case 'b':
			bold = optarg;
			break;
		case 'l':
			logo = optarg;
			break;
		case 's':
			sock = optarg;
			break;
		case 'k':
			if (keys_add_path(&a.keys, optarg) < 0) {
				say("keys: cannot open %s (%s)", optarg, strerror(errno));
				return 2;
			}
			break;
		case 'n':
			no_keys = 1;
			break;
		case 'T':
			trace_path = optarg;
			break;
		case 'h':
			usage(stdout);
			return 0;
		case 'V':
			puts(VERSION);
			return 0;
		default:
			usage(stderr);
			return 2;
		}
	}
	if (optind != argc) {
		usage(stderr);
		return 2;
	}
	if (sock) {
		snprintf(a.sock, sizeof(a.sock), "%s", sock);
	} else {
		const char *root = getenv("OMAMOBILE_LINK_ROOT");
		snprintf(a.sock, sizeof(a.sock), "%s%s", root ? root : "", SOCKET_PATH);
	}
	if (trace_path) {
		a.trace_fd = open(trace_path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0600);
		if (a.trace_fd < 0) {
			say("trace: cannot open %s (%s)", trace_path, strerror(errno));
			return 2;
		}
	}
	a.scan_keys = !no_keys && !a.keys.fixed;
	theme_load(&a.th, theme);
	a.fonts = fonts_open(font, bold, logo);

	sigset_t sigs;
	sigemptyset(&sigs);
	sigaddset(&sigs, SIGTERM);
	sigaddset(&sigs, SIGINT);
	sigaddset(&sigs, SIGHUP);
	sigprocmask(SIG_BLOCK, &sigs, NULL);
	signal(SIGPIPE, SIG_IGN);
	int sfd = signalfd(-1, &sigs, SFD_CLOEXEC | SFD_NONBLOCK);

	if (a.demo) {
		a.link.fd = STDIN_FILENO;
		fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
		model_connected(&a.m);
	}
	open_output(&a);
	a.next_probe = now_s() + 5;

	int quit = 0;
	while (!quit && !a.m.off) {
		double now = now_s();
		/* The daemon */
		if (!a.demo && a.link.fd < 0 && now >= a.next_connect) {
			if (link_connect(&a.link, a.sock) == 0) {
				model_connected(&a.m);
				say("daemon: connected");
				a.dirty = 1;
			}
			a.next_connect = now + 1;
		}
		/* The keys: looked for again while there are none */
		if (a.scan_keys && a.keys.n == 0 && now >= a.next_scan) {
			if (keys_scan(&a.keys, "/dev/input") == 0 && a.next_scan == 0)
				say("keys: no volume key found yet; looking again every 5 s");
			a.next_scan = now + 5;
		}
		if (now >= a.next_probe) {
			probe_again(&a);
			a.next_probe = now + 5;
		}
		/* A countdown, and a small move against burn-in each minute */
		if (a.m.pairing == P_LOCKED)
			a.dirty = 1;
		if (pixels(a.out.kind) && a.out.kind != OUT_MEMORY) {
			int drift = ((int)(now / 60) % 5 - 2) * a.out.shadow.h / 200;
			if (drift != a.drift) {
				a.drift = drift;
				a.dirty = 1;
			}
		}
		if (a.dirty)
			present(&a, 0);
		tell_state(&a);

		struct pollfd p[KEYS_MAX + 3];
		int n = 0, ilink = -1, idrm = -1, isig = -1, ikeys = 0;
		if (a.link.fd >= 0) {
			ilink = n;
			p[n++] = (struct pollfd){ .fd = a.link.fd, .events = POLLIN };
		}
		if (drm_fd(&a.out) >= 0) {
			idrm = n;
			p[n++] = (struct pollfd){ .fd = drm_fd(&a.out), .events = POLLIN };
		}
		if (sfd >= 0) {
			isig = n;
			p[n++] = (struct pollfd){ .fd = sfd, .events = POLLIN };
		}
		ikeys = n;
		for (int i = 0; i < a.keys.n; i++)
			p[n++] = (struct pollfd){ .fd = a.keys.fd[i], .events = POLLIN };
		int timeout = a.m.pairing == P_LOCKED ? 500 : 1000;
		if (poll(p, (nfds_t)n, timeout) < 0 && errno != EINTR)
			break;
		if (isig >= 0 && p[isig].revents) {
			struct signalfd_siginfo si;
			if (read(sfd, &si, sizeof(si)) > 0) {
				say("signal %u: ending", si.ssi_signo);
				quit = 1;
			}
		}
		if (idrm >= 0 && p[idrm].revents)
			drm_event(&a.out);
		if (ilink >= 0 && p[ilink].revents) {
			if (link_read(&a.link, on_line, &a) < 0) {
				if (a.demo) {
					a.link.fd = -1; /* standard input ended: keep showing */
				} else {
					say("daemon: gone; waiting for it");
					model_disconnected(&a.m);
					a.dirty = 1;
					a.next_connect = now_s() + 1;
				}
			}
		}
		/* Backwards: a source that ended is swapped with the last one */
		for (int i = a.keys.n - 1; i >= 0; i--) {
			if (!p[ikeys + i].revents)
				continue;
			int presses = keys_read(&a.keys, i);
			for (int k = 0; k < presses && k < 8; k++)
				on_keys(&a, 1);
		}
	}
	if (a.m.off)
		say("daemon: off; the session owns the display from here");
	/* The background alone: no code stays on the panel */
	model_forget_code(&a.m);
	present(&a, 1);
	close_output(&a);
	keys_close(&a.keys);
	if (!a.demo)
		link_close(&a.link);
	fonts_close(a.fonts);
	vt_restore();
	return 0;
}
