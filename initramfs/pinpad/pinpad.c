// SPDX-License-Identifier: MIT
// omamobile-pinpad: the boot-time PIN pad for an encrypted root
// (docs/SECURITY-PLAN.md §11.5). It runs in the initramfs, draws on /dev/fb0
// and reads touch and the Volume and Power keys from evdev. On OK it starts
// COMMAND (cryptsetup open ... --key-file=-) with the PIN on its standard
// input, through a pipe, with no newline. The PIN is kept in one mlock'ed
// buffer, wiped after every try, and written nowhere else: no log, no file,
// no kmsg.
//
//   omamobile-pinpad [--marker FILE] [--done PATH] [--font DIR] -- COMMAND...
//   omamobile-pinpad --charger      a charging boot: dark until Power is
//                                   held (exit 10) or the cable is out (11)
//   omamobile-pinpad --power-off | --restart
//
// Exit status: 0 COMMAND succeeded, or PATH (--done) appeared, unlocked
// another way (SSH); 3 no input for the power-off time; 4 the test input
// ended; 5 no usable display; 10 and 11 as above; 1 usage or setup error.
//
// --marker FILE is created once the pad is on the screen; the init's USB
// safety net stops when it sees it. COMMAND exiting 2 is a wrong PIN
// (cryptsetup's "no permission"); after the fifth wrong PIN each try waits
// 5 s, then twice as long each time, at most 5 minutes. The count is in RAM:
// this slows someone at the screen, not an attack on a copy of the disk.
//
// Tests (tests/pinpad) only: PINPAD_FB (a file) with PINPAD_FB_SIZE=WxH
// stands in for fb0 as 32-bit XRGB; PINPAD_INPUT (a FIFO of struct
// input_event) for evdev, with PINPAD_TOUCH_MAX=WxH as its touch range;
// PINPAD_TRACE=1 prints what happens (never a digit) on stderr;
// PINPAD_BLANK_MS, PINPAD_OFF_MS, PINPAD_BACKOFF_MS, PINPAD_HOLD_MS,
// PINPAD_UNPLUG_MS and PINPAD_SYSFS change the times and the sysfs root.
// PINPAD_TTY names the console set to KD_GRAPHICS while the pad is up
// (default /dev/tty0; with PINPAD_FB, none unless PINPAD_TTY is set).
// PINPAD_TOUCH_SWAP=x, y or xy mirrors the touch panel's axes, for a phone
// whose panel turns out mirrored (a descriptor key then packs it).
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define PIN_MAX 64
#define MAX_INPUTS 32

/* Omarchy's default theme, as the splash (#1a1b26) */
#define C_BG     0x1a1b26
#define C_KEY    0x24283b
#define C_KEY_HI 0x414868
#define C_TEXT   0xc0caf5
#define C_DIM    0x565f89
#define C_ACCENT 0x7aa2f7
#define C_ERROR  0xf7768e

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */

static int trace_on;

/*
 * vsnprintf for %d, %ld, %s and %%, nothing else. The pad has no other
 * formatting, so it links no stdio: musl's printf needs 128-bit float
 * helpers that a plain clang has no library for on aarch64.
 */
static int vfmt(char *buf, size_t n, const char *f, va_list ap)
{
	size_t o = 0;

#define OUT(c) do { if (o + 1 < n) buf[o] = (c); o++; } while (0)
	for (; *f; f++) {
		if (*f != '%') {
			OUT(*f);
			continue;
		}
		f++;
		if (*f == 's') {
			for (const char *s = va_arg(ap, const char *); s && *s; s++)
				OUT(*s);
		} else if (*f == 'd' || (*f == 'l' && f[1] == 'd')) {
			long v = *f == 'd' ? va_arg(ap, int) : va_arg(ap, long);
			unsigned long u = v < 0 ? -(unsigned long)v : (unsigned long)v;
			char tmp[24];
			int k = 0;

			if (*f == 'l')
				f++;
			do
				tmp[k++] = '0' + u % 10;
			while (u /= 10);
			if (v < 0)
				OUT('-');
			while (k)
				OUT(tmp[--k]);
		} else if (*f == '%') {
			OUT('%');
		} else {
			break;
		}
	}
#undef OUT
	if (n)
		buf[o < n ? o : n - 1] = 0;
	return (int)o;
}

static int fmt(char *buf, size_t n, const char *f, ...)
{
	va_list ap;
	int r;

	va_start(ap, f);
	r = vfmt(buf, n, f, ap);
	va_end(ap);
	return r;
}

static void say(const char *prefix, const char *f, va_list ap)
{
	char line[512];
	size_t len = strlen(prefix);

	memcpy(line, prefix, len);
	vfmt(line + len, sizeof(line) - len - 1, f, ap);
	len = strlen(line);
	line[len++] = '\n';
	if (write(2, line, len) < 0)
		return;
}

static void trace(const char *f, ...)
{
	va_list ap;

	if (!trace_on)
		return;
	va_start(ap, f);
	say("pinpad: ", f, ap);
	va_end(ap);
}

static void warnx(const char *f, ...)
{
	va_list ap;

	va_start(ap, f);
	say("omamobile-pinpad: ", f, ap);
	va_end(ap);
}

static int64_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static long env_ms(const char *name, long def)
{
	const char *v = getenv(name);
	char *end;
	long n;

	if (!v || !*v)
		return def;
	n = strtol(v, &end, 10);
	return (*end || n < 0) ? def : n;
}

static int parse_size(const char *s, int *w, int *h)
{
	char *end;

	if (!s)
		return 0;
	*w = (int)strtol(s, &end, 10);
	if (*end != 'x')
		return 0;
	*h = (int)strtol(end + 1, &end, 10);
	return !*end && *w > 0 && *h > 0;
}

static void sleep_ms(long ms)
{
	struct timespec ts = { ms / 1000, (ms % 1000) * 1000000L };

	while (nanosleep(&ts, &ts) && errno == EINTR)
		;
}

/* ------------------------------------------------------------------ */
/* Display: a 0xRRGGBB canvas, converted to fb0's format on flush      */

struct display {
	int fd;
	int w, h;           /* visible size */
	int bpp;            /* bytes per pixel: 2, 3 or 4 */
	int stride;         /* fb line length in bytes */
	off_t offset;       /* byte offset of the visible area */
	struct fb_bitfield r, g, b, a;
	uint32_t *canvas;
	uint8_t *out;
	int blanked;
};

/*
 * The console's text stays off the pad: the kernel's messages and the
 * init's shell on tty1 draw on fb0 too. KD_GRAPHICS on the foreground
 * console stops the console drawing anything (and a console write to a
 * stalled display, which stalled the whole phone in PT2), until KD_TEXT is
 * set again on the way out. Not under PINPAD_FB (tests).
 */
static int console_fd = -1;

static void console_text(void)
{
	if (console_fd < 0)
		return;
	ioctl(console_fd, KDSETMODE, KD_TEXT);
	close(console_fd);
	console_fd = -1;
}

static void console_restore_and_die(int sig)
{
	console_text();
	signal(sig, SIG_DFL);
	raise(sig);
}

static void console_graphics(void)
{
	const char *tty = getenv("PINPAD_TTY");

	if (getenv("PINPAD_FB") && !tty)
		return;
	console_fd = open(tty ? tty : "/dev/tty0", O_RDWR | O_NOCTTY | O_CLOEXEC);
	if (console_fd < 0)
		return;
	if (ioctl(console_fd, KDSETMODE, KD_GRAPHICS)) {
		trace("KDSETMODE: %s", strerror(errno));
		close(console_fd);
		console_fd = -1;
		return;
	}
	atexit(console_text);
	signal(SIGTERM, console_restore_and_die);
	signal(SIGINT, console_restore_and_die);
	signal(SIGHUP, console_restore_and_die);
}

static int display_open(struct display *d)
{
	const char *file = getenv("PINPAD_FB");

	memset(d, 0, sizeof(*d));
	if (file) {
		if (!parse_size(getenv("PINPAD_FB_SIZE"), &d->w, &d->h))
			return -1;
		d->fd = open(file, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
		if (d->fd < 0)
			return -1;
		d->bpp = 4;
		d->stride = d->w * 4;
		d->r = (struct fb_bitfield){ 16, 8, 0 };
		d->g = (struct fb_bitfield){ 8, 8, 0 };
		d->b = (struct fb_bitfield){ 0, 8, 0 };
	} else {
		struct fb_var_screeninfo v;
		struct fb_fix_screeninfo f;

		d->fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
		if (d->fd < 0)
			return -1;
		if (ioctl(d->fd, FBIOGET_VSCREENINFO, &v) || ioctl(d->fd, FBIOGET_FSCREENINFO, &f))
			goto bad;
		if (f.type != FB_TYPE_PACKED_PIXELS || f.visual != FB_VISUAL_TRUECOLOR)
			goto bad;
		if (v.bits_per_pixel != 16 && v.bits_per_pixel != 24 && v.bits_per_pixel != 32)
			goto bad;
		d->w = v.xres;
		d->h = v.yres;
		d->bpp = v.bits_per_pixel / 8;
		d->stride = f.line_length;
		if (d->w <= 0 || d->h <= 0 || d->stride < d->w * d->bpp)
			goto bad;
		d->offset = (off_t)v.yoffset * d->stride + (off_t)v.xoffset * d->bpp;
		d->r = v.red;
		d->g = v.green;
		d->b = v.blue;
		d->a = v.transp;
		if (d->r.length > 8 || d->g.length > 8 || d->b.length > 8 || d->a.length > 8)
			goto bad;
	}
	d->canvas = calloc((size_t)d->w * d->h, 4);
	d->out = malloc((size_t)d->stride * d->h);
	if (!d->canvas || !d->out)
		goto bad;
	return 0;
bad:
	close(d->fd);
	d->fd = -1;
	return -1;
}

static uint32_t pack_px(const struct display *d, uint32_t c)
{
	uint32_t r = c >> 16 & 0xff, g = c >> 8 & 0xff, b = c & 0xff, p;

	p = (r >> (8 - d->r.length)) << d->r.offset |
	    (g >> (8 - d->g.length)) << d->g.offset |
	    (b >> (8 - d->b.length)) << d->b.offset;
	if (d->a.length)
		p |= ((1u << d->a.length) - 1) << d->a.offset;
	return p;
}

static void flush(struct display *d)
{
	size_t total = (size_t)d->stride * d->h, done = 0;

	for (int y = 0; y < d->h; y++) {
		uint8_t *row = d->out + (size_t)y * d->stride;
		const uint32_t *src = d->canvas + (size_t)y * d->w;

		for (int x = 0; x < d->w; x++) {
			uint32_t p = pack_px(d, src[x]);

			memcpy(row + x * d->bpp, &p, d->bpp); /* little-endian */
		}
	}
	while (done < total) {
		ssize_t n = pwrite(d->fd, d->out + done, total - done, d->offset + done);

		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;
		done += n;
	}
}

static void fill(struct display *d, uint32_t c)
{
	for (size_t i = 0; i < (size_t)d->w * d->h; i++)
		d->canvas[i] = c;
}

static uint32_t blend(uint32_t bg, uint32_t fg, int a)
{
	uint32_t out = 0;

	for (int s = 0; s < 24; s += 8) {
		int cb = bg >> s & 0xff, cf = fg >> s & 0xff;

		out |= (uint32_t)(cb + (cf - cb) * a / 255) << s;
	}
	return out;
}

static void put(struct display *d, int x, int y, uint32_t c, int a)
{
	uint32_t *p;

	if (x < 0 || y < 0 || x >= d->w || y >= d->h || a <= 0)
		return;
	p = &d->canvas[(size_t)y * d->w + x];
	*p = a >= 255 ? c : blend(*p, c, a);
}

static void rect(struct display *d, int x0, int y0, int w, int h, uint32_t c)
{
	for (int y = y0; y < y0 + h; y++)
		for (int x = x0; x < x0 + w; x++)
			put(d, x, y, c, 255);
}

/* An antialiased disc of radius r around (cx, cy) */
static void disc(struct display *d, double cx, double cy, double r, uint32_t c)
{
	for (int y = (int)(cy - r - 1); y <= (int)(cy + r + 1); y++)
		for (int x = (int)(cx - r - 1); x <= (int)(cx + r + 1); x++) {
			double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
			double cov = r + 0.5 - sqrt(dx * dx + dy * dy);

			if (cov > 0)
				put(d, x, y, c, cov >= 1 ? 255 : (int)(cov * 255));
		}
}

/* A ring: the outline of a disc, for an empty PIN dot */
static void ring(struct display *d, double cx, double cy, double r, double t, uint32_t c)
{
	for (int y = (int)(cy - r - 1); y <= (int)(cy + r + 1); y++)
		for (int x = (int)(cx - r - 1); x <= (int)(cx + r + 1); x++) {
			double dx = x + 0.5 - cx, dy = y + 0.5 - cy, dist = sqrt(dx * dx + dy * dy);
			double cov = fmin(r + 0.5 - dist, dist - (r - t) + 0.5);

			if (cov > 0)
				put(d, x, y, c, cov >= 1 ? 255 : (int)(cov * 255));
		}
}

/* A left-pointing triangle with its tip at (x, cy), for the delete key */
static void tri_left(struct display *d, int x, int cy, int len, int half, uint32_t c)
{
	for (int i = 0; i < len; i++) {
		int hh = half * i / len;

		for (int y = cy - hh; y <= cy + hh; y++)
			put(d, x + i, y, c, 255);
	}
}

/* ------------------------------------------------------------------ */
/* Text: glyphs pre-rendered from the theme's font (mkfont), else a     */
/* built-in 5x7 font scaled up, capitals only                          */

struct glyph {
	int w;
	const uint8_t *alpha;
};

struct font {
	int h;
	struct glyph g[128];
	uint8_t *blob;
	int scale; /* the built-in font: pixels per dot; 0 for a loaded font */
};

static const uint8_t font5x7[][8] = {
	/* char, 7 rows of 5 bits */
	{ '0', 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E },
	{ '1', 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E },
	{ '2', 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F },
	{ '3', 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E },
	{ '4', 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 },
	{ '5', 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E },
	{ '6', 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E },
	{ '7', 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },
	{ '8', 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E },
	{ '9', 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C },
	{ 'A', 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
	{ 'B', 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E },
	{ 'C', 0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E },
	{ 'D', 0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C },
	{ 'E', 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F },
	{ 'F', 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10 },
	{ 'G', 0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F },
	{ 'H', 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
	{ 'I', 0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E },
	{ 'J', 0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C },
	{ 'K', 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11 },
	{ 'L', 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F },
	{ 'M', 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11 },
	{ 'N', 0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11 },
	{ 'O', 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
	{ 'P', 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 },
	{ 'Q', 0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D },
	{ 'R', 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 },
	{ 'S', 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E },
	{ 'T', 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 },
	{ 'U', 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E },
	{ 'V', 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 },
	{ 'W', 0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A },
	{ 'X', 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11 },
	{ 'Y', 0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04 },
	{ 'Z', 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F },
	{ '.', 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C },
	{ ':', 0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00 },
	{ '-', 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00 },
	{ '(', 0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02 },
	{ ')', 0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08 },
};

static const uint8_t *builtin_rows(int ch)
{
	if (ch >= 'a' && ch <= 'z')
		ch -= 'a' - 'A';
	for (size_t i = 0; i < sizeof(font5x7) / sizeof(font5x7[0]); i++)
		if (font5x7[i][0] == ch)
			return &font5x7[i][1];
	return NULL;
}

/*
 * The mkfont format: "OMPF", u16 count, u16 height, then per glyph a u8
 * character, a u16 width and width * height alpha bytes. Little-endian.
 */
static int font_load(struct font *f, const char *path)
{
	struct stat st;
	size_t pos = 8;
	int fd, count;

	memset(f, 0, sizeof(*f));
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	if (fstat(fd, &st) || st.st_size < 8 || st.st_size > (16 << 20))
		goto bad;
	f->blob = malloc(st.st_size);
	if (!f->blob || read(fd, f->blob, st.st_size) != st.st_size)
		goto bad;
	close(fd);
	fd = -1;
	if (memcmp(f->blob, "OMPF", 4))
		goto bad;
	count = f->blob[4] | f->blob[5] << 8;
	f->h = f->blob[6] | f->blob[7] << 8;
	if (f->h <= 0)
		goto bad;
	for (int i = 0; i < count; i++) {
		int ch, w;

		if (pos + 3 > (size_t)st.st_size)
			goto bad;
		ch = f->blob[pos];
		w = f->blob[pos + 1] | f->blob[pos + 2] << 8;
		pos += 3;
		if (ch >= 128 || pos + (size_t)w * f->h > (size_t)st.st_size)
			goto bad;
		f->g[ch].w = w;
		f->g[ch].alpha = f->blob + pos;
		pos += (size_t)w * f->h;
	}
	return 0;
bad:
	if (fd >= 0)
		close(fd);
	free(f->blob);
	memset(f, 0, sizeof(*f));
	return -1;
}

static void font_builtin(struct font *f, int height)
{
	memset(f, 0, sizeof(*f));
	f->scale = height / 9 > 0 ? height / 9 : 1;
	f->h = 9 * f->scale;
}

static int text_width(const struct font *f, const char *s)
{
	int w = 0;

	for (; *s; s++) {
		if (f->scale)
			w += 6 * f->scale;
		else if ((unsigned char)*s < 128)
			w += f->g[(unsigned char)*s].w;
	}
	return w;
}

static void text(struct display *d, const struct font *f, const char *s, int cx, int cy, uint32_t c)
{
	int x = cx - text_width(f, s) / 2, y0 = cy - f->h / 2;

	for (; *s; s++) {
		unsigned char ch = *s;

		if (f->scale) {
			const uint8_t *rows = builtin_rows(ch);

			for (int r = 0; rows && r < 7; r++)
				for (int col = 0; col < 5; col++)
					if (rows[r] & (0x10 >> col))
						rect(d, x + col * f->scale, y0 + (r + 1) * f->scale,
						     f->scale, f->scale, c);
			x += 6 * f->scale;
		} else if (ch < 128 && f->g[ch].alpha) {
			for (int y = 0; y < f->h; y++)
				for (int gx = 0; gx < f->g[ch].w; gx++)
					put(d, x + gx, y0 + y, c, f->g[ch].alpha[y * f->g[ch].w + gx]);
			x += f->g[ch].w;
		} else if (ch < 128) {
			x += f->g[ch].w;
		}
	}
}

/* ------------------------------------------------------------------ */
/* Input                                                               */

#define TEST_BIT(bits, n) ((bits)[(n) / (8 * sizeof(long))] >> ((n) % (8 * sizeof(long))) & 1)
#define NLONGS(n) (((n) + 8 * sizeof(long) - 1) / (8 * sizeof(long)))

struct input {
	int fd;
	int touch;             /* reports absolute positions */
	int mt;                /* multi-touch protocol B */
	int xmin, xmax, ymin, ymax;
	int slot;
	int down[10], x[10], y[10];
	int st_down, st_x, st_y; /* single-touch (ABS_X/Y, BTN_TOUCH) */
	int was_down;
};

struct inputs {
	struct input in[MAX_INPUTS];
	int n;
	unsigned long opened; /* bit per /dev/input/eventN already looked at */
	int test;             /* PINPAD_INPUT */
	int ended;
};

static void input_add_test(struct inputs *is)
{
	const char *path = getenv("PINPAD_INPUT");
	struct input *in = &is->in[0];
	int w, h;

	memset(in, 0, sizeof(*in));
	in->fd = open(path, O_RDONLY | O_CLOEXEC);
	if (in->fd < 0) {
		warnx("PINPAD_INPUT %s: %s", path, strerror(errno));
		exit(1);
	}
	fcntl(in->fd, F_SETFL, O_NONBLOCK);
	in->touch = in->mt = 1;
	if (!parse_size(getenv("PINPAD_TOUCH_MAX"), &w, &h))
		w = h = 4096;
	in->xmax = w - 1;
	in->ymax = h - 1;
	is->n = 1;
	is->test = 1;
}

/* Open every evdev node not looked at yet that has touch or the keys */
static void input_scan(struct inputs *is)
{
	for (int i = 0; i < MAX_INPUTS && is->n < MAX_INPUTS; i++) {
		unsigned long evbits[NLONGS(EV_MAX + 1)] = { 0 };
		unsigned long keybits[NLONGS(KEY_MAX + 1)] = { 0 };
		unsigned long absbits[NLONGS(ABS_MAX + 1)] = { 0 };
		struct input *in = &is->in[is->n];
		char path[32];
		int fd;

		if (is->opened >> i & 1)
			continue;
		fmt(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		is->opened |= 1ul << i;
		ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits);
		ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits);
		ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbits)), absbits);
		memset(in, 0, sizeof(*in));
		in->fd = fd;
		if (TEST_BIT(evbits, EV_ABS) && TEST_BIT(absbits, ABS_MT_POSITION_X) &&
		    TEST_BIT(absbits, ABS_MT_POSITION_Y)) {
			struct input_absinfo ax, ay;

			if (!ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ax) &&
			    !ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ay)) {
				in->touch = 1;
				in->mt = TEST_BIT(absbits, ABS_MT_SLOT);
				in->xmin = ax.minimum, in->xmax = ax.maximum;
				in->ymin = ay.minimum, in->ymax = ay.maximum;
			}
		} else if (TEST_BIT(evbits, EV_ABS) && TEST_BIT(absbits, ABS_X) &&
			   TEST_BIT(absbits, ABS_Y) && TEST_BIT(keybits, BTN_TOUCH)) {
			struct input_absinfo ax, ay;

			if (!ioctl(fd, EVIOCGABS(ABS_X), &ax) && !ioctl(fd, EVIOCGABS(ABS_Y), &ay)) {
				in->touch = 1;
				in->xmin = ax.minimum, in->xmax = ax.maximum;
				in->ymin = ay.minimum, in->ymax = ay.maximum;
			}
		}
		if (!in->touch && !(TEST_BIT(evbits, EV_KEY) &&
				    (TEST_BIT(keybits, KEY_POWER) || TEST_BIT(keybits, KEY_VOLUMEUP) ||
				     TEST_BIT(keybits, KEY_VOLUMEDOWN)))) {
			close(fd);
			continue;
		}
		trace("input event%d: %s", i, in->touch ? "touch" : "keys");
		is->n++;
	}
}

/* What one input event means to the pad */
enum act { A_NONE, A_DOWN, A_MOVE, A_UP, A_KEY, A_KEY_UP };

struct action {
	enum act a;
	int x, y; /* touch, in panel pixels */
	int key;  /* evdev key code */
};

static int touch_swap; /* bit 0: mirror x, bit 1: mirror y */

static int scale(int v, int min, int max, int size)
{
	long range = (long)max - min + 1;

	if (range <= 0)
		return 0;
	v = (int)(((long)v - min) * size / range);
	return v < 0 ? 0 : v >= size ? size - 1 : v;
}

/* One event read from in; returns 1 with *out set when it means something */
static int input_event_act(struct input *in, const struct input_event *ev, int w, int h, struct action *out)
{
	out->a = A_NONE;
	if (ev->type == EV_KEY && !in->touch) {
		if (ev->code != KEY_POWER && ev->code != KEY_VOLUMEUP && ev->code != KEY_VOLUMEDOWN)
			return 0;
		if (ev->value == 1)
			out->a = A_KEY;
		else if (ev->value == 0)
			out->a = A_KEY_UP;
		out->key = ev->code;
		return out->a != A_NONE;
	}
	if (ev->type == EV_KEY && in->touch && ev->code == BTN_TOUCH && !in->mt) {
		in->st_down = ev->value;
		return 0;
	}
	/* The test input carries keys too */
	if (ev->type == EV_KEY && (ev->code == KEY_POWER || ev->code == KEY_VOLUMEUP ||
				   ev->code == KEY_VOLUMEDOWN)) {
		out->a = ev->value == 1 ? A_KEY : ev->value == 0 ? A_KEY_UP : A_NONE;
		out->key = ev->code;
		return out->a != A_NONE;
	}
	if (ev->type == EV_ABS && in->touch) {
		int s = in->slot;

		switch (ev->code) {
		case ABS_MT_SLOT:
			in->slot = ev->value >= 0 && ev->value < 10 ? ev->value : 0;
			break;
		case ABS_MT_TRACKING_ID:
			in->down[s] = ev->value >= 0;
			break;
		case ABS_MT_POSITION_X:
			in->x[s] = ev->value;
			if (!in->mt)
				in->down[s] = 1; /* protocol A: a position means a contact */
			break;
		case ABS_MT_POSITION_Y:
			in->y[s] = ev->value;
			break;
		case ABS_X:
			in->st_x = ev->value;
			break;
		case ABS_Y:
			in->st_y = ev->value;
			break;
		}
		return 0;
	}
	if (ev->type == EV_SYN && ev->code == SYN_REPORT && in->touch) {
		int down = 0, x = 0, y = 0;

		for (int s = 0; s < 10; s++)
			if (in->down[s]) {
				down = 1, x = in->x[s], y = in->y[s];
				break;
			}
		if (!down && in->st_down)
			down = 1, x = in->st_x, y = in->st_y;
		/* Protocol A: a report with no position has no contact */
		if (!in->mt)
			in->down[0] = 0;
		x = scale(x, in->xmin, in->xmax, w);
		y = scale(y, in->ymin, in->ymax, h);
		if (touch_swap & 1)
			x = w - 1 - x;
		if (touch_swap & 2)
			y = h - 1 - y;
		if (down) {
			out->a = in->was_down ? A_MOVE : A_DOWN;
			out->x = x, out->y = y;
		} else if (in->was_down) {
			out->a = A_UP;
		}
		in->was_down = down;
		return out->a != A_NONE;
	}
	return 0;
}

/*
 * Wait up to timeout ms (one poll) for one action. Returns 1 with *out, 0
 * when nothing that means anything came, -1 when the test input ended.
 */
static int input_wait(struct inputs *is, int timeout, int w, int h, struct action *out)
{
	static struct input_event pending[64];
	static int npending, ppos, pfrom;
	int polled = 0;

	for (;;) {
		struct pollfd pf[MAX_INPUTS];

		while (ppos < npending) {
			struct input_event *ev = &pending[ppos++];

			if (input_event_act(&is->in[pfrom], ev, w, h, out))
				return 1;
		}
		if (is->ended)
			return -1;
		if (polled)
			return 0;
		polled = 1;
		for (int i = 0; i < is->n; i++)
			pf[i] = (struct pollfd){ .fd = is->in[i].fd, .events = POLLIN };
		if (poll(pf, is->n, timeout < 0 ? 0 : timeout) <= 0)
			continue;
		for (int i = 0; i < is->n; i++) {
			ssize_t n;

			if (!(pf[i].revents & (POLLIN | POLLHUP | POLLERR)))
				continue;
			n = read(is->in[i].fd, pending, sizeof(pending));
			if (n == 0 && is->test) {
				is->ended = 1;
				break;
			}
			if (n < (ssize_t)sizeof(struct input_event))
				continue;
			npending = n / sizeof(struct input_event);
			ppos = 0;
			pfrom = i;
			break;
		}
	}
}

/* ------------------------------------------------------------------ */
/* The pad                                                             */

#define NKEYS 12
#define K_DEL 9
#define K_ZERO 10
#define K_OK 11

struct pad {
	struct display d;
	struct font big, small;
	int kx[NKEYS], ky[NKEYS], kw, kh; /* cells */
	int pressed;                      /* key under the finger, or -1 */
	int highlight;                    /* key chosen with Volume, or -1 */
	char *pin;                        /* mlock'ed */
	int len;
	const char *title;
	char message[64];
	uint32_t message_colour;
	int shake;
};

static void layout(struct pad *p)
{
	int w = p->d.w, h = p->d.h;
	int margin = w / 12, gap = w / 30;
	int top = h * 40 / 100, bottom = h * 93 / 100;

	p->kw = (w - 2 * margin - 2 * gap) / 3;
	p->kh = (bottom - top - 3 * gap) / 4;
	if (p->kh > p->kw)
		p->kh = p->kw;
	top = bottom - 4 * p->kh - 3 * gap;
	for (int i = 0; i < NKEYS; i++) {
		p->kx[i] = margin + (i % 3) * (p->kw + gap);
		p->ky[i] = top + (i / 3) * (p->kh + gap);
	}
	trace("layout %d %d", w, h);
	for (int i = 0; i < NKEYS; i++)
		trace("key %d %d %d %d %d", i, p->kx[i], p->ky[i], p->kw, p->kh);
}

static int key_at(const struct pad *p, int x, int y)
{
	for (int i = 0; i < NKEYS; i++)
		if (x >= p->kx[i] && x < p->kx[i] + p->kw && y >= p->ky[i] && y < p->ky[i] + p->kh)
			return i;
	return -1;
}

static void draw(struct pad *p, int show_keys)
{
	struct display *d = &p->d;
	int w = d->w, h = d->h;
	double dot_r = w / 60.0, dot_gap = w / 18.0;
	int ndots = p->len > 0 ? p->len : 0, dots_y = h * 27 / 100;
	static const char *labels[NKEYS] = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "OK" };

	fill(d, C_BG);
	text(d, &p->small, p->title, w / 2, h * 19 / 100, C_TEXT);
	/* The dots: one per digit, centred; past what fits, the count */
	if (ndots && ndots * dot_gap < w * 0.8) {
		double x0 = w / 2.0 - (ndots - 1) * dot_gap / 2 + p->shake;

		for (int i = 0; i < ndots; i++)
			disc(d, x0 + i * dot_gap, dots_y, dot_r, C_ACCENT);
	} else if (ndots) {
		char n[16];

		fmt(n, sizeof(n), "%d", ndots);
		text(d, &p->small, n, w / 2 + p->shake, dots_y, C_ACCENT);
	} else {
		ring(d, w / 2.0 + p->shake, dots_y, dot_r, dot_r / 3, C_DIM);
	}
	if (p->message[0])
		text(d, &p->small, p->message, w / 2, h * 33 / 100, p->message_colour);
	if (!show_keys)
		return;
	for (int i = 0; i < NKEYS; i++) {
		double cx = p->kx[i] + p->kw / 2.0, cy = p->ky[i] + p->kh / 2.0;
		double r = (p->kw < p->kh ? p->kw : p->kh) * 0.46;
		uint32_t bg = (i == p->pressed || i == p->highlight) ? C_KEY_HI : C_KEY;

		if (i == K_OK)
			bg = (i == p->pressed || i == p->highlight) ? C_TEXT : C_ACCENT;
		disc(d, cx, cy, r, bg);
		if (i == p->highlight)
			ring(d, cx, cy, r, r / 14 + 1, C_TEXT);
		if (i == K_DEL) {
			int len = (int)(r * 0.9), half = (int)(r * 0.32);
			int x = (int)(cx - len / 2), th = half / 3 + 1;

			tri_left(d, x, (int)cy, half, half, C_TEXT);
			rect(d, x + half - 1, (int)cy - th / 2, len - half, th, C_TEXT);
		} else {
			text(d, &p->big, labels[i], (int)cx, (int)cy, i == K_OK ? C_BG : C_TEXT);
		}
	}
}

static void show(struct pad *p, int show_keys)
{
	draw(p, show_keys);
	flush(&p->d);
	trace("draw dots=%d message=%s", p->len, p->message[0] ? p->message : "-");
}

static void set_message(struct pad *p, uint32_t colour, const char *f, ...)
{
	va_list ap;

	va_start(ap, f);
	vfmt(p->message, sizeof(p->message), f, ap);
	va_end(ap);
	p->message_colour = colour;
}

static void wipe_pin(struct pad *p)
{
	explicit_bzero(p->pin, PIN_MAX + 1);
	p->len = 0;
}

static void blank(struct pad *p, int on)
{
	if (on == p->d.blanked)
		return;
	p->d.blanked = on;
	if (on) {
		fill(&p->d, 0);
		flush(&p->d);
		if (!getenv("PINPAD_FB"))
			ioctl(p->d.fd, FBIOBLANK, FB_BLANK_POWERDOWN);
	} else if (!getenv("PINPAD_FB")) {
		ioctl(p->d.fd, FBIOBLANK, FB_BLANK_UNBLANK);
	}
	trace(on ? "blank" : "unblank");
}

/*
 * Run the command with the PIN on its standard input. Returns its exit
 * status, or -1 if it could not run.
 */
static int run_unlock(struct pad *p, char **cmd)
{
	int fds[2], status;
	pid_t pid;

	if (pipe2(fds, O_CLOEXEC))
		return -1;
	pid = fork();
	if (pid < 0) {
		close(fds[0]);
		close(fds[1]);
		return -1;
	}
	if (pid == 0) {
		int null = open("/dev/null", O_WRONLY);

		dup2(fds[0], 0);
		if (null >= 0)
			dup2(null, 1);
		execvp(cmd[0], cmd);
		_exit(127);
	}
	close(fds[0]);
	for (int done = 0; done < p->len;) {
		ssize_t n = write(fds[1], p->pin + done, p->len - done);

		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;
		done += n;
	}
	close(fds[1]);
	wipe_pin(p);
	while (waitpid(pid, &status, 0) < 0)
		if (errno != EINTR)
			return -1;
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static long backoff_ms(int wrong, long base)
{
	long ms = base, cap = 300000;

	if (wrong < 5)
		return 0;
	for (int i = 5; i < wrong && ms < cap; i++)
		ms *= 2;
	return ms < cap ? ms : cap;
}

static void touch_marker(const char *path)
{
	int fd;

	if (!path)
		return;
	fd = open(path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
	if (fd >= 0)
		close(fd);
}

static int pad_main(const char *marker, const char *done, const char *fontdir, char **cmd)
{
	struct pad p = { .pressed = -1, .highlight = -1, .title = "Enter PIN" };
	struct inputs is = { 0 };
	long blank_after = env_ms("PINPAD_BLANK_MS", 60000);
	long off_after = env_ms("PINPAD_OFF_MS", 600000);
	long base = env_ms("PINPAD_BACKOFF_MS", 5000);
	int64_t last_input = now_ms(), last_scan = 0, wait_until = 0;
	int wrong = 0, swallow = 0;
	char path[512];

	if (display_open(&p.d)) {
		warnx("no usable framebuffer");
		return 5;
	}
	console_graphics();
	p.pin = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (p.pin == MAP_FAILED)
		return 1;
	if (mlock(p.pin, 4096))
		trace("mlock failed: %s", strerror(errno));
	madvise(p.pin, 4096, MADV_DONTDUMP);
	fmt(path, sizeof(path), "%s/big.font", fontdir);
	if (font_load(&p.big, path))
		font_builtin(&p.big, p.d.w / 11);
	fmt(path, sizeof(path), "%s/small.font", fontdir);
	if (font_load(&p.small, path))
		font_builtin(&p.small, p.d.w / 20);
	trace("font %s", p.big.scale ? "built-in" : "loaded");
	layout(&p);
	if (getenv("PINPAD_INPUT"))
		input_add_test(&is);
	show(&p, 1);
	touch_marker(marker);
	trace("ready");

	for (;;) {
		struct action a;
		int64_t t = now_ms();
		int r, activate = -1;

		if (done && access(done, F_OK) == 0) {
			trace("unlocked elsewhere");
			wipe_pin(&p);
			return 0;
		}
		if (!is.test && t - last_scan >= 2000) {
			input_scan(&is);
			last_scan = t;
		}
		if (wait_until) {
			if (t >= wait_until) {
				wait_until = 0;
				p.message[0] = 0;
				p.title = "Enter PIN";
				trace("wait over");
				show(&p, 1);
			} else {
				set_message(&p, C_ERROR, "Try again in %ld s", (long)((wait_until - t + 999) / 1000));
				if (!p.d.blanked)
					show(&p, 0);
			}
		}
		if (t - last_input >= off_after) {
			trace("idle: power off");
			wipe_pin(&p);
			return 3;
		}
		if (!p.d.blanked && t - last_input >= blank_after)
			blank(&p, 1);

		r = input_wait(&is, wait_until ? 1000 - (int)(now_ms() % 1000) : 1000, p.d.w, p.d.h, &a);
		if (r < 0) {
			trace("input ended");
			wipe_pin(&p);
			return 4;
		}
		if (r == 0)
			continue;
		last_input = now_ms();
		if (p.d.blanked) {
			/* The touch or key that wakes the screen does nothing else */
			blank(&p, 0);
			swallow = 1;
			show(&p, !wait_until);
		}
		if (swallow) {
			if (a.a == A_UP || a.a == A_KEY_UP)
				swallow = 0;
			continue;
		}
		if (wait_until)
			continue;
		switch (a.a) {
		case A_DOWN:
		case A_MOVE: {
			int k = key_at(&p, a.x, a.y);

			if (a.a == A_MOVE && k == p.pressed)
				break;
			p.pressed = a.a == A_DOWN || k == p.pressed ? k : -1;
			p.highlight = -1;
			show(&p, 1);
			break;
		}
		case A_UP:
			activate = p.pressed;
			p.pressed = -1;
			break;
		case A_KEY:
			if (a.key == KEY_VOLUMEUP)
				p.highlight = p.highlight < 0 ? 0 : (p.highlight + NKEYS - 1) % NKEYS;
			else if (a.key == KEY_VOLUMEDOWN)
				p.highlight = p.highlight < 0 ? 0 : (p.highlight + 1) % NKEYS;
			else if (a.key == KEY_POWER)
				activate = p.highlight;
			if (activate < 0)
				show(&p, 1);
			break;
		default:
			break;
		}
		if (activate < 0)
			continue;
		trace("press %s", activate == K_OK ? "ok" : activate == K_DEL ? "delete" : "digit");
		if (activate == K_DEL) {
			if (p.len)
				p.pin[--p.len] = 0;
		} else if (activate == K_OK) {
			int rc;

			if (!p.len) {
				show(&p, 1);
				continue;
			}
			p.title = "Unlocking...";
			p.message[0] = 0;
			p.highlight = -1;
			show(&p, 0);
			trace("submit");
			rc = run_unlock(&p, cmd);
			trace("result %d", rc);
			p.title = "Enter PIN";
			if (rc == 0) {
				trace("unlocked");
				return 0;
			}
			if (done && access(done, F_OK) == 0) {
				trace("unlocked elsewhere");
				return 0;
			}
			if (rc == 2) {
				long ms;

				wrong++;
				set_message(&p, C_ERROR, "Wrong PIN");
				for (int i = 0; i < 6; i++) {
					p.shake = (i % 2 ? -1 : 1) * p.d.w / 40;
					show(&p, 1);
					sleep_ms(30);
				}
				p.shake = 0;
				ms = backoff_ms(wrong, base);
				trace("wrong %d wait %ld", wrong, ms);
				if (ms) {
					wait_until = now_ms() + ms;
					p.title = "Wrong PIN";
				}
			} else {
				warnx("the unlock command failed (status %d)", rc);
				set_message(&p, C_ERROR, "Unlock failed (%d)", rc);
			}
		} else {
			if (p.len < PIN_MAX)
				p.pin[p.len++] = activate == K_ZERO ? '0' : '1' + activate;
			if (p.message_colour == C_ERROR && !wait_until)
				p.message[0] = 0;
		}
		show(&p, !wait_until);
	}
}

/* ------------------------------------------------------------------ */
/* Charging boot                                                       */

static const char *sysfs(void)
{
	const char *s = getenv("PINPAD_SYSFS");

	return s && *s ? s : "/sys";
}

static int read_line(const char *path, char *buf, size_t n)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	ssize_t got;

	if (fd < 0)
		return -1;
	got = read(fd, buf, n - 1);
	close(fd);
	if (got <= 0)
		return -1;
	buf[got] = 0;
	buf[strcspn(buf, "\n")] = 0;
	return 0;
}

/*
 * 1: the cable is in, 0: out, -1: unknown. A power supply other than the
 * battery that reads online decides; with none, the USB device controller's
 * state ("not attached" with the cable out) does.
 */
static int cable_in(void)
{
	char dir[256], path[640], buf[64];
	int seen = 0, online = 0;
	struct dirent *e;
	DIR *dp;

	fmt(dir, sizeof(dir), "%s/class/power_supply", sysfs());
	if ((dp = opendir(dir))) {
		while ((e = readdir(dp))) {
			if (e->d_name[0] == '.')
				continue;
			fmt(path, sizeof(path), "%s/%s/type", dir, e->d_name);
			if (read_line(path, buf, sizeof(buf)) || !strcmp(buf, "Battery"))
				continue;
			fmt(path, sizeof(path), "%s/%s/online", dir, e->d_name);
			if (read_line(path, buf, sizeof(buf)))
				continue;
			seen = 1;
			online |= atoi(buf) > 0;
		}
		closedir(dp);
	}
	if (seen)
		return online;
	fmt(dir, sizeof(dir), "%s/class/udc", sysfs());
	if ((dp = opendir(dir))) {
		while ((e = readdir(dp))) {
			if (e->d_name[0] == '.')
				continue;
			fmt(path, sizeof(path), "%s/%s/state", dir, e->d_name);
			if (read_line(path, buf, sizeof(buf)))
				continue;
			seen = 1;
			online |= strcmp(buf, "not attached") != 0;
		}
		closedir(dp);
	}
	return seen ? online : -1;
}

static int charger_main(void)
{
	struct display d;
	struct inputs is = { 0 };
	long hold = env_ms("PINPAD_HOLD_MS", 1000), unplug = env_ms("PINPAD_UNPLUG_MS", 5000);
	int64_t power_down = 0, out_since = 0, last_scan = 0;

	if (display_open(&d) == 0) {
		console_graphics();
		fill(&d, 0);
		flush(&d);
		if (!getenv("PINPAD_FB"))
			ioctl(d.fd, FBIOBLANK, FB_BLANK_POWERDOWN);
	}
	if (getenv("PINPAD_INPUT"))
		input_add_test(&is);
	trace("charger: waiting");
	for (;;) {
		struct action a;
		int64_t t = now_ms();
		int in = cable_in(), r;

		if (in == 0) {
			if (!out_since)
				out_since = t;
			if (t - out_since >= unplug) {
				trace("charger: cable out");
				return 11;
			}
		} else {
			out_since = 0;
		}
		if (power_down && t - power_down >= hold) {
			trace("charger: power held");
			return 10;
		}
		if (!is.test && t - last_scan >= 2000) {
			input_scan(&is);
			last_scan = t;
		}
		r = input_wait(&is, 100, 1, 1, &a);
		if (r < 0)
			return 4;
		if (r > 0 && (a.a == A_KEY || a.a == A_KEY_UP) && a.key == KEY_POWER) {
			if (a.a == A_KEY)
				power_down = now_ms();
			else if (a.a == A_KEY_UP)
				power_down = 0;
		}
	}
}

/* ------------------------------------------------------------------ */

static void usage(void)
{
	static const char u[] = "usage: omamobile-pinpad [--marker FILE] [--done PATH] [--font DIR] -- COMMAND...\n"
				"       omamobile-pinpad --charger | --power-off | --restart\n";

	if (write(2, u, sizeof(u) - 1) < 0)
		return;
}

int main(int argc, char **argv)
{
	const char *marker = NULL, *done = NULL, *fontdir = "/usr/share/omamobile-pinpad";
	const char *swap;
	int i;

	trace_on = getenv("PINPAD_TRACE") && !strcmp(getenv("PINPAD_TRACE"), "1");
	signal(SIGPIPE, SIG_IGN);
	/* A touch panel mirrored against the screen; none known yet (PR2) */
	swap = getenv("PINPAD_TOUCH_SWAP");
	if (swap)
		touch_swap = (strchr(swap, 'x') ? 1 : 0) | (strchr(swap, 'y') ? 2 : 0);
	if (argc == 2 && !strcmp(argv[1], "--charger"))
		return charger_main();
	if (argc == 2 && (!strcmp(argv[1], "--power-off") || !strcmp(argv[1], "--restart"))) {
		sync();
		reboot(!strcmp(argv[1], "--power-off") ? RB_POWER_OFF : RB_AUTOBOOT);
		warnx("reboot: %s", strerror(errno));
		return 1;
	}
	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--") && i + 1 < argc)
			return pad_main(marker, done, fontdir, argv + i + 1);
		if (i + 1 >= argc)
			break;
		if (!strcmp(argv[i], "--marker"))
			marker = argv[++i];
		else if (!strcmp(argv[i], "--done"))
			done = argv[++i];
		else if (!strcmp(argv[i], "--font"))
			fontdir = argv[++i];
		else
			break;
	}
	usage();
	return 1;
}
