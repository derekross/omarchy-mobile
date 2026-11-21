/*
 * Checks Tactus's Paste key's "is there anything to paste": which kinds of
 * copy count, what the clipboard history's file says, and that a change of
 * the file is noticed without anyone asking.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-clipboard.h"

#include <glib/gstdio.h>
#include <gio/gio.h>

static int checks, failures, changes;

static void
check (const char *what, gboolean got, gboolean want)
{
  checks++;
  if (!!got == !!want) {
    g_print ("ok   %s\n", what);
  } else {
    failures++;
    g_print ("FAIL %s: got %d want %d\n", what, got, want);
  }
}

static gboolean
has (const char *json)
{
  return tactus_clipboard_history_newest (json, -1, NULL);
}

static gboolean
on_changed (gpointer data)
{
  changes++;
  return G_SOURCE_REMOVE;
}

/* Until the watcher says what is wanted, or two seconds */
static gboolean
wait_for (TactusClipboard *clip, gboolean history)
{
  gint64 end = g_get_monotonic_time () + 2 * G_TIME_SPAN_SECOND;

  while (g_get_monotonic_time () < end) {
    while (g_main_context_iteration (NULL, FALSE))
      ;
    if (tactus_clipboard_has_history (clip) == history)
      return TRUE;
    g_usleep (5000);
  }
  return FALSE;
}

int
main (int argc, char *argv[])
{
  TactusClipEntry e = { .index = -1 };

  /* kinds of copy */
  check ("plain text pastes", tactus_clipboard_mime_pastes ("text/plain"), TRUE);
  check ("so does it with its character set", tactus_clipboard_mime_pastes ("text/plain;charset=utf-8"), TRUE);
  check ("and a web page's text", tactus_clipboard_mime_pastes ("text/html"), TRUE);
  check ("text as an X11 program names it", tactus_clipboard_mime_pastes ("UTF8_STRING"), TRUE);
  check ("a picture", tactus_clipboard_mime_pastes ("image/png"), TRUE);
  check ("not a password manager's mark alone", tactus_clipboard_mime_pastes ("x-kde-passwordManagerHint"), FALSE);
  check ("nor something of a program's own", tactus_clipboard_mime_pastes ("application/x-private"), FALSE);
  check ("nor nothing", tactus_clipboard_mime_pastes (NULL), FALSE);

  /* the history's file, by the shell's own rules */
  check ("an empty list is no history", has ("[]\n"), FALSE);
  check ("nor is no file's worth of nothing", has (""), FALSE);
  check ("nor something that isn't a list", has ("{\"type\":\"text\",\"text\":\"a\"}"), FALSE);
  check ("nor what isn't JSON", has ("[ {\"type\": "), FALSE);
  check ("a text is", has ("[\n  {\n    \"type\": \"text\",\n    \"text\": \"hello\"\n  }\n]\n"), TRUE);
  check ("a text of white space only is not", has ("[{\"type\":\"text\",\"text\":\" \\n\\t \"}]"), FALSE);
  check ("an entry of no kind is not", has ("[{\"text\":\"hello\"}]"), FALSE);
  check ("an older file's plain string is", has ("[\"hello\"]"), TRUE);
  check ("and its \"kind\" for \"type\"", has ("[{\"kind\":\"text\",\"text\":\"hello\"}]"), TRUE);
  check ("a picture with a path is", has ("[{\"type\":\"image\",\"path\":\"/tmp/a.png\",\"mime\":\"image/png\"}]"), TRUE);
  check ("one without is not", has ("[{\"type\":\"image\",\"mime\":\"image/png\"}]"), FALSE);
  check ("numbers and nulls are passed over", has ("[1, null, [], {\"type\":\"file\"}]"), FALSE);

  check ("the newest entry is the first that counts",
         tactus_clipboard_history_newest ("[{\"type\":\"text\",\"text\":\"  \"}, null, {\"type\":\"text\",\"text\":\"b\"}, \"c\"]",
                                          -1, &e) && e.index == 2 && !e.image, TRUE);
  check ("a picture comes with its path and kind",
         tactus_clipboard_history_newest ("[{\"type\":\"image\",\"path\":\"/tmp/a.jpg\",\"mime\":\"image/jpeg\"},{\"type\":\"text\",\"text\":\"b\"}]",
                                          -1, &e) && e.index == 0 && e.image &&
         g_strcmp0 (e.path, "/tmp/a.jpg") == 0 && g_strcmp0 (e.mime, "image/jpeg") == 0, TRUE);
  g_free (e.path);
  g_free (e.mime);
  check ("and is a PNG where the file doesn't say",
         tactus_clipboard_history_newest ("[{\"type\":\"image\",\"path\":\"/tmp/a\"}]", -1, &e) &&
         g_strcmp0 (e.mime, "image/png") == 0, TRUE);
  g_free (e.path);
  g_free (e.mime);
  {
    g_autofree char *path = tactus_clipboard_history_path ();

    check ("the history is where the shell keeps it",
           g_str_has_suffix (path, "/.local/state/omarchy/clipboard-history.json"), TRUE);
  }

  /* the watcher: told by the file, not by a clock */
  {
    g_autofree char *dir = g_dir_make_tmp ("tactus-paste-XXXXXX", NULL);
    g_autofree char *path = g_build_filename (dir, "clipboard-history.json", NULL);
    g_autofree char *other = g_build_filename (dir, "new.json", NULL);
    TactusClipboard *clip = tactus_clipboard_new (NULL, NULL, path, on_changed, NULL);

    check ("no file: no history", wait_for (clip, FALSE) && !tactus_clipboard_has_history (clip), TRUE);
    check ("the clipboard, where the compositor doesn't show it, counts as holding something",
           tactus_clipboard_has_copy (clip) && tactus_clipboard_can_paste (clip), TRUE);
    check ("and there is no newest entry", tactus_clipboard_newest (clip) == NULL, TRUE);

    g_file_set_contents (path, "[{\"type\":\"text\",\"text\":\"one\"}]\n", -1, NULL);
    check ("the file is written: a history", wait_for (clip, TRUE), TRUE);
    check ("whose newest entry is the first", tactus_clipboard_newest (clip) &&
           tactus_clipboard_newest (clip)->index == 0, TRUE);

    g_file_set_contents (path, "[]\n", -1, NULL);
    check ("the history is cleared: none", wait_for (clip, FALSE), TRUE);

    /* replaced by a rename, as an editor or a careful writer does */
    g_file_set_contents (other, "[{\"type\":\"image\",\"path\":\"/tmp/a.png\"}]\n", -1, NULL);
    g_rename (other, path);
    check ("the file is replaced: a history again", wait_for (clip, TRUE), TRUE);
    check ("and the newest is the picture", tactus_clipboard_newest (clip) &&
           tactus_clipboard_newest (clip)->image, TRUE);

    g_unlink (path);
    check ("the file is removed: none", wait_for (clip, FALSE), TRUE);
    /* the clipboard counted as holding something throughout, so there was always something to paste */
    check ("and nobody was told of a change that was none", changes == 0, TRUE);

    tactus_clipboard_free (clip);
    g_rmdir (dir);
  }

  g_print ("%d checks, %d failed\n", checks, failures);
  return failures ? 1 : 0;
}
