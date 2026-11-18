/*
 * The emoji page of Tactus, tried with no window on screen:
 * taps, slides, the signs of the kinds, skin tones, the keys around.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "../src/pos-emoji-picker.c"

#include "pos-main.h"

static GString *picked;
static int n_delete, n_done, n_mic, n_search;
static int checks, failures;


static void
on_picked (PosEmojiPicker *self, const char *emoji)
{
  g_string_append (picked, emoji);
}


static void
count (int *n)
{
  (*n)++;
}


static void
check (const char *what, gboolean ok, const char *detail)
{
  checks++;
  if (!ok)
    failures++;
  g_print ("%s %-52s %s\n", ok ? "ok  " : "FAIL", what, detail ?: "");
}


static void
wait_ms (int ms)
{
  gint64 until = g_get_monotonic_time () + ms * 1000;

  while (g_get_monotonic_time () < until) {
    while (g_main_context_iteration (NULL, FALSE))
      ;
    g_usleep (2000);
  }
}


static void
touch (PosEmojiPicker *w, GdkEventType type, double x, double y)
{
  GdkEvent *event = gdk_event_new (type);
  GdkSeat *seat = gdk_display_get_default_seat (gdk_display_get_default ());

  event->touch.window = g_object_ref (gtk_widget_get_window (GTK_WIDGET (w)));
  event->touch.sequence = GINT_TO_POINTER (1);
  event->touch.x = x;
  event->touch.y = y;
  event->touch.time = g_get_monotonic_time () / 1000;
  gdk_event_set_device (event, gdk_seat_get_pointer (seat));
  gtk_widget_event (GTK_WIDGET (w), event);
  gdk_event_free (event);
}


static void
tap (PosEmojiPicker *w, double x, double y)
{
  touch (w, GDK_TOUCH_BEGIN, x, y);
  touch (w, GDK_TOUCH_END, x, y);
}


int
main (int argc, char **argv)
{
  GtkWidget *window;
  PosEmojiPicker *w;
  double row0, pitch, col0, max;
  g_autofree char *first = NULL;
  g_autofree char *detail = NULL;
  EmojiItem *toned = NULL;
  guint toned_at = 0;

  gtk_init (&argc, &argv);
  pos_init ();
  picked = g_string_new (NULL);

  w = POS_EMOJI_PICKER (pos_emoji_picker_new ());
  g_signal_connect (w, "emoji-picked", G_CALLBACK (on_picked), NULL);
  g_signal_connect_swapped (w, "delete-last", G_CALLBACK (count), &n_delete);
  g_signal_connect_swapped (w, "done", G_CALLBACK (count), &n_done);
  g_signal_connect_swapped (w, "mic", G_CALLBACK (count), &n_mic);
  g_signal_connect_swapped (w, "search", G_CALLBACK (count), &n_search);

  window = gtk_offscreen_window_new ();
  gtk_widget_set_size_request (GTK_WIDGET (w), 360, -1);
  gtk_container_add (GTK_CONTAINER (window), GTK_WIDGET (w));
  gtk_widget_show_all (window);
  /* until every emoji is in */
  for (int i = 0; i < 400 && w->populate_id; i++)
    wait_ms (10);

  row0 = w->row0;
  pitch = w->pitch;
  col0 = w->col0;
  max = scroll_max (w);
  g_print ("page %dx%d, %d rows, pitch %.1f, row of emoji %.0f long\n", w->width, w->height, w->rows, pitch,
           w->content);
  for (int k = 0; k < TACTUS_N_KINDS; k++)
    g_print ("  kind %d: %u emoji from %.0f\n", k, w->kinds[k]->len, w->kind_x[k]);

  check ("there are emoji of every kind but the ones used lately",
         w->kinds[TACTUS_KIND_RECENT]->len == 0 && w->kinds[TACTUS_KIND_SMILEYS]->len > 100 &&
         w->kinds[TACTUS_KIND_FLAGS]->len > 50, NULL);

  /* a tap */
  first = g_strdup (((EmojiItem *) g_ptr_array_index (w->kinds[TACTUS_KIND_SMILEYS], 0))->text);
  tap (w, col0, row0);
  check ("a tap on the first emoji types it", g_str_equal (picked->str, first), picked->str);
  g_string_truncate (picked, 0);
  tap (w, col0 + pitch, row0 + 2 * pitch);
  check ("a tap on another",
         g_str_equal (picked->str, ((EmojiItem *) g_ptr_array_index (w->kinds[TACTUS_KIND_SMILEYS], 6))->text),
         picked->str);
  g_string_truncate (picked, 0);

  /* a slide */
  touch (w, GDK_TOUCH_BEGIN, 300, row0);
  for (int x = 290; x >= 100; x -= 10)
    touch (w, GDK_TOUCH_UPDATE, x, row0);
  wait_ms (120);
  touch (w, GDK_TOUCH_END, 100, row0);
  detail = g_strdup_printf ("slid %.0f", w->scroll);
  check ("a slide moves the emoji and types none", picked->len == 0 && fabs (w->scroll - 190.0) < 11.0, detail);
  check ("a finger that rested first leaves them where they are", w->tick_id == 0, NULL);

  /* past the start */
  touch (w, GDK_TOUCH_BEGIN, 100, row0);
  touch (w, GDK_TOUCH_UPDATE, 200, row0);
  touch (w, GDK_TOUCH_UPDATE, 350, row0);
  touch (w, GDK_TOUCH_UPDATE, 500, row0);
  check ("pulled past the start they follow by less", w->scroll < 0.0 && scroll_shown (w) > w->scroll, NULL);
  wait_ms (120);
  touch (w, GDK_TOUCH_END, 500, row0);
  check ("and go back to it when let go", w->jumping && fabs (w->jump_to) < 0.5, NULL);
  stop_sliding (w);
  w->scroll = 0.0;

  /* the signs */
  tap (w, bar_x (w, TACTUS_KIND_FOOD), w->bar_y);
  check ("the apple goes to the food", w->jumping && fabs (w->jump_to - w->kind_x[TACTUS_KIND_FOOD]) < 1.0, NULL);
  stop_sliding (w);
  w->scroll = w->kind_x[TACTUS_KIND_FOOD];
  check ("and the apple is the sign in view", kind_in_view (w) == TACTUS_KIND_FOOD, NULL);
  tap (w, bar_x (w, TACTUS_KIND_RECENT), w->bar_y);
  check ("the clock does nothing while nothing was used", !w->jumping, NULL);
  w->scroll = max;
  check ("at the end the flag is in view", kind_in_view (w) == TACTUS_KIND_FLAGS, NULL);

  /* skin tones */
  for (guint i = 0; i < w->kinds[TACTUS_KIND_SMILEYS]->len && !toned; i++) {
    EmojiItem *item = g_ptr_array_index (w->kinds[TACTUS_KIND_SMILEYS], i);

    if (item->tones) {
      toned = item;
      toned_at = i;
    }
  }
  check ("some emoji come in skin tones", toned != NULL, toned ? toned->text : NULL);
  if (toned) {
    guint col = toned_at / w->rows, row = toned_at % w->rows;
    double cx, cy = row0 + row * pitch;
    g_autofree char *plain = emoji_text (toned->data, 0, NULL);
    g_autofree char *medium = emoji_text (toned->data, 0x1f3fd, NULL);

    w->scroll = CLAMP (w->kind_x[TACTUS_KIND_SMILEYS] + col * pitch - 3 * pitch, 0.0, max);
    cx = (col0 - pitch / 2) + w->kind_x[TACTUS_KIND_SMILEYS] + (col + 0.5) * pitch - w->scroll;

    tap (w, cx, cy);
    check ("a tap types it plain", g_str_equal (picked->str, plain), picked->str);
    g_string_truncate (picked, 0);

    touch (w, GDK_TOUCH_BEGIN, cx, cy);
    wait_ms (LONG_PRESS_MS + 80);
    check ("held, its tones open", w->tones_open && w->tones_item == toned, NULL);
    touch (w, GDK_TOUCH_UPDATE, w->tones_x + (6.0 + 3.5 * E_TONES_PITCH) * w->vs, cy);
    touch (w, GDK_TOUCH_END, w->tones_x + (6.0 + 3.5 * E_TONES_PITCH) * w->vs, cy);
    check ("the fourth is the medium tone", g_str_equal (picked->str, medium), picked->str);
    g_string_truncate (picked, 0);
  }

  /* the keys around */
  w->scroll = 0.0;
  touch (w, GDK_TOUCH_BEGIN, w->width - E_DELETE_X * w->s, w->bar_y);
  check ("the delete key deletes as it goes down", n_delete == 1, NULL);
  wait_ms (DELETE_DELAY_MS + 3 * DELETE_EVERY_MS + 40);
  touch (w, GDK_TOUCH_END, w->width - E_DELETE_X * w->s, w->bar_y);
  detail = g_strdup_printf ("%d", n_delete);
  check ("and on while it is held", n_delete >= 4 && n_delete <= 6, detail);
  wait_ms (3 * DELETE_EVERY_MS);
  check ("and stops when let go", n_delete <= 6, NULL);

  tap (w, E_ABC_X * w->s, w->abc_y);
  check ("ABC", n_done == 1, NULL);
  tap (w, w->width - E_MIC_X * w->s, w->mic_y);
  check ("the microphone", n_mic == 1, NULL);
  tap (w, 180, (E_FIELD_TOP + E_FIELD_H / 2) * w->vs);
  check ("the search field", n_search == 1, NULL);
  check ("none of them typed an emoji", picked->len == 0, picked->str);

  /* the emoji used lately lead the next time the page comes up */
  gtk_widget_hide (GTK_WIDGET (w));
  gtk_widget_show (GTK_WIDGET (w));
  wait_ms (50);
  detail = g_strdup_printf ("%u", w->kinds[TACTUS_KIND_RECENT]->len);
  check ("what was typed is among the ones used lately", w->kinds[TACTUS_KIND_RECENT]->len == 4, detail);
  if (w->kinds[TACTUS_KIND_RECENT]->len > 0) {
    tap (w, col0, row0);
    check ("the latest first, with its tone",
           toned == NULL || g_str_has_prefix (picked->str, "") , picked->str);
    check ("the clock is the sign in view", kind_in_view (w) == TACTUS_KIND_RECENT, NULL);
  }

  /* one the font has no picture for is kept out of sight, on the page and in the search */
  {
    g_autoptr (GSettings) settings = g_settings_new ("mobi.phosh.osk.EmojiPicker");
    g_autoptr (GVariant) before = g_settings_get_value (settings, "recent-emoji");
    g_autoptr (GtkWidget) search = g_object_ref_sink (pos_emoji_search_new ());
    guint shown = w->kinds[TACTUS_KIND_RECENT]->len;
    guint32 code = 0x2fe0; /* not assigned to anything: no font draws it */
    GVariantBuilder builder;
    GVariantIter iter;
    GVariant *entry;

    g_variant_builder_init (&builder, G_VARIANT_TYPE ("a((auss)u)"));
    g_variant_builder_add (&builder, "(@(auss)u)",
                           g_variant_new ("(@auss)",
                                          g_variant_new_fixed_array (G_VARIANT_TYPE_UINT32, &code, 1, sizeof code),
                                          "no such emoji", ""),
                           0);
    g_variant_iter_init (&iter, before);
    while ((entry = g_variant_iter_next_value (&iter))) {
      g_variant_builder_add_value (&builder, entry);
      g_variant_unref (entry);
    }
    g_settings_set_value (settings, "recent-emoji", g_variant_builder_end (&builder));

    load_recent (w);
    detail = g_strdup_printf ("%u shown of %u kept", w->kinds[TACTUS_KIND_RECENT]->len, shown + 1);
    check ("one the font has no picture for is not shown", shown > 0 && w->kinds[TACTUS_KIND_RECENT]->len == shown,
           detail);
    pos_emoji_search_reset (POS_EMOJI_SEARCH (search));
    detail = g_strdup_printf ("%u", POS_EMOJI_SEARCH (search)->found->len);
    check ("nor by the search before anything is typed", POS_EMOJI_SEARCH (search)->found->len == shown, detail);
    pos_emoji_search_type (POS_EMOJI_SEARCH (search), "grin");
    detail = g_strdup_printf ("%u", POS_EMOJI_SEARCH (search)->found->len);
    check ("the search finds emoji by a part of their name", POS_EMOJI_SEARCH (search)->found->len >= 3, detail);
    g_settings_set_value (settings, "recent-emoji", before);
  }

  g_print ("\n%d checks, %d failed\n", checks, failures);
  return failures ? 1 : 0;
}
