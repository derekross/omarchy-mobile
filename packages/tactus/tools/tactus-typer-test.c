/*
 * Tactus's typing, tried against make-believe text fields: one
 * that tells its text and can take text away (as GTK, Qt and the browser do),
 * one that tells nothing (as the GPUI applications), one that is slow, one
 * that ignores requests to delete, and the browser, which tells nothing more
 * until its last word was answered and takes text away counting from the
 * cursor it last told of.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-typer.h"

#include <glib.h>
#include <glib/gstdio.h>

#include <stdio.h>
#include <string.h>

typedef struct {
  char  *text;
  gsize  cursor, anchor;
} Report;

typedef struct {
  gboolean     tells;
  gboolean     ignores_erase;
  gboolean     enter_sends;
  gboolean     hold;
  GString     *text;
  gsize        cursor, anchor;
  GPtrArray   *held;
  gint64       now;
  TactusTyper *typer;
  gboolean     shift;
  guint        by_keys, by_field;

  /* The browser */
  gboolean     gated;        /* it tells nothing more until its last word was answered */
  gboolean     answered;     /* the keyboard's answers reach it */
  guint        commits, done; /* its words so far, and the last one it was answered for */
  Report      *waiting;      /* what it has to tell once answered */
  Report      *told;         /* what it last told */
  guint        lost_erases;  /* requests to take text away that it could not place */

  /* The keyboard's answers */
  gboolean     ack_due;
  guint        acks;
} Field;

static int failed, checked;

/*
 * The text field
 */

static void
report_free (gpointer data)
{
  Report *r = data;

  g_free (r->text);
  g_free (r);
}


static Report *
report_new (Field *f)
{
  Report *r = g_new0 (Report, 1);

  r->text = g_strdup (f->text->str);
  r->cursor = f->cursor;
  r->anchor = f->anchor;
  return r;
}


static gboolean
report_same (const Report *a, const Report *b)
{
  return a && b && g_str_equal (a->text, b->text) && a->cursor == b->cursor && a->anchor == b->anchor;
}

static void gated_send (Field *f);

/* The keyboard's answers go out once the typing engine is done with what it was told */
static void
pump (Field *f)
{
  while (f->ack_due) {
    f->ack_due = FALSE;
    if (f->gated && f->answered) {
      f->done = f->commits;
      gated_send (f);
    }
  }
}

/* The browser tells what it has to tell, if its last word was answered */
static void
gated_send (Field *f)
{
  Report *r;

  if (f->done != f->commits || f->waiting == NULL)
    return;

  r = g_steal_pointer (&f->waiting);
  g_clear_pointer (&f->told, report_free);
  f->told = r;
  f->commits++;
  tactus_typer_state (f->typer, r->text, r->cursor, r->anchor);
  pump (f);
}

/* The page in the browser has changed */
static void
gated_set (Field *f)
{
  Report *r = report_new (f);

  if (report_same (r, f->told)) {
    report_free (r);
    return;
  }
  g_clear_pointer (&f->waiting, report_free);
  f->waiting = r;
  gated_send (f);
}


static void
deliver (Field *f, Report *r)
{
  if (f->tells)
    tactus_typer_state (f->typer, r->text, r->cursor, r->anchor);
  else
    tactus_typer_state (f->typer, NULL, 0, 0);
  pump (f);
}


static void
report (Field *f)
{
  Report *r;

  if (f->gated) {
    gated_set (f);
    return;
  }

  r = report_new (f);
  if (f->hold) {
    g_ptr_array_add (f->held, r);
    return;
  }
  deliver (f, r);
  report_free (r);
}


static void
flush (Field *f)
{
  /* in their order: what it has to tell meanwhile comes after what it kept */
  while (f->held->len > 0) {
    Report *r = g_ptr_array_steal_index (f->held, 0);

    deliver (f, r);
    report_free (r);
  }
  f->hold = FALSE;
}


static gboolean
delete_selection (Field *f)
{
  gsize lo = MIN (f->cursor, f->anchor), hi = MAX (f->cursor, f->anchor);

  if (lo == hi)
    return FALSE;
  g_string_erase (f->text, lo, hi - lo);
  f->cursor = f->anchor = lo;
  return TRUE;
}


static gboolean
backspace (Field *f)
{
  const char *prev;

  if (delete_selection (f))
    return TRUE;
  if (f->cursor == 0)
    return FALSE;
  prev = g_utf8_find_prev_char (f->text->str, f->text->str + f->cursor);
  g_string_erase (f->text, prev - f->text->str, f->text->str + f->cursor - prev);
  f->cursor = f->anchor = prev - f->text->str;
  return TRUE;
}


static void
op_commit (const char *text, gpointer data)
{
  Field *f = data;

  /* what the keyboard sends is an answer too */
  if (f->gated)
    f->done = f->commits;
  delete_selection (f);
  g_string_insert (f->text, f->cursor, text);
  f->cursor += strlen (text);
  f->anchor = f->cursor;
  /* The browser first tells what it had to tell before this; the page's new
   * text comes after, and waits for the next answer */
  if (f->gated)
    gated_send (f);
  report (f);
}


static void
op_erase (guint n_chars, guint n_bytes, gboolean by_keys, gpointer data)
{
  Field *f = data;

  if (by_keys) {
    f->by_keys += n_chars;
    for (guint i = 0; i < n_chars; i++) {
      if (backspace (f))
        report (f);
    }
    return;
  }

  f->by_field += n_chars;
  if (f->ignores_erase)
    return;
  if (f->gated) {
    f->done = f->commits;
    /* It counts from the cursor it last told of: behind, it takes nothing away */
    if (f->told == NULL || f->told->cursor != f->cursor || !g_str_equal (f->told->text, f->text->str)) {
      f->lost_erases++;
      gated_send (f);
      return;
    }
  }
  n_bytes = MIN (n_bytes, f->cursor);
  g_string_erase (f->text, f->cursor - n_bytes, n_bytes);
  f->cursor -= n_bytes;
  f->anchor = f->cursor;
  if (f->gated)
    gated_send (f);
  report (f);
}


static void
op_key (const char *symbol, gpointer data)
{
  Field *f = data;

  if (g_str_equal (symbol, "KEY_BACKSPACE")) {
    if (backspace (f))
      report (f);
  } else if (g_str_equal (symbol, "KEY_ENTER")) {
    if (f->enter_sends) {
      gboolean had = f->text->len > 0;

      g_string_truncate (f->text, 0);
      f->cursor = f->anchor = 0;
      if (had)
        report (f);
    } else {
      op_commit ("\n", f);
    }
  } else if (g_str_equal (symbol, "KEY_NEWLINE")) {
    /* Return with Shift: a line break in a field that sends on Return too */
    op_commit ("\n", f);
  } else if (g_str_equal (symbol, "KEY_LEFT")) {
    if (f->cursor > 0) {
      f->cursor = g_utf8_find_prev_char (f->text->str, f->text->str + f->cursor) - f->text->str;
      f->anchor = f->cursor;
      report (f);
    }
  } else if (g_str_equal (symbol, "KEY_RIGHT")) {
    if (f->cursor < f->text->len) {
      f->cursor = g_utf8_next_char (f->text->str + f->cursor) - f->text->str;
      f->anchor = f->cursor;
      report (f);
    }
  }
}


static void
op_shift (gboolean wanted, gboolean context_changed, gpointer data)
{
  Field *f = data;

  f->shift = wanted;
}


static void
op_wake (guint ms, gpointer data)
{
}


static void
op_ack (gpointer data)
{
  Field *f = data;

  f->acks++;
  f->ack_due = TRUE;
}


static gint64
clock_now (gpointer data)
{
  Field *f = data;

  return f->now;
}


static Field *
field_new (gboolean tells)
{
  static const TactusTyperOps ops = { op_commit, op_erase, op_key, op_shift, op_wake, op_ack };
  Field *f = g_new0 (Field, 1);

  f->tells = tells;
  f->text = g_string_new (NULL);
  f->held = g_ptr_array_new_with_free_func (report_free);
  f->now = 1000 * G_TIME_SPAN_SECOND;
  f->typer = tactus_typer_new (&ops, f);
  tactus_typer_set_clock (f->typer, clock_now, f);
  tactus_typer_focus (f->typer, TRUE);
  /* a text field says hello when it gets the keyboard */
  report (f);
  return f;
}

/* A text field in the browser, holding @text. @answered: the keyboard's
 * answers reach it. */
static Field *
field_new_browser (gboolean answered, const char *text)
{
  static const TactusTyperOps ops = { op_commit, op_erase, op_key, op_shift, op_wake, op_ack };
  Field *f = g_new0 (Field, 1);

  f->tells = TRUE;
  f->gated = TRUE;
  f->answered = answered;
  f->text = g_string_new (text);
  f->cursor = f->anchor = f->text->len;
  f->held = g_ptr_array_new_with_free_func (report_free);
  f->now = 1000 * G_TIME_SPAN_SECOND;
  f->typer = tactus_typer_new (&ops, f);
  tactus_typer_set_clock (f->typer, clock_now, f);
  tactus_typer_focus (f->typer, TRUE);
  /* It says hello without its text, and has the text to tell once answered */
  f->commits = 1;
  tactus_typer_state (f->typer, NULL, 0, 0);
  pump (f);
  gated_set (f);
  return f;
}


static void
field_free (Field *f)
{
  tactus_typer_free (f->typer);
  g_clear_pointer (&f->waiting, report_free);
  g_clear_pointer (&f->told, report_free);
  g_ptr_array_unref (f->held);
  g_string_free (f->text, TRUE);
  g_free (f);
}

/* The owner, or the application, changed the text field by other means than our keys */
static void
field_set (Field *f, const char *text, gsize cursor, gsize anchor)
{
  g_string_assign (f->text, text);
  f->cursor = cursor;
  f->anchor = anchor;
  report (f);
}

/*
 * The owner's fingers
 */

static void
advance (Field *f, guint ms)
{
  f->now += ms * G_TIME_SPAN_MILLISECOND;
  tactus_typer_poll (f->typer);
}


static void
press (Field *f, const char *symbol)
{
  TactusTap tap = { .valid = TRUE };

  advance (f, 130);
  tactus_typer_key (f->typer, symbol, g_utf8_strlen (symbol, -1) == 1 ? &tap : NULL);
}

/* Type text as on the keyboard: a small letter comes out as a capital while
 * Shift is on by itself; "\b" is Backspace and "\n" Return */
static void
type (Field *f, const char *text)
{
  for (const char *p = text; *p; p = g_utf8_next_char (p)) {
    char sym[8] = { 0 };

    g_utf8_strncpy (sym, p, 1);
    if (*p == '\b') {
      advance (f, 130);
      tactus_typer_backspace (f->typer, TACTUS_BACKSPACE_TAP);
    } else if (*p == '\n') {
      press (f, "KEY_ENTER");
    } else {
      if (g_ascii_islower (*p) && f->shift)
        sym[0] = g_ascii_toupper (*p);
      press (f, sym);
    }
  }
}

/*
 * Checks
 */

static void
expect (Field *f, const char *what, const char *text)
{
  g_autofree char *got = g_strescape (f->text->str, "\"");
  g_autofree char *want = g_strescape (text, "\"");
  gboolean ok = g_str_equal (f->text->str, text);

  checked++;
  if (!ok)
    failed++;
  printf ("%s %-44s \"%s\"", ok ? "  ok" : "FAIL", what, got);
  if (!ok)
    printf ("  wanted \"%s\"", want);
  printf ("\n");
}

/* The typer's copy is what the text field holds before the cursor */
static void
expect_copy (Field *f, const char *what)
{
  g_autofree char *copy = tactus_typer_dup_before (f->typer);
  g_autofree char *before = g_strndup (f->text->str, MIN (f->cursor, f->anchor));
  gboolean ok = g_str_equal (copy, before);

  checked++;
  if (!ok)
    failed++;
  printf ("%s %-44s copy \"%s\"", ok ? "  ok" : "FAIL", what, copy);
  if (!ok)
    printf ("  field \"%s\"", before);
  printf ("\n");
}


static void
expect_shift (Field *f, const char *what, gboolean wanted)
{
  gboolean ok = !!f->shift == !!wanted;

  checked++;
  if (!ok)
    failed++;
  printf ("%s %-44s Shift %s\n", ok ? "  ok" : "FAIL", what, f->shift ? "on" : "off");
}

/*
 * Tests
 */

static void
test_basic (gboolean tells)
{
  Field *f = field_new (tells);

  printf ("== typing (%s)\n", tells ? "a field that tells" : "a field that tells nothing");
  expect_shift (f, "an empty field", TRUE);
  type (f, "teh ");
  expect (f, "a slip, a space", "The ");
  expect_shift (f, "in a sentence", FALSE);
  type (f, "wrold.");
  expect (f, "a slip, a full stop", "The world.");
  type (f, " ");
  expect_shift (f, "after a full stop", TRUE);
  type (f, "i think im right");
  expect (f, "I and I'm", "The world. I think I'm right");
  type (f, "  ");
  expect (f, "two spaces", "The world. I think I'm right. ");
  expect_shift (f, "after two spaces", TRUE);
  type (f, "ok!  ");
  expect (f, "two spaces after !", "The world. I think I'm right. Ok!  ");
  type (f, "see you tomorow?");
  expect (f, "a question mark", "The world. I think I'm right. Ok!  See you tomorrow?");
  expect_copy (f, "the copy");
  field_free (f);
}


static void
test_slow (void)
{
  Field *f = field_new (TRUE);

  printf ("== a field that tells late\n");
  /* Text is taken away only once the field has shown what was sent: a key
   * that may take some away waits for that, a quarter of a second at most */
  type (f, "it ");
  f->hold = TRUE;
  type (f, "wsa");
  advance (f, 60);
  tactus_typer_key (f->typer, " ", NULL);
  expect (f, "the space waits for the field", "It wsa");
  advance (f, 100);
  flush (f);
  expect (f, "told in time: the word is corrected", "It was ");
  expect_copy (f, "the copy");

  /* what is typed while a key waits keeps its place after it */
  f->hold = TRUE;
  type (f, "teh");
  advance (f, 40);
  tactus_typer_key (f->typer, " ", NULL);
  advance (f, 40);
  tactus_typer_key (f->typer, "c", NULL);
  advance (f, 40);
  tactus_typer_key (f->typer, "a", NULL);
  advance (f, 40);
  tactus_typer_key (f->typer, "t", NULL);
  expect (f, "keys after the one that waits wait too", "It was teh");
  flush (f);
  expect (f, "in their order, once it is told", "It was the cat");
  expect_copy (f, "the copy");
  field_free (f);

  /* too late: the key goes in, the word stays as it was typed, and nothing waits for a while */
  f = field_new (TRUE);
  f->hold = TRUE;
  type (f, "teh");
  advance (f, 60);
  tactus_typer_key (f->typer, " ", NULL);
  expect (f, "the space waits", "Teh");
  advance (f, 300);
  expect (f, "not told in time: the word stays", "Teh ");
  type (f, "cat sat ");
  expect (f, "typed on, nothing waits", "Teh cat sat ");
  flush (f);
  expect_copy (f, "the copy, once told");
  type (f, "donw. ");
  expect (f, "caught up: corrected again", "Teh cat sat down. ");
  expect_shift (f, "after it", TRUE);

  /* held for more than a second */
  f->hold = TRUE;
  type (f, "it wsa ");
  advance (f, 1500);
  type (f, "late ");
  flush (f);
  expect (f, "told after a long while: nothing lost", "Teh cat sat down. It wsa late ");
  expect_copy (f, "the copy");
  type (f, "adn on ");
  expect (f, "and corrected again after", "Teh cat sat down. It wsa late and on ");
  field_free (f);
}

/* The browser. Answered, it tells its text after every key; unanswered, it is
 * a key behind, and a request to take text away would take nothing. */
static void
test_browser (gboolean answered)
{
  Field *f = field_new_browser (answered, "");

  printf ("== the browser (%s)\n", answered ? "its words answered" : "left unanswered");
  expect_shift (f, "an empty field", TRUE);
  type (f, "h");
  expect_shift (f, "after the first letter", FALSE);
  type (f, "ello ");
  /* unanswered, it is behind: the space waits its quarter of a second for nothing */
  if (!answered)
    advance (f, 300);
  expect (f, "a word", "Hello ");
  expect_copy (f, "the copy");
  type (f, "teh wrold. ");
  if (answered) {
    expect (f, "slips are corrected", "Hello the world. ");
  } else {
    expect (f, "slips stay: text can't be taken away", "Hello teh wrold. ");
  }
  expect_shift (f, "after a full stop", TRUE);
  type (f, "ok");
  expect_copy (f, "the copy");

  checked++;
  if (f->lost_erases) {
    failed++;
    printf ("FAIL %u requests to take text away went nowhere\n", f->lost_erases);
  } else {
    printf ("  ok no request to take text away went nowhere\n");
  }
  field_free (f);

  /* in the middle of a sentence that was there */
  f = field_new_browser (answered, "See you ");
  if (answered)
    expect_shift (f, "text was there: no capital", FALSE);
  type (f, "t");
  expect_shift (f, "after a letter", FALSE);
  type (f, "omorow ");
  if (answered)
    expect (f, "corrected after what was there", "See you tomorrow ");
  field_free (f);
}

/* The dictionary is English: on another language's layout words stay as typed */
static void
test_language (void)
{
  Field *f = field_new (TRUE);

  printf ("== another language's layout\n");
  tactus_typer_set_language (f->typer, "de");
  type (f, "teh wrold. ");
  expect (f, "nothing is corrected", "Teh wrold. ");
  expect_shift (f, "a sentence still starts with a capital", TRUE);
  tactus_typer_set_language (f->typer, "en");
  type (f, "teh ");
  expect (f, "back on the English layout", "Teh wrold. The ");
  field_free (f);
}

/* A field that tells nothing is answered once, when it gets the keyboard */
static void
test_answers (void)
{
  Field *f = field_new (FALSE);

  printf ("== answers\n");
  type (f, "teh cat sat. ok ");
  checked++;
  if (f->acks != 1) {
    failed++;
    printf ("FAIL a field that tells nothing got %u answers\n", f->acks);
  } else {
    printf ("  ok a field that tells nothing is answered once\n");
  }
  field_free (f);
}


static void
test_tokens (gboolean tells)
{
  Field *f = field_new (tells);

  printf ("== not words (%s)\n", tells ? "tells" : "tells nothing");
  type (f, "see example.cmo and bob@gmial.com #hashtga abc123 x-rya /usr/bni ");
  expect (f, "addresses, tags, paths", "See example.cmo and bob@gmial.com #hashtga abc123 x-rya /usr/bni ");
  type (f, "TEH Zorblat GitHub ");
  expect (f, "capitals", "See example.cmo and bob@gmial.com #hashtga abc123 x-rya /usr/bni TEH Zorblat GitHub ");
  type (f, "(teh) \"wrold\" ");
  expect (f, "brackets and quotes",
          "See example.cmo and bob@gmial.com #hashtga abc123 x-rya /usr/bni TEH Zorblat GitHub (the) \"world\" ");
  expect_copy (f, "the copy");
  field_free (f);
}


static void
test_enter (void)
{
  Field *f = field_new (TRUE);

  printf ("== Return\n");
  type (f, "helo\n");
  expect (f, "a lone word", "Helo\n");
  expect_shift (f, "a new line", TRUE);
  type (f, "i am helo\n");
  expect (f, "running text", "Helo\nI am hello\n");
  expect_copy (f, "the copy");
  field_free (f);

  f = field_new (FALSE);
  f->enter_sends = TRUE;
  type (f, "ok thanks\n");
  expect (f, "sent off", "");
  expect_shift (f, "the next message", TRUE);
  type (f, "sure ");
  expect (f, "the next message", "Sure ");
  field_free (f);

  /* Return held: a line break where Return sends */
  f = field_new (FALSE);
  f->enter_sends = TRUE;
  type (f, "first line");
  press (f, "KEY_NEWLINE");
  expect (f, "Return held keeps what was written", "First line\n");
  expect_shift (f, "a capital after the new line", TRUE);
  type (f, "helo");
  press (f, "KEY_NEWLINE");
  expect (f, "a lone word before a new line is corrected: it is running text", "First line\nHello\n");
  type (f, "ok\n");
  expect (f, "Return itself still sends", "");
  field_free (f);

  f = field_new (TRUE);
  type (f, "one teh");
  press (f, "KEY_NEWLINE");
  type (f, "two");
  expect (f, "Return held in a field that tells what it holds", "One the\nTwo");
  expect_copy (f, "the copy");
  field_free (f);
}


static void
test_silent (void)
{
  Field *f = field_new (FALSE);

  printf ("== a field that tells nothing: the cursor moves, the text is sent\n");
  type (f, "hello there");
  advance (f, 1000);
  /* the owner taps the application's Send */
  g_string_truncate (f->text, 0);
  f->cursor = f->anchor = 0;
  report (f);
  expect_shift (f, "sent with the application's button", TRUE);
  type (f, "ok");
  /* … and quickly */
  advance (f, 300);
  g_string_truncate (f->text, 0);
  f->cursor = f->anchor = 0;
  report (f);
  type (f, "sure ");
  expect (f, "sent a moment after the last key", "Sure ");

  /* the text field settles in two steps */
  type (f, "a");
  f->now += 10 * G_TIME_SPAN_MILLISECOND;
  report (f);
  f->now += 10 * G_TIME_SPAN_MILLISECOND;
  report (f);
  type (f, "nd teh ");
  expect (f, "settling is not a change", "Sure and the ");

  /* a pause in mid word */
  type (f, "te");
  advance (f, 3000);
  type (f, "h ");
  expect (f, "a word typed with a long pause", "Sure and the teh ");

  /* Backspace where we thought nothing was */
  advance (f, 1000);
  g_string_assign (f->text, "see you tom");
  f->cursor = f->anchor = f->text->len;
  report (f);
  expect_shift (f, "a field we know nothing of", TRUE);
  type (f, "\b\b\b");
  expect_shift (f, "after deleting what was there", FALSE);
  type (f, "soon ");
  expect (f, "typing on", "see you soon ");

  /* the cursor moved with the space bar */
  press (f, "KEY_LEFT");
  expect_shift (f, "after moving the cursor", FALSE);
  field_free (f);
}


static void
test_moved (void)
{
  Field *f = field_new (TRUE);
  g_autofree char *copy = NULL;

  printf ("== a field that tells: the cursor moves, text is selected\n");
  field_set (f, "hello world", 5, 5);
  type (f, "s ");
  expect (f, "typing in the middle", "hellos  world");
  expect_copy (f, "the copy");

  field_set (f, "teh", 3, 3);
  type (f, " ");
  expect (f, "a word that was there", "teh ");

  field_set (f, "te", 2, 2);
  type (f, "h ");
  expect (f, "a word that was begun", "the ");

  field_set (f, "wor ld", 2, 2);
  type (f, "x ");
  expect (f, "inside a word", "wox r ld");

  field_set (f, "abc def", 7, 4);
  type (f, "\b");
  expect (f, "Backspace on a selection", "abc ");
  expect_copy (f, "the copy");

  field_set (f, "abc def", 7, 4);
  type (f, "x");
  expect (f, "typing over a selection", "abc x");
  expect_copy (f, "the copy");

  field_set (f, "", 0, 0);
  type (f, "\b");
  advance (f, 400);
  expect_shift (f, "Backspace in an empty field", TRUE);

  field_set (f, "hello world", 11, 11);
  press (f, "KEY_LEFT");
  press (f, "KEY_LEFT");
  expect_copy (f, "after arrows");
  press (f, "KEY_RIGHT");
  press (f, "KEY_RIGHT");
  press (f, "KEY_RIGHT");
  advance (f, 400);
  expect_copy (f, "an arrow at the end");
  field_free (f);
}


static void
test_ignores (void)
{
  Field *f = field_new (TRUE);

  printf ("== a field that tells, but ignores requests to delete\n");
  f->ignores_erase = TRUE;
  type (f, "teh ");
  expect (f, "the first time", "TehThe ");
  type (f, "wrold ");
  expect (f, "from then on", "TehThe world ");
  printf ("     (%u by the field, %u by keys)\n", f->by_field, f->by_keys);
  field_free (f);
}


static void
test_backspace (gboolean tells)
{
  Field *f = field_new (tells);

  printf ("== Backspace (%s)\n", tells ? "tells" : "tells nothing");
  type (f, "hello there friend");
  advance (f, 130);
  tactus_typer_backspace (f->typer, TACTUS_BACKSPACE_WORD);
  expect (f, "held: a word", "Hello there ");
  advance (f, 130);
  tactus_typer_backspace (f->typer, TACTUS_BACKSPACE_WORD);
  expect (f, "held: another", "Hello ");
  advance (f, 130);
  tactus_typer_backspace (f->typer, TACTUS_BACKSPACE_WORD);
  expect (f, "held: the last", "");
  expect_shift (f, "empty again", TRUE);
  expect_copy (f, "the copy");

  type (f, "teh ");
  type (f, "\b\b\bhe ");
  expect (f, "put back, then mended by hand", "The ");
  type (f, "teh ");
  expect (f, "still corrected", "The the ");
  field_free (f);
}


static void
test_put_back (gboolean tells)
{
  Field *f = field_new (tells);
  const char *slip = tells ? "wrold" : "tommorow";
  g_autofree char *typed = g_strdup_printf ("%s ", slip);
  g_autofree char *kept = NULL;
  g_autofree char *again = NULL;

  printf ("== a correction taken back (%s)\n", tells ? "tells" : "tells nothing");
  type (f, "a ");
  type (f, typed);
  type (f, "\b");
  kept = g_strdup_printf ("A %s", slip);
  expect (f, "Backspace after a correction", kept);
  type (f, " ");
  again = g_strdup_printf ("A %s %s ", slip, slip);
  type (f, typed);
  expect (f, "kept, and left alone from then on", again);
  expect_copy (f, "the copy");
  field_free (f);
}


static void
test_other (void)
{
  Field *f = field_new (FALSE);

  printf ("== other things\n");
  type (f, "funy");
  tactus_typer_text (f->typer, "\360\237\230\200", TRUE);
  expect (f, "an emoji ends a word", "Funny\360\237\230\200");
  field_free (f);

  f = field_new (TRUE);
  tactus_typer_set_hints (f->typer, TACTUS_HINT_LOWERCASE);
  expect_shift (f, "a field that wants small letters", FALSE);
  tactus_typer_set_hints (f->typer, TACTUS_HINT_AUTO_CAPS);
  type (f, "teh ");
  expect (f, "a field that asked for capitals alone (a web page)", "The ");
  tactus_typer_set_hints (f->typer, TACTUS_HINT_AUTO_CAPS | TACTUS_HINT_SPELLCHECK | TACTUS_HINT_COMPLETION);
  type (f, "teh ");
  expect (f, "a field that asked for corrections too", "The the ");
  tactus_typer_set_hints (f->typer, TACTUS_HINT_SENSITIVE);
  type (f, "teh ");
  expect (f, "a field nothing is to be learned from", "The the the ");
  tactus_typer_set_hints (f->typer, TACTUS_HINT_HIDDEN | TACTUS_HINT_SENSITIVE);
  type (f, "teh ");
  expect (f, "a secret", "The the the teh ");
  field_free (f);

  f = field_new (TRUE);
  type (f, "e.g. this vs. that. wait... what. \"yes.\" ok");
  expect (f, "where sentences start", "E.g. this vs. that. Wait... what. \"Yes.\" Ok");
  field_free (f);

  f = field_new (FALSE);
  type (f, "ok ");
  advance (f, 2000);
  type (f, " x");
  expect (f, "two slow spaces", "Ok  x");
  field_free (f);
}

/* Known to go wrong, and why: shown, not counted */
static void
test_limits (void)
{
  Field *f = field_new (FALSE);

  printf ("== known limits (not counted)\n");
  type (f, "ok");
  /* sent off within a tenth of a second of the last key's echo: no way to tell */
  f->now += 50 * G_TIME_SPAN_MILLISECOND;
  g_string_truncate (f->text, 0);
  f->cursor = f->anchor = 0;
  report (f);
  type (f, "sure ");
  printf ("     sent off right on the last key, then \"sure \": \"%s\"\n", f->text->str);
  field_free (f);
}


int
main (int argc, char **argv)
{
  g_autofree char *tmp = g_dir_make_tmp ("tactus-typer-XXXXXX", NULL);

  /* What the keyboard learns here is not the owner's */
  g_setenv ("XDG_DATA_HOME", tmp, TRUE);
  g_setenv ("XDG_STATE_HOME", tmp, TRUE);

  if (!tactus_ac_available ()) {
    printf ("no dictionary\n");
    return 2;
  }

  test_basic (TRUE);
  test_basic (FALSE);
  test_slow ();
  test_browser (TRUE);
  test_browser (FALSE);
  test_answers ();
  test_language ();
  test_tokens (TRUE);
  test_tokens (FALSE);
  test_enter ();
  test_silent ();
  test_moved ();
  test_ignores ();
  test_backspace (TRUE);
  test_backspace (FALSE);
  test_other ();
  test_put_back (TRUE);
  test_put_back (FALSE);
  test_limits ();

  printf ("%d of %d failed\n", failed, checked);
  return failed ? 1 : 0;
}
