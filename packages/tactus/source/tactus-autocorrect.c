/*
 * Tactus's autocorrection: which word the owner meant.
 *
 * A typed word is weighed against the words it could have been: by where
 * each finger landed (a tap near the edge of a key speaks for its neighbour),
 * by how common each word is, and by the usual slips (two letters swapped,
 * one missed or doubled, a missed space, a missing apostrophe). A word the
 * dictionary knows is replaced only when the taps themselves were close
 * calls; a word the owner took back once is left alone from then on. A word
 * with a capital in mid sentence is a name: it is changed only by the taps,
 * and only to a word or name the dictionary knows.
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
/* Which word follows which: tools/tactus-word-pairs.py's counts in Tatoeba's
 * English sentences. TACTUS_WORD_PAIRS names another file, for the tests. */
#define PAIRS_DEFAULT TACTUS_PKGDATADIR "/word-pairs.txt"
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
/* … and may be a word the word list counts as rare, or not at all ("widget"),
 * if a typed word this long has one key hit beside it, as a close call */
#define GUESS_SLIP   5
/* A known word gives way only to a clearly likelier one, and only when the taps were close calls */
#define KNOWN_MARGIN 4.0
#define KNOWN_REACH  1.5
/* A tap is a close call for the key beside it when it is a third of the way
 * there or more: the word it would make costs at most this much of what it
 * costs from the middle of the key */
#define CLOSE_CALL   0.3
/* … and where it would make two slips at once (a tap too many as well), a fifth */
#define CLOSE_TIGHT  0.2
#define OTHER_MARGIN 1.0
/* How fast the keyboard learns where this owner's fingers land, and how far it may go */
#define BIAS_RATE    0.01
#define BIAS_MAX_X   0.15
#define BIAS_MAX_Y   0.25
#define BIAS_SAVE    40
/* … and the typed word long enough */
#define GUESS_LONG   7

/* Context. What a word's neighbours say for it: how much more often than
 * by chance the pair was seen, as a log, no more than this either way */
#define CTX_CLIP     3.0
/* … weighed this much against the taps and the word's own count */
#define CTX_WEIGHT   0.7
/* A pair seen fewer times than the word pairs keep counts as seen this often */
#define CTX_ABSENT   3.0
/* A word the dictionary knows gives way to the one beside it, its changed
 * letters close calls, only where its neighbours say this much more for
 * that one … */
#define CTX_STRONG   3.5
/* … and the whole weighing too, by this much */
#define CTX_MARGIN   2.5

/* Keys that grow: a letter likelier next takes a little of its neighbours'
 * room. What it may take is at most this, in the taps' currency, less than
 * the distance between two keys' middles, so a tap in a key's middle is that
 * key's. */
#define PRIOR_MAX    0.8
#define PRIOR_SCALE  0.3
#define PRIOR_FLOOR  0.002
/* How many pairs after the word before it takes to trust them fully */
#define PRIOR_PAIRS  40.0

typedef struct {
  guint64 key;   /* the first word's number above the second's */
  guint   count;
} Pair;

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
static GPtrArray    *by_letters;      /* Entry *, by letters: the words a beginning may become */
/* The word pairs */
static GHashTable   *pair_id;         /* word -> its number + 1 */
static GPtrArray    *pair_word;       /* number -> word */
static GArray       *pair_seen;       /* number -> guint: how often the word was seen */
static GArray       *pairs;           /* Pair, by key */
static double        pair_total;
/* The words either side of the word being corrected, if known */
static int           ctx_before = -1, ctx_after = -1;
/* The keys' share of the next letter while a word is typed */
static double        prior[26];
static gboolean      prior_on;
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
  "msg", "msgs", "pic", "pics", "vid", "vids", "convo", "convos", "ppl", "txt", "tactus",
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


static int
cmp_letters (gconstpointer a, gconstpointer b)
{
  return strcmp ((*(Entry *const *) a)->letters, (*(Entry *const *) b)->letters);
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

  by_letters = g_ptr_array_new ();
  for (int i = 1; i <= MAX_LEN; i++) {
    for (guint j = 0; j < by_len[i]->len; j++)
      g_ptr_array_add (by_letters, &g_array_index (by_len[i], Entry, j));
  }
  g_ptr_array_sort (by_letters, cmp_letters);
}


static int
cmp_pair (gconstpointer a, gconstpointer b)
{
  guint64 x = ((const Pair *) a)->key, y = ((const Pair *) b)->key;

  return x < y ? -1 : x > y;
}

/* tools/tactus-word-pairs.py's file: "total N", "sentences N", "words", then
 * "word count" lines, "pairs", then lines of a word and the words seen after
 * it, "word:count" */
static void
load_pairs (const char *path)
{
  g_autofree char *contents = NULL;
  char *save = NULL;
  enum { HEAD, WORDS, PAIRS } part = HEAD;
  guint sentences = 0;

  if (!g_file_get_contents (path, &contents, NULL, NULL)) {
    g_warning ("No word pairs at %s: the keyboard corrects words without their context", path);
    return;
  }
  pair_id = g_hash_table_new (g_str_hash, g_str_equal);
  pair_word = g_ptr_array_new ();
  pair_seen = g_array_new (FALSE, FALSE, sizeof (guint));
  pairs = g_array_new (FALSE, FALSE, sizeof (Pair));

  for (char *line = strtok_r (contents, "\n", &save); line; line = strtok_r (NULL, "\n", &save)) {
    if (line[0] == '#')
      continue;
    if (part == HEAD) {
      if (g_str_has_prefix (line, "total "))
        pair_total = g_ascii_strtod (line + 6, NULL);
      else if (g_str_has_prefix (line, "sentences "))
        sentences = (guint) g_ascii_strtoull (line + 10, NULL, 10);
      else if (strcmp (line, "words") == 0) {
        /* the start of a sentence is a word of its own */
        char *start = g_string_chunk_insert (chunk, "^");

        g_hash_table_insert (pair_id, start, GUINT_TO_POINTER (1));
        g_ptr_array_add (pair_word, start);
        g_array_append_val (pair_seen, sentences);
        part = WORDS;
      }
    } else if (part == WORDS) {
      char *space = strchr (line, ' ');
      guint count;

      if (strcmp (line, "pairs") == 0) {
        part = PAIRS;
        continue;
      }
      if (space == NULL)
        continue;
      *space = '\0';
      count = (guint) g_ascii_strtoull (space + 1, NULL, 10);
      line = g_string_chunk_insert (chunk, line);
      g_hash_table_insert (pair_id, line, GUINT_TO_POINTER (pair_word->len + 1));
      g_ptr_array_add (pair_word, line);
      g_array_append_val (pair_seen, count);
    } else {
      char *rest = strchr (line, ' '), *item, *save2 = NULL;
      guint a;

      if (rest == NULL)
        continue;
      *rest++ = '\0';
      a = GPOINTER_TO_UINT (g_hash_table_lookup (pair_id, line));
      if (a == 0)
        continue;
      for (item = strtok_r (rest, " ", &save2); item; item = strtok_r (NULL, " ", &save2)) {
        char *colon = strchr (item, ':');
        Pair pair;
        guint b;

        if (colon == NULL)
          continue;
        *colon = '\0';
        b = GPOINTER_TO_UINT (g_hash_table_lookup (pair_id, item));
        if (b == 0)
          continue;
        pair.key = ((guint64) (a - 1) << 32) | (b - 1);
        pair.count = (guint) g_ascii_strtoull (colon + 1, NULL, 10);
        g_array_append_val (pairs, pair);
      }
    }
  }
  g_array_sort (pairs, cmp_pair);
  if (pair_total < 1.0 || pairs->len == 0) {
    g_warning ("The word pairs at %s are empty: the keyboard corrects words without their context", path);
    g_clear_pointer (&pairs, g_array_unref);
  }
}

/* A word's number among the word pairs; -1 if it has none. Its letters
 * only, small: "Don't" is "dont". */
static int
pair_of (const char *word)
{
  char letters[MAX_LEN + 1];
  size_t n = 0;

  if (pairs == NULL || word == NULL)
    return -1;
  for (const char *p = word; *p; p++) {
    if (*p == '\'')
      continue;
    if (!g_ascii_isalpha (*p) || n >= MAX_LEN)
      return -1;
    letters[n++] = g_ascii_tolower (*p);
  }
  letters[n] = '\0';
  return (int) GPOINTER_TO_UINT (g_hash_table_lookup (pair_id, letters)) - 1;
}

static guint
pair_count (int a, int b)
{
  Pair want = { .key = ((guint64) a << 32) | (guint) b };
  guint lo = 0, hi = pairs->len;

  while (lo < hi) {
    guint mid = (lo + hi) / 2;
    int c = cmp_pair (&g_array_index (pairs, Pair, mid), &want);

    if (c == 0)
      return g_array_index (pairs, Pair, mid).count;
    if (c < 0)
      lo = mid + 1;
    else
      hi = mid;
  }
  return 0;
}

/* How much more often than by chance @b was seen after @a, as a log */
static double
pair_say (int a, int b)
{
  double expected, seen;

  if (a < 0 || b < 0)
    return 0.0;
  expected = (double) g_array_index (pair_seen, guint, a) * g_array_index (pair_seen, guint, b) / pair_total;
  seen = pair_count (a, b);
  return CLAMP (log ((seen + CTX_ABSENT) / (expected + CTX_ABSENT)), -CTX_CLIP, CTX_CLIP);
}

/* What the words either side say for @text, a word or two ("a lot") */
static double
context_for (const char *text)
{
  const char *space;
  double say = 0.0;

  if (ctx_before < 0 && ctx_after < 0)
    return 0.0;
  space = strchr (text, ' ');
  if (ctx_before >= 0) {
    g_autofree char *first = space ? g_strndup (text, space - text) : g_strdup (text);

    say += pair_say (ctx_before, pair_of (first));
  }
  if (ctx_after >= 0)
    say += pair_say (pair_of (space ? strrchr (text, ' ') + 1 : text), ctx_after);
  return say;
}


static void
ensure_init (void)
{
  const char *freq_path = g_getenv ("TACTUS_WORD_COUNTS") ?: FREQ_DEFAULT;
  const char *pairs_path = g_getenv ("TACTUS_WORD_PAIRS") ?: PAIRS_DEFAULT;
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
  load_pairs (pairs_path);
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


/* A word as typed: its letters, where each finger landed, and how far that
 * was from the key it was read as */
typedef struct {
  char     letters[MAX_LEN + 1];
  double   tx[MAX_LEN], ty[MAX_LEN], own[MAX_LEN];
  size_t   n;
  double   cost;       /* all of @own */
  gboolean have_taps;
} Typed;


typedef struct {
  char    text[2 * MAX_LEN + 4];
  double  score;
  double  reach;     /* how much further from the taps than the word as typed */
  double  say;       /* what the words either side say for it */
  gboolean by_taps;  /* a word of the same letters count, weighed tap by tap */
  gboolean found;
} Best;


static void
consider (Best *best, const char *text, double cost, guint count, double typed_cost, gboolean by_taps)
{
  double score, say;

  if (count < OFFERED)
    return;
  say = context_for (text);
  score = cost - log ((double) count) - CTX_WEIGHT * say;
  if (best->found && score >= best->score)
    return;

  g_strlcpy (best->text, text, sizeof (best->text));
  best->score = score;
  best->say = say;
  best->reach = cost - typed_cost;
  best->by_taps = by_taps;
  best->found = TRUE;
}

/* Whether the tap for letter @i of @t was a close call for @key: on its way
 * there by @close of the distance from the middle of the key it hit or more */
static gboolean
close_call (const Typed *t, size_t i, char key, double close)
{
  double x, y, ox, oy, c;

  if (!t->have_taps || !key_pos (key, &x, &y) || !key_pos (t->letters[i], &ox, &oy))
    return FALSE;
  c = KX * (t->tx[i] - x) * (t->tx[i] - x) + KY * (t->ty[i] - y) * (t->ty[i] - y);
  return c - t->own[i] <= close * (KX * (ox - x) * (ox - x) + KY * (oy - y) * (oy - y));
}

/* The words of as many letters as @t, weighed tap by tap. A word seen fewer
 * than @floor times, or any word if @close_only, is offered only where the
 * taps were close calls (@close) for each letter it changes. @extra is added
 * to what each costs, and @typed_cost is what the word as typed costs. */
static void
weigh_taps (Best *best, const Typed *t, guint floor, gboolean close_only, double close,
            double reach_max, double extra, double typed_cost, gboolean by_taps)
{
  for (guint w = 0; w < by_len[t->n]->len; w++) {
    Entry *e = &g_array_index (by_len[t->n], Entry, w);
    double cost = 0.0;
    gboolean out = FALSE, near = TRUE;
    guint changed = 0;

    if (e->count < OFFERED || strcmp (e->display, t->letters) == 0)
      continue;
    if ((e->count < floor || close_only) && !t->have_taps)
      continue;
    for (size_t i = 0; i < t->n; i++) {
      double x = 0.0, y = 0.0, c;

      key_pos (e->letters[i], &x, &y);
      c = KX * (t->tx[i] - x) * (t->tx[i] - x) + KY * (t->ty[i] - y) * (t->ty[i] - y);
      if (c > LETTER_MAX) {
        out = TRUE;
        break;
      }
      cost += c;
      if (e->letters[i] != t->letters[i]) {
        changed++;
        near = near && close_call (t, i, e->letters[i], close);
      }
    }
    if (out || cost - t->cost > reach_max)
      continue;
    if ((e->count < floor || close_only) && !(changed > 0 && near))
      continue;
    consider (best, e->display, typed_cost + extra + cost - t->cost, e->count, typed_cost, by_taps);
  }
}

/* Which letter of @a was hit as the key beside it to make @b; -1 if that isn't all */
static int
one_slip (const char *a, const char *b)
{
  size_t n = strlen (a);
  int at = -1;
  double ax, ay, bx, by;

  if (strlen (b) != n)
    return -1;
  for (size_t i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      if (at >= 0)
        return -1;
      at = i;
    }
  }
  if (at < 0 || !key_pos (a[at], &ax, &ay) || !key_pos (b[at], &bx, &by) ||
      (ax - bx) * (ax - bx) + (ay - by) * (ay - by) > 1.3)
    return -1;
  return at;
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

/* The word that was meant by @word, or NULL to keep it. @again: it was
 * kept once, and now the word after it is known too: only what the words
 * either side say may change it. */
static char *
correct (const char *word, const TactusTap *taps, guint n_taps, gboolean sentence_start, gboolean again)
{
  static const char *const i_tails[] = { "m", "ll", "ve", "d", NULL };
  g_autofree char *lower = NULL;
  size_t n;
  gboolean have_taps, solid, seen, name, short_form;
  Typed t = { .n = 0 };
  double *tx = t.tx, *ty = t.ty;
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
  name = g_ascii_isupper (word[0]) && !sentence_start;

  lower = g_ascii_strdown (word, -1);
  if (strcmp (lower, "i") == 0)
    return strcmp (word, "I") == 0 ? NULL : g_strdup ("I");
  if (n == 1)
    return NULL;
  /* A word the owner taught stays */
  if (g_hash_table_contains (learned, lower))
    return NULL;

  typed_count = count_of (lower);

  if (!name && g_strv_contains (acronyms, lower)) {
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
  /* A short form people write ("btw", "pics", "msgs") is meant as much as a
   * word the owner taught: a tap near the edge of a key doesn't make it the
   * far commoner word next to it ("btw" is not "bye") */
  short_form = g_strv_contains (informal, lower);
  if (short_form)
    typed_count = MAX (typed_count, LEARNED);

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
      t.own[i] = KX * (tx[i] - x) * (tx[i] - x) + KY * (ty[i] - y) * (ty[i] - y);
      typed_cost += t.own[i];
    }
  }
  memcpy (t.letters, lower, n + 1);
  t.n = n;
  t.cost = typed_cost;
  t.have_taps = have_taps;

  /* How much further from the taps than the word as typed a word may be */
  if (have_taps)
    reach_max = REACH_TAPS + REACH_MORE * MAX ((int) n - REACH_LONG, 0);
  else
    reach_max = n <= 4 ? REACH_SHORT : REACH_BLIND;

  /* A name that isn't one the dictionary knows (nor a word people write) is
   * changed only where the taps were close calls toward one it does know:
   * "Vigip" for "Vigil". With no taps to go by, it stays. */
  if (name) {
    if (again || !have_taps || solid || typed_count >= COMMON)
      return NULL;
    weigh_taps (&best, &t, OFFERED, TRUE, CLOSE_CALL, reach_max, 0.0, typed_cost, TRUE);
    typed_score = typed_cost - log ((double) MAX (typed_count, 1)) + UNKNOWN;
    g_debug ("a name of %u letters (%.1f) against one of %u (%.1f): replaced %d", (guint) n, typed_score,
             best.found ? (guint) strlen (best.text) : 0, best.score,
             best.found && best.score < typed_score - OTHER_MARGIN);
    if (best.found && best.score < typed_score - OTHER_MARGIN)
      return with_case (word, best.text);
    return NULL;
  }

  typed_score = typed_cost - log ((double) MAX (typed_count, 1)) - CTX_WEIGHT * context_for (lower);
  if (!solid)
    typed_score += seen ? SEEN : UNKNOWN;
  if (again)
    goto in_context;

  /* Words of as many letters, tap by tap (among them the same letters with an
   * apostrophe); a rarer one only where the taps point to it */
  weigh_taps (&best, &t, floor, FALSE, CLOSE_CALL, reach_max, 0.0, typed_cost, TRUE);

  /* A tap too many, and among the rest a key hit beside the one meant:
   * "ipgone" for "phone". Only where the taps were close calls. */
  if (!solid && have_taps && n >= 5) {
    for (size_t skip = 0; skip < n; skip++) {
      Typed less = { .n = n - 1, .have_taps = TRUE };

      for (size_t i = 0, j = 0; i < n; i++) {
        if (i == skip)
          continue;
        less.letters[j] = lower[i];
        less.tx[j] = tx[i];
        less.ty[j] = ty[i];
        less.own[j] = t.own[i];
        less.cost += t.own[i];
        j++;
      }
      less.letters[n - 1] = '\0';
      weigh_taps (&best, &less, floor, TRUE, CLOSE_TIGHT, reach_max, COST_EXTRA, typed_cost, FALSE);
    }
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
        int at;

        for (const char *q = guess; plain && *q; q++)
          plain = g_ascii_islower (*q);
        if (!plain)
          continue;
        far = edits (lower, guess);
        count = count_of (guess);
        /* one key beside the right one in a longer word, and the tap was a
         * close call: the word list may just not have it */
        if (count < floor && n >= GUESS_SLIP && (at = one_slip (lower, guess)) >= 0 &&
            close_call (&t, at, guess[at], CLOSE_CALL))
          count = MAX (count, OFFERED);
        else if (count < floor)
          continue;
        if (far == 1 || (far == 2 && n >= GUESS_LONG && count >= GUESS_TWO))
          consider (&best, guess, typed_cost + COST_GUESS * far + 0.2 * g, count, typed_cost, FALSE);
      }
      if (n_guesses > 0)
        Hunspell_free_list (hun, &guesses, n_guesses);
    }
  }

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

in_context:
  /* A word the dictionary knows, where the words either side speak for the
   * one beside it far more than for it ("the bot" is "the boy"): only with
   * each changed letter a close call, and never a short form people write */
  if (solid && have_taps && !short_form && (ctx_before >= 0 || ctx_after >= 0)) {
    Best near = { .found = FALSE };
    double typed_say = context_for (lower);

    weigh_taps (&near, &t, COMMON, TRUE, CLOSE_CALL, reach_max, 0.0, typed_cost, TRUE);
    if (near.found) {
      gboolean take = near.say - typed_say >= CTX_STRONG && near.score < typed_score - CTX_MARGIN;

      g_debug ("a word of %u letters (%.1f, context %.1f) against one of %u (%.1f, context %.1f): replaced %d",
               (guint) n, typed_score, typed_say, (guint) strlen (near.text), near.score, near.say, take);
      if (take)
        return with_case (word, near.text);
    }
  }

  return NULL;
}

/* Where @word starts a sentence and nothing is known before it, the start
 * of a sentence is what comes before it */
static void
set_context (const char *before, const char *after, gboolean sentence_start)
{
  ctx_before = before ? pair_of (before) : sentence_start ? pair_of ("^") : -1;
  ctx_after = after ? pair_of (after) : -1;
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
  return tactus_ac_correct_in (word, taps, n_taps, sentence_start, NULL);
}

/**
 * tactus_ac_correct_in:
 * @before:(nullable): The word before it, with a space alone between them
 *
 * As tactus_ac_correct(), with what the word before says for each word it
 * could be.
 */
char *
tactus_ac_correct_in (const char *word, const TactusTap *taps, guint n_taps, gboolean sentence_start,
                      const char *before)
{
  char *fixed;

  ensure_init ();
  set_context (before, NULL, sentence_start);
  fixed = correct (word, taps, n_taps, sentence_start, FALSE);
  ctx_before = ctx_after = -1;
  return fixed;
}

/**
 * tactus_ac_reconsider:
 * @word: A word kept as typed
 * @before:(nullable): The word before it
 * @after: The word typed after it, with a space alone between them
 *
 * A word kept as it was typed, weighed again now that the word after it is
 * known: it changes only where the words either side speak far more for a
 * word beside it, its changed letters close calls.
 *
 * Returns:(transfer full)(nullable): The word that was meant, or %NULL to keep it
 */
char *
tactus_ac_reconsider (const char *word, const TactusTap *taps, guint n_taps, gboolean sentence_start,
                      const char *before, const char *after)
{
  char *fixed;

  ensure_init ();
  if (after == NULL)
    return NULL;
  set_context (before, after, sentence_start);
  fixed = correct (word, taps, n_taps, sentence_start, TRUE);
  ctx_before = ctx_after = -1;
  return fixed;
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

/*
 * Keys that grow
 */

/* The first entry in by_letters whose letters are not before @prefix */
static guint
first_with (const char *prefix)
{
  guint lo = 0, hi = by_letters->len;

  while (lo < hi) {
    guint mid = (lo + hi) / 2;

    if (strcmp (((Entry *) g_ptr_array_index (by_letters, mid))->letters, prefix) < 0)
      lo = mid + 1;
    else
      hi = mid;
  }
  return lo;
}

/**
 * tactus_ac_set_typing:
 * @before:(nullable): The word before the one being typed, with a space alone between them
 * @prefix:(nullable): The letters typed of the word so far ("" at its start);
 *   %NULL where no word is being typed that may be corrected
 * @sentence_start: Whether the word starts a sentence
 *
 * Which letter is likely next, for the keys to lean toward it: by how often
 * the words that start so are written and, where they were seen after the
 * word before, how often they were seen there.
 */
void
tactus_ac_set_typing (const char *before, const char *prefix, gboolean sentence_start)
{
  double uni[26] = { 0 }, bi[26] = { 0 }, uni_all = 0.0, bi_all = 0.0, share = 0.0, top = 0.0;
  size_t n;
  int a;

  prior_on = FALSE;
  ensure_init ();
  if (prefix == NULL || by_letters == NULL)
    return;
  n = strlen (prefix);
  if (n >= MAX_LEN)
    return;
  for (size_t i = 0; i < n; i++) {
    if (prefix[i] < 'a' || prefix[i] > 'z')
      return;
  }

  for (guint i = first_with (prefix); i < by_letters->len; i++) {
    Entry *e = g_ptr_array_index (by_letters, i);

    if (strncmp (e->letters, prefix, n) != 0)
      break;
    if (e->letters[n] == '\0')
      continue;
    uni[e->letters[n] - 'a'] += e->count;
    uni_all += e->count;
  }
  if (uni_all <= 0.0)
    return;

  /* The words seen after the word before */
  a = before ? pair_of (before) : sentence_start ? pair_of ("^") : -1;
  if (a >= 0) {
    Pair want = { .key = (guint64) a << 32 };
    guint lo = 0, hi = pairs->len;

    while (lo < hi) {
      guint mid = (lo + hi) / 2;

      if (cmp_pair (&g_array_index (pairs, Pair, mid), &want) < 0)
        lo = mid + 1;
      else
        hi = mid;
    }
    for (guint i = lo; i < pairs->len && g_array_index (pairs, Pair, i).key >> 32 == (guint64) a; i++) {
      Pair *p = &g_array_index (pairs, Pair, i);
      const char *b = g_ptr_array_index (pair_word, (guint) (p->key & 0xffffffff));

      if (strncmp (b, prefix, n) != 0 || b[n] < 'a' || b[n] > 'z')
        continue;
      bi[b[n] - 'a'] += p->count;
      bi_all += p->count;
    }
    share = bi_all / (bi_all + PRIOR_PAIRS);
  }

  for (int l = 0; l < 26; l++) {
    prior[l] = (1.0 - share) * uni[l] / uni_all + (bi_all > 0.0 ? share * bi[l] / bi_all : 0.0);
    top = MAX (top, prior[l]);
  }
  for (int l = 0; l < 26; l++)
    prior[l] = MAX (0.0, PRIOR_MAX + PRIOR_SCALE * log ((prior[l] + PRIOR_FLOOR) / (top + PRIOR_FLOOR)));
  prior_on = TRUE;
}

/**
 * tactus_ac_tap_prior:
 * @symbol: A key's symbol
 *
 * Returns: How much room the key may take from its neighbours now, in the
 *   taps' currency: 0 when no word is being typed, never more than a key's
 *   middle is from its neighbour's
 */
double
tactus_ac_tap_prior (const char *symbol)
{
  char c;

  if (!prior_on || symbol == NULL || symbol[0] == '\0' || symbol[1] != '\0')
    return 0.0;
  c = g_ascii_tolower (symbol[0]);
  if (c < 'a' || c > 'z')
    return 0.0;
  return prior[c - 'a'];
}

/**
 * tactus_ac_tap_cost:
 * @symbol: A key's symbol
 * @dx: How far right of the key's middle a tap landed (with the owner's
 *   learned offset taken off), in key widths
 * @dy: How far below it, in row heights
 *
 * Returns: How far the tap is from the key, less what the key may take for
 *   being likely next: of two keys, the tap is the lower one's
 */
double
tactus_ac_tap_cost (const char *symbol, double dx, double dy)
{
  return KX * dx * dx + KY * dy * dy - tactus_ac_tap_prior (symbol);
}
