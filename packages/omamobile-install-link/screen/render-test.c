/* SPDX-License-Identifier: MIT */
/*
 * Test only, never installed: draw the screen for a list of the daemon's
 * lines into memory and save it as a PNG, with where each thing went.
 *
 *   render-test WxH OUT.png [--disconnected] [--theme F] < lines
 *
 * Prints `size W H`, one `box WHAT X Y W H` per line of text, and
 * `code_px N` (a digit's height) for test/all's checks.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include "screen.h"

void say(const char *fmt, ...)
{
	(void)fmt;
}

static void be32(unsigned char *p, uint32_t v)
{
	p[0] = (unsigned char)(v >> 24);
	p[1] = (unsigned char)(v >> 16);
	p[2] = (unsigned char)(v >> 8);
	p[3] = (unsigned char)v;
}

static void chunk(FILE *f, const char *type, const unsigned char *data, uint32_t len)
{
	unsigned char hdr[8];
	be32(hdr, len);
	memcpy(hdr + 4, type, 4);
	fwrite(hdr, 1, 8, f);
	if (len)
		fwrite(data, 1, len, f);
	uLong crc = crc32(0, (const Bytef *)type, 4);
	crc = crc32(crc, data, len);
	unsigned char c[4];
	be32(c, (uint32_t)crc);
	fwrite(c, 1, 4, f);
}

static int png(const char *path, const struct canvas *c)
{
	size_t raw_len = (size_t)c->h * (1 + (size_t)c->w * 3);
	unsigned char *raw = malloc(raw_len), *z;
	uLongf zlen = compressBound(raw_len);
	FILE *f;

	if (!raw)
		return -1;
	for (int y = 0; y < c->h; y++) {
		unsigned char *r = raw + (size_t)y * (1 + (size_t)c->w * 3);
		*r++ = 0;
		for (int x = 0; x < c->w; x++) {
			uint32_t p = c->px[(size_t)y * c->stride + x];
			*r++ = (unsigned char)(p >> 16);
			*r++ = (unsigned char)(p >> 8);
			*r++ = (unsigned char)p;
		}
	}
	z = malloc(zlen);
	if (!z || compress2(z, &zlen, raw, raw_len, 6) != Z_OK)
		return -1;
	f = fopen(path, "wb");
	if (!f)
		return -1;
	unsigned char ihdr[13];
	be32(ihdr, (uint32_t)c->w);
	be32(ihdr + 4, (uint32_t)c->h);
	ihdr[8] = 8;
	ihdr[9] = 2;
	ihdr[10] = ihdr[11] = ihdr[12] = 0;
	fwrite("\x89PNG\r\n\x1a\n", 1, 8, f);
	chunk(f, "IHDR", ihdr, 13);
	chunk(f, "IDAT", z, (uint32_t)zlen);
	chunk(f, "IEND", NULL, 0);
	free(raw);
	free(z);
	return fclose(f);
}

int main(int argc, char **argv)
{
	struct model m;
	struct theme th;
	struct canvas c;
	struct layout l;
	const char *theme = NULL;
	int connected = 1;
	char line[256];

	if (argc < 3 || sscanf(argv[1], "%dx%d", &c.w, &c.h) != 2 || c.w <= 0 || c.h <= 0) {
		fprintf(stderr, "usage: render-test WxH OUT.png [--disconnected] [--theme F] < lines\n");
		return 2;
	}
	for (int i = 3; i < argc; i++) {
		if (!strcmp(argv[i], "--disconnected"))
			connected = 0;
		else if (!strcmp(argv[i], "--theme") && i + 1 < argc)
			theme = argv[++i];
	}
	c.stride = c.w;
	c.px = calloc((size_t)c.w * c.h, 4);
	model_init(&m);
	if (connected)
		model_connected(&m);
	while (fgets(line, sizeof(line), stdin)) {
		size_t n = strcspn(line, "\n");
		if (model_line(&m, line, n, 100.0) != L_CHANGED) {
			fprintf(stderr, "render-test: a line the model ignored\n");
			return 1;
		}
	}
	theme_load(&th, theme);
	struct fonts *f = fonts_open(getenv("RT_FONT"), getenv("RT_BOLD"), getenv("RT_LOGO"));
	if (!fonts_ok(f)) {
		fprintf(stderr, "render-test: no font\n");
		return 3;
	}
	render(&c, f, &th, &m, 100.0, 0, 0, &l);
	printf("size %d %d\n", c.w, c.h);
	for (int i = 0; i < l.n; i++)
		printf("box %s %d %d %d %d\n", l.box[i].what, l.box[i].x, l.box[i].y, l.box[i].w, l.box[i].h);
	printf("code_px %d\n", l.code_px);
	printf("background %06x\n", c.px[0] & 0xffffff);
	fonts_close(f);
	return png(argv[2], &c) ? 1 : 0;
}
