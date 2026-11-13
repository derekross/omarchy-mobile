/* SPDX-License-Identifier: MIT */
/*
 * omamobile-install-screen: the first-start screen of the install link
 * (docs/INSTALL-LINK-PLAN.md §3.3). It shows what the daemon's screen
 * socket says (the pairing code among it) on the panel before any session
 * or display manager exists, and tells the daemon when a volume key is
 * pressed (an act at the phone, §2.5).
 *
 * The code is never written to a log, a file or a command line (§9): it
 * lives in struct model, is drawn into pixels and is wiped when it is
 * replaced.
 */
#ifndef OMAMOBILE_INSTALL_SCREEN_H
#define OMAMOBILE_INSTALL_SCREEN_H

#include <stdint.h>
#include <stddef.h>

#define CODE_LEN 6
#define STEP_MAX 32

/* ------------------------------------------------------------- the model */

enum phase { PH_WAITING, PH_SETUP, PH_STOPPED };
enum pairing {
	P_NONE,       /* connected, but no code is known (a late start) */
	P_CODE,       /* a code is shown */
	P_LOCKED,     /* pair is locked for wait_s; the next code comes after */
	P_LOCKED_ACT, /* locked until someone presses a volume key */
	P_PAIRED,     /* a host is paired: no code */
};
enum note { N_NONE, N_WRONG, N_VERSION, N_NOSPACE, N_DAMAGED };

struct model {
	int connected;  /* to the daemon's screen socket */
	int off;        /* the daemon said `off`: the screen ends */
	enum phase phase;
	char step[STEP_MAX + 1];
	enum pairing pairing;
	char code[CODE_LEN + 1]; /* digits, or empty */
	unsigned code_serial;    /* counts the codes shown: for the trace */
	double lock_until;       /* monotonic seconds, for P_LOCKED */
	enum note note;
	unsigned left;           /* N_WRONG: tries before a new code */
};

/* What a line did */
enum line_result { L_IGNORED, L_CHANGED };

void model_init(struct model *m);
/* One line from the daemon, without its newline. now: monotonic seconds. */
enum line_result model_line(struct model *m, const char *line, size_t len, double now);
/* The daemon went away: nothing it said holds any more. */
void model_disconnected(struct model *m);
void model_connected(struct model *m);
/* Wipe the code from memory. */
void model_forget_code(struct model *m);

/* The words on the screen, from the model. Pointers into static strings or
 * into buf. */
enum tone { T_NORMAL, T_ACCENT, T_WARN, T_ERROR, T_MUTED };
struct texts {
	const char *title;
	enum tone title_tone;
	const char *code; /* the digits, or NULL */
	const char *sub;
	enum tone sub_tone;
	const char *note;
	enum tone note_tone;
	const char *hint;
	char buf[3][160];
};
void model_texts(const struct model *m, double now, struct texts *t);
/* A trace line for tests: never the code, only its serial. */
int model_trace(const struct model *m, char *out, size_t n);
/* One line for Plymouth's message line (it holds the code) */
void model_message(const struct model *m, double now, char *out, size_t n);

/* ------------------------------------------------------------- the theme */

struct theme {
	uint32_t background, foreground, bright, accent, muted, warn, error;
};
/* Omarchy's default theme (Tokyo Night) when FILE is NULL or unreadable;
 * the keys it understands are those of a theme's colors.toml. */
void theme_load(struct theme *th, const char *file);

/* ------------------------------------------------------------ the canvas */

struct canvas {
	uint32_t *px; /* XRGB8888 */
	int w, h;
	int stride;   /* in pixels */
};

struct fonts; /* render.c */
struct fonts *fonts_open(const char *regular, const char *bold, const char *logo);
int fonts_ok(const struct fonts *f);
void fonts_close(struct fonts *f);

/* Where each thing went, for the tests' clipping checks */
#define BOX_MAX 24
struct box {
	const char *what;
	int x, y, w, h;
};
struct layout {
	int n;
	struct box box[BOX_MAX];
	int code_px; /* the code's glyph height in pixels */
};

/* Draw the model; drift moves everything down by that many pixels (a
 * slow move against burn-in). blank: the background alone. */
void render(struct canvas *c, struct fonts *f, const struct theme *th, const struct model *m,
	    double now, int drift, int blank, struct layout *out);

/* --------------------------------------------------------------- outputs */

enum out_kind { OUT_NONE, OUT_DRM, OUT_FB, OUT_PLYMOUTH, OUT_MEMORY };

struct drm_out;
struct fb_out;

struct output {
	enum out_kind kind;
	struct canvas shadow; /* drawn here, then copied out */
	struct drm_out *drm;
	struct fb_out *fb;
	char shown[256]; /* plymouth: the message shown */
};

/* drm.c: 0, or -1 with errno (EBUSY: a device is there but another
 * program holds it) */
int drm_open(struct output *o);
int drm_present(struct output *o);
int drm_fd(const struct output *o);
void drm_event(struct output *o);
int drm_busy(const struct output *o); /* a flip is still on its way */
void drm_close(struct output *o);

/* fb.c */
int fb_open(struct output *o);
int fb_present(struct output *o);
void fb_close(struct output *o);

/* plymouth.c */
int plymouth_ping(void);
int plymouth_show(struct output *o, const char *text);
void plymouth_close(struct output *o);

/* The VT's text mode, kept away from the picture while fb0 is drawn */
void vt_graphics(void);
void vt_restore(void);

/* ------------------------------------------------------------ the keys */

#define KEYS_MAX 8
struct keys {
	int fd[KEYS_MAX];
	int n;
	int fixed;            /* the sources were named (--keys): no scan */
	double last_press;    /* event time of the last press reported */
};
void keys_init(struct keys *k);
int keys_add_path(struct keys *k, const char *path);
/* Open every /dev/input/event* that has a volume key; returns how many */
int keys_scan(struct keys *k, const char *dir);
/* Read what fd i has; returns the presses to report (0, 1, ...), -1 when
 * the source has ended (it is closed and removed) */
int keys_read(struct keys *k, int i);
void keys_close(struct keys *k);

/* ------------------------------------------------------------- the link */

struct link {
	int fd;
	char buf[256];
	size_t len;
	int discarding; /* an overlong line is being skipped */
};
void link_init(struct link *l);
int link_connect(struct link *l, const char *path);
/* Read what is there; calls fn for each whole line. 0, or -1 when the
 * daemon has gone (the socket is closed). */
int link_read(struct link *l, void (*fn)(void *, const char *, size_t), void *arg);
int link_key(struct link *l);
void link_close(struct link *l);

/* log.c */
void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#endif
