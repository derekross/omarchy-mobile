/* SPDX-License-Identifier: MIT */
/*
 * The second output: the kernel's framebuffer, /dev/fb0. It is there where
 * simpledrm still has the screen (or gs-decon runs with fbdev=1). Writes to
 * it reach a command-mode panel only through the fbdev emulation's damage
 * handling, which commits (and so triggers DECON); a pan to the same
 * offset after each frame asks for that commit. While it is drawn, the VT
 * is put in graphics mode so the console's text and cursor stay off the
 * picture, and it is put back at the end.
 *
 * A framebuffer whose DRM device another program holds as master shows
 * nothing of what is written to it, so main.c tries Plymouth first then.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/kd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include "screen.h"

struct fb_out {
	int fd;
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	uint8_t *map;
	size_t size;
};

static int vt_fd = -1;
static int vt_mode = -1;

void vt_graphics(void)
{
	if (vt_fd >= 0)
		return;
	vt_fd = open("/dev/tty0", O_RDWR | O_CLOEXEC | O_NOCTTY);
	if (vt_fd < 0)
		return;
	int mode;
	if (ioctl(vt_fd, KDGETMODE, &mode) == 0 && ioctl(vt_fd, KDSETMODE, KD_GRAPHICS) == 0) {
		vt_mode = mode;
		return;
	}
	close(vt_fd);
	vt_fd = -1;
}

void vt_restore(void)
{
	if (vt_fd < 0)
		return;
	if (vt_mode >= 0)
		ioctl(vt_fd, KDSETMODE, vt_mode);
	close(vt_fd);
	vt_fd = -1;
	vt_mode = -1;
}

int fb_open(struct output *o)
{
	struct fb_out *f = calloc(1, sizeof(*f));

	if (!f)
		return -1;
	f->fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
	if (f->fd < 0)
		goto fail;
	if (ioctl(f->fd, FBIOGET_VSCREENINFO, &f->var) || ioctl(f->fd, FBIOGET_FSCREENINFO, &f->fix))
		goto fail;
	if ((f->var.bits_per_pixel != 32 && f->var.bits_per_pixel != 16) || f->var.xres == 0 || f->var.yres == 0) {
		errno = ENOTSUP;
		goto fail;
	}
	f->size = (size_t)f->fix.line_length * f->var.yres_virtual;
	f->map = mmap(NULL, f->size, PROT_READ | PROT_WRITE, MAP_SHARED, f->fd, 0);
	if (f->map == MAP_FAILED) {
		f->map = NULL;
		goto fail;
	}
	o->shadow.w = (int)f->var.xres;
	o->shadow.h = (int)f->var.yres;
	o->shadow.stride = o->shadow.w;
	o->shadow.px = calloc((size_t)o->shadow.w * o->shadow.h, 4);
	if (!o->shadow.px)
		goto fail;
	o->fb = f;
	o->kind = OUT_FB;
	vt_graphics();
	say("output: /dev/fb0, %ux%u, %u bits", f->var.xres, f->var.yres, f->var.bits_per_pixel);
	return 0;
fail:
	if (f->map)
		munmap(f->map, f->size);
	if (f->fd >= 0)
		close(f->fd);
	free(f);
	return -1;
}

static uint32_t pack(const struct fb_var_screeninfo *v, uint32_t c)
{
	uint32_t r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff;

	r >>= 8 - v->red.length;
	g >>= 8 - v->green.length;
	b >>= 8 - v->blue.length;
	return r << v->red.offset | g << v->green.offset | b << v->blue.offset;
}

int fb_present(struct output *o)
{
	struct fb_out *f = o->fb;
	const struct fb_var_screeninfo *v = &f->var;
	int plain = v->bits_per_pixel == 32 && v->red.offset == 16 && v->green.offset == 8 && v->blue.offset == 0;

	for (int y = 0; y < o->shadow.h; y++) {
		uint8_t *row = f->map + (size_t)(y + v->yoffset) * f->fix.line_length + (size_t)v->xoffset * (v->bits_per_pixel / 8);
		const uint32_t *src = o->shadow.px + (size_t)y * o->shadow.stride;
		if (plain) {
			memcpy(row, src, (size_t)o->shadow.w * 4);
		} else if (v->bits_per_pixel == 32) {
			for (int x = 0; x < o->shadow.w; x++)
				((uint32_t *)row)[x] = pack(v, src[x]);
		} else {
			for (int x = 0; x < o->shadow.w; x++)
				((uint16_t *)row)[x] = (uint16_t)pack(v, src[x]);
		}
	}
	/* Ask the emulation for a commit: a command-mode panel needs one */
	struct fb_var_screeninfo pan = *v;
	ioctl(f->fd, FBIOPAN_DISPLAY, &pan);
	return 0;
}

void fb_close(struct output *o)
{
	struct fb_out *f = o->fb;

	if (!f)
		return;
	munmap(f->map, f->size);
	close(f->fd);
	free(f);
	o->fb = NULL;
	if (o->shadow.px) {
		explicit_bzero(o->shadow.px, (size_t)o->shadow.w * o->shadow.h * 4);
		free(o->shadow.px);
	}
	memset(&o->shadow, 0, sizeof(o->shadow));
	o->kind = OUT_NONE;
	vt_restore();
}
