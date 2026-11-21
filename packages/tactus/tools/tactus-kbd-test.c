/*
 * Drives Tactus's widget with no window on screen: draws it to
 * PNGs and plays touches into it, checking what gets typed.
 *
 *   tactus-kbd-test OUTDIR [width]
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "pos-osk-widget.c"

#include "pos-main.h"

#include <glib/gstdio.h>

static GString *typed;
static GString *log_events;
static int failures;
static int checks;
static const char *outdir;
static gboolean emulate_sentences;

#define SEQ(n) ((GdkEventSequence *) GUINT_TO_POINTER (100 + (n)))

static void
wait_ms (guint ms)
{
  gint64 end = g_get_monotonic_time () + ms * G_TIME_SPAN_MILLISECOND;

  while (g_get_monotonic_time () < end) {
    while (g_main_context_iteration (NULL, FALSE))
      ;
    g_usleep (2000);
  }
  while (g_main_context_iteration (NULL, FALSE))
    ;
}


static gboolean
sentence_start (const char *text)
{
  size_t len = strlen (text);

  if (len == 0 || text[len - 1] == '\n')
    return TRUE;
  if (text[len - 1] != ' ')
    return FALSE;
  while (len && text[len - 1] == ' ')
    len--;
  return len && strchr (".!?", text[len - 1]);
}


static void
on_symbol (PosOskWidget *w, const char *symbol)
{
  if (g_strcmp0 (symbol, "KEY_BACKSPACE") == 0) {
    if (typed->len) {
      const char *prev = g_utf8_find_prev_char (typed->str, typed->str + typed->len);
      g_string_truncate (typed, prev - typed->str);
    }
  } else if (g_strcmp0 (symbol, "KEY_ENTER") == 0) {
    g_string_append_c (typed, '\n');
  } else if (g_str_has_prefix (symbol, "KEY_")) {
    g_string_append_printf (typed, "<%s>", symbol + 4);
  } else {
    g_string_append (typed, symbol);
  }
  /* What the input surface does: capitals where a sentence starts */
  if (emulate_sentences)
    pos_osk_widget_set_autoshift (w, sentence_start (typed->str), FALSE);
}


static void
on_strip (PosOskWidget *w, const char *which)
{
  g_string_append_printf (log_events, "strip:%s ", which);
}


static void
on_down (PosOskWidget *w, const char *symbol)
{
  g_string_append_printf (log_events, "down:%s ", symbol ? symbol : "-");
}


static void
check_str (const char *what, const char *got, const char *want)
{
  checks++;
  if (g_strcmp0 (got, want) == 0) {
    g_print ("ok   %-58s '%s'\n", what, got);
  } else {
    failures++;
    g_print ("FAIL %-58s got '%s' want '%s'\n", what, got, want);
  }
}


static void
check_int (const char *what, int got, int want)
{
  checks++;
  if (got == want) {
    g_print ("ok   %-58s %d\n", what, got);
  } else {
    failures++;
    g_print ("FAIL %-58s got %d want %d\n", what, got, want);
  }
}


static TactusGeom *
find_key (PosOskWidget *w, const char *name)
{
  PosOskWidgetKeyboardLayer *layer = pos_osk_widget_get_current_layer (w);

  if (g_strcmp0 (name, "emoji") == 0)
    return &w->emoji;
  if (g_strcmp0 (name, "mic") == 0)
    return &w->mic;

  for (int r = 0; r < layer->n_rows; r++) {
    PosOskWidgetRow *row = &layer->rows[r];

    for (int k = 0; k < row->geoms->len; k++) {
      TactusGeom *g = &g_array_index (row->geoms, TactusGeom, k);
      const char *symbol = pos_osk_key_get_symbol (g->key);
      const char *label = pos_osk_key_get_label (g->key);

      if (g_strcmp0 (name, "shift") == 0 && g->role == TACTUS_ROLE_SHIFT)
        return g;
      if (g_strcmp0 (name, "sym2") == 0 && g->role == TACTUS_ROLE_SYM2)
        return g;
      if (g_strcmp0 (name, "sym") == 0 && g->role == TACTUS_ROLE_SYM)
        return g;
      if (g_strcmp0 (name, "bksp") == 0 && g->role == TACTUS_ROLE_BACKSPACE)
        return g;
      if (g_strcmp0 (name, "return") == 0 && g->role == TACTUS_ROLE_RETURN)
        return g;
      if (g_strcmp0 (name, "space") == 0 && g->role == TACTUS_ROLE_SPACE)
        return g;
      if (g->role == TACTUS_ROLE_CHAR && (g_strcmp0 (symbol, name) == 0 || g_strcmp0 (label, name) == 0))
        return g;
    }
  }
  return NULL;
}


static void
send_touch (PosOskWidget *w, GdkEventType type, int seq, double x, double y)
{
  GdkEvent *event = gdk_event_new (type);
  GdkSeat *seat = gdk_display_get_default_seat (gdk_display_get_default ());

  event->touch.window = g_object_ref (gtk_widget_get_window (GTK_WIDGET (w)));
  event->touch.send_event = TRUE;
  event->touch.time = g_get_monotonic_time () / 1000;
  event->touch.x = x;
  event->touch.y = y;
  event->touch.sequence = SEQ (seq);
  event->touch.emulating_pointer = FALSE;
  gdk_event_set_device (event, gdk_seat_get_pointer (seat));
  gtk_widget_event (GTK_WIDGET (w), event);
  gdk_event_free (event);
}


static void
key_xy (PosOskWidget *w, const char *name, double *x, double *y)
{
  TactusGeom *g = find_key (w, name);

  if (g == NULL) {
    g_print ("FAIL no key '%s' on this page\n", name);
    failures++;
    *x = *y = -1000;
    return;
  }
  *x = g->vx + g->vw / 2;
  *y = g->vy + g->vh / 2;
}


static void
down (PosOskWidget *w, int seq, const char *name)
{
  double x, y;

  key_xy (w, name, &x, &y);
  send_touch (w, GDK_TOUCH_BEGIN, seq, x, y);
}


static void
move (PosOskWidget *w, int seq, const char *name)
{
  double x, y;

  key_xy (w, name, &x, &y);
  send_touch (w, GDK_TOUCH_UPDATE, seq, x, y);
}


static void
up (PosOskWidget *w, int seq, const char *name)
{
  double x, y;

  key_xy (w, name, &x, &y);
  send_touch (w, GDK_TOUCH_END, seq, x, y);
}


static void
tap (PosOskWidget *w, const char *name)
{
  double x, y;

  key_xy (w, name, &x, &y);
  send_touch (w, GDK_TOUCH_BEGIN, 0, x, y);
  send_touch (w, GDK_TOUCH_END, 0, x, y);
}


static void
type (PosOskWidget *w, const char *text)
{
  for (const char *p = text; *p; p = g_utf8_next_char (p)) {
    char buf[8] = { 0 };

    g_utf8_strncpy (buf, p, 1);
    tap (w, buf[0] == ' ' ? "space" : buf);
  }
}


static void
snap (GtkWidget *window, PosOskWidget *w, const char *name)
{
  const int scale = 3;
  int width = gtk_widget_get_allocated_width (GTK_WIDGET (w));
  int height = gtk_widget_get_allocated_height (GTK_WIDGET (w));
  cairo_surface_t *surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, width * scale, height * scale);
  cairo_t *cr = cairo_create (surface);
  g_autofree char *path = g_build_filename (outdir, name, NULL);

  while (g_main_context_iteration (NULL, FALSE))
    ;
  cairo_scale (cr, scale, scale);
  /* a text page behind, so that the clear band above the keyboard shows */
  cairo_set_source_rgb (cr, w->theme.dark ? 0.0 : 1.0, w->theme.dark ? 0.0 : 1.0, w->theme.dark ? 0.0 : 1.0);
  cairo_paint (cr);
  gtk_widget_draw (GTK_WIDGET (w), cr);
  cairo_destroy (cr);
  cairo_surface_write_to_png (surface, path);
  cairo_surface_destroy (surface);
}


static gboolean
same_rgb (TactusRgb a, guint hex)
{
  return fabs (a.r - ((hex >> 16) & 0xff) / 255.0) < 0.002 && fabs (a.g - ((hex >> 8) & 0xff) / 255.0) < 0.002 &&
         fabs (a.b - (hex & 0xff) / 255.0) < 0.002;
}


/* The colours of the applied Omarchy theme, Tactus's own without one, and the owner's way to keep Tactus's own */
static void
check_theme (void)
{
  g_autofree char *dir = g_dir_make_tmp ("tactus-theme-XXXXXX", NULL);
  g_autofree char *colors = g_build_filename (dir, "colors.toml", NULL);
  g_autofree char *own_dir = g_build_filename (g_get_user_config_dir (), "tactus", NULL);
  g_autofree char *own = g_build_filename (own_dir, "own-colours", NULL);
  g_autofree char *before = g_strdup (g_getenv ("TACTUS_THEME_COLORS"));
  TactusTheme t;

  g_setenv ("TACTUS_THEME_COLORS", colors, TRUE);
  g_file_set_contents (colors, "mode = \"dark\"\n\naccent = \"#7e9cd8\"\nmuted = \"#54546D\"\n"
                       "background = \"#1f1f28\"\ndark_background = \"#17171e\"\n"
                       "lighter_background = \"#223249\"\nforeground = \"#dcd7ba\"\n", -1, NULL);
  tactus_theme_init (&t, FALSE);
  check_int ("a dark Omarchy theme is dark whatever the desktop asks", t.dark, TRUE);
  check_int ("the panel in the theme's darker background", same_rgb (t.panel, 0x17171e), TRUE);
  check_int ("the keys in its lighter background", same_rgb (t.key, 0x223249), TRUE);
  check_int ("the letters in its foreground", same_rgb (t.text, 0xdcd7ba), TRUE);
  check_int ("the caret in its accent", same_rgb (t.accent, 0x7e9cd8), TRUE);

  g_file_set_contents (colors, "mode = \"light\"\nbackground = \"#f2ecbc\"\nforeground = \"#545464\"\n", -1, NULL);
  tactus_theme_init (&t, TRUE);
  check_int ("a light theme is light, its missing colours mixed from the ones it has",
             !t.dark && same_rgb (t.text, 0x545464) && !same_rgb (t.key, 0xf2ecbc), TRUE);

  g_file_set_contents (colors, "accent = \"#7e9cd8\"\n", -1, NULL);
  tactus_theme_init (&t, FALSE);
  check_int ("without a background and a foreground, Tactus's own light colours",
             !t.dark && same_rgb (t.panel, 0xe2e3e8), TRUE);

  g_file_set_contents (colors, "background = \"#1f1f28\"\nforeground = \"#dcd7ba\"\n", -1, NULL);
  g_mkdir_with_parents (own_dir, 0700);
  g_file_set_contents (own, "", -1, NULL);
  tactus_theme_init (&t, TRUE);
  check_int ("an owner who keeps Tactus's own colours gets them", t.dark && same_rgb (t.panel, 0x1f1f1f), TRUE);
  g_unlink (own);
  g_rmdir (own_dir);

  g_unlink (colors);
  g_rmdir (dir);
  /* the pictures that follow are drawn as the caller asked */
  if (before)
    g_setenv ("TACTUS_THEME_COLORS", before, TRUE);
  else
    g_unsetenv ("TACTUS_THEME_COLORS");
}


/* Whether the widget draws its panel over a point, or lets what is behind it show */
static gboolean
panel_at (PosOskWidget *w, int x, int y)
{
  int width = gtk_widget_get_allocated_width (GTK_WIDGET (w));
  int height = gtk_widget_get_allocated_height (GTK_WIDGET (w));
  cairo_surface_t *surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, width, height);
  cairo_t *cr = cairo_create (surface);
  guint32 pixel;

  /* behind it, a colour no keyboard has */
  cairo_set_source_rgb (cr, 1.0, 0.0, 1.0);
  cairo_paint (cr);
  gtk_widget_draw (GTK_WIDGET (w), cr);
  cairo_destroy (cr);
  cairo_surface_flush (surface);
  memcpy (&pixel,
          cairo_image_surface_get_data (surface) + y * cairo_image_surface_get_stride (surface) + 4 * x,
          sizeof pixel);
  cairo_surface_destroy (surface);

  return (pixel & 0x00ffffff) != 0x00ff00ff;
}


static void
reset (PosOskWidget *w)
{
  pos_osk_widget_cancel_touches (w);
  w->autoshift = FALSE;
  pos_osk_widget_set_layer (w, POS_OSK_WIDGET_LAYER_NORMAL);
  w->last_shift_tap = 0;
  g_string_truncate (typed, 0);
  g_string_truncate (log_events, 0);
  emulate_sentences = FALSE;
}


/* Where the keys of every page are, in the widget: "page name x y", for
 * whoever drives the real keyboard with touches */
static void
print_map (PosOskWidget *w)
{
  static const char *const pages[] = { "letters", "capitals", "numbers", "symbols" };

  g_print ("size %d %d clear %u\n", gtk_widget_get_allocated_width (GTK_WIDGET (w)),
           gtk_widget_get_allocated_height (GTK_WIDGET (w)), pos_osk_widget_get_overhang (w));
  for (guint l = 0; l < G_N_ELEMENTS (pages); l++) {
    PosOskWidgetKeyboardLayer *layer;

    pos_osk_widget_set_layer (w, l);
    while (g_main_context_iteration (NULL, FALSE))
      ;
    if (pos_osk_widget_get_layer (w) != l && l != POS_OSK_WIDGET_LAYER_NORMAL)
      continue;
    layer = pos_osk_widget_get_current_layer (w);
    for (int r = 0; r < layer->n_rows; r++) {
      PosOskWidgetRow *row = &layer->rows[r];

      for (int k = 0; row->geoms && k < row->geoms->len; k++) {
        TactusGeom *g = &g_array_index (row->geoms, TactusGeom, k);
        const char *name = pos_osk_key_get_symbol (g->key);

        if (g->role == TACTUS_ROLE_SHIFT)
          name = "shift";
        else if (g->role == TACTUS_ROLE_SYM2)
          name = "sym2";
        else if (g->role == TACTUS_ROLE_SYM)
          name = "sym";
        else if (g->role == TACTUS_ROLE_BACKSPACE)
          name = "bksp";
        else if (g->role == TACTUS_ROLE_RETURN)
          name = "return";
        else if (g->role == TACTUS_ROLE_SPACE)
          name = "space";
        g_print ("%s %s %.1f %.1f\n", pages[l], name, g->vx + g->vw / 2, g->vy + g->vh / 2);
      }
    }
  }
  g_print ("any emoji %.1f %.1f\n", w->emoji.vx + w->emoji.vw / 2, w->emoji.vy + w->emoji.vh / 2);
  g_print ("any mic %.1f %.1f\n", w->mic.vx + w->mic.vw / 2, w->mic.vy + w->mic.vh / 2);
}


int
main (int argc, char **argv)
{
  GtkWidget *window;
  PosOskWidget *w;
  g_autoptr (GError) err = NULL;
  int width = argc > 2 ? atoi (argv[2]) : 360;
  int height;
  double x, y;

  outdir = argc > 1 ? argv[1] : ".";
  if (g_strcmp0 (outdir, "--map") != 0)
    g_mkdir_with_parents (outdir, 0755);

  gtk_init (&argc, &argv);
  pos_init ();

  typed = g_string_new (NULL);
  log_events = g_string_new (NULL);

  if (g_strcmp0 (outdir, "--map") != 0)
    check_theme ();

  w = pos_osk_widget_new (PHOSH_OSK_FEATURE_DEFAULT);
  if (!pos_osk_widget_set_layout (w, "us", "us", "English (US)", "us", NULL, &err))
    g_error ("layout: %s", err->message);
  g_signal_connect (w, "key-symbol", G_CALLBACK (on_symbol), NULL);
  g_signal_connect (w, "strip-key", G_CALLBACK (on_strip), NULL);
  g_signal_connect (w, "key-down", G_CALLBACK (on_down), NULL);

  window = gtk_offscreen_window_new ();
  height = tactus_height_for_width (w, width);
  gtk_widget_set_size_request (GTK_WIDGET (w), width, height);
  gtk_container_add (GTK_CONTAINER (window), GTK_WIDGET (w));
  gtk_widget_show_all (window);
  wait_ms (50);

  if (g_strcmp0 (outdir, "--map") == 0) {
    print_map (w);
    return 0;
  }

  g_print ("widget %dx%d, overhang %.0f, key %.2fx%.2f, pitch %.2f, cell %.3f, strip %.1f\n",
           gtk_widget_get_allocated_width (GTK_WIDGET (w)),
           gtk_widget_get_allocated_height (GTK_WIDGET (w)), w->overhang,
           find_key (w, "q")->vw, w->key_h, w->pitch,
           pos_osk_widget_get_current_layer (w)->key_width, w->strip_h);

  /* ---- the panel's corners ---- */
  {
    int top = pos_osk_widget_get_overhang (w), under = pos_osk_widget_get_panel_under (w);
    int right = gtk_widget_get_allocated_width (GTK_WIDGET (w)) - 1;

    if (width == 360)
      check_int ("the windows reach this far under the panel's top", under, 8);
    check_int ("past a top corner what is behind shows", panel_at (w, 0, top + 1), FALSE);
    check_int ("a little way along the top", panel_at (w, 2, top + 1), FALSE);
    check_int ("and a little way down the side", panel_at (w, 0, top + 3), FALSE);
    check_int ("no deeper than the windows reach, on the left", panel_at (w, 0, top + under), TRUE);
    check_int ("or on the right", panel_at (w, right, top + under), TRUE);
    check_int ("the other corner is cut the same", panel_at (w, right, top + 1), FALSE);
    check_int ("between them the panel starts at its top", panel_at (w, right / 2, top + 1), TRUE);
  }

  /* ---- pictures ---- */
  snap (window, w, "01-lower.png");
  tap (w, "shift");
  snap (window, w, "02-shift.png");
  wait_ms (400);
  tap (w, "shift");
  tap (w, "shift");
  check_int ("double tap locks Shift", pos_osk_widget_get_caps_lock (w), TRUE);
  snap (window, w, "03-capslock.png");
  reset (w);
  tap (w, "sym");
  snap (window, w, "04-numbers.png");
  tap (w, "sym2");
  snap (window, w, "05-symbols.png");
  reset (w);

  /* ---- typing ---- */
  type (w, "hello");
  check_str ("plain letters", typed->str, "hello");
  reset (w);

  tap (w, "shift");
  check_int ("Shift: capitals page", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_CAPS);
  tap (w, "A");
  check_int ("after one capital: small letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  tap (w, "b");
  check_str ("Shift is for one letter", typed->str, "Ab");
  reset (w);

  wait_ms (400);
  tap (w, "shift");
  tap (w, "shift");
  check_int ("two quick taps: locked", pos_osk_widget_get_caps_lock (w), TRUE);
  tap (w, "A");
  tap (w, "B");
  check_str ("locked capitals", typed->str, "AB");
  tap (w, "shift");
  check_int ("a tap unlocks", pos_osk_widget_get_caps_lock (w), FALSE);
  check_int ("and small letters are back", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  reset (w);

  wait_ms (400);
  tap (w, "shift");
  wait_ms (450);
  tap (w, "shift");
  check_int ("two slow taps: on, then off", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  check_int ("and not locked", pos_osk_widget_get_caps_lock (w), FALSE);
  reset (w);

  /* numbers */
  type (w, "a");
  tap (w, "sym");
  check_int ("123: numbers page", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  tap (w, "1");
  tap (w, "2");
  check_int ("numbers stay for more numbers", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  tap (w, "space");
  check_int ("a space goes back to letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  check_str ("letters, numbers, space", typed->str, "a12 ");
  reset (w);

  type (w, "don");
  tap (w, "sym");
  tap (w, "'");
  check_int ("an apostrophe goes back to letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  type (w, "t");
  check_str ("don't", typed->str, "don't");
  reset (w);

  tap (w, "sym");
  tap (w, "sym2");
  check_int ("#+=: symbols page", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS2);
  tap (w, "[");
  tap (w, "sym2");
  check_int ("123 there: numbers page", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  tap (w, "sym");
  check_int ("ABC: letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  check_str ("a bracket", typed->str, "[");
  reset (w);

  /* slide from 123 to a key */
  down (w, 1, "sym");
  check_int ("123 switches as the finger comes down", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  move (w, 1, "?");
  up (w, 1, "?");
  check_str ("slide from 123 to ?", typed->str, "?");
  check_int ("and back to letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  reset (w);

  /* hold 123, type with another finger */
  down (w, 1, "sym");
  down (w, 2, "4");
  up (w, 2, "4");
  down (w, 2, "5");
  up (w, 2, "5");
  check_int ("held 123: still numbers", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  up (w, 1, "sym");
  check_int ("let go: letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  check_str ("numbers under a held 123", typed->str, "45");
  reset (w);

  /* delete */
  type (w, "abc");
  down (w, 1, "bksp");
  check_str ("delete works as the finger comes down", typed->str, "ab");
  up (w, 1, "bksp");
  check_str ("and not again when it lifts", typed->str, "ab");
  reset (w);

  /* slide between keys */
  down (w, 1, "q");
  move (w, 1, "w");
  up (w, 1, "w");
  check_str ("slide from q to w types w", typed->str, "w");
  reset (w);

  /* two fingers */
  down (w, 1, "a");
  down (w, 2, "s");
  check_str ("second finger down types the first key", typed->str, "a");
  up (w, 1, "a");
  check_str ("first finger up adds nothing", typed->str, "a");
  up (w, 2, "s");
  check_str ("second finger up types its key", typed->str, "as");
  reset (w);

  /* Shift held for several capitals */
  down (w, 1, "shift");
  down (w, 2, "A");
  up (w, 2, "A");
  down (w, 2, "B");
  up (w, 2, "B");
  up (w, 1, "shift");
  check_str ("Shift held: capitals", typed->str, "AB");
  check_int ("let go: small letters", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  type (w, "c");
  check_str ("then small", typed->str, "ABc");
  reset (w);

  /* slide from Shift to a letter */
  down (w, 1, "shift");
  move (w, 1, "D");
  up (w, 1, "D");
  check_str ("slide from Shift to d: a capital", typed->str, "D");
  check_int ("and small letters after", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  reset (w);

  /* accents */
  down (w, 1, "e");
  wait_ms (LONG_PRESS_MS + 80);
  check_int ("holding e shows its accents", w->popup.active, TRUE);
  if (w->popup.active) {
    g_autofree char *row = NULL;
    GString *s = g_string_new (NULL);

    for (int i = 0; i < w->popup.options->len; i++)
      g_string_append_printf (s, "%s ", (char *) g_ptr_array_index (w->popup.options, i));
    row = g_string_free (s, FALSE);
    check_str ("the row of accents", row, "ë é e è ê ě ẽ ē ė ę ");
    snap (window, w, "06-accents.png");
    key_xy (w, "e", &x, &y);
    send_touch (w, GDK_TOUCH_UPDATE, 1, x - pos_osk_widget_get_current_layer (w)->key_width, y - 40);
    snap (window, w, "07-accents-sel.png");
    send_touch (w, GDK_TOUCH_END, 1, x - pos_osk_widget_get_current_layer (w)->key_width, y - 40);
  }
  check_str ("one to the left of e is é", typed->str, "é");
  check_int ("the row is gone", w->popup.active, FALSE);
  reset (w);

  down (w, 1, "e");
  wait_ms (LONG_PRESS_MS + 80);
  up (w, 1, "e");
  check_str ("held and let go without moving: plain e", typed->str, "e");
  reset (w);

  down (w, 1, "o");
  wait_ms (LONG_PRESS_MS + 80);
  snap (window, w, "08-accents-o.png");
  up (w, 1, "o");
  reset (w);
  down (w, 1, "a");
  wait_ms (LONG_PRESS_MS + 80);
  snap (window, w, "09-accents-a.png");
  up (w, 1, "a");
  reset (w);
  down (w, 1, "c");
  wait_ms (LONG_PRESS_MS + 80);
  snap (window, w, "10-accents-c.png");
  up (w, 1, "c");
  reset (w);

  /* a quick tap on a key with accents types it */
  tap (w, "e");
  check_str ("a tap on e", typed->str, "e");
  reset (w);

  /* Return held: a new line, typed while it is held and once */
  down (w, 1, "return");
  wait_ms (LONG_PRESS_MS + 80);
  check_str ("holding Return: a new line while it is held", typed->str, "<NEWLINE>");
  wait_ms (LONG_PRESS_MS + 80);
  check_str ("held on: still the one", typed->str, "<NEWLINE>");
  up (w, 1, "return");
  check_str ("letting go types nothing more", typed->str, "<NEWLINE>");
  reset (w);
  tap (w, "return");
  check_str ("a tap on Return is Return", typed->str, "\n");
  reset (w);

  /* the space bar as a touch pad */
  down (w, 1, "space");
  wait_ms (LONG_PRESS_MS + 80);
  check_int ("holding space: touch pad", pos_osk_widget_get_mode (w), POS_OSK_WIDGET_MODE_CURSOR);
  snap (window, w, "11-touchpad.png");
  key_xy (w, "space", &x, &y);
  send_touch (w, GDK_TOUCH_UPDATE, 1, x + 3 * CURSOR_STEP_X + 1, y);
  send_touch (w, GDK_TOUCH_UPDATE, 1, x, y);
  send_touch (w, GDK_TOUCH_END, 1, x, y);
  check_str ("three right, three left, no space", typed->str, "<RIGHT><RIGHT><RIGHT><LEFT><LEFT><LEFT>");
  check_int ("letters again", pos_osk_widget_get_mode (w), POS_OSK_WIDGET_MODE_KEYBOARD);
  reset (w);

  tap (w, "space");
  check_str ("a tap on space", typed->str, " ");
  reset (w);

  /* under the keys */
  tap (w, "emoji");
  tap (w, "mic");
  check_str ("emoji and dictation", strstr (log_events->str, "strip:") ?: "", "strip:emoji down:- strip:mic ");
  check_str ("they type nothing", typed->str, "");
  reset (w);

  /* return */
  type (w, "a");
  tap (w, "return");
  check_str ("return", typed->str, "a\n");
  reset (w);

  /* capitals where a sentence starts */
  emulate_sentences = TRUE;
  pos_osk_widget_set_autoshift (w, TRUE, TRUE);
  check_int ("an empty field: capitals", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_CAPS);
  snap (window, w, "12-autoshift.png");
  tap (w, "H");
  type (w, "i");
  tap (w, "sym");
  tap (w, ".");
  check_int ("a full stop: still numbers", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_SYMBOLS);
  tap (w, "space");
  check_int ("then a space: capitals again", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_CAPS);
  tap (w, "Y");
  type (w, "o");
  check_str ("two sentences", typed->str, "Hi. Yo");
  /* the owner turns the automatic capital off */
  type (w, " ");
  tap (w, "sym");
  tap (w, "?");
  tap (w, "space");
  check_int ("after ? and space: capitals", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_CAPS);
  wait_ms (400);
  tap (w, "shift");
  check_int ("Shift turns that off", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  pos_osk_widget_set_autoshift (w, TRUE, FALSE);
  check_int ("and it stays off while nothing changes", pos_osk_widget_get_layer (w), POS_OSK_WIDGET_LAYER_NORMAL);
  type (w, "n");
  check_str ("a small letter by choice", typed->str, "Hi. Yo ? n");
  reset (w);

  /* every key is found at its own centre, and between keys the nearer one wins */
  {
    PosOskWidgetKeyboardLayer *layer = pos_osk_widget_get_current_layer (w);
    int wrong = 0;

    for (int r = 0; r < layer->n_rows; r++) {
      PosOskWidgetRow *row = &layer->rows[r];

      for (int k = 0; k < row->geoms->len; k++) {
        TactusGeom *g = &g_array_index (row->geoms, TactusGeom, k);

        if (tactus_hit_test (w, g->vx + g->vw / 2, g->vy + g->vh / 2) != g)
          wrong++;
        if (tactus_hit_test (w, g->vx + 1, g->vy - w->gap_v / 2 + 1) != g)
          wrong++;
        if (tactus_hit_test (w, g->vx + g->vw - 1, g->vy + g->vh + w->gap_v / 2 - 1) != g)
          wrong++;
      }
    }
    check_int ("every key answers at its centre and to its half of the gaps", wrong, 0);
    check_int ("left of a: a", tactus_hit_test (w, 2, find_key (w, "a")->vy + 5) == find_key (w, "a"), TRUE);
    check_int ("right of l: l", tactus_hit_test (w, width - 2, find_key (w, "l")->vy + 5) == find_key (w, "l"), TRUE);
    check_int ("just under the space bar: space",
               tactus_hit_test (w, width / 2, tactus_keys_bottom (w) + 6) == find_key (w, "space"), TRUE);
    check_int ("under the middle of the keys, lower: nothing",
               tactus_hit_test (w, width / 2, tactus_keys_bottom (w) + 30) == NULL, TRUE);
  }

  /* a pressed key, and dark */
  down (w, 1, "g");
  snap (window, w, "13-pressed.png");
  up (w, 1, "g");
  reset (w);
  tactus_theme_init (&w->theme, TRUE);
  snap (window, w, "14-dark-lower.png");
  tap (w, "shift");
  snap (window, w, "15-dark-shift.png");
  reset (w);
  down (w, 1, "e");
  wait_ms (LONG_PRESS_MS + 80);
  snap (window, w, "16-dark-accents.png");
  up (w, 1, "e");
  reset (w);

  /* the terminal's keys: no room for accents above, and a bar may sit on top */
  tactus_theme_init (&w->theme, FALSE);
  if (!pos_osk_widget_set_layout (w, "terminal", "terminal", "Terminal", "terminal", NULL, &err))
    g_error ("layout: %s", err->message);
  gtk_widget_queue_resize (GTK_WIDGET (w));
  while (g_main_context_iteration (NULL, FALSE))
    ;
  pos_osk_widget_set_flat_top (w, TRUE);
  snap (window, w, "17-terminal.png");
  g_print ("terminal: %dx%d, clear %u, panel %u\n",
           gtk_widget_get_allocated_width (GTK_WIDGET (w)),
           gtk_widget_get_allocated_height (GTK_WIDGET (w)),
           pos_osk_widget_get_overhang (w), pos_osk_widget_get_panel_height (w));

  g_print ("\n%d checks, %d failed\n", checks, failures);
  return failures ? 1 : 0;
}
