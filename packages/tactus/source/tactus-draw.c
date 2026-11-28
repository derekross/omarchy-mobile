/*
 * Drawing for Tactus: panel, keys, labels and icons.
 *
 * Everything here is drawn from measurements in points (1 pt of a 390 pt wide
 * phone) and scaled by the caller's factor, so the keyboard keeps its
 * proportions on any width.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-draw.h"

#include <gio/gio.h>
#include <math.h>
#include <string.h>

#define TACTUS_FONT_FAMILY "Adwaita Sans, Inter, Noto Sans, sans-serif"
/* The share of the font size taken by the lowercase letters and by the capitals (Inter) */
#define TACTUS_X_HEIGHT   0.546
#define TACTUS_CAP_HEIGHT 0.727
/* Icon stroke, in points */
#define TACTUS_STROKE 1.7


static TactusRgb
mix (TactusRgb a, TactusRgb b, double amount)
{
  return (TactusRgb) { a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount, a.b + (b.b - a.b) * amount };
}


/* The colours that follow from the panel, the keys and the text */
static void
derive (TactusTheme *theme)
{
  theme->field = mix (theme->panel, theme->key, 0.45);
  theme->hint  = mix (theme->text, theme->panel, 0.45);
  theme->sign  = mix (theme->text, theme->panel, 0.2);
  theme->disc  = mix (theme->panel, theme->text, 0.14);
}


static char *
state_file (const char *name)
{
  const char *state = g_getenv ("XDG_STATE_HOME");

  if (state && *state)
    return g_build_filename (state, "omarchy", "current", name, NULL);
  return g_build_filename (g_get_home_dir (), ".local", "state", "omarchy", "current", name, NULL);
}


static gboolean
parse_hex (const char *text, TactusRgb *rgb)
{
  guint v[3];
  size_t n;

  if (!text)
    return FALSE;
  if (*text == '#')
    text++;
  n = strlen (text);
  if (n != 6 || strspn (text, "0123456789abcdefABCDEF") != 6)
    return FALSE;
  for (int i = 0; i < 3; i++) {
    char two[3] = { text[2 * i], text[2 * i + 1], 0 };

    v[i] = (guint) g_ascii_strtoull (two, NULL, 16);
  }
  *rgb = (TactusRgb) { v[0] / 255.0, v[1] / 255.0, v[2] / 255.0 };
  return TRUE;
}


/*
 * The applied Omarchy theme's colours (its colors.toml: background,
 * foreground, accent and their variants, and the mode), as
 * omamobile-keyboard-theme reads them for squeekboard: the panel in the
 * theme's darker background, the keys in its lighter one, the text in its
 * foreground. FALSE when there is no such file, or the owner keeps Tactus's
 * own colours ($XDG_CONFIG_HOME/tactus/own-colours).
 */
static gboolean
theme_from_omarchy (TactusTheme *theme)
{
  g_autofree char *own = g_build_filename (g_get_user_config_dir (), "tactus", "own-colours", NULL);
  g_autofree char *path = NULL;
  g_autofree char *text = NULL;
  g_auto (GStrv) lines = NULL;
  g_autoptr (GHashTable) values = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, g_free);
  TactusRgb bg, fg, lighter, darker;
  const char *mode;

  if (g_file_test (own, G_FILE_TEST_EXISTS))
    return FALSE;
  path = g_strdup (g_getenv ("TACTUS_THEME_COLORS"));
  if (path == NULL || *path == '\0') {
    g_free (path);
    path = state_file ("theme" G_DIR_SEPARATOR_S "colors.toml");
  }
  if (!g_file_get_contents (path, &text, NULL, NULL))
    return FALSE;

  lines = g_strsplit (text, "\n", -1);
  for (int i = 0; lines[i]; i++) {
    g_auto (GStrv) kv = g_strsplit (lines[i], "=", 2);
    char *key, *value;

    if (!kv[0] || !kv[1])
      continue;
    key = g_strstrip (kv[0]);
    value = g_strstrip (kv[1]);
    if (*key == '#' || *key == '\0')
      continue;
    if (*value == '"') {
      char *end = strchr (value + 1, '"');

      if (!end)
        continue;
      *end = '\0';
      value++;
    }
    g_hash_table_replace (values, g_strdup (key), g_strdup (value));
  }

  if (!parse_hex (g_hash_table_lookup (values, "background"), &bg) ||
      !parse_hex (g_hash_table_lookup (values, "foreground"), &fg))
    return FALSE;
  mode = g_hash_table_lookup (values, "mode");
  theme->dark = g_strcmp0 (mode, "light") != 0;
  if (!parse_hex (g_hash_table_lookup (values, "lighter_background"), &lighter))
    lighter = mix (bg, fg, 0.08);
  if (!parse_hex (g_hash_table_lookup (values, "dark_background"), &darker))
    darker = mix (bg, theme->dark ? (TactusRgb) { 0, 0, 0 } : (TactusRgb) { 1, 1, 1 }, 0.2);

  theme->panel          = darker;
  theme->key            = lighter;
  theme->key_pressed    = mix (lighter, fg, 0.28);
  theme->text           = fg;
  theme->icon           = fg;
  theme->popup          = mix (lighter, fg, 0.10);
  theme->popup_selected = mix (lighter, fg, 0.30);
  derive (theme);
  if (!parse_hex (g_hash_table_lookup (values, "accent"), &theme->accent) &&
      !parse_hex (g_hash_table_lookup (values, "blue"), &theme->accent))
    theme->accent = fg;
  if (parse_hex (g_hash_table_lookup (values, "muted"), &theme->hint))
    theme->hint = mix (theme->hint, fg, 0.25);
  return TRUE;
}


/**
 * tactus_theme_init:
 * @theme: The keyboard's colours, filled in
 * @dark: Whether the desktop asks for dark (used without an Omarchy theme)
 *
 * The applied Omarchy theme's colours when there is one, else Tactus's own
 * light or dark ones.
 */
void
tactus_theme_init (TactusTheme *theme, gboolean dark)
{
  if (theme_from_omarchy (theme))
    return;

  theme->dark = dark;
  if (dark) {
    theme->panel          = (TactusRgb){  31 / 255.0,  31 / 255.0,  31 / 255.0 };
    theme->key            = (TactusRgb){  67 / 255.0,  67 / 255.0,  67 / 255.0 };
    theme->key_pressed    = (TactusRgb){ 100 / 255.0, 100 / 255.0, 102 / 255.0 };
    theme->text           = (TactusRgb){ 1.0, 1.0, 1.0 };
    theme->icon           = (TactusRgb){ 1.0, 1.0, 1.0 };
    theme->popup          = (TactusRgb){  58 / 255.0,  58 / 255.0,  60 / 255.0 };
    theme->popup_selected = (TactusRgb){ 104 / 255.0, 104 / 255.0, 108 / 255.0 };
  } else {
    theme->panel          = (TactusRgb){ 226 / 255.0, 227 / 255.0, 232 / 255.0 };
    theme->key            = (TactusRgb){ 253 / 255.0, 253 / 255.0, 255 / 255.0 };
    theme->key_pressed    = (TactusRgb){ 232 / 255.0, 233 / 255.0, 236 / 255.0 };
    theme->text           = (TactusRgb){ 0.0, 0.0, 0.0 };
    theme->icon           = (TactusRgb){  20 / 255.0,  20 / 255.0,  22 / 255.0 };
    theme->popup          = (TactusRgb){ 249 / 255.0, 249 / 255.0, 251 / 255.0 };
    theme->popup_selected = (TactusRgb){ 184 / 255.0, 185 / 255.0, 188 / 255.0 };
  }
  derive (theme);
  theme->accent = (TactusRgb) { 0.0, 0.478, 1.0 };
  /* Tactus's own: the emoji page as it was drawn before these came from here */
  if (dark) {
    theme->field = (TactusRgb) {  44 / 255.0,  44 / 255.0,  46 / 255.0 };
    theme->hint  = (TactusRgb) { 152 / 255.0, 152 / 255.0, 159 / 255.0 };
    theme->sign  = (TactusRgb) { 205 / 255.0, 205 / 255.0, 210 / 255.0 };
    theme->disc  = (TactusRgb) {  72 / 255.0,  72 / 255.0,  74 / 255.0 };
  } else {
    theme->field = (TactusRgb) { 239 / 255.0, 240 / 255.0, 244 / 255.0 };
    theme->hint  = (TactusRgb) { 114 / 255.0, 115 / 255.0, 119 / 255.0 };
    theme->sign  = (TactusRgb) {  67 / 255.0,  68 / 255.0,  72 / 255.0 };
    theme->disc  = (TactusRgb) { 210 / 255.0, 211 / 255.0, 215 / 255.0 };
  }
}


/**
 * tactus_theme_watch:
 * @instance: The widget whose colours follow the theme
 * @changed: Called with @instance when Omarchy applies another theme
 *
 * omarchy-theme-set writes current/theme.generation each time it applies a
 * theme; the keyboard takes the new colours from there without a restart.
 */
void
tactus_theme_watch (gpointer instance, GCallback changed)
{
  static GFileMonitor *monitor;

  if (monitor == NULL) {
    g_autofree char *path = state_file ("theme.generation");
    g_autoptr (GFile) file = g_file_new_for_path (path);

    monitor = g_file_monitor_file (file, G_FILE_MONITOR_NONE, NULL, NULL);
    if (monitor == NULL)
      return;
  }
  g_signal_connect_object (monitor, "changed", changed, instance, G_CONNECT_SWAPPED);
}


/**
 * tactus_theme_css:
 * @theme: The keyboard's colours
 *
 * Returns:(transfer full): Style rules that give what the keyboard doesn't
 *   draw itself (the emoji, the number pad, the bars) the keyboard's colours,
 *   and leave the window clear where nothing is drawn
 */
char *
tactus_theme_css (const TactusTheme *theme)
{
  char panel[8], key[8], pressed[8], text[8], under[8];

#define HEX(buf, c) g_snprintf (buf, sizeof (buf), "#%02x%02x%02x", \
                                (guint) (c.r * 255 + 0.5), (guint) (c.g * 255 + 0.5), (guint) (c.b * 255 + 0.5))
  HEX (panel, theme->panel);
  HEX (key, theme->key);
  HEX (pressed, theme->key_pressed);
  HEX (text, theme->text);
#undef HEX

  /* A bar's corners, as the panel's (tactus_panel_path) on the narrowest
   * keyboard, 360 wide of the 390 it is drawn for: no deeper than the windows
   * reach under it */
  g_snprintf (under, sizeof (under), "%dpx", tactus_panel_under (360.0 / 390.0));

  return g_strconcat (
    "pos-input-surface, pos-input-surface.background { background-color: transparent; }\n"
    "pos-emoji-picker, pos-keypad, pos-shortcuts-bar, pos-completion-bar {"
    " background-color: ", panel, "; color: ", text, ";"
    " border-radius: 22px 22px 0 0 / ", under, " ", under, " 0 0; }\n"
    "pos-emoji-picker .view, pos-emoji-picker scrolledwindow, pos-emoji-picker viewport,"
    " pos-emoji-picker flowbox, pos-emoji-picker flowboxchild { background: transparent; color: ", text, "; }\n"
    "pos-emoji-picker button, #pos-emoji-switcher .view button {"
    " background: transparent; color: ", text, "; border: none; box-shadow: none; text-shadow: none; }\n"
    "pos-emoji-picker button.action { background: ", key, "; color: ", text, ";"
    " border-radius: 7px; padding: 6px 12px; margin: 2px 4px; }\n"
    "pos-emoji-picker button.action:active { background: ", pressed, "; }\n"
    "#pos-emoji-switcher .view button:checked { background-color: ", pressed, "; }\n"
    "pos-emoji-picker separator { background-color: alpha(", text, ", 0.12); min-width: 1px; }\n"
    "pos-keypad { padding: 10px 3px 6px 3px; }\n"
    "pos-keypad button { background: ", key, "; color: ", text, ";"
    " border: none; box-shadow: none; text-shadow: none; border-radius: 7px; margin: 3px; }\n"
    "pos-keypad button:active { background: ", pressed, "; }\n"
    "pos-shortcuts-bar button { background: ", key, "; color: ", text, ";"
    " border: none; box-shadow: none; text-shadow: none; }\n",
    NULL);
}


void
tactus_set_source (cairo_t *cr, const TactusRgb *rgb, double alpha)
{
  cairo_set_source_rgba (cr, rgb->r, rgb->g, rgb->b, alpha);
}


void
tactus_rounded_rect (cairo_t *cr, double x, double y, double w, double h, double r)
{
  r = MIN (r, MIN (w, h) / 2.0);
  cairo_new_sub_path (cr);
  cairo_arc (cr, x + w - r, y + r, r, -G_PI_2, 0);
  cairo_arc (cr, x + w - r, y + h - r, r, 0, G_PI_2);
  cairo_arc (cr, x + r, y + h - r, r, G_PI_2, G_PI);
  cairo_arc (cr, x + r, y + r, r, G_PI, 3 * G_PI_2);
  cairo_close_path (cr);
}

/*
 * How far the applications' windows reach under the top of the panel, in
 * pixels: what shows past its round corners is then the application in front,
 * not the wallpaper behind it. The keyboard asks the compositor for that much
 * less room than its panel is high. Little, because that much of a window's
 * lower edge is behind the panel: at 12 px on a screen 360 wide a message
 * box 11 px above its window's edge lost its lower line.
 */
int
tactus_panel_under (double scale)
{
  return (int) (9.0 * scale + 0.5);
}

/*
 * The keyboard's panel: square at the bottom (the screen's own corners are
 * there), and at the top two wide corners that ease into the edges rather
 * than meeting them as arcs do. They reach further along the top than down
 * the sides: only as deep as the windows reach under the panel
 * (tactus_panel_under), so that nothing shows past them that isn't a window's.
 */
void
tactus_panel_path (cairo_t *cr, double x, double y, double w, double h, double scale)
{
  double a = MIN (24.0 * scale, w / 2.0);            /* how far along the top a corner reaches */
  double d = MIN (tactus_panel_under (scale), h);    /* and how far down the side */
  double pull = 23.2 / 33.0;                         /* of the control points, fitted to a measured corner */
  double ka = a * pull, kd = d * pull;

  cairo_new_sub_path (cr);
  cairo_move_to (cr, x, y + h);
  cairo_line_to (cr, x, y + d);
  cairo_curve_to (cr, x, y + d - kd, x + a - ka, y, x + a, y);
  cairo_line_to (cr, x + w - a, y);
  cairo_curve_to (cr, x + w - a + ka, y, x + w, y + d - kd, x + w, y + d);
  cairo_line_to (cr, x + w, y + h);
  cairo_close_path (cr);
}

/*
 * A label centred on (cx, cy): horizontally by its width, vertically by the
 * band of the letters named (so "a" and "g" share a baseline, and capitals
 * sit as capitals do).
 */
void
tactus_draw_label (cairo_t       *cr,
                   const char    *text,
                   double         cx,
                   double         cy,
                   double         size_px,
                   int            weight,
                   TactusBand       band,
                   const TactusRgb *rgb)
{
  g_autoptr (PangoLayout) layout = pango_cairo_create_layout (cr);
  PangoFontDescription *font = pango_font_description_new ();
  PangoRectangle logical;
  double ratio = band == TACTUS_BAND_X_HEIGHT ? TACTUS_X_HEIGHT : TACTUS_CAP_HEIGHT;
  double baseline_y, baseline;

  pango_font_description_set_family (font, TACTUS_FONT_FAMILY);
  pango_font_description_set_absolute_size (font, size_px * PANGO_SCALE);
  pango_font_description_set_weight (font, weight);
  pango_layout_set_font_description (layout, font);
  pango_font_description_free (font);

  pango_layout_set_text (layout, text, -1);
  pango_layout_get_extents (layout, NULL, &logical);
  baseline = (double) pango_layout_get_baseline (layout) / PANGO_SCALE;
  baseline_y = cy + ratio * size_px / 2.0;

  cairo_save (cr);
  tactus_set_source (cr, rgb, 1.0);
  cairo_move_to (cr,
                 cx - (double) logical.width / PANGO_SCALE / 2.0 - (double) logical.x / PANGO_SCALE,
                 baseline_y - baseline);
  pango_cairo_show_layout (cr, layout);
  cairo_restore (cr);
}


static void
icon_begin (cairo_t *cr, double cx, double cy, double scale)
{
  cairo_save (cr);
  cairo_new_path (cr);
  cairo_translate (cr, cx, cy);
  cairo_scale (cr, scale, scale);
  cairo_set_line_width (cr, TACTUS_STROKE);
  cairo_set_line_join (cr, CAIRO_LINE_JOIN_ROUND);
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
}

/* Shift: an arrow pointing up; outlined when off, solid when on, with a bar under it when locked */
void
tactus_icon_shift (cairo_t *cr, double cx, double cy, double scale, TactusShiftState state)
{
  /* locked: the same arrow, shorter, with a bar under it */
  double stem_bottom = state == TACTUS_SHIFT_LOCKED ? 4.4 : 8.0;
  double top = state == TACTUS_SHIFT_LOCKED ? -8.6 : -8.0;
  double wings = top + (state == TACTUS_SHIFT_LOCKED ? 9.4 : 10.2);

  icon_begin (cr, cx, cy, scale);
  cairo_move_to (cr, 0.0, top);
  cairo_line_to (cr, 9.2, wings);
  cairo_line_to (cr, 3.85, wings);
  cairo_line_to (cr, 3.85, stem_bottom);
  cairo_line_to (cr, -3.85, stem_bottom);
  cairo_line_to (cr, -3.85, wings);
  cairo_line_to (cr, -9.2, wings);
  cairo_close_path (cr);
  if (state == TACTUS_SHIFT_OFF) {
    cairo_stroke (cr);
  } else {
    cairo_fill_preserve (cr);
    cairo_stroke (cr);
  }
  if (state == TACTUS_SHIFT_LOCKED) {
    tactus_rounded_rect (cr, -4.7, 6.6, 9.4, 2.3, 0.9);
    cairo_fill (cr);
  }
  cairo_restore (cr);
}

/* Delete: a tag pointing left with a cross in it */
void
tactus_icon_delete (cairo_t *cr, double cx, double cy, double scale, gboolean filled,
                    const TactusRgb *cutout)
{
  const double r = 2.4, top = -7.4, bottom = 7.4, right = 9.4, shoulder = -4.2, tip = -9.2;
  cairo_pattern_t *colour;

  icon_begin (cr, cx, cy, scale);
  colour = cairo_pattern_reference (cairo_get_source (cr));
  cairo_move_to (cr, tip, 0.0);
  cairo_line_to (cr, shoulder, top);
  cairo_line_to (cr, right - r, top);
  cairo_arc (cr, right - r, top + r, r, -G_PI_2, 0);
  cairo_line_to (cr, right, bottom - r);
  cairo_arc (cr, right - r, bottom - r, r, 0, G_PI_2);
  cairo_line_to (cr, shoulder, bottom);
  cairo_close_path (cr);
  if (filled) {
    cairo_fill_preserve (cr);
    cairo_stroke (cr);
    if (cutout)
      tactus_set_source (cr, cutout, 1.0);
  } else {
    cairo_stroke (cr);
  }
  /* the cross */
  cairo_move_to (cr, -0.8, -3.0);
  cairo_line_to (cr, 5.2, 3.0);
  cairo_move_to (cr, -0.8, 3.0);
  cairo_line_to (cr, 5.2, -3.0);
  cairo_stroke (cr);
  cairo_set_source (cr, colour);
  cairo_pattern_destroy (colour);
  cairo_restore (cr);
}

/* Return: across the top, down the right side, and back to the left with an arrowhead */
void
tactus_icon_return (cairo_t *cr, double cx, double cy, double scale)
{
  const double r = 2.6, top = -7.4, line = 2.0, right = 9.3, left = -9.2, head = 5.5;

  icon_begin (cr, cx, cy, scale);
  cairo_move_to (cr, 1.8, top);
  cairo_line_to (cr, right - r, top);
  cairo_arc (cr, right - r, top + r, r, -G_PI_2, 0);
  cairo_line_to (cr, right, line - r);
  cairo_arc (cr, right - r, line - r, r, 0, G_PI_2);
  cairo_line_to (cr, left, line);
  cairo_stroke (cr);
  cairo_move_to (cr, left + head, line - head);
  cairo_line_to (cr, left, line);
  cairo_line_to (cr, left + head, line + head);
  cairo_stroke (cr);
  cairo_restore (cr);
}

/*
 * The emoji key: a laughing face. On a light keyboard it is drawn in
 * outline, on a dark one as a solid disc with the features cut out.
 */
void
tactus_icon_emoji (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                   double alpha)
{
  const TactusRgb *ink = &theme->icon;
  const TactusRgb *features = theme->dark ? &theme->panel : &theme->icon;
  const TactusRgb *teeth = theme->dark ? &theme->icon : &theme->panel;

  icon_begin (cr, cx, cy, scale);
  cairo_push_group (cr);

  tactus_set_source (cr, ink, 1.0);
  if (theme->dark) {
    cairo_arc (cr, 0, 0, 13.35, 0, 2 * G_PI);
    cairo_fill (cr);
  } else {
    cairo_arc (cr, 0, 0, 12.5, 0, 2 * G_PI);
    cairo_stroke (cr);
  }

  /* eyes: a little taller than wide */
  tactus_set_source (cr, features, 1.0);
  for (int side = -1; side <= 1; side += 2) {
    cairo_save (cr);
    cairo_translate (cr, side * 4.1, -3.0);
    cairo_scale (cr, 1.45, 1.8);
    cairo_arc (cr, 0, 0, 1.0, 0, 2 * G_PI);
    cairo_restore (cr);
    cairo_fill (cr);
  }

  /* the laughing mouth: a crescent with its corners turned up */
  cairo_save (cr);
  cairo_move_to (cr, -9.0, 1.9);
  cairo_curve_to (cr, -4.5, 4.6, 4.5, 4.6, 9.0, 1.9);
  cairo_curve_to (cr, 8.0, 7.7, 4.0, 10.0, 0.0, 10.0);
  cairo_curve_to (cr, -4.0, 10.0, -8.0, 7.7, -9.0, 1.9);
  cairo_close_path (cr);
  cairo_fill_preserve (cr);
  /* the teeth: a band along the upper lip, inside the mouth only */
  cairo_clip (cr);
  tactus_set_source (cr, teeth, 1.0);
  cairo_move_to (cr, -9.0, 2.35);
  cairo_curve_to (cr, -4.5, 5.05, 4.5, 5.05, 9.0, 2.35);
  cairo_line_to (cr, 9.0, 4.5);
  cairo_curve_to (cr, 4.5, 7.2, -4.5, 7.2, -9.0, 4.5);
  cairo_close_path (cr);
  cairo_fill (cr);
  cairo_restore (cr);

  cairo_pop_group_to_source (cr);
  cairo_paint_with_alpha (cr, alpha);
  cairo_restore (cr);
}

/* The dictation key: a microphone on its stand */
void
tactus_icon_mic (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                 double alpha)
{
  icon_begin (cr, cx, cy, scale);
  cairo_push_group (cr);
  tactus_set_source (cr, &theme->icon, 1.0);

  /* the capsule */
  if (theme->dark) {
    tactus_rounded_rect (cr, -4.2, -14.0, 8.4, 18.2, 4.2);
    cairo_fill (cr);
  } else {
    tactus_rounded_rect (cr, -3.35, -13.15, 6.7, 16.5, 3.35);
    cairo_stroke (cr);
  }
  /* the holder */
  cairo_move_to (cr, -8.5, -3.0);
  cairo_line_to (cr, -8.5, 0.0);
  cairo_arc_negative (cr, 0.0, 0.0, 8.5, G_PI, 0);
  cairo_line_to (cr, 8.5, -3.0);
  cairo_stroke (cr);
  /* the stem and the foot */
  cairo_move_to (cr, 0.0, 8.5);
  cairo_line_to (cr, 0.0, 13.1);
  cairo_stroke (cr);
  cairo_move_to (cr, -5.6, 13.15);
  cairo_line_to (cr, 5.6, 13.15);
  cairo_stroke (cr);

  cairo_pop_group_to_source (cr);
  cairo_paint_with_alpha (cr, alpha);
  cairo_restore (cr);
}

/*
 * The paste key: a clipboard with two lines of writing on it. As the other
 * two, in outline on a light keyboard and solid on a dark one with the writing
 * cut out; the clip stands clear of the board on both.
 */
void
tactus_icon_paste (cairo_t *cr, double cx, double cy, double scale, const TactusTheme *theme,
                   double alpha)
{
  const TactusRgb *ink = &theme->icon;
  const TactusRgb *writing = theme->dark ? &theme->panel : &theme->icon;

  icon_begin (cr, cx, cy, scale);
  cairo_push_group (cr);
  tactus_set_source (cr, ink, 1.0);

  /* the board */
  if (theme->dark) {
    tactus_rounded_rect (cr, -9.6, -11.0, 19.2, 24.4, 3.4);
    cairo_fill (cr);
  } else {
    tactus_rounded_rect (cr, -8.75, -10.15, 17.5, 22.7, 2.6);
    cairo_stroke (cr);
  }
  /* room around the clip, which sits over the board's top edge */
  tactus_set_source (cr, &theme->panel, 1.0);
  tactus_rounded_rect (cr, -6.6, -15.4, 13.2, 8.4, 3.0);
  cairo_fill (cr);
  /* the clip */
  tactus_set_source (cr, ink, 1.0);
  tactus_rounded_rect (cr, -4.9, -13.7, 9.8, 5.0, 1.8);
  cairo_fill (cr);

  /* the writing */
  tactus_set_source (cr, writing, 1.0);
  cairo_move_to (cr, -4.7, 0.6);
  cairo_line_to (cr, 4.7, 0.6);
  cairo_move_to (cr, -4.7, 6.2);
  cairo_line_to (cr, 1.6, 6.2);
  cairo_stroke (cr);

  cairo_pop_group_to_source (cr);
  cairo_paint_with_alpha (cr, alpha);
  cairo_restore (cr);
}

/*
 * The emoji page
 */

#define KIND_STROKE 1.5

static void
kind_begin (cairo_t *cr, double cx, double cy, double scale, const TactusRgb *rgb)
{
  cairo_save (cr);
  /* nothing left over from what was drawn before joins in */
  cairo_new_path (cr);
  cairo_translate (cr, cx, cy);
  cairo_scale (cr, scale, scale);
  cairo_set_line_width (cr, KIND_STROKE);
  cairo_set_line_join (cr, CAIRO_LINE_JOIN_ROUND);
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
  tactus_set_source (cr, rgb, 1.0);
}

#define DEG(d) ((d) * G_PI / 180.0)

/**
 * tactus_icon_kind:
 *
 * The sign of a kind of emoji, in the row under them: a clock for the ones
 * used lately, a face, an animal, an apple, a ball, a car, a light bulb, a
 * heart, a flag. Drawn in a box of about 17 points.
 */
void
tactus_icon_kind (cairo_t *cr, TactusKind kind, double cx, double cy, double scale, const TactusRgb *rgb)
{
  kind_begin (cr, cx, cy, scale, rgb);

  switch (kind) {
  case TACTUS_KIND_RECENT:
    cairo_arc (cr, 0, 0, 8.0, 0, 2 * G_PI);
    cairo_stroke (cr);
    cairo_move_to (cr, 0, -4.9);
    cairo_line_to (cr, 0, 0.2);
    cairo_line_to (cr, -4.2, 0.2);
    cairo_stroke (cr);
    break;

  case TACTUS_KIND_SMILEYS:
    cairo_arc (cr, 0, 0, 8.3, 0, 2 * G_PI);
    cairo_stroke (cr);
    cairo_arc (cr, -3.0, -2.5, 1.15, 0, 2 * G_PI);
    cairo_fill (cr);
    cairo_arc (cr, 3.0, -2.5, 1.15, 0, 2 * G_PI);
    cairo_fill (cr);
    cairo_move_to (cr, -5.0, 1.0);
    cairo_line_to (cr, 5.0, 1.0);
    cairo_curve_to (cr, 5.0, 4.4, 2.8, 6.3, 0, 6.3);
    cairo_curve_to (cr, -2.8, 6.3, -5.0, 4.4, -5.0, 1.0);
    cairo_close_path (cr);
    cairo_fill (cr);
    break;

  case TACTUS_KIND_ANIMALS:
    /* a round head with two round ears */
    cairo_arc (cr, 0, 1.2, 6.6, 0, 2 * G_PI);
    cairo_stroke (cr);
    cairo_arc (cr, -5.5, -4.6, 2.9, DEG (108), DEG (342));
    cairo_stroke (cr);
    cairo_arc (cr, 5.5, -4.6, 2.9, DEG (198), DEG (432));
    cairo_stroke (cr);
    cairo_arc (cr, -2.5, -0.2, 0.95, 0, 2 * G_PI);
    cairo_fill (cr);
    cairo_arc (cr, 2.5, -0.2, 0.95, 0, 2 * G_PI);
    cairo_fill (cr);
    cairo_save (cr);
    cairo_translate (cr, 0, 3.0);
    cairo_scale (cr, 1.5, 1.05);
    cairo_arc (cr, 0, 0, 1.0, 0, 2 * G_PI);
    cairo_restore (cr);
    cairo_fill (cr);
    break;

  case TACTUS_KIND_FOOD:
    cairo_move_to (cr, 0, -3.4);
    cairo_curve_to (cr, 2.2, -5.4, 7.4, -4.4, 7.4, 0.8);
    cairo_curve_to (cr, 7.4, 5.4, 4.2, 8.8, 1.8, 8.8);
    cairo_curve_to (cr, 0.9, 8.8, 0.6, 8.2, 0, 8.2);
    cairo_curve_to (cr, -0.6, 8.2, -0.9, 8.8, -1.8, 8.8);
    cairo_curve_to (cr, -4.2, 8.8, -7.4, 5.4, -7.4, 0.8);
    cairo_curve_to (cr, -7.4, -4.4, -2.2, -5.4, 0, -3.4);
    cairo_close_path (cr);
    cairo_stroke (cr);
    /* its leaf */
    cairo_move_to (cr, 0.6, -5.0);
    cairo_curve_to (cr, 0.8, -7.6, 3.0, -8.9, 4.8, -8.7);
    cairo_curve_to (cr, 4.6, -6.5, 2.8, -4.8, 0.6, -5.0);
    cairo_close_path (cr);
    cairo_fill (cr);
    break;

  case TACTUS_KIND_ACTIVITY:
    cairo_arc (cr, 0, 0, 8.2, 0, 2 * G_PI);
    cairo_stroke (cr);
    /* the ball's patches: one in the middle, five at the rim */
    for (int i = 0; i < 5; i++) {
      double a = DEG (-90 + 72 * i);

      if (i == 0)
        cairo_move_to (cr, 3.1 * cos (a), 3.1 * sin (a));
      else
        cairo_line_to (cr, 3.1 * cos (a), 3.1 * sin (a));
    }
    cairo_close_path (cr);
    cairo_fill (cr);
    cairo_set_line_width (cr, 1.1);
    for (int i = 0; i < 5; i++) {
      double a = DEG (-90 + 72 * i), b = DEG (-90 + 72 * i + 36);

      cairo_move_to (cr, 3.1 * cos (a), 3.1 * sin (a));
      cairo_line_to (cr, 5.6 * cos (a), 5.6 * sin (a));
      cairo_stroke (cr);
      /* a patch at the rim, between two seams */
      cairo_move_to (cr, 8.0 * cos (b - DEG (20)), 8.0 * sin (b - DEG (20)));
      cairo_line_to (cr, 5.9 * cos (b - DEG (11)), 5.9 * sin (b - DEG (11)));
      cairo_line_to (cr, 5.9 * cos (b + DEG (11)), 5.9 * sin (b + DEG (11)));
      cairo_line_to (cr, 8.0 * cos (b + DEG (20)), 8.0 * sin (b + DEG (20)));
      cairo_arc_negative (cr, 0, 0, 8.0, b + DEG (20), b - DEG (20));
      cairo_fill (cr);
    }
    break;

  case TACTUS_KIND_TRAVEL:
    /* a small car from the side */
    tactus_rounded_rect (cr, -10.2, -0.4, 20.4, 5.6, 2.4);
    cairo_stroke (cr);
    cairo_move_to (cr, -6.2, -0.4);
    cairo_curve_to (cr, -5.2, -3.6, -4.2, -5.8, -2.0, -5.8);
    cairo_line_to (cr, 3.0, -5.8);
    cairo_curve_to (cr, 5.0, -5.8, 6.4, -3.2, 7.4, -0.4);
    cairo_stroke (cr);
    cairo_move_to (cr, 0.4, -5.8);
    cairo_line_to (cr, 0.4, -0.4);
    cairo_stroke (cr);
    cairo_arc (cr, -5.4, 5.4, 2.3, 0, 2 * G_PI);
    cairo_fill (cr);
    cairo_arc (cr, 5.4, 5.4, 2.3, 0, 2 * G_PI);
    cairo_fill (cr);
    break;

  case TACTUS_KIND_OBJECTS:
    /* a light bulb */
    cairo_arc (cr, 0, -3.0, 5.6, DEG (128), DEG (412));
    cairo_stroke (cr);
    cairo_move_to (cr, 3.45, 1.4);
    cairo_line_to (cr, 2.4, 4.4);
    cairo_line_to (cr, -2.4, 4.4);
    cairo_line_to (cr, -3.45, 1.4);
    cairo_stroke (cr);
    cairo_move_to (cr, -2.2, 6.5);
    cairo_line_to (cr, 2.2, 6.5);
    cairo_stroke (cr);
    cairo_move_to (cr, -1.3, 8.5);
    cairo_line_to (cr, 1.3, 8.5);
    cairo_stroke (cr);
    break;

  case TACTUS_KIND_SYMBOLS:
    cairo_move_to (cr, 0, 7.5);
    cairo_curve_to (cr, -3.2, 4.9, -8.0, 1.7, -8.0, -2.5);
    cairo_curve_to (cr, -8.0, -5.3, -6.0, -7.3, -3.8, -7.3);
    cairo_curve_to (cr, -2.2, -7.3, -0.8, -6.3, 0, -4.8);
    cairo_curve_to (cr, 0.8, -6.3, 2.2, -7.3, 3.8, -7.3);
    cairo_curve_to (cr, 6.0, -7.3, 8.0, -5.3, 8.0, -2.5);
    cairo_curve_to (cr, 8.0, 1.7, 3.2, 4.9, 0, 7.5);
    cairo_close_path (cr);
    cairo_stroke (cr);
    break;

  case TACTUS_KIND_FLAGS:
    cairo_move_to (cr, -6.6, -7.8);
    cairo_line_to (cr, -6.6, 8.0);
    cairo_stroke (cr);
    cairo_move_to (cr, -6.6, -6.4);
    cairo_curve_to (cr, -2.6, -8.6, 0.6, -4.4, 7.2, -6.8);
    cairo_line_to (cr, 7.2, 2.0);
    cairo_curve_to (cr, 0.6, 4.4, -2.6, 0.2, -6.6, 2.4);
    cairo_stroke (cr);
    break;

  case TACTUS_N_KINDS:
  default:
    break;
  }

  cairo_restore (cr);
}


void
tactus_icon_magnifier (cairo_t *cr, double cx, double cy, double scale, const TactusRgb *rgb)
{
  kind_begin (cr, cx, cy, scale, rgb);
  cairo_set_line_width (cr, 1.9);
  cairo_arc (cr, -1.5, -1.5, 5.9, 0, 2 * G_PI);
  cairo_stroke (cr);
  cairo_move_to (cr, 2.9, 2.9);
  cairo_line_to (cr, 7.3, 7.3);
  cairo_stroke (cr);
  cairo_restore (cr);
}

/* What empties the search field: a cross on a disc */
void
tactus_icon_clear (cairo_t *cr, double cx, double cy, double scale, const TactusRgb *disc, const TactusRgb *cross)
{
  kind_begin (cr, cx, cy, scale, disc);
  cairo_arc (cr, 0, 0, 8.4, 0, 2 * G_PI);
  cairo_fill (cr);
  tactus_set_source (cr, cross, 1.0);
  cairo_set_line_width (cr, 1.9);
  cairo_move_to (cr, -3.0, -3.0);
  cairo_line_to (cr, 3.0, 3.0);
  cairo_move_to (cr, 3.0, -3.0);
  cairo_line_to (cr, -3.0, 3.0);
  cairo_stroke (cr);
  cairo_restore (cr);
}

#define TACTUS_EMOJI_FONT "Noto Color Emoji"

/**
 * tactus_emoji_font_size:
 * @cr: Where emoji will be drawn
 * @ink_px: How wide an emoji should come out
 *
 * Returns: The font size that makes a face that wide
 */
double
tactus_emoji_font_size (cairo_t *cr, double ink_px)
{
  g_autoptr (PangoLayout) layout = pango_cairo_create_layout (cr);
  PangoFontDescription *font = pango_font_description_new ();
  PangoRectangle ink;

  pango_font_description_set_family (font, TACTUS_EMOJI_FONT);
  pango_font_description_set_absolute_size (font, 100.0 * PANGO_SCALE);
  pango_layout_set_font_description (layout, font);
  pango_font_description_free (font);
  pango_layout_set_text (layout, "\360\237\230\200", -1);
  pango_layout_get_extents (layout, &ink, NULL);
  if (ink.width <= 0)
    return ink_px;
  return 100.0 * ink_px / ((double) ink.width / PANGO_SCALE);
}

/* An emoji with its middle at (cx, cy) */
void
tactus_draw_emoji (cairo_t *cr, const char *emoji, double cx, double cy, double size_px, double alpha)
{
  g_autoptr (PangoLayout) layout = pango_cairo_create_layout (cr);
  PangoFontDescription *font = pango_font_description_new ();
  PangoRectangle ink;

  pango_font_description_set_family (font, TACTUS_EMOJI_FONT);
  pango_font_description_set_absolute_size (font, size_px * PANGO_SCALE);
  pango_layout_set_font_description (layout, font);
  pango_font_description_free (font);
  pango_layout_set_text (layout, emoji, -1);
  pango_layout_get_extents (layout, &ink, NULL);

  cairo_save (cr);
  cairo_move_to (cr,
                 cx - ((double) ink.x + ink.width / 2.0) / PANGO_SCALE,
                 cy - ((double) ink.y + ink.height / 2.0) / PANGO_SCALE);
  if (alpha < 1.0) {
    cairo_push_group (cr);
    pango_cairo_show_layout (cr, layout);
    cairo_pop_group_to_source (cr);
    cairo_paint_with_alpha (cr, alpha);
  } else {
    pango_cairo_show_layout (cr, layout);
  }
  cairo_restore (cr);
}
