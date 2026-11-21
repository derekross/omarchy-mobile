/*
 * Draws Tactus's look to a PNG, with no window: a check of the
 * drawing code (panel, keys, labels, icons) against reference pictures.
 *
 *   tactus-draw-test OUT.png [light|dark] [lower|upper] [width]
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-draw.h"

#include <string.h>
#include <stdlib.h>

int
main (int argc, char **argv)
{
  const char *out = argc > 1 ? argv[1] : "tactus-draw-test.png";
  gboolean dark = argc > 2 && strcmp (argv[2], "dark") == 0;
  gboolean upper = argc > 3 && strcmp (argv[3], "upper") == 0;
  double W = argc > 4 ? atof (argv[4]) : 360.0;
  const int device_scale = 3;
  const double s = W / 390.0, vs = MIN (W, 430.0) / 390.0;
  const double inset = 3.5 * s, cell = (W - 2 * inset) / 10.0;
  const double gap_h = 6.5 * vs, key_h = 43 * vs, pitch = 54 * vs, top_pad = 12 * vs;
  const double strip_h = 71.5 * vs, overhang = 20;
  const double H = overhang + top_pad + 3 * pitch + key_h + strip_h;
  const char *rows[3] = { "qwertyuiop", "asdfghjkl", "zxcvbnm" };
  const double offs[3] = { 0.0, 0.5, 1.5 };
  TactusTheme theme;
  cairo_surface_t *surface;
  cairo_t *cr;
  double y;

  tactus_theme_init (&theme, dark);
  surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, (int) (W * device_scale),
                                        (int) (H * device_scale + 0.5));
  cr = cairo_create (surface);
  cairo_scale (cr, device_scale, device_scale);

  /* what is behind the keyboard */
  cairo_set_source_rgb (cr, dark ? 0 : 1, dark ? 0 : 1, dark ? 0 : 1);
  cairo_paint (cr);

  tactus_panel_path (cr, 0, overhang, W, H - overhang, vs);
  tactus_set_source (cr, &theme.panel, 1.0);
  cairo_fill (cr);

  for (int r = 0; r < 3; r++) {
    y = overhang + top_pad + r * pitch;
    for (int i = 0; rows[r][i]; i++) {
      char label[2] = { upper ? g_ascii_toupper (rows[r][i]) : rows[r][i], 0 };
      double x = inset + (offs[r] + i) * cell + gap_h / 2;

      if (!dark) {
        tactus_rounded_rect (cr, x, y + 1.0, cell - gap_h, key_h, 6.8 * vs);
        cairo_set_source_rgba (cr, 0, 0, 0, 0.06);
        cairo_fill (cr);
      }
      tactus_rounded_rect (cr, x, y, cell - gap_h, key_h, 6.8 * vs);
      tactus_set_source (cr, &theme.key, 1.0);
      cairo_fill (cr);
      tactus_draw_label (cr, label, x + (cell - gap_h) / 2, y + key_h / 2 - (upper ? 1.4 * vs : 0),
                         (upper ? 21.1 : 23.85) * vs, upper ? 420 : 360,
                         upper ? TACTUS_BAND_CAP_HEIGHT : TACTUS_BAND_X_HEIGHT, &theme.text);
    }
  }
  /* shift and delete */
  y = overhang + top_pad + 2 * pitch;
  {
    double sw = 1.5 * cell - gap_h - 7.8 * s;
    double x = inset + gap_h / 2;

    tactus_rounded_rect (cr, x, y, sw, key_h, 6.8 * vs);
    tactus_set_source (cr, &theme.key, 1.0);
    cairo_fill (cr);
    tactus_set_source (cr, &theme.icon, 1.0);
    tactus_icon_shift (cr, x + sw / 2, y + key_h / 2, vs, upper ? TACTUS_SHIFT_ON : TACTUS_SHIFT_OFF);

    x = W - inset - gap_h / 2 - sw;
    tactus_rounded_rect (cr, x, y, sw, key_h, 6.8 * vs);
    tactus_set_source (cr, &theme.key, 1.0);
    cairo_fill (cr);
    tactus_set_source (cr, &theme.icon, 1.0);
    tactus_icon_delete (cr, x + sw / 2, y + key_h / 2, vs, FALSE, NULL);
  }
  /* bottom row */
  y = overhang + top_pad + 3 * pitch;
  {
    double tw = 2.5 * cell - gap_h;
    double x = inset + gap_h / 2;

    tactus_rounded_rect (cr, x, y, tw, key_h, 6.8 * vs);
    tactus_set_source (cr, &theme.key, 1.0);
    cairo_fill (cr);
    tactus_draw_label (cr, "123", x + tw / 2, y + key_h / 2 - 1.0 * vs, 18.3 * vs, 400,
                       TACTUS_BAND_CAP_HEIGHT, &theme.text);

    x = inset + 2.5 * cell + gap_h / 2;
    tactus_rounded_rect (cr, x, y, 5 * cell - gap_h, key_h, 6.8 * vs);
    tactus_set_source (cr, &theme.key, 1.0);
    cairo_fill (cr);

    x = inset + 7.5 * cell + gap_h / 2;
    tactus_rounded_rect (cr, x, y, tw, key_h, 6.8 * vs);
    tactus_set_source (cr, &theme.key, 1.0);
    cairo_fill (cr);
    tactus_set_source (cr, &theme.icon, 1.0);
    tactus_icon_return (cr, x + tw / 2, y + key_h / 2, vs);
  }
  /* the strip */
  y = overhang + top_pad + 3 * pitch + key_h;
  tactus_icon_emoji (cr, 42.2 * s, y + 38.2 * vs, vs, &theme, 1.0);
  tactus_icon_mic (cr, W - 42.8 * s, y + 37.3 * vs, vs, &theme, 1.0);

  cairo_destroy (cr);
  cairo_surface_write_to_png (surface, out);
  cairo_surface_destroy (surface);
  return 0;
}
