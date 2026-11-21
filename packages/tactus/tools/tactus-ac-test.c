/*
 * Tactus's autocorrection, tried on words: what each becomes.
 *
 * tactus-ac-test            the built-in list
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
near_miss (const char *typed, const char *want)
{
  size_t n = strlen (typed);
  TactusTap *taps = g_new0 (TactusTap, n);

  for (size_t i = 0; i < n; i++) {
    double tx, ty, wx, wy;

    taps[i].valid = TRUE;
    if (!want || strlen (want) != n || !key_pos (typed[i], &tx, &ty) || !key_pos (want[i], &wx, &wy))
      continue;
    taps[i].dx = CLAMP (0.42 * (wx - tx), -0.48, 0.48);
    taps[i].dy = CLAMP (0.42 * (wy - ty), -0.48, 0.48);
  }
  return taps;
}


static int
run (const Case *c, gboolean with_taps)
{
  g_autofree TactusTap *taps = with_taps ? near_miss (c->typed, c->want) : NULL;
  g_autofree char *got = tactus_ac_correct (c->typed, taps, taps ? strlen (c->typed) : 0, c->start);
  gboolean ok = g_strcmp0 (got, c->want) == 0;

  printf ("%s %-13s -> %-14s", ok ? "  ok" : "FAIL", c->typed, got ?: "(stays)");
  if (!ok)
    printf (" wanted %s", c->want ?: "(stays)");
  printf ("\n");
  return ok ? 0 : 1;
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

  t0 = g_get_monotonic_time ();
  for (int i = 0; i < 200; i++)
    g_free (tactus_ac_correct ("somthing", NULL, 0, FALSE));
  printf ("== %.2f ms a word\n", (g_get_monotonic_time () - t0) / 200.0 / 1000.0);

  printf ("%d failed\n", failed);
  return failed ? 1 : 0;
}
