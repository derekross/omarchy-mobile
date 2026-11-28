/*
 * Drawing for Tactus: panel, keys, labels and icons.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <cairo.h>
#include <glib-object.h>
#include <pango/pangocairo.h>

G_BEGIN_DECLS

typedef struct {
  double r, g, b;
} TactusRgb;

typedef struct {
  gboolean  dark;
  TactusRgb panel;
  TactusRgb key;
  TactusRgb key_pressed;
  TactusRgb text;
  TactusRgb icon;
  TactusRgb popup;
  TactusRgb popup_selected;
  /* the emoji page's search field, its hint, the kinds' signs and the disc
   * behind the one in view */
  TactusRgb field;
  TactusRgb hint;
  TactusRgb sign;
  TactusRgb disc;
  /* the caret */
  TactusRgb accent;
} TactusTheme;

typedef enum {
  TACTUS_SHIFT_OFF,
  TACTUS_SHIFT_ON,
  TACTUS_SHIFT_LOCKED,
} TactusShiftState;

/* How a label sits on its key: the band of the letter that is centred */
typedef enum {
  TACTUS_BAND_X_HEIGHT,   /* lowercase letters */
  TACTUS_BAND_CAP_HEIGHT, /* capitals, digits, punctuation */
} TactusBand;

void   tactus_theme_init      (TactusTheme *theme, gboolean dark);
void   tactus_theme_watch     (gpointer instance, GCallback changed);
char  *tactus_theme_css       (const TactusTheme *theme);
void   tactus_set_source      (cairo_t *cr, const TactusRgb *rgb, double alpha);
void   tactus_rounded_rect    (cairo_t *cr, double x, double y, double w, double h, double r);
int    tactus_panel_under     (double scale);
void   tactus_panel_path      (cairo_t *cr, double x, double y, double w, double h, double scale);
void   tactus_draw_label      (cairo_t         *cr,
                               const char      *text,
                               double           cx,
                               double           cy,
                               double           size_px,
                               int              weight,
                               TactusBand       band,
                               const TactusRgb *rgb);
void   tactus_icon_shift      (cairo_t *cr, double cx, double cy, double scale, TactusShiftState state);
void   tactus_icon_delete     (cairo_t *cr, double cx, double cy, double scale, gboolean filled,
                               const TactusRgb *cutout);
void   tactus_icon_return     (cairo_t *cr, double cx, double cy, double scale);
void   tactus_icon_emoji      (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                               double alpha);
void   tactus_icon_paste      (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                               double alpha);
void   tactus_icon_mic        (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                               double alpha);

/* The emoji page: what its kinds of emoji are, in the order of their signs */
typedef enum {
  TACTUS_KIND_RECENT,
  TACTUS_KIND_SMILEYS,
  TACTUS_KIND_ANIMALS,
  TACTUS_KIND_FOOD,
  TACTUS_KIND_ACTIVITY,
  TACTUS_KIND_TRAVEL,
  TACTUS_KIND_OBJECTS,
  TACTUS_KIND_SYMBOLS,
  TACTUS_KIND_FLAGS,
  TACTUS_N_KINDS,
} TactusKind;

void   tactus_icon_kind       (cairo_t *cr, TactusKind kind, double cx, double cy, double scale,
                               const TactusRgb *rgb);
void   tactus_icon_magnifier  (cairo_t *cr, double cx, double cy, double scale, const TactusRgb *rgb);
void   tactus_icon_clear      (cairo_t *cr, double cx, double cy, double scale, const TactusRgb *disc,
                               const TactusRgb *cross);
void   tactus_draw_emoji      (cairo_t *cr, const char *emoji, double cx, double cy, double size_px,
                               double alpha);
double tactus_emoji_font_size (cairo_t *cr, double ink_px);

G_END_DECLS
