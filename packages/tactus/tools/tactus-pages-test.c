/*
 * The pages of Tactus that it doesn't draw itself (the emoji,
 * the number pad), with no window on screen: their size, and a picture of
 * each in light and dark.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-draw.h"
#include "pos-emoji-picker.h"
#include "pos-keypad.h"
#include "pos-main.h"
#include "pos-style-manager.h"

#include <gtk/gtk.h>
#include <handy.h>

#define WIDTH  360
#define PANEL  267
#define CLEAR  59

static int snap_height = PANEL + CLEAR;
static int snap_clear = CLEAR;


static void
settle (void)
{
  for (int i = 0; i < 50; i++) {
    while (g_main_context_iteration (NULL, FALSE))
      ;
    g_usleep (10000);
  }
}


static void
snap (GtkWidget *window, const char *dir, const char *name, gboolean dark)
{
  const int scale = 3;
  cairo_surface_t *surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, WIDTH * scale, snap_height * scale);
  cairo_t *cr = cairo_create (surface);
  g_autofree char *path = g_build_filename (dir, name, NULL);

  settle ();
  cairo_scale (cr, scale, scale);
  /* a text page behind, so that what is clear shows */
  cairo_set_source_rgb (cr, dark ? 0.0 : 1.0, dark ? 0.0 : 1.0, dark ? 0.0 : 1.0);
  cairo_paint (cr);
  cairo_translate (cr, 0, snap_clear);
  gtk_widget_draw (gtk_bin_get_child (GTK_BIN (window)), cr);
  cairo_destroy (cr);
  cairo_surface_write_to_png (surface, path);
  cairo_surface_destroy (surface);
}


/* As the input surface does for the number pad */
static gboolean
on_page_draw (GtkWidget *widget, cairo_t *cr)
{
  gtk_render_background (gtk_widget_get_style_context (widget), cr, 0, 0,
                         gtk_widget_get_allocated_width (widget),
                         gtk_widget_get_allocated_height (widget));
  return GDK_EVENT_PROPAGATE;
}


/* A page that knows its own height */
static GtkWidget *
own_page (GtkWidget *widget, const char *what, int *height)
{
  GtkWidget *window = gtk_offscreen_window_new ();
  int min = 0, nat = 0;

  gtk_widget_set_visible (widget, TRUE);
  gtk_container_add (GTK_CONTAINER (window), widget);
  gtk_widget_set_size_request (widget, WIDTH, -1);
  gtk_widget_show (window);
  settle ();
  gtk_widget_get_preferred_height (widget, &min, &nat);
  g_print ("%s: %dx%d (wants %d)\n", what, gtk_widget_get_allocated_width (widget),
           gtk_widget_get_allocated_height (widget), nat);
  *height = gtk_widget_get_allocated_height (widget);
  return window;
}


static GtkWidget *
page (GtkWidget *widget, const char *what)
{
  GtkWidget *window = gtk_offscreen_window_new ();
  int min = 0, nat = 0;

  gtk_widget_set_visible (widget, TRUE);
  gtk_container_add (GTK_CONTAINER (window), widget);
  gtk_widget_get_preferred_height_for_width (widget, WIDTH, &min, &nat);
  g_print ("%s: at least %d high, would like %d\n", what, min, nat);
  gtk_widget_set_size_request (widget, WIDTH, PANEL);
  gtk_window_set_default_size (GTK_WINDOW (window), WIDTH, PANEL);
  gtk_widget_show (window);
  settle ();
  g_print ("%s: given %dx%d\n", what, gtk_widget_get_allocated_width (widget),
           gtk_widget_get_allocated_height (widget));
  return window;
}


int
main (int argc, char **argv)
{
  const char *dir = argc > 1 ? argv[1] : ".";
  g_autoptr (PosStyleManager) style = NULL;
  g_autoptr (GtkCssProvider) provider = NULL;
  GtkWidget *emoji, *keypad, *pad;
  TactusTheme theme;

  g_mkdir_with_parents (dir, 0755);
  gtk_init (&argc, &argv);
  hdy_init ();
  pos_init ();

  style = pos_style_manager_new ();
  provider = gtk_css_provider_new ();
  gtk_style_context_add_provider_for_screen (gdk_screen_get_default (), GTK_STYLE_PROVIDER (provider),
                                             GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 10);

  emoji = page (gtk_label_new (""), "nothing");
  pad = pos_keypad_new ();
  pos_keypad_set_letters_visible (POS_KEYPAD (pad), TRUE);
  pos_keypad_set_symbols_visible (POS_KEYPAD (pad), TRUE);
  g_signal_connect (pad, "draw", G_CALLBACK (on_page_draw), NULL);
  keypad = page (pad, "number pad");

  for (int dark = 0; dark <= 1; dark++) {
    g_autofree char *css = NULL;

    tactus_theme_init (&theme, dark);
    css = tactus_theme_css (&theme);
    gtk_css_provider_load_from_data (provider, css, -1, NULL);
    snap (keypad, dir, dark ? "keypad-dark.png" : "keypad-light.png", dark);
  }

  /* the emoji page and the search for emoji draw themselves, to their own height */
  {
    GtkWidget *search = pos_emoji_search_new ();
    GtkWidget *window;
    int height = 0;

    snap_clear = 0;
    window = own_page (gtk_bin_get_child (GTK_BIN (emoji)) ? pos_emoji_picker_new () : pos_emoji_picker_new (),
                       "emoji", &height);
    snap_height = height;
    snap (window, dir, "emoji-light.png", FALSE);

    window = own_page (search, "emoji search", &height);
    snap_height = height;
    snap (window, dir, "search-empty.png", FALSE);
    pos_emoji_search_type (POS_EMOJI_SEARCH (search), "smil");
    snap (window, dir, "search-smil.png", FALSE);
  }
  return 0;
}
