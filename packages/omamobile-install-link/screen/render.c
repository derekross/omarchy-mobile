/* SPDX-License-Identifier: MIT */
/*
 * Drawing: the model's words in a centred column, in Omarchy's look as far
 * as a framebuffer goes: the theme's background and colours, Omarchy's
 * logo from its own icon font, and JetBrains Mono (the font Omarchy's
 * login screen uses), all from packages the root image carries:
 *
 *   ttf-jetbrains-mono-nerd-basic  /usr/share/fonts/TTF/JetBrainsMonoNerdFont-{Regular,Bold}.ttf
 *   omarchy-settings               /usr/share/omarchy/default/fonts/omarchy/omarchy.ttf (U+E900, the logo)
 *
 * with Noto Sans and DejaVu Sans as fallbacks for the text. Every size
 * follows the panel's: the column is laid out, measured, and shrunk until
 * it fits, and no line is wider than the panel, so nothing is clipped at
 * any size.
 */
#include <stdlib.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include "screen.h"

struct fonts {
	FT_Library lib;
	FT_Face regular, bold, logo;
};

static const char *regular_paths[] = {
	"/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
	"/usr/share/fonts/noto/NotoSans-Regular.ttf",
	"/usr/share/fonts/TTF/DejaVuSans.ttf",
	NULL,
};
static const char *bold_paths[] = {
	"/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf",
	"/usr/share/fonts/noto/NotoSans-Bold.ttf",
	"/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
	NULL,
};
static const char *logo_paths[] = {
	"/usr/share/omarchy/default/fonts/omarchy/omarchy.ttf",
	NULL,
};
#define LOGO_CHAR 0xE900

static FT_Face face_from(FT_Library lib, const char *want, const char **list)
{
	FT_Face face;

	if (want && *want)
		return FT_New_Face(lib, want, 0, &face) ? NULL : face;
	for (; *list; list++)
		if (!FT_New_Face(lib, *list, 0, &face))
			return face;
	return NULL;
}

struct fonts *fonts_open(const char *regular, const char *bold, const char *logo)
{
	struct fonts *f = calloc(1, sizeof(*f));

	if (!f || FT_Init_FreeType(&f->lib)) {
		free(f);
		return NULL;
	}
	f->regular = face_from(f->lib, regular, regular_paths);
	f->bold = face_from(f->lib, bold, bold_paths);
	if (!f->bold)
		f->bold = f->regular;
	f->logo = face_from(f->lib, logo, logo_paths);
	if (f->logo && !FT_Get_Char_Index(f->logo, LOGO_CHAR)) {
		FT_Done_Face(f->logo);
		f->logo = NULL;
	}
	return f;
}

int fonts_ok(const struct fonts *f)
{
	return f && f->regular;
}

void fonts_close(struct fonts *f)
{
	if (!f)
		return;
	if (f->logo)
		FT_Done_Face(f->logo);
	if (f->bold && f->bold != f->regular)
		FT_Done_Face(f->bold);
	if (f->regular)
		FT_Done_Face(f->regular);
	FT_Done_FreeType(f->lib);
	free(f);
}

/* ------------------------------------------------------------- drawing */

static void fill(struct canvas *c, uint32_t colour)
{
	for (int y = 0; y < c->h; y++) {
		uint32_t *row = c->px + (size_t)y * c->stride;
		for (int x = 0; x < c->w; x++)
			row[x] = colour;
	}
}

static void blend(struct canvas *c, const FT_Bitmap *bm, int x0, int y0, uint32_t colour)
{
	int sr = (colour >> 16) & 0xff, sg = (colour >> 8) & 0xff, sb = colour & 0xff;

	for (unsigned j = 0; j < bm->rows; j++) {
		int y = y0 + (int)j;
		if (y < 0 || y >= c->h)
			continue;
		const unsigned char *src = bm->buffer + (long)j * bm->pitch;
		uint32_t *row = c->px + (size_t)y * c->stride;
		for (unsigned i = 0; i < bm->width; i++) {
			int x = x0 + (int)i;
			unsigned a = src[i];
			if (x < 0 || x >= c->w || !a)
				continue;
			uint32_t d = row[x];
			int dr = (d >> 16) & 0xff, dg = (d >> 8) & 0xff, db = d & 0xff;
			dr += (int)((sr - dr) * (int)a / 255);
			dg += (int)((sg - dg) * (int)a / 255);
			db += (int)((sb - db) * (int)a / 255);
			row[x] = (uint32_t)dr << 16 | (uint32_t)dg << 8 | (uint32_t)db;
		}
	}
}

/* The next code point of a UTF-8 string (the screen's own words) */
static unsigned next_char(const char **s)
{
	const unsigned char *p = (const unsigned char *)*s;
	unsigned c = *p++;

	if (c >= 0xe0 && c < 0xf0 && p[0] && p[1]) {
		c = (c & 0x0f) << 12 | (p[0] & 0x3fu) << 6 | (p[1] & 0x3fu);
		p += 2;
	} else if (c >= 0xc0 && c < 0xe0 && p[0]) {
		c = (c & 0x1f) << 6 | (p[0] & 0x3fu);
		p += 1;
	}
	*s = (const char *)p;
	return c;
}

static int set_size(FT_Face face, int px)
{
	if (px < 4)
		px = 4;
	return FT_Set_Pixel_Sizes(face, 0, (FT_UInt)px) ? -1 : 0;
}

/* Width of n bytes of s at the face's current size */
static int measure(FT_Face face, const char *s, size_t n)
{
	const char *end = s + n;
	int w = 0;

	while (s < end && *s) {
		unsigned ch = next_char(&s);
		if (!FT_Load_Char(face, ch, FT_LOAD_DEFAULT))
			w += (int)(face->glyph->advance.x >> 6);
	}
	return w;
}

static void draw_run(struct canvas *c, FT_Face face, const char *s, size_t n, int x, int baseline, uint32_t colour)
{
	const char *end = s + n;

	while (s < end && *s) {
		unsigned ch = next_char(&s);
		if (FT_Load_Char(face, ch, FT_LOAD_RENDER))
			continue;
		FT_GlyphSlot g = face->glyph;
		blend(c, &g->bitmap, x + g->bitmap_left, baseline - g->bitmap_top, colour);
		x += (int)(g->advance.x >> 6);
	}
}

/* ------------------------------------------------------------- layout */

#define LINES_MAX 6
struct block {
	const char *what;
	FT_Face face;
	int px;           /* font size */
	uint32_t colour;
	const char *text; /* words, wrapped; NULL for the code and the logo */
	int is_code, is_logo;
	int gap;          /* space after it */
	/* worked out */
	int nlines;
	const char *line[LINES_MAX];
	size_t len[LINES_MAX];
	int asc, height, line_h;
};

/* Wrap b->text at spaces into lines no wider than max_w; 0 if it fits in
 * LINES_MAX lines with no word wider than max_w */
static int wrap(struct block *b, int max_w)
{
	const char *s = b->text;

	b->nlines = 0;
	while (*s) {
		while (*s == ' ')
			s++;
		if (!*s)
			break;
		if (b->nlines == LINES_MAX)
			return -1;
		const char *start = s, *fit = NULL;
		const char *p = s;
		for (;;) {
			const char *word_end = p;
			while (*word_end && *word_end != ' ')
				word_end++;
			if (measure(b->face, start, (size_t)(word_end - start)) > max_w)
				break;
			fit = word_end;
			if (!*word_end)
				break;
			p = word_end + 1;
		}
		if (!fit)
			return -1; /* one word wider than the line */
		b->line[b->nlines] = start;
		b->len[b->nlines] = (size_t)(fit - start);
		b->nlines++;
		s = fit;
	}
	return 0;
}

static int code_width(FT_Face face, const char *code)
{
	/* Two groups of three, a space between */
	int w = measure(face, code, CODE_LEN);
	return w + measure(face, " ", 1);
}

/* Size each block at scale s; 0 when everything fits the width */
static int measure_blocks(struct block *b, int n, int max_w, int min_px)
{
	for (int i = 0; i < n; i++) {
		for (;;) {
			if (set_size(b[i].face, b[i].px) < 0)
				return -1;
			int ok;
			if (b[i].is_logo) {
				ok = 1;
				b[i].nlines = 1;
			} else if (b[i].is_code) {
				ok = code_width(b[i].face, b[i].text) <= max_w;
				b[i].nlines = 1;
			} else {
				ok = wrap(&b[i], max_w) == 0;
			}
			if (ok || b[i].px <= min_px)
				break;
			b[i].px = b[i].px * 9 / 10;
		}
		FT_Size_Metrics *sm = &b[i].face->size->metrics;
		b[i].asc = (int)(sm->ascender >> 6);
		b[i].line_h = (int)((sm->ascender - sm->descender) >> 6);
		if (b[i].is_code || b[i].is_logo)
			b[i].height = b[i].line_h;
		else
			b[i].height = b[i].nlines * (b[i].line_h * 12 / 10) - b[i].line_h * 2 / 10;
	}
	return 0;
}

static uint32_t tone(const struct theme *th, enum tone t, uint32_t normal)
{
	switch (t) {
	case T_ACCENT:
		return th->accent;
	case T_WARN:
		return th->warn;
	case T_ERROR:
		return th->error;
	case T_MUTED:
		return th->muted;
	default:
		return normal;
	}
}

static void add_box(struct layout *l, const char *what, int x, int y, int w, int h)
{
	if (!l || l->n >= BOX_MAX)
		return;
	l->box[l->n++] = (struct box){ what, x, y, w, h };
}

void render(struct canvas *c, struct fonts *f, const struct theme *th, const struct model *m,
	    double now, int drift, int blank, struct layout *out)
{
	struct texts t;
	struct block b[6];
	int n = 0;

	if (out)
		memset(out, 0, sizeof(*out));
	fill(c, th->background);
	if (blank || !fonts_ok(f))
		return;
	model_texts(m, now, &t);

	/* u: the size everything follows. On a tall phone, the width; on a
	 * wide panel, the height, with no room for the logo */
	double u = c->w < c->h * 0.75 ? c->w : c->h * 0.75;
	int max_w = c->w * 86 / 100;
	memset(b, 0, sizeof(b));
	if (f->logo && c->h >= c->w)
		b[n++] = (struct block){ .what = "logo", .face = f->logo, .px = (int)(u * 0.16), .colour = th->foreground,
					 .is_logo = 1, .gap = (int)(u * 0.10) };
	b[n++] = (struct block){ .what = "title", .face = f->bold, .px = (int)(u * 0.056),
				 .colour = tone(th, t.title_tone, th->bright), .text = t.title, .gap = (int)(u * 0.08) };
	if (t.code)
		b[n++] = (struct block){ .what = "code", .face = f->bold, .px = (int)(u * 0.20), .colour = th->accent,
					 .text = t.code, .is_code = 1, .gap = (int)(u * 0.06) };
	if (t.sub)
		b[n++] = (struct block){ .what = "sub", .face = f->regular, .px = (int)(u * 0.044),
					 .colour = tone(th, t.sub_tone, th->foreground), .text = t.sub, .gap = (int)(u * 0.05) };
	if (t.note)
		b[n++] = (struct block){ .what = "note", .face = f->regular, .px = (int)(u * 0.044),
					 .colour = tone(th, t.note_tone, th->foreground), .text = t.note, .gap = (int)(u * 0.05) };
	if (t.hint)
		b[n++] = (struct block){ .what = "hint", .face = f->regular, .px = (int)(u * 0.036), .colour = th->muted,
					 .text = t.hint, .gap = 0 };
	b[n - 1].gap = 0;

	/* Lay out, then shrink the whole column until it fits the height */
	int total = 0;
	for (int pass = 0; pass < 6; pass++) {
		if (measure_blocks(b, n, max_w, 6) < 0)
			return;
		total = 0;
		for (int i = 0; i < n; i++)
			total += b[i].height + b[i].gap;
		if (total <= c->h * 90 / 100)
			break;
		double k = (double)c->h * 0.88 / total;
		for (int i = 0; i < n; i++) {
			b[i].px = (int)(b[i].px * k);
			b[i].gap = (int)(b[i].gap * k);
		}
	}

	int y = (c->h - total) / 2 + drift;
	if (y < 0)
		y = 0;
	if (y + total > c->h)
		y = c->h - total > 0 ? c->h - total : 0;
	for (int i = 0; i < n; i++) {
		set_size(b[i].face, b[i].px);
		if (b[i].is_logo) {
			if (!FT_Load_Char(b[i].face, LOGO_CHAR, FT_LOAD_RENDER)) {
				FT_GlyphSlot g = b[i].face->glyph;
				int gx = (c->w - (int)g->bitmap.width) / 2;
				int gy = y + b[i].asc - g->bitmap_top;
				blend(c, &g->bitmap, gx, gy, b[i].colour);
				add_box(out, "logo", gx, gy, (int)g->bitmap.width, (int)g->bitmap.rows);
			}
		} else if (b[i].is_code) {
			int w = code_width(b[i].face, b[i].text);
			int x = (c->w - w) / 2;
			int base = y + b[i].asc;
			int first = measure(b[i].face, b[i].text, 3) + measure(b[i].face, " ", 1);
			draw_run(c, b[i].face, b[i].text, 3, x, base, b[i].colour);
			draw_run(c, b[i].face, b[i].text + 3, 3, x + first, base, b[i].colour);
			add_box(out, "code", x, y, w, b[i].height);
			if (out) {
				/* The digits' own height: a digit's bitmap */
				if (!FT_Load_Char(b[i].face, '0', FT_LOAD_RENDER))
					out->code_px = (int)b[i].face->glyph->bitmap.rows;
			}
		} else {
			int ly = y;
			for (int k = 0; k < b[i].nlines; k++) {
				int w = measure(b[i].face, b[i].line[k], b[i].len[k]);
				int x = (c->w - w) / 2;
				draw_run(c, b[i].face, b[i].line[k], b[i].len[k], x, ly + b[i].asc, b[i].colour);
				add_box(out, b[i].what, x, ly, w, b[i].line_h);
				ly += b[i].line_h * 12 / 10;
			}
		}
		y += b[i].height + b[i].gap;
	}
}
