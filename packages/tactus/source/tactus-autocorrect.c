/*
 * Tactus's autocorrection: which word the owner meant.
 *
 * A typed word is weighed against the words it could have been: by where
 * each finger landed (a tap near the edge of a key speaks for its neighbour),
 * by how common each word is, and by the usual slips (two letters swapped,
 * one missed or doubled, a missed space, a missing apostrophe). A word the
 * dictionary knows is replaced only when the taps themselves were close
 * calls; a word the owner took back once is left alone from then on.
 *
 * English on a QWERTY keyboard only.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define G_LOG_DOMAIN "tactus-autocorrect"

#include "pos-config.h"

#include "tactus-autocorrect.h"

#include <glib/gstdio.h>
#include <hunspell.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

#define DICT_DIRS    "/usr/share/hunspell:/usr/share/myspell:/usr/share/myspell/dicts"
/* How often each word is seen in everyday writing: "word count" lines, the
 * commonest first (hermitdave's FrequencyWords, en_50k.txt). TACTUS_WORD_COUNTS
 * in the environment names another file, for the tests. */
#define FREQ_DEFAULT TACTUS_PKGDATADIR "/en_50k.txt"
#define MAX_LEN      24
/* How often a word is seen in the list before it counts as everyday writing */
#define COMMON       300
/* The least a word must be seen to be offered at all */
#define OFFERED      50
/* What a word the owner taught the keyboard counts as */
#define LEARNED      50000
/* The spread of a finger around the key it aims at: across in key widths, down in row heights */
#define SIGMA_X      0.42
#define SIGMA_Y      0.36
#define KX           (1.0 / (2.0 * SIGMA_X * SIGMA_X))
#define KY           (1.0 / (2.0 * SIGMA_Y * SIGMA_Y))
/* No letter of a guess may be further from its tap than this */
#define LETTER_MAX   9.0
/* … nor all of them together than this (about two keys missed by a whole
 * key), a little more for each letter of a long word */
#define REACH_TAPS   6.0
#define REACH_LONG   6
#define REACH_MORE   0.6
/* With no taps to go by: one key missed in a short word, two in a longer one */
#define REACH_SHORT  4.6
#define REACH_BLIND  6.8
/* The usual slips, in the same currency as the taps */
#define COST_SWAP    2.5
#define COST_EXTRA   3.0
#define COST_MISSED  3.0
/* a letter that should have been typed twice, or once */
#define COST_DOUBLE  1.5
/* the g of -ing left off */
#define COST_DROPPED 1.0
#define COST_SPLIT   2.5
#define COST_GUESS   3.2

/* How common both halves must be for a word to be two words run together */
#define SPLIT_COMMON 2000
/* A word not in the dictionary starts this far behind; one that is not, but
 * that people do write, this far */
#define UNKNOWN      8.0
#define SEEN         3.0
/* What such a word is replaced by is an everyday word: slips of rare words are rare */
#define FIX_COMMON   1000
/* The dictionary's own guess may differ by two letters only if it is a very common word */
#define GUESS_TWO    20000
/* A known word gives way only to a clearly likelier one, and only when the taps were close calls */
#define KNOWN_MARGIN 4.0
#define KNOWN_REACH  1.5
#define OTHER_MARGIN 1.0
/* How fast the keyboard learns where this owner's fingers land, and how far it may go */
#define BIAS_RATE    0.01
#define BIAS_MAX_X   0.15
#define BIAS_MAX_Y   0.25
#define BIAS_SAVE    40
/* … and the typed word long enough */
#define GUESS_LONG   7

typedef struct {
  const char *letters; /* a to z only: what is typed */
  const char *display; /* with its apostrophe, and "I" */
  guint       count;
} Entry;

static gboolean      inited;
static Hunhandle    *hun;
static GHashTable   *freq;
static GHashTable   *learned;
static GStringChunk *chunk;
static GArray       *by_len[MAX_LEN + 1];
static double        bias_x, bias_y;
static guint         bias_unsaved;
static gboolean      bias_loaded;

/* Written the way people write, not in the dictionary */
static const char *const informal[] = {
  "ok", "okay", "k", "kk", "lol", "lmao", "lmfao", "rofl", "omg", "omfg", "wtf", "wth", "idk",
  "idc", "btw", "tbh", "imo", "imho", "fyi", "asap", "brb", "afk", "gtg", "ttyl", "irl", "omw",
  "smh", "ikr", "nvm", "tmi", "bff", "fomo", "yolo", "jk", "gg", "ty", "tysm", "yw", "np",
  "hbu", "wyd", "hmu", "ily", "ngl", "fr", "rn", "af", "ofc", "lmk", "iirc", "afaik", "tldr",
  "eta", "aka", "etc", "vs", "ie", "eg", "bc", "cuz", "coz", "tho", "thru", "tmrw", "tmr",
  "pls", "plz", "thx", "ur", "u", "xoxo",
  "haha", "hahaha", "hehe", "hah", "heh", "hmm", "hm", "mhm", "uh", "um", "umm", "uhh", "yea",
  "yeh", "ya", "nah", "nope", "yep", "yup", "yeah", "aww", "aw", "wow", "whoa", "yay", "yikes",
  "oops", "whoops", "meh", "duh", "eh", "huh", "shh", "psst", "ew", "eww", "ooh", "oh", "ah",
  "aha", "ahh", "argh", "grr", "ugh", "hey", "hi", "yo", "bye", "nite",
  "gonna", "wanna", "gotta", "kinda", "sorta", "dunno", "gimme", "lemme", "outta", "tryna",
  "wifi", "emoji", "emojis", "selfie", "app", "apps", "blog", "podcast", "login", "username",
  "hotspot", "online", "offline", "email", "emails", "internet", "website", "smartphone",
  "laptop", "linux", "github", "ssh", "sudo", "repo", "config", "kernel", "bluetooth",
  "screenshot", "livestream", "inbox", "unfollow", "hashtag", "admin", "sync",
  NULL,
};


/* Words with an apostrophe, by the letters people type for them. The word
 * list counts their halves apart ("don" and "t"), so the counts are set here,
 * in its measure. Left out where the letters are a word of their own that is
 * as likely meant: its, well, were, hell, shell, wed, shed, ill, id, lets. */
static const struct {
  const char *letters;
  const char *display;
  guint       count;
} contractions[] = {
  { "im", "I'm", 5000000 }, { "ive", "I've", 800000 },
  { "dont", "don't", 4100000 }, { "didnt", "didn't", 1100000 }, { "doesnt", "doesn't", 470000 },
  { "isnt", "isn't", 430000 }, { "wasnt", "wasn't", 310000 }, { "cant", "can't", 1200000 },
  { "wont", "won't", 400000 }, { "wouldnt", "wouldn't", 290000 }, { "couldnt", "couldn't", 230000 },
  { "shouldnt", "shouldn't", 120000 }, { "arent", "aren't", 180000 }, { "werent", "weren't", 90000 },
  { "havent", "haven't", 250000 }, { "hasnt", "hasn't", 70000 }, { "hadnt", "hadn't", 45000 },
  { "aint", "ain't", 200000 }, { "mustnt", "mustn't", 17000 },
  { "thats", "that's", 2500000 }, { "whats", "what's", 1000000 }, { "hes", "he's", 1000000 },
  { "shes", "she's", 600000 }, { "theres", "there's", 800000 }, { "heres", "here's", 300000 },
  { "whos", "who's", 250000 }, { "hows", "how's", 80000 }, { "wheres", "where's", 200000 },
  { "youre", "you're", 2000000 }, { "theyre", "they're", 600000 },
  { "youll", "you'll", 400000 }, { "theyll", "they'll", 100000 }, { "itll", "it'll", 80000 },
  { "thatll", "that'll", 30000 }, { "youve", "you've", 400000 }, { "weve", "we've", 300000 },
  { "theyve", "they've", 100000 }, { "couldve", "could've", 30000 }, { "wouldve", "would've", 30000 },
  { "shouldve", "should've", 30000 }, { "youd", "you'd", 150000 }, { "theyd", "they'd", 50000 },
  { "hed", "he'd", 70000 }, { "yall", "y'all", 20000 }, { "oclock", "o'clock", 30000 },
  { "maam", "ma'am", 80000 },
};

/* Halves of those words that the word list counts as words: what they count as on their own */
static const struct {
  const char *word;
  guint       count;
} recount[] = {
  { "don", 3000 }, { "won", 60000 }, { "haven", 2000 }, { "re", 3000 }, { "shan", 100 },
  { "ain", 100 }, { "ll", 0 }, { "ve", 0 }, { "didn", 0 }, { "doesn", 0 }, { "isn", 0 },
  { "wasn", 0 }, { "wouldn", 0 }, { "couldn", 0 }, { "shouldn", 0 }, { "aren", 0 },
  { "weren", 0 }, { "hasn", 0 }, { "hadn", 0 }, { "mustn", 0 },
};

/* Written in capitals */
static const char *const acronyms[] = {
  "tv", "fbi", "dna", "usa", "uk", "nyc", "dvd", "ceo", "atm", "gps", "usb", "pdf", "diy",
  "faq", "vip", "ufo", "nasa", "bbc", "nba", "nfl", "suv", "hiv", "html", "url", "api",
  NULL,
};


static gboolean
key_pos (char c, double *x, double *y)
{
  static const char *rows[] = { "qwertyuiop", "asdfghjkl", "zxcvbnm" };
  static const double first[] = { 0.5, 1.0, 2.0 };

  for (int r = 0; r < 3; r++) {
    const char *at = strchr (rows[r], c);

    if (at && c) {
      *x = first[r] + (at - rows[r]);
      *y = r;
      return TRUE;
    }
  }
  return FALSE;
}


static char *
state_path (const char *name)
{
  return g_build_filename (g_get_user_state_dir (), "tactus", name, NULL);
}


static char *
words_path (void)
{
  return g_build_filename (g_get_user_data_dir (), "tactus", "words.txt", NULL);
}


static gboolean
hun_ok (const char *word)
{
  return hun && Hunspell_spell (hun, word);
}


static guint
count_of (const char *lower)
{
  guint count = freq ? GPOINTER_TO_UINT (g_hash_table_lookup (freq, lower)) : 0;

  if (learned && g_hash_table_contains (learned, lower))
    count = MAX (count, LEARNED);
  return count;
}

/* A word that stands: in the dictionary (also as a name), taught, or everyday writing */
static gboolean
is_solid (const char *lower)
{
  g_autofree char *capital = NULL;

  if (learned && g_hash_table_contains (learned, lower))
    return TRUE;
  if (hun_ok (lower))
    return TRUE;
  /* a name ("michael"); of two letters, the dictionary takes about anything */
  if (strlen (lower) >= 3) {
    capital = g_strdup (lower);
    capital[0] = g_ascii_toupper (capital[0]);
    if (hun_ok (capital))
      return TRUE;
  }
  return g_strv_contains (informal, lower);
}


static void
load_bias (void)
{
  g_autofree char *path = state_path ("touch");
  g_autofree char *contents = NULL;
  char *end = NULL;
  double x, y;

  bias_loaded = TRUE;
  if (!g_file_get_contents (path, &contents, NULL, NULL))
    return;

  x = g_ascii_strtod (contents, &end);
  if (end == contents)
    return;
  y = g_ascii_strtod (end, NULL);
  if (fabs (x) <= BIAS_MAX_X && fabs (y) <= BIAS_MAX_Y) {
    bias_x = x;
    bias_y = y;
  }
}

/**
 * tactus_ac_save:
 *
 * Keep what was learned about where the owner's fingers land.
 */
void
tactus_ac_save (void)
{
  g_autofree char *path = state_path ("touch");
  g_autofree char *dir = g_path_get_dirname (path);
  g_autofree char *text = NULL;
  char bx[G_ASCII_DTOSTR_BUF_SIZE], by[G_ASCII_DTOSTR_BUF_SIZE];

  if (!bias_loaded || bias_unsaved == 0)
    return;

  g_ascii_formatd (bx, sizeof (bx), "%.4f", bias_x);
  g_ascii_formatd (by, sizeof (by), "%.4f", bias_y);
  text = g_strdup_printf ("%s %s\n", bx, by);
  g_mkdir_with_parents (dir, 0700);
  if (g_file_set_contents (path, text, -1, NULL))
    bias_unsaved = 0;
}


static void
add_entry (const char *letters, const char *display, guint count)
{
  size_t len = strlen (letters);
  Entry entry;

  if (len < 1 || len > MAX_LEN)
    return;

  entry.letters = g_string_chunk_insert (chunk, letters);
  entry.display = g_string_chunk_insert (chunk, display);
  entry.count = count;
  g_array_append_val (by_len[len], entry);
}

/* The words a typed word can become: the dictionary's words by how often
 * they are written, names with their capital, and the words with an
 * apostrophe by the letters people type for them */
static void
build_index (void)
{
  GHashTableIter iter;
  gpointer key, value;

  for (int i = 0; i <= MAX_LEN; i++)
    by_len[i] = g_array_new (FALSE, FALSE, sizeof (Entry));

  g_hash_table_iter_init (&iter, freq);
  while (g_hash_table_iter_next (&iter, &key, &value)) {
    const char *word = key;
    guint count = GPOINTER_TO_UINT (value);
    size_t n = strlen (word);
    gboolean plain = TRUE;

    if (count < OFFERED || n > MAX_LEN)
      continue;
    for (const char *p = word; *p; p++)
      plain = plain && *p >= 'a' && *p <= 'z';
    if (!plain)
      continue;

    if (n == 1) {
      /* "a" and "I" are the words of one letter */
      if (word[0] == 'a')
        add_entry ("a", "a", count);
      else if (word[0] == 'i')
        add_entry ("i", "I", count);
      continue;
    }

    if (hun_ok (word)) {
      add_entry (word, word, count);
    } else if (n >= 3) {
      g_autofree char *capital = g_strdup (word);

      capital[0] = g_ascii_toupper (capital[0]);
      if (hun_ok (capital))
        add_entry (word, capital, count);
    }
  }

  for (guint i = 0; i < G_N_ELEMENTS (contractions); i++)
    add_entry (contractions[i].letters, contractions[i].display, contractions[i].count);
}


static void
ensure_init (void)
{
  const char *freq_path = g_getenv ("TACTUS_WORD_COUNTS") ?: FREQ_DEFAULT;
  g_auto (GStrv) dirs = g_strsplit (DICT_DIRS, ":", -1);
  g_autofree char *contents = NULL;
  g_autofree char *words = words_path ();

  if (inited)
    return;
  inited = TRUE;

  for (int i = 0; dirs[i] && hun == NULL; i++) {
    g_autofree char *aff = g_build_filename (dirs[i], "en_US.aff", NULL);
    g_autofree char *dic = g_build_filename (dirs[i], "en_US.dic", NULL);

    if (g_file_test (aff, G_FILE_TEST_EXISTS) && g_file_test (dic, G_FILE_TEST_EXISTS))
      hun = Hunspell_create (aff, dic);
  }
  if (hun == NULL)
    g_warning ("No English dictionary: the keyboard does not correct");

  chunk = g_string_chunk_new (4096);
  freq = g_hash_table_new (g_str_hash, g_str_equal);
  if (g_file_get_contents (freq_path, &contents, NULL, NULL)) {
    char *save = NULL;

    for (char *line = strtok_r (contents, "\n", &save); line; line = strtok_r (NULL, "\n", &save)) {
      char *space = strchr (line, ' ');
      guint64 count;

      if (space == NULL)
        continue;
      *space = '\0';
      count = g_ascii_strtoull (space + 1, NULL, 10);
      g_hash_table_insert (freq, g_string_chunk_insert (chunk, line),
                           GUINT_TO_POINTER ((guint) MIN (count, G_MAXUINT)));
    }
    for (guint i = 0; i < G_N_ELEMENTS (recount); i++) {
      if (g_hash_table_contains (freq, recount[i].word))
        g_hash_table_replace (freq, (gpointer) recount[i].word, GUINT_TO_POINTER (recount[i].count));
    }
  } else {
    g_warning ("No word list at %s: the keyboard corrects by the dictionary alone", freq_path);
  }

  learned = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
  g_clear_pointer (&contents, g_free);
  if (g_file_get_contents (words, &contents, NULL, NULL)) {
    g_auto (GStrv) lines = g_strsplit (contents, "\n", -1);

    for (int i = 0; lines[i]; i++) {
      g_strstrip (lines[i]);
      if (*lines[i])
        g_hash_table_add (learned, g_ascii_strdown (lines[i], -1));
    }
  }

  if (hun)
    build_index ();
  load_bias ();
}

/**
 * tactus_ac_available:
 *
 * Returns: %TRUE if there is a dictionary to correct by
 */
gboolean
tactus_ac_available (void)
{
  ensure_init ();
  return hun != NULL;
}

/**
 * tactus_ac_learn:
 * @word: A word the owner wants as typed
 *
 * The owner took a correction of this word back: leave it alone from now on.
 * The words are kept on this device only.
 */
void
tactus_ac_learn (const char *word)
{
  g_autofree char *path = words_path ();
  g_autofree char *dir = g_path_get_dirname (path);
  g_autofree char *lower = NULL;
  FILE *f;

  ensure_init ();
  if (word == NULL || *word == '\0' || strchr (word, ' '))
    return;

  lower = g_ascii_strdown (word, -1);
  if (g_hash_table_contains (learned, lower))
    return;
  g_hash_table_add (learned, g_strdup (lower));

  g_mkdir_with_parents (dir, 0700);
  f = g_fopen (path, "a");
  if (f) {
    fprintf (f, "%s\n", lower);
    fclose (f);
  }
}


typedef struct {
  char    text[2 * MAX_LEN + 4];
  double  score;
  double  reach;     /* how much further from the taps than the word as typed */
  gboolean by_taps;  /* a word of the same letters count, weighed tap by tap */
  gboolean found;
} Best;


static void
consider (Best *best, const char *text, double cost, guint count, double typed_cost, gboolean by_taps)
{
  double score;

  if (count < OFFERED)
    return;
  score = cost - log ((double) count);
  if (best->found && score >= best->score)
    return;

  g_strlcpy (best->text, text, sizeof (best->text));
  best->score = score;
  best->reach = cost - typed_cost;
  best->by_taps = by_taps;
  best->found = TRUE;
}

/* The count and the written form of a word of these letters, if it may be offered */
static guint
offer (const char *letters, const char **display)
{
  size_t len = strlen (letters);
  guint best = 0;

  *display = NULL;
  if (len < 1 || len > MAX_LEN)
    return 0;

  for (guint i = 0; i < by_len[len]->len; i++) {
    Entry *e = &g_array_index (by_len[len], Entry, i);

    if (e->count > best && strcmp (e->letters, letters) == 0) {
      best = e->count;
      *display = e->display;
    }
  }
  return best;
}


static char *
with_case (const char *typed, const char *fixed)
{
  char *out = g_strdup (fixed);

  if (g_ascii_isupper (typed[0]))
    out[0] = g_ascii_toupper (out[0]);
  return out;
}

/* The fewest single-letter changes (one swapped pair counts once) from one word to another */
static guint
edits (const char *a, const char *b)
{
  size_t n = strlen (a), m = strlen (b);
  g_autofree guint *d = g_new0 (guint, (n + 1) * (m + 1));
#define D(i, j) d[(i) * (m + 1) + (j)]

  for (size_t i = 0; i <= n; i++)
    D (i, 0) = i;
  for (size_t j = 0; j <= m; j++)
    D (0, j) = j;
  for (size_t i = 1; i <= n; i++) {
    for (size_t j = 1; j <= m; j++) {
      guint cost = g_ascii_tolower (a[i - 1]) == g_ascii_tolower (b[j - 1]) ? 0 : 1;
      guint v = MIN (D (i - 1, j) + 1, D (i, j - 1) + 1);

      v = MIN (v, D (i - 1, j - 1) + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1])
        v = MIN (v, D (i - 2, j - 2) + 1);
      D (i, j) = v;
    }
  }
  return D (n, m);
#undef D
}

/**
 * tactus_ac_correct:
 * @word: The word as typed
 * @taps:(nullable): Where the finger landed for each of its letters
 * @n_taps: How many of those there are
 * @sentence_start: Whether the word starts a sentence, so that its capital says nothing
 *
 * Returns:(transfer full)(nullable): The word that was meant, or %NULL to keep it as typed
 */
char *
tactus_ac_correct (const char *word, const TactusTap *taps, guint n_taps, gboolean sentence_start)
{
  static const char *const i_tails[] = { "m", "ll", "ve", "d", NULL };
  g_autofree char *lower = NULL;
  size_t n;
  gboolean have_taps, solid, seen;
  double tx[MAX_LEN], ty[MAX_LEN];
  double typed_cost = 0.0, typed_score, reach_max;
  guint typed_count, floor;
  Best best = { .found = FALSE };
  const char *display;

  ensure_init ();
  if (hun == NULL || word == NULL || *word == '\0')
    return NULL;

  n = strlen (word);
  if (n > MAX_LEN)
    return NULL;

  /* "i'm" and its kin, typed with the apostrophe */
  if (word[0] == 'i' && word[1] == '\'' && g_strv_contains (i_tails, word + 2)) {
    char *fixed = g_strdup (word);

    fixed[0] = 'I';
    return fixed;
  }

  /* Letters only; a capital in mid sentence is a name, and all capitals are meant */
  for (size_t i = 0; i < n; i++) {
    if (!g_ascii_isalpha (word[i]))
      return NULL;
    if (i > 0 && g_ascii_isupper (word[i]))
      return NULL;
  }
  if (g_ascii_isupper (word[0]) && !sentence_start)
    return NULL;

  lower = g_ascii_strdown (word, -1);
  if (strcmp (lower, "i") == 0)
    return strcmp (word, "I") == 0 ? NULL : g_strdup ("I");
  if (n == 1)
    return NULL;
  /* A word the owner taught stays */
  if (g_hash_table_contains (learned, lower))
    return NULL;

  typed_count = count_of (lower);

  if (g_strv_contains (acronyms, lower)) {
    char *upper = g_ascii_strup (lower, -1);

    if (strcmp (upper, word) != 0)
      return upper;
    g_free (upper);
    return NULL;
  }
  /* A name typed small: "paris", "monday" */
  if (n >= 3 && typed_count >= COMMON && !hun_ok (lower)) {
    g_autofree char *capital = g_strdup (lower);

    capital[0] = g_ascii_toupper (capital[0]);
    if (hun_ok (capital))
      return strcmp (capital, word) == 0 ? NULL : g_steal_pointer (&capital);
  }

  /* How the word stands: solid (the dictionary's, the owner's, everyday
   * writing), seen (not a word, but people do write it: "alot", "goin"), or
   * not known at all */
  solid = is_solid (lower);
  seen = !solid && typed_count >= COMMON;
  /* What a word that isn't solid is replaced by is an everyday word */
  floor = solid ? OFFERED : FIX_COMMON;

  have_taps = taps != NULL && n_taps == n;
  for (size_t i = 0; have_taps && i < n; i++)
    have_taps = taps[i].valid;

  /* Where each finger landed, on a keyboard of unit keys. With no taps to go
   * by, as if each was dead centre: then only the letters speak. */
  for (size_t i = 0; i < n; i++) {
    double x = 0.0, y = 0.0;

    if (!key_pos (lower[i], &x, &y))
      return NULL;
    tx[i] = x;
    ty[i] = y;
    if (have_taps) {
      tx[i] += taps[i].dx - bias_x;
      ty[i] += taps[i].dy - bias_y;
      typed_cost += KX * (tx[i] - x) * (tx[i] - x) + KY * (ty[i] - y) * (ty[i] - y);
    }
  }

  /* Words of as many letters, tap by tap; among them the same letters with an apostrophe */
  if (have_taps)
    reach_max = REACH_TAPS + REACH_MORE * MAX ((int) n - REACH_LONG, 0);
  else
    reach_max = n <= 4 ? REACH_SHORT : REACH_BLIND;
  for (guint w = 0; w < by_len[n]->len; w++) {
    Entry *e = &g_array_index (by_len[n], Entry, w);
    double cost = 0.0;
    gboolean out = FALSE;

    if (e->count < floor || strcmp (e->display, lower) == 0)
      continue;
    for (size_t i = 0; i < n; i++) {
      double x = 0.0, y = 0.0, c;

      key_pos (e->letters[i], &x, &y);
      c = KX * (tx[i] - x) * (tx[i] - x) + KY * (ty[i] - y) * (ty[i] - y);
      if (c > LETTER_MAX) {
        out = TRUE;
        break;
      }
      cost += c;
    }
    if (out || cost - typed_cost > reach_max)
      continue;
    consider (&best, e->display, cost, e->count, typed_cost, TRUE);
  }

  /* The usual slips of a word that isn't one: two letters swapped, a letter
   * too many, a letter missed, a space missed or hit as the key above it */
  if (!solid) {
    char cand[MAX_LEN + 4];
    const char *az = "abcdefghijklmnopqrstuvwxyz";
    guint count;

    for (size_t i = 0; i + 1 < n; i++) {
      if (lower[i] == lower[i + 1])
        continue;
      memcpy (cand, lower, n + 1);
      cand[i] = lower[i + 1];
      cand[i + 1] = lower[i];
      if ((count = offer (cand, &display)) >= floor)
        consider (&best, display, typed_cost + COST_SWAP, count, typed_cost, FALSE);
    }
    if (n > 2) {
      for (size_t i = 0; i < n; i++) {
        memcpy (cand, lower, i);
        memcpy (cand + i, lower + i + 1, n - i);
        /* not down to a word with an apostrophe: "iam" is "I am", not "I'm" */
        if ((count = offer (cand, &display)) >= floor && !strchr (display, '\'')) {
          gboolean twice = (i > 0 && lower[i] == lower[i - 1]) || lower[i] == lower[i + 1];

          consider (&best, display, typed_cost + (twice ? COST_DOUBLE : COST_EXTRA), count, typed_cost, FALSE);
        }
      }
    }
    if (n + 1 <= MAX_LEN) {
      for (size_t i = 0; i <= n; i++) {
        for (const char *c = az; *c; c++) {
          memcpy (cand, lower, i);
          cand[i] = *c;
          memcpy (cand + i + 1, lower + i, n - i + 1);
          if ((count = offer (cand, &display)) >= floor) {
            gboolean twice = (i > 0 && *c == lower[i - 1]) || (i < n && *c == lower[i]);
            /* "goin", "nothin" */
            gboolean dropped = i == n && *c == 'g' && n >= 4 && g_str_has_suffix (lower, "in");

            consider (&best, display, typed_cost + (dropped ? COST_DROPPED : twice ? COST_DOUBLE : COST_MISSED),
                      count, typed_cost, FALSE);
          }
        }
      }
    }
    if (n >= 3) {
      for (size_t i = 1; i < n; i++) {
        char left[MAX_LEN + 1], right[MAX_LEN + 1];
        const char *dl, *dr;
        guint cl, cr;

        memcpy (left, lower, i);
        left[i] = '\0';
        cl = offer (left, &dl);
        if (cl < SPLIT_COMMON)
          continue;

        /* the space was missed */
        memcpy (right, lower + i, n - i + 1);
        cr = offer (right, &dr);
        if (cr >= SPLIT_COMMON && n >= 4 - (i == 1 ? 1 : 0)) {
          g_autofree char *both = g_strdup_printf ("%s %s", dl, dr);

          consider (&best, both, typed_cost + COST_SPLIT, MIN (cl, cr), typed_cost, FALSE);
        }

        /* a key of the row above the space bar was hit for it */
        if (n >= 5 && i + 1 < n && strchr ("cvbnm", lower[i])) {
          memcpy (right, lower + i + 1, n - i);
          cr = offer (right, &dr);
          if (cr >= SPLIT_COMMON) {
            g_autofree char *both = g_strdup_printf ("%s %s", dl, dr);

            consider (&best, both, typed_cost + COST_SPLIT + 1.0, MIN (cl, cr), typed_cost, FALSE);
          }
        }
      }
    }

    /* The dictionary's own guesses, where nothing above explains the word:
     * spelled as it sounds ("definately") */
    if (!best.found && n <= 16) {
      char **guesses = NULL;
      int n_guesses = Hunspell_suggest (hun, &guesses, lower);

      for (int g = 0; g < MIN (n_guesses, 3); g++) {
        const char *guess = guesses[g];
        gboolean plain = g_str_is_ascii (guess);
        guint far;

        for (const char *q = guess; plain && *q; q++)
          plain = g_ascii_islower (*q);
        if (!plain)
          continue;
        far = edits (lower, guess);
        count = count_of (guess);
        if (count < floor)
          continue;
        if (far == 1 || (far == 2 && n >= GUESS_LONG && count >= GUESS_TWO))
          consider (&best, guess, typed_cost + COST_GUESS * far + 0.2 * g, count, typed_cost, FALSE);
      }
      if (n_guesses > 0)
        Hunspell_free_list (hun, &guesses, n_guesses);
    }
  }

  typed_score = typed_cost - log ((double) MAX (typed_count, 1));
  if (!solid)
    typed_score += seen ? SEEN : UNKNOWN;

  if (best.found) {
    gboolean take;

    if (solid)
      take = best.by_taps && best.reach <= KNOWN_REACH && best.score < typed_score - KNOWN_MARGIN;
    else
      take = best.score < typed_score - OTHER_MARGIN;

    /* Letter counts only: what was typed never goes to a log (known: 2 solid,
     * 1 seen, 0 not in the dictionary) */
    g_debug ("a word of %u letters (known %d, %.1f) against one of %u (%.1f, reach %.1f): replaced %d",
             (guint) g_utf8_strlen (word, -1), solid ? 2 : seen ? 1 : 0, typed_score,
             (guint) g_utf8_strlen (best.text, -1), best.score, best.reach, take);
    if (take)
      return with_case (word, best.text);
  }

  return NULL;
}

/**
 * tactus_ac_observe:
 * @typed: A word as its letters were read
 * @meant: The word that went to the text field
 * @taps: Where the finger landed for each letter of @typed
 * @n_taps: How many of those
 *
 * Learn where this owner's fingers land compared to the keys they aim at,
 * from a word that is trusted to be what was meant.
 */
void
tactus_ac_observe (const char *typed, const char *meant, const TactusTap *taps, guint n_taps)
{
  g_autofree char *a = NULL;
  g_autofree char *b = NULL;
  size_t n, m = 0;

  ensure_init ();
  if (typed == NULL || meant == NULL || taps == NULL)
    return;

  n = strlen (typed);
  if (n != n_taps || n < 2 || n > MAX_LEN)
    return;

  a = g_ascii_strdown (typed, -1);
  /* the word that was meant, by its letters */
  b = g_malloc0 (strlen (meant) + 1);
  for (const char *p = meant; *p; p++) {
    if (g_ascii_isalpha (*p))
      b[m++] = g_ascii_tolower (*p);
    else if (*p != '\'')
      return;
  }
  if (m != n)
    return;
  if (count_of (b) < COMMON) {
    const char *display;

    if (offer (b, &display) < COMMON)
      return;
  }

  for (size_t i = 0; i < n; i++) {
    double x, y, mx, my, ox, oy;

    if (!taps[i].valid || !key_pos (a[i], &x, &y) || !key_pos (b[i], &mx, &my))
      continue;
    ox = CLAMP (x + taps[i].dx - mx, -1.0, 1.0);
    oy = CLAMP (y + taps[i].dy - my, -1.0, 1.0);
    bias_x = CLAMP ((1.0 - BIAS_RATE) * bias_x + BIAS_RATE * ox, -BIAS_MAX_X, BIAS_MAX_X);
    bias_y = CLAMP ((1.0 - BIAS_RATE) * bias_y + BIAS_RATE * oy, -BIAS_MAX_Y, BIAS_MAX_Y);
    bias_unsaved++;
  }
  if (bias_unsaved >= BIAS_SAVE)
    tactus_ac_save ();
}

/**
 * tactus_ac_get_bias:
 * @dx:(out): How far right of where they aim this owner's fingers land, in key widths
 * @dy:(out): How far below, in row heights
 *
 * Returns: %TRUE (there is always an answer; it starts at none)
 */
gboolean
tactus_ac_get_bias (double *dx, double *dy)
{
  ensure_init ();
  *dx = bias_x;
  *dy = bias_y;
  return TRUE;
}
