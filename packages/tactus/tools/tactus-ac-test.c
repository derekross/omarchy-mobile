/*
 * Tactus's autocorrection, tried on words: what each becomes.
 *
 * tactus-ac-test            the built-in list (the words in context only with
 *                           TACTUS_WORD_PAIRS set: the package's check does)
 * tactus-ac-test WORD...    these words, with no taps to go by
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-autocorrect.h"

#include <glib.h>

#include <stdio.h>
#include <string.h>

typedef struct {
  const char *typed;
  const char *want;  /* NULL: stays as typed */
  gboolean    start; /* it starts a sentence */
  gboolean    taps;  /* only with taps to go by */
  const char *aim;   /* the keys the fingers aimed at, letter by letter (NULL: @want's) */
} Case;

static const Case cases[] = {
  /* slips */
  { "teh", "the" }, { "beyyer", "better" }, { "js", "is" }, { "waybetter", "way better" },
  { "hemko", "hello", FALSE, TRUE }, { "wrold", "world" }, { "recieve", "receive" },
  { "definately", "definitely" }, { "seperate", "separate" }, { "tommorow", "tomorrow" },
  { "thnaks", "thanks" }, { "becuase", "because" }, { "adn", "and" }, { "taht", "that" },
  { "wich", "which" }, { "alot", "a lot" }, { "atleast", "at least" }, { "iam", "I am" },
  { "helo", "hello" }, { "helllo", "hello" }, { "goign", "going" }, { "somthing", "something" },
  { "abotu", "about" }, { "jsut", "just" }, { "knwo", "know" }, { "yuo", "you" },
  { "tge", "the" }, { "thr", "the" }, { "whta", "what" }, { "peopel", "people" },
  { "freind", "friend" }, { "thankyou", "thank you" },
  { "ofcourse", "of course" }, { "probaly", "probably" }, { "realy", "really" },
  { "goimg", "going" }, { "tjis", "this" }, { "wgat", "what" }, { "yoi", "you" },
  { "thwn", "then" }, { "abput", "about" }, { "wotk", "work" }, { "gokng", "going" },
  { "hellonthere", "hello there" }, { "seebyou", "see you" },
  { "Teh", "The", TRUE }, { "Hemko", "Hello", TRUE, TRUE },
  { "colour", "color" }, { "goin", "going" }, { "ofc", NULL }, { "lmk", NULL }, { "tonite", NULL },
  /* apostrophes */
  { "i", "I" }, { "im", "I'm" }, { "ive", "I've" }, { "dont", "don't" }, { "cant", "can't" },
  { "wont", "won't" }, { "thats", "that's" }, { "youre", "you're" }, { "hows", "how's" },
  { "didnt", "didn't" }, { "isnt", "isn't" }, { "whats", "what's" }, { "hes", "he's" },
  { "theyre", "they're" }, { "couldnt", "couldn't" }, { "i'm", "I'm" }, { "i'll", "I'll" },
  { "Dont", "Don't", TRUE },
  /* names and capitals */
  { "paris", "Paris" }, { "monday", "Monday" }, { "tv", "TV" }, { "michael", "Michael" },
  { "january", "January" },
  /* stays */
  { "the", NULL }, { "its", NULL }, { "well", NULL }, { "were", NULL }, { "ill", NULL },
  { "id", NULL }, { "lol", NULL }, { "ok", NULL }, { "wifi", NULL }, { "omarchy", NULL },
  { "fediverse", NULL }, { "hyprland", NULL }, { "github", NULL }, { "gonna", NULL },
  { "bows", NULL }, { "fir", NULL }, { "hi", NULL }, { "hey", NULL },
  { "yeah", NULL }, { "nope", NULL }, { "haha", NULL }, { "hmm", NULL }, { "ugh", NULL },
  { "tbh", NULL }, { "btw", NULL }, { "app", NULL }, { "emoji", NULL }, { "let", NULL },
  { "lets", NULL }, { "hell", NULL }, { "shell", NULL }, { "wed", NULL }, { "may", NULL },
  { "mark", NULL }, { "will", NULL }, { "in", NULL }, { "on", NULL }, { "of", NULL },
  { "if", NULL }, { "or", NULL }, { "so", NULL }, { "do", NULL }, { "go", NULL },
  { "no", NULL }, { "us", NULL }, { "an", NULL }, { "as", NULL }, { "at", NULL },
  { "Zorblat", NULL }, { "NASA", NULL }, { "GitHub", NULL }, { "kernel", NULL },
  { "linux", NULL }, { "sudo", NULL }, { "laptop", NULL }, { "dictation", NULL },
  { "Paris", NULL, TRUE }, { "The", NULL, TRUE }, { "I", NULL },
  /* short forms people write */
  { "msgs", NULL }, { "msg", NULL }, { "pics", NULL }, { "pic", NULL }, { "vids", NULL },
  { "vid", NULL }, { "convo", NULL }, { "ppl", NULL }, { "tactus", NULL }, { "Tactus", NULL, TRUE },
  { "btw", NULL, FALSE, TRUE, "bye" }, { "Btw", NULL, TRUE, TRUE, "Bye" }, { "idk", NULL, FALSE, TRUE, "ids" },
  { "brb", NULL, FALSE, TRUE, "bob" }, { "thx", NULL, FALSE, TRUE, "the" }, { "ty", NULL, FALSE, TRUE, "to" },
  { "rn", NULL, FALSE, TRUE, "tn" }, { "smh", NULL, FALSE, TRUE, "she" }, { "lol", NULL, FALSE, TRUE, "lot" },
  /* a slip into a word the word list doesn't count, but the dictionary knows */
  { "widgrt", "widget", FALSE, TRUE }, { "widgrt", NULL, FALSE, TRUE, "widgrt" },
  /* a rarer word where the taps point to it */
  { "lics", "pics", FALSE, TRUE }, { "pahsijg", "pausing", FALSE, TRUE },
  /* a tap too many, and a key next to the one meant */
  { "ipgone", "phone", FALSE, TRUE, "iphone" },
  /* a name: only by the taps, and only to a word or name the dictionary knows */
  { "Vigip", "Vigil", FALSE, TRUE }, { "Carmos", "Carlos", FALSE, TRUE }, { "Mivhwel", "Michael", FALSE, TRUE },
  { "Zorblat", NULL, FALSE, TRUE, "Zorblat" }, { "Hemko", NULL, FALSE, TRUE, "Hemko" },
};


static gboolean
key_pos (char c, double *x, double *y)
{
  static const char *rows[] = { "qwertyuiop", "asdfghjkl", "zxcvbnm" };
  static const double first[] = { 0.5, 1.0, 2.0 };

  c = g_ascii_tolower (c);
  for (int r = 0; r < 3; r++) {
    const char *at = c ? strchr (rows[r], c) : NULL;

    if (at) {
      *x = first[r] + (at - rows[r]);
      *y = r;
      return TRUE;
    }
  }
  return FALSE;
}

/* Taps as of a finger that aimed at @want and landed on @typed's keys: inside
 * each key that was hit, toward the key that was meant */
static TactusTap *
near_miss (const char *typed, const char *want, double off)
{
  size_t n = strlen (typed);
  TactusTap *taps = g_new0 (TactusTap, n);

  for (size_t i = 0; i < n; i++) {
    double tx, ty, wx, wy;

    taps[i].valid = TRUE;
    if (!want || strlen (want) != n || !key_pos (typed[i], &tx, &ty) || !key_pos (want[i], &wx, &wy))
      continue;
    taps[i].dx = CLAMP (off * (wx - tx), -0.48, 0.48);
    taps[i].dy = CLAMP (off * (wy - ty), -0.48, 0.48);
  }
  return taps;
}


static int
run_off (const Case *c, gboolean with_taps, double off)
{
  g_autofree TactusTap *taps = with_taps ? near_miss (c->typed, c->aim ?: c->want, off) : NULL;
  g_autofree char *got = tactus_ac_correct (c->typed, taps, taps ? strlen (c->typed) : 0, c->start);
  gboolean ok = g_strcmp0 (got, c->want) == 0;

  printf ("%s %-13s -> %-14s", ok ? "  ok" : "FAIL", c->typed, got ?: "(stays)");
  if (!ok)
    printf (" wanted %s", c->want ?: "(stays)");
  printf ("\n");
  return ok ? 0 : 1;
}


static int
run (const Case *c, gboolean with_taps)
{
  return run_off (c, with_taps, 0.42);
}


int
main (int argc, char **argv)
{
  int failed = 0;
  gint64 t0;

  if (!tactus_ac_available ()) {
    printf ("no dictionary\n");
    return 2;
  }

  if (argc > 1) {
    for (int i = 1; i < argc; i++) {
      g_autofree char *got = tactus_ac_correct (argv[i], NULL, 0, FALSE);

      printf ("%s -> %s\n", argv[i], got ?: "(stays)");
    }
    return 0;
  }

  printf ("== letters alone\n");
  for (guint i = 0; i < G_N_ELEMENTS (cases); i++) {
    if (!cases[i].taps)
      failed += run (&cases[i], FALSE);
  }

  printf ("== with taps that nearly missed\n");
  for (guint i = 0; i < G_N_ELEMENTS (cases); i++)
    failed += run (&cases[i], TRUE);

  /* A word the dictionary knows, hit at the edge next to a far likelier one */
  {
    static const Case edge[] = { { "fir", "for" }, { "hid", "his" }, { "thr", "the" }, { "og", "of" } };

    printf ("== at the edge of a key\n");
    for (guint i = 0; i < G_N_ELEMENTS (edge); i++)
      failed += run (&edge[i], TRUE);
  }

  /* A word people write, hit off the centre of a key but well inside it, next
   * to a likelier word: it stays */
  {
    static const Case inside[] = {
      { "bot", NULL, FALSE, TRUE, "boy" }, { "pics", NULL, FALSE, TRUE, "lice" },
      { "relayed", NULL, FALSE, TRUE, "related" }, { "msgs", NULL, FALSE, TRUE, "mags" },
      { "vids", NULL, FALSE, TRUE, "bids" },
    };

    printf ("== a third of a key off the centre\n");
    for (guint i = 0; i < G_N_ELEMENTS (inside); i++)
      failed += run_off (&inside[i], TRUE, 0.3);
  }

  /* Words in context: what the word before and, looking back, the word after
   * say. Taps a close call toward @aim. */
  if (g_getenv ("TACTUS_WORD_PAIRS")) {
    static const struct {
      const char *before, *typed, *aim, *after, *want;
    } in_context[] = {
      /* the word before */
      { "the", "bot", "boy", NULL, "boy" }, { "is", "relayed", "related", NULL, "related" },
      { "i", "lime", "like", NULL, "like" },
      { "the", "yet", "get", NULL, NULL }, { "i", "hope", "hope", NULL, NULL },
      /* looking back, with the word after */
      { "out", "if", "of", "the", "of" }, { "is", "relayed", "related", "to", "related" },
      { "i", "relayed", "related", "to", NULL }, { "out", "if", "if", "the", NULL },
      { "the", "whole", "while", "he", NULL }, { "the", "btw", "bye", "is", NULL },
    };

    printf ("== in context\n");
    for (guint i = 0; i < G_N_ELEMENTS (in_context); i++) {
      const char *typed = in_context[i].typed;
      g_autofree TactusTap *taps = near_miss (typed, in_context[i].aim, 0.42);
      g_autofree char *got = in_context[i].after
        ? tactus_ac_reconsider (typed, taps, strlen (typed), FALSE, in_context[i].before, in_context[i].after)
        : tactus_ac_correct_in (typed, taps, strlen (typed), FALSE, in_context[i].before);
      gboolean ok = g_strcmp0 (got, in_context[i].want) == 0;
      g_autofree char *where = g_strdup_printf ("%s %s %s", in_context[i].before, typed, in_context[i].after ?: "");

      printf ("%s %-22s -> %-14s", ok ? "  ok" : "FAIL", where, got ?: "(stays)");
      if (!ok)
        printf (" wanted %s", in_context[i].want ?: "(stays)");
      printf ("\n");
      failed += !ok;
    }
  } else {
    printf ("== in context # SKIP no TACTUS_WORD_PAIRS\n");
  }

  t0 = g_get_monotonic_time ();
  for (int i = 0; i < 200; i++)
    g_free (tactus_ac_correct ("somthing", NULL, 0, FALSE));
  printf ("== %.2f ms a word\n", (g_get_monotonic_time () - t0) / 200.0 / 1000.0);

  printf ("%d failed\n", failed);
  return failed ? 1 : 0;
}
