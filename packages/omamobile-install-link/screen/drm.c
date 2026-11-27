/* SPDX-License-Identifier: MIT */
/*
 * The first output: a DRM device, as Plymouth uses it before any session.
 *
 * On the Pixel 7 Pro, gs-decon (KMS, stage 2 by default) replaces
 * simpledrm a few seconds into the boot and registers no fbdev console
 * unless gs_decon.fbdev=1 (DISPLAY-PLAN "Default KMS and the boot
 * handover"), so /dev/fb0 is usually gone by the time the root runs: a DRM
 * client is the way to the panel there. Plymouth opens gs-decon the same
 * way, with no compositor. The panel is a DSI command-mode panel: a frame
 * reaches it only on a DECON trigger, which a commit gives. So every
 * update is a commit (a page flip between two dumb buffers, or a legacy
 * SetCrtc where the flip is refused), never a write into a buffer already
 * on screen.
 *
 * It needs DRM master: free once Plymouth has quit (plymouth-quit runs
 * before multi-user.target, which the link's unit follows). On close the
 * screen is drawn blank first, then master is dropped and the device
 * closed, so the display manager finds it free and no code is left on a
 * panel whose driver keeps the last frame.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include "screen.h"

struct dumb {
	uint32_t handle, fb, pitch;
	uint64_t size;
	uint8_t *map;
};

struct drm_out {
	int fd;
	char path[32];
	uint32_t crtc, conn;
	drmModeModeInfo mode;
	struct dumb buf[2];
	int front;    /* the buffer on screen, -1 before the first frame */
	int pending;  /* a flip is on its way */
	int no_flip;  /* the driver refused a flip: SetCrtc each time */
};

static void dumb_free(int fd, struct dumb *d)
{
	if (d->map)
		munmap(d->map, d->size);
	if (d->fb)
		drmModeRmFB(fd, d->fb);
	if (d->handle) {
		struct drm_mode_destroy_dumb dd = { .handle = d->handle };
		drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dd);
	}
	memset(d, 0, sizeof(*d));
}

static int dumb_alloc(int fd, struct dumb *d, int w, int h)
{
	struct drm_mode_create_dumb cd = { .width = (uint32_t)w, .height = (uint32_t)h, .bpp = 32 };
	struct drm_mode_map_dumb md = { 0 };

	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd))
		return -1;
	d->handle = cd.handle;
	d->pitch = cd.pitch;
	d->size = cd.size;
	if (drmModeAddFB(fd, (uint32_t)w, (uint32_t)h, 24, 32, d->pitch, d->handle, &d->fb))
		goto fail;
	md.handle = d->handle;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md))
		goto fail;
	d->map = mmap(NULL, d->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)md.offset);
	if (d->map == MAP_FAILED) {
		d->map = NULL;
		goto fail;
	}
	return 0;
fail:
	dumb_free(fd, d);
	return -1;
}

/* A connected connector, its CRTC and its mode: the one on screen now if
 * there is one (Plymouth's), so the panel's mode does not change */
static int pick(int fd, struct drm_out *d)
{
	drmModeRes *res = drmModeGetResources(fd);
	int found = 0;

	if (!res)
		return 0;
	for (int i = 0; i < res->count_connectors && !found; i++) {
		drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
		if (!c)
			continue;
		if (c->connection != DRM_MODE_CONNECTED || c->count_modes == 0) {
			drmModeFreeConnector(c);
			continue;
		}
		uint32_t crtc = 0;
		drmModeEncoder *e = c->encoder_id ? drmModeGetEncoder(fd, c->encoder_id) : NULL;
		if (e && e->crtc_id)
			crtc = e->crtc_id;
		for (int k = 0; !crtc && k < c->count_encoders; k++) {
			drmModeEncoder *pe = drmModeGetEncoder(fd, c->encoders[k]);
			if (!pe)
				continue;
			for (int j = 0; j < res->count_crtcs; j++)
				if (pe->possible_crtcs & (1u << j)) {
					crtc = res->crtcs[j];
					break;
				}
			drmModeFreeEncoder(pe);
		}
		if (e)
			drmModeFreeEncoder(e);
		if (crtc) {
			drmModeCrtc *cur = drmModeGetCrtc(fd, crtc);
			int m = 0;
			for (int j = 0; j < c->count_modes; j++)
				if (c->modes[j].type & DRM_MODE_TYPE_PREFERRED) {
					m = j;
					break;
				}
			d->mode = c->modes[m];
			if (cur && cur->mode_valid)
				d->mode = cur->mode;
			if (cur)
				drmModeFreeCrtc(cur);
			d->crtc = crtc;
			d->conn = c->connector_id;
			found = 1;
		}
		drmModeFreeConnector(c);
	}
	drmModeFreeResources(res);
	return found;
}

int drm_open(struct output *o)
{
	int busy = 0;

	for (int i = 0; i < 8; i++) {
		struct drm_out *d = calloc(1, sizeof(*d));
		if (!d)
			return -1;
		snprintf(d->path, sizeof(d->path), "/dev/dri/card%d", i);
		d->fd = open(d->path, O_RDWR | O_CLOEXEC | O_NONBLOCK);
		if (d->fd < 0) {
			free(d);
			continue;
		}
		if (!pick(d->fd, d)) {
			close(d->fd);
			free(d);
			continue;
		}
		/* The first to open a device with no master is its master */
		if (!drmIsMaster(d->fd) && drmSetMaster(d->fd)) {
			busy = 1;
			close(d->fd);
			free(d);
			continue;
		}
		int w = d->mode.hdisplay, h = d->mode.vdisplay;
		if (dumb_alloc(d->fd, &d->buf[0], w, h) || dumb_alloc(d->fd, &d->buf[1], w, h)) {
			dumb_free(d->fd, &d->buf[0]);
			drmDropMaster(d->fd);
			close(d->fd);
			free(d);
			continue;
		}
		o->shadow.px = calloc((size_t)w * h, 4);
		if (!o->shadow.px) {
			dumb_free(d->fd, &d->buf[0]);
			dumb_free(d->fd, &d->buf[1]);
			close(d->fd);
			free(d);
			return -1;
		}
		o->shadow.w = w;
		o->shadow.h = h;
		o->shadow.stride = w;
		d->front = -1;
		o->drm = d;
		o->kind = OUT_DRM;
		say("output: %s, %dx%d at %u Hz", d->path, w, h, d->mode.vrefresh);
		return 0;
	}
	errno = busy ? EBUSY : ENODEV;
	return -1;
}

int drm_fd(const struct output *o)
{
	return o->drm ? o->drm->fd : -1;
}

int drm_busy(const struct output *o)
{
	return o->drm && o->drm->pending;
}

static void flipped(int fd, unsigned seq, unsigned s, unsigned us, void *data)
{
	(void)fd;
	(void)seq;
	(void)s;
	(void)us;
	((struct drm_out *)data)->pending = 0;
}

void drm_event(struct output *o)
{
	drmEventContext ev = { .version = 2, .page_flip_handler = flipped };

	if (o->drm)
		drmHandleEvent(o->drm->fd, &ev);
}

int drm_present(struct output *o)
{
	struct drm_out *d = o->drm;
	int back = d->front == 0 ? 1 : 0;
	struct dumb *b = &d->buf[back];

	for (int y = 0; y < o->shadow.h; y++)
		memcpy(b->map + (size_t)y * b->pitch, o->shadow.px + (size_t)y * o->shadow.stride, (size_t)o->shadow.w * 4);
	if (d->front >= 0 && !d->no_flip) {
		if (!drmModePageFlip(d->fd, d->crtc, b->fb, DRM_MODE_PAGE_FLIP_EVENT, d)) {
			d->pending = 1;
			d->front = back;
			return 0;
		}
		say("output: the driver refused a page flip (%s); a mode set for each frame", strerror(errno));
		d->no_flip = 1;
	}
	if (drmModeSetCrtc(d->fd, d->crtc, b->fb, 0, 0, &d->conn, 1, &d->mode)) {
		say("output: %s: mode set failed (%s)", d->path, strerror(errno));
		return -1;
	}
	/* A driver that wants to be told what changed (harmless otherwise) */
	drmModeDirtyFB(d->fd, b->fb, NULL, 0);
	d->front = back;
	return 0;
}

void drm_close(struct output *o)
{
	struct drm_out *d = o->drm;

	if (!d)
		return;
	/* Wait for a flip on its way (the blank frame), at most 200 ms */
	for (int i = 0; i < 20 && d->pending; i++) {
		struct pollfd p = { .fd = d->fd, .events = POLLIN };
		if (poll(&p, 1, 10) > 0)
			drm_event(o);
	}
	/* Wipe both buffers before they go back to the kernel */
	for (int i = 0; i < 2; i++)
		if (d->buf[i].map)
			explicit_bzero(d->buf[i].map, d->buf[i].size);
	dumb_free(d->fd, &d->buf[0]);
	dumb_free(d->fd, &d->buf[1]);
	drmDropMaster(d->fd);
	close(d->fd);
	free(d);
	o->drm = NULL;
	if (o->shadow.px) {
		explicit_bzero(o->shadow.px, (size_t)o->shadow.w * o->shadow.h * 4);
		free(o->shadow.px);
	}
	memset(&o->shadow, 0, sizeof(o->shadow));
	o->kind = OUT_NONE;
}
