/*
 * Tactus's typing: what goes to the text field for each key.
 *
 * Every key is put into the text field at once; nothing is held back as
 * "text being composed". When a word ends, the letters just typed may be
 * replaced by the word that was meant. For that the typer keeps its own copy
 * of the text before the cursor.
 *
 * A text field of the usual kind tells what it holds after every change, and
 * can take text away before the cursor on request. The copy is then checked
 * against what the field tells, and the field is right when they differ.
 *
 * Some text fields tell nothing and can't take text away (the GPUI
 * applications). There the copy is all there is: it is built from our own
 * keys, text is taken away with presses of Backspace, and a sign of life from
 * the field that no key of ours explains means the cursor went elsewhere or
 * the text was sent off, so the copy starts afresh.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define G_LOG_DOMAIN "tactus-typer"

#include "tactus-typer.h"

#include <string.h>

/* How much of the text before the cursor is kept, in characters */
#define MODEL_MAX       512
#define WORD_MAX        24
/* A field that tells nothing: how long after a key its first sign of life is that key's echo */
#define ECHO_US         (1 * G_TIME_SPAN_SECOND)
/* … and how long after an echo another one still belongs to it */
#define ECHO_TAIL_US    (100 * G_TIME_SPAN_MILLISECOND)
/* A field that tells: how long it has to show what a key did (Backspace, an arrow) */
#define OTHER_WAIT_US   (300 * G_TIME_SPAN_MILLISECOND)
/* … and text put in or taken away */
#define INSERT_WAIT_US  (1 * G_TIME_SPAN_SECOND)
/* A field that tells: how long a key that may take text away waits for the
 * field to show what was sent before it */
#define HOLD_US         (250 * G_TIME_SPAN_MILLISECOND)
/* … and how long nothing waits once that was not enough */
#define HOLD_OFF_US     (3 * G_TIME_SPAN_SECOND)
/* Keys sent before a field first told its text: how many may be put after what it then tells */
#define FIRST_MAX       8
/* How often a text field is answered at most, and for how many seconds on end */
#define ACKS_A_SECOND   40
#define ACK_SECONDS     5
/* A field that tells nothing: a word typed with a pause this long is left alone */
#define PAUSE_US        (2500 * G_TIME_SPAN_MILLISECOND)
/* Two spaces this close together after a word are a full stop */
#define DOUBLE_SPACE_US (1500 * G_TIME_SPAN_MILLISECOND)

typedef struct {
  gunichar  c;
  TactusTap tap;
  gint64    time; /* when a key of ours typed it; 0 for text that was there */
} TactusChar;

typedef enum {
  TACTUS_OP_INSERT, /* text put in */
  TACTUS_OP_ERASE,  /* text taken away on request: as sure as text put in */
  TACTUS_OP_OTHER,  /* a key: what it does is up to the text field */
} TactusOpKind;

/* Something sent to a text field that tells, until the field has shown it */
typedef struct {
  TactusOpKind kind;
  gint64       time;
  char        *predicted; /* the text before the cursor once the field has done it; NULL: can't know */
  gboolean     anchored;
} TactusOp;

typedef enum {
  TACTUS_IN_KEY,
  TACTUS_IN_BACKSPACE,
  TACTUS_IN_TEXT,
} TactusInKind;

/* A key that waits for the text field to catch up */
typedef struct {
  TactusInKind    kind;
  char           *text; /* the key's symbol, or the text */
  TactusTap       tap;
  gboolean        has_tap;
  TactusBackspace how;
  gboolean        ends_word;
} TactusInput;

struct _TactusTyper {
  TactusTyperOps ops;
  gpointer       data;
  gint64       (*now) (gpointer data);
  gpointer       now_data;

  gboolean       active;
  guint          hints;
  gboolean       foreign; /* the layout is of a language the dictionary doesn't know */

  /* The text before the cursor */
  GArray        *chars;      /* TactusChar */
  gboolean       anchored;   /* it starts where the text (or its line) starts */
  gboolean       after_word; /* a letter follows the cursor */
  gboolean       selection;  /* some text is selected */

  /* A text field that tells */
  gboolean       reporting;
  gboolean       no_delete;  /* … but turned out to ignore requests to take text away */
  char          *acked;      /* what it last told */
  gboolean       acked_anchored;
  GArray        *pending;    /* TactusOp */
  char          *if_ignored; /* what it holds if it ignored the last request to take text away */
  GArray        *held;       /* TactusInput: keys that wait for it to show what was sent */
  gint64         held_since;
  gint64         no_hold_until;
  gboolean       draining;

  /* Answers to a text field, which may be waiting for one before it tells more */
  gboolean       greeted;
  gint64         ack_second;
  guint          acks;
  guint          ack_full_seconds;
  gboolean       ack_muted;

  /* A text field that tells nothing */
  gint64         last_send;
  gboolean       echo_seen;
  gint64         echo_time;
  gint64         settle_until;

  /* The last correction, while Backspace can still take it back */
  gboolean       undo_armed;
  char          *undo_typed;
  char          *undo_made;
  /* The word last put back: typed again, it is meant */
  char          *rejected;

  /* Say in the log what is done and why (never what is typed) */
  gboolean       trace;
};

#define note(self, ...) G_STMT_START { if ((self)->trace) g_message (__VA_ARGS__); } G_STMT_END

/*
 * Characters
 */

static gboolean
is_space (gunichar c)
{
  return c == ' ' || c == '\t' || c == 0xa0;
}


static gboolean
is_word_char (gunichar c)
{
  return g_unichar_isalpha (c) || c == '\'' || c == 0x2019;
}

/* What may stand between a space and the word it opens */
static gboolean
is_opener (gunichar c)
{
  return c == '(' || c == '[' || c == '{' || c == '"' || c == 0x201c || c == 0x2018 ||
         c == 0xab || c == 0xbf || c == 0xa1;
}

/* What may stand between the end of a sentence and the space after it */
static gboolean
is_closer (gunichar c)
{
  return c == ')' || c == ']' || c == '}' || c == '"' || c == '\'' || c == 0x201d ||
         c == 0x2019 || c == 0xbb;
}

/* What ends a word in a way that says the word is done: sentence punctuation, an emoji */
static gboolean
ends_word (const char *text)
{
  gunichar c = g_utf8_get_char (text);

  if (strchr (".,?!;:)]}\"", (int) c) && c < 0x80)
    return TRUE;
  return c == 0x2026 || c == 0x201d || c == 0xbb;
}

/*
 * The copy of the text before the cursor
 */

static gint64
now_us (TactusTyper *self)
{
  return self->now ? self->now (self->now_data) : g_get_monotonic_time ();
}


static TactusChar *
char_at (TactusTyper *self, guint i)
{
  return &g_array_index (self->chars, TactusChar, i);
}


static char *
model_dup (TactusTyper *self, guint from, guint to)
{
  GString *out = g_string_new (NULL);

  for (guint i = from; i < to && i < self->chars->len; i++)
    g_string_append_unichar (out, char_at (self, i)->c);
  return g_string_free (out, FALSE);
}


static guint
model_bytes (TactusTyper *self, guint from, guint to)
{
  guint bytes = 0;

  for (guint i = from; i < to && i < self->chars->len; i++)
    bytes += g_unichar_to_utf8 (char_at (self, i)->c, NULL);
  return bytes;
}


static void
model_append (TactusTyper *self, const char *text, const TactusTap *tap, gint64 time)
{
  gboolean one = g_utf8_strlen (text, -1) == 1;

  for (const char *p = text; *p; p = g_utf8_next_char (p)) {
    TactusChar ch = { .c = g_utf8_get_char (p), .time = time };

    if (ch.c == 0xa0)
      ch.c = ' ';
    if (tap && one)
      ch.tap = *tap;
    g_array_append_val (self->chars, ch);
  }

  if (self->chars->len > MODEL_MAX) {
    g_array_remove_range (self->chars, 0, self->chars->len - MODEL_MAX);
    self->anchored = FALSE;
  }
}


static void
model_pop (TactusTyper *self, guint n)
{
  n = MIN (n, self->chars->len);
  if (n)
    g_array_remove_range (self->chars, self->chars->len - n, n);
}

/* Take the text before the cursor as given. What was typed by taps and is
 * still there keeps its taps. */
static void
model_adopt (TactusTyper *self, const char *text, gboolean anchored)
{
  GArray *fresh = g_array_new (FALSE, TRUE, sizeof (TactusChar));
  guint old = self->chars->len, n;

  for (const char *p = text; p && *p; p = g_utf8_next_char (p)) {
    TactusChar ch = { .c = g_utf8_get_char (p) };

    g_array_append_val (fresh, ch);
  }
  n = fresh->len;

  for (guint i = 1; i <= MIN (old, n); i++) {
    TactusChar *was = char_at (self, old - i);
    TactusChar *is = &g_array_index (fresh, TactusChar, n - i);

    if (was->c != is->c)
      break;
    *is = *was;
  }

  g_array_unref (self->chars);
  self->chars = fresh;
  self->anchored = anchored;
}


static void
model_reset (TactusTyper *self, gboolean anchored)
{
  g_array_set_size (self->chars, 0);
  self->anchored = anchored;
  self->after_word = FALSE;
  self->selection = FALSE;
}

/* Two accounts of the text before the cursor agree. One that doesn't reach
 * back to the start may be the shorter of the two. */
static gboolean
same_text (const char *a, gboolean a_anchored, const char *b, gboolean b_anchored)
{
  size_t la = strlen (a), lb = strlen (b);

  if (la == lb)
    return memcmp (a, b, la) == 0;
  if (la < lb)
    return !a_anchored && memcmp (b + lb - la, a, la) == 0;
  return !b_anchored && memcmp (a + la - lb, b, lb) == 0;
}

/*
 * Capitals
 */

/* Whether a sentence starts after the first @pos characters */
static gboolean
sentence_start_at (TactusTyper *self, guint pos)
{
  guint i = pos, end;
  gunichar c;

  while (i > 0 && is_opener (char_at (self, i - 1)->c))
    i--;
  if (i == 0)
    return self->anchored;

  c = char_at (self, i - 1)->c;
  if (c == '\n')
    return TRUE;
  if (!is_space (c))
    return FALSE;
  while (i > 0 && is_space (char_at (self, i - 1)->c))
    i--;
  if (i == 0)
    return self->anchored;
  if (char_at (self, i - 1)->c == '\n')
    return TRUE;

  while (i > 0 && is_closer (char_at (self, i - 1)->c))
    i--;
  if (i == 0)
    return FALSE;

  c = char_at (self, i - 1)->c;
  if (c == '!' || c == '?')
    return TRUE;
  if (c != '.')
    return FALSE;
  /* Three dots trail off; they don't end a sentence */
  if (i >= 2 && char_at (self, i - 2)->c == '.')
    return FALSE;

  /* "e.g. this", "i.e. that", "one vs. the other" */
  end = i - 1;
  i = end;
  while (i > 0 && !is_space (char_at (self, i - 1)->c) && char_at (self, i - 1)->c != '\n')
    i--;
  if (end - i <= 3) {
    g_autofree char *token = model_dup (self, i, end);
    g_autofree char *lower = g_utf8_strdown (token, -1);

    if (g_str_equal (lower, "e.g") || g_str_equal (lower, "i.e") || g_str_equal (lower, "vs"))
      return FALSE;
  }
  return TRUE;
}

/**
 * tactus_typer_wants_capital:
 * @self: The typer
 *
 * Returns: Whether the next letter should be a capital
 */
gboolean
tactus_typer_wants_capital (TactusTyper *self)
{
  guint h = self->hints, len = self->chars->len;

  if (!self->active)
    return FALSE;
  if (h & (TACTUS_HINT_HIDDEN | TACTUS_HINT_LOWERCASE))
    return FALSE;
  if (h & TACTUS_HINT_UPPERCASE)
    return TRUE;
  if (h & TACTUS_HINT_TITLECASE) {
    gunichar last;

    if (len == 0)
      return self->anchored;
    last = char_at (self, len - 1)->c;
    if (is_space (last) || last == '\n')
      return TRUE;
  }
  /* A field that says what it wants, and didn't ask for capitals */
  if (h != 0 && !(h & (TACTUS_HINT_AUTO_CAPS | TACTUS_HINT_TITLECASE)))
    return FALSE;

  return sentence_start_at (self, len);
}


static void
update_shift (TactusTyper *self, gboolean context_changed)
{
  if (self->ops.shift)
    self->ops.shift (tactus_typer_wants_capital (self), context_changed, self->data);
}


static gboolean
corrects (TactusTyper *self)
{
  guint h = self->hints;

  /* Only where what is typed is hidden. That a field didn't ask for
   * corrections says nothing: a page in the browser asks for them only when
   * its author wrote so, and nearly none do, though all expect them. */
  if (h & TACTUS_HINT_HIDDEN)
    return FALSE;
  if (self->foreign)
    return FALSE;
  return tactus_ac_available ();
}

/* Nothing is learned from what goes into a field that asked for that */
static gboolean
learns (TactusTyper *self)
{
  return !(self->hints & (TACTUS_HINT_HIDDEN | TACTUS_HINT_SENSITIVE));
}

/*
 * What was sent and not yet shown
 */

static void
op_clear (gpointer data)
{
  TactusOp *op = data;

  g_clear_pointer (&op->predicted, g_free);
}


static void
arm_wake (TactusTyper *self)
{
  gint64 now = now_us (self), first = G_MAXINT64;

  for (guint i = 0; i < self->pending->len; i++) {
    TactusOp *op = &g_array_index (self->pending, TactusOp, i);
    gint64 due = op->time + (op->kind == TACTUS_OP_OTHER ? OTHER_WAIT_US : INSERT_WAIT_US);

    first = MIN (first, due);
  }
  if (self->held->len > 0)
    first = MIN (first, self->held_since + HOLD_US);
  if (first == G_MAXINT64 || self->ops.wake == NULL)
    return;
  self->ops.wake ((guint) (MAX (first - now, 0) / 1000) + 5, self->data);
}

/* Note that something went to the text field. @known: the copy shows what
 * the field holds once it has done it. */
static void
sent (TactusTyper *self, TactusOpKind kind, gboolean known)
{
  gint64 now = now_us (self);

  self->last_send = now;
  self->echo_seen = FALSE;

  if (self->reporting) {
    TactusOp op = { .kind = kind, .time = now, .anchored = self->anchored };

    if (known)
      op.predicted = model_dup (self, 0, self->chars->len);
    g_array_append_val (self->pending, op);
    arm_wake (self);
  }
}


static void
disarm_undo (TactusTyper *self)
{
  self->undo_armed = FALSE;
  g_clear_pointer (&self->undo_typed, g_free);
  g_clear_pointer (&self->undo_made, g_free);
}

/*
 * Sending
 */

/* The copy is brought up to date before anything goes out, so that an answer
 * from the text field always finds it as it will be */
static void
insert (TactusTyper *self, const char *text, const TactusTap *tap)
{
  self->selection = FALSE;
  model_append (self, text, tap, now_us (self));
  sent (self, TACTUS_OP_INSERT, TRUE);
  self->ops.commit (text, self->data);
}

/* Take the last @n characters away and put @text there */
static void
replace (TactusTyper *self, guint n, const char *text)
{
  gboolean by_keys = !self->reporting || self->no_delete;
  guint len = self->chars->len, bytes;

  self->selection = FALSE;
  n = MIN (n, len);
  if (n > 0) {
    if (!by_keys) {
      g_autofree char *whole = model_dup (self, 0, len);

      g_free (self->if_ignored);
      self->if_ignored = g_strconcat (whole, text, NULL);
    }
    bytes = model_bytes (self, len - n, len);
    model_pop (self, n);
    sent (self, TACTUS_OP_ERASE, TRUE);
    self->ops.erase (n, bytes, by_keys, self->data);
  }
  if (text && *text) {
    model_append (self, text, NULL, now_us (self));
    sent (self, TACTUS_OP_INSERT, TRUE);
    self->ops.commit (text, self->data);
  }
}

/*
 * Words
 */

/* Where the word the cursor is at the end of starts; the length of the text if there is none */
static guint
word_start (TactusTyper *self)
{
  guint s = self->chars->len;

  while (s > 0 && is_word_char (char_at (self, s - 1)->c))
    s--;
  return s;
}

/* Whether text can be taken away now. A text field that tells must have shown
 * all that was sent to it: the browser takes text away counting from the
 * cursor it last told of, not from where the cursor is, so a request that
 * comes before it has caught up takes nothing or the wrong letters. One that
 * has text taken away with Backspace only needs no key's outcome to be open. */
static gboolean
settled (TactusTyper *self)
{
  if (!self->reporting)
    return TRUE;

  if (!self->no_delete)
    return self->pending->len == 0;

  for (guint i = 0; i < self->pending->len; i++) {
    if (g_array_index (self->pending, TactusOp, i).kind == TACTUS_OP_OTHER)
      return FALSE;
  }
  return TRUE;
}

/* Why the word from @s to the cursor is left as it is, whatever the
 * dictionary says; NULL if it is known well enough to be replaced */
static const char *
word_stays_because (TactusTyper *self, guint s)
{
  guint len = self->chars->len;

  if (s >= len)
    return "no word";
  if (len - s > WORD_MAX)
    return "too long";
  if (self->after_word)
    return "a letter follows the cursor";
  /* The owner was typing it */
  if (char_at (self, len - 1)->time == 0)
    return "not typed just now";

  if (s == 0) {
    if (!self->anchored)
      return "what is before it is not known";
  } else {
    gunichar before = char_at (self, s - 1)->c;

    /* Part of something longer ("user@host", "example.com", "x-ray") is not a word to correct */
    if (!is_space (before) && before != '\n' && !is_opener (before))
      return "part of something longer";
  }

  if (!settled (self))
    return "the text field has not shown all that was sent";

  if (!self->reporting) {
    /* Typed in one go */
    for (guint i = s; i < len; i++) {
      if (char_at (self, i)->time == 0)
        return "not all of it typed just now";
      if (i > s && char_at (self, i)->time - char_at (self, i - 1)->time > PAUSE_US)
        return "typed with a long pause";
    }
  }
  return NULL;
}

/* The word that was meant by the one from @s to the cursor, or NULL to keep it */
static char *
meant (TactusTyper *self, guint s)
{
  guint len = self->chars->len, n = len - s;
  g_autofree char *word = model_dup (self, s, len);
  g_autofree TactusTap *taps = g_new0 (TactusTap, n);
  gboolean have_taps = TRUE;
  char *fixed;

  /* Put back once and typed again, or kept after it was put back: it is meant */
  if (self->rejected) {
    gboolean again = g_ascii_strcasecmp (self->rejected, word) == 0;

    g_clear_pointer (&self->rejected, g_free);
    if (again) {
      if (learns (self))
        tactus_ac_learn (word);
      note (self, "a word of %u letters kept: it was put back before", n);
      return NULL;
    }
  }

  if (!corrects (self)) {
    note (self, "a word of %u letters kept: the field asked for no corrections (hints 0x%x)", n, self->hints);
    return NULL;
  }

  for (guint i = 0; i < n; i++) {
    taps[i] = char_at (self, s + i)->tap;
    have_taps = have_taps && taps[i].valid;
  }

  fixed = tactus_ac_correct (word, have_taps ? taps : NULL, n, sentence_start_at (self, s));
  if (fixed && g_str_equal (fixed, word))
    g_clear_pointer (&fixed, g_free);
  if (have_taps && learns (self))
    tactus_ac_observe (word, fixed ?: word, taps, n);
  note (self, "a word of %u letters %s (%s)", n, fixed ? "corrected" : "kept by the dictionary",
        have_taps ? "taps" : "letters only");

  return fixed;
}

/* The word at the cursor is done and @tail follows it. Returns: whether
 * it took care of @tail as well. */
static gboolean
finish_word (TactusTyper *self, const char *tail)
{
  guint s = word_start (self);
  g_autofree char *fixed = NULL;
  g_autofree char *typed = NULL;
  g_autofree char *made = NULL;

  const char *why = word_stays_because (self, s);

  if (why) {
    if (s < self->chars->len)
      note (self, "a word of %u letters kept: %s", self->chars->len - s, why);
    return FALSE;
  }

  fixed = meant (self, s);
  if (fixed == NULL)
    return FALSE;

  typed = model_dup (self, s, self->chars->len);
  made = g_strconcat (fixed, tail, NULL);
  /* Letter counts only: what was typed never goes to a log */
  g_debug ("a word of %u letters corrected to one of %u",
           (guint) g_utf8_strlen (typed, -1), (guint) g_utf8_strlen (fixed, -1));
  replace (self, self->chars->len - s, made);

  disarm_undo (self);
  self->undo_armed = TRUE;
  self->undo_typed = g_steal_pointer (&typed);
  self->undo_made = g_steal_pointer (&made);
  return TRUE;
}

/*
 * Keys
 */

static void
type_letter (TactusTyper *self, const char *text, const TactusTap *tap)
{
  disarm_undo (self);
  insert (self, text, tap);
}


static void
type_space (TactusTyper *self)
{
  guint len = self->chars->len;
  gint64 now = now_us (self);

  /* Two spaces after a word: a full stop and a space */
  if (len >= 2 && char_at (self, len - 1)->c == ' ' && char_at (self, len - 1)->time != 0 &&
      now - char_at (self, len - 1)->time < DOUBLE_SPACE_US && !self->after_word && settled (self)) {
    gunichar before = char_at (self, len - 2)->c;

    if (!is_space (before) && before != '\n' && !(before < 0x80 && strchr (".,?!;:-/", (int) before))) {
      disarm_undo (self);
      replace (self, 1, ". ");
      /* a third space is a space */
      char_at (self, self->chars->len - 1)->time = 0;
      return;
    }
  }

  if (finish_word (self, " "))
    return;

  disarm_undo (self);
  insert (self, " ", NULL);
}


static void
type_other (TactusTyper *self, const char *text, gboolean ends)
{
  if (ends && finish_word (self, text))
    return;

  disarm_undo (self);
  insert (self, text, NULL);
}


static void
type_enter (TactusTyper *self)
{
  guint s = word_start (self), line = s;
  gboolean prose = FALSE;

  /* Only in running text: a lone word sent off with Return (a search, a name) stays as typed */
  while (line > 0 && char_at (self, line - 1)->c != '\n') {
    if (is_word_char (char_at (self, line - 1)->c))
      prose = TRUE;
    line--;
  }
  if (prose)
    finish_word (self, "");
  disarm_undo (self);

  if (self->reporting) {
    model_append (self, "\n", NULL, 0);
    sent (self, TACTUS_OP_OTHER, TRUE);
  } else {
    /* A new line or a message sent off: either way what comes next starts afresh */
    model_reset (self, TRUE);
    sent (self, TACTUS_OP_OTHER, FALSE);
  }
  self->ops.key ("KEY_ENTER", self->data);
}

/* A key that moves the cursor, or one we know nothing about */
static void
type_key (TactusTyper *self, const char *symbol)
{
  disarm_undo (self);
  /* Where the cursor is now, only the text field knows: one that tells will
   * tell, and until then nothing is corrected */
  if (!self->reporting)
    model_reset (self, FALSE);
  sent (self, TACTUS_OP_OTHER, FALSE);
  self->ops.key (symbol, self->data);
}

/* What a key does, once it is its turn */
static void
act_backspace (TactusTyper *self, TactusBackspace how)
{
  guint len;

  /* Right after a correction: the word as it was typed comes back */
  if (how == TACTUS_BACKSPACE_TAP && self->undo_armed) {
    g_autofree char *typed = g_steal_pointer (&self->undo_typed);
    g_autofree char *made = g_steal_pointer (&self->undo_made);
    guint n = g_utf8_strlen (made, -1);

    disarm_undo (self);
    if (n <= self->chars->len && settled (self)) {
      g_autofree char *tail = model_dup (self, self->chars->len - n, self->chars->len);

      if (g_str_equal (tail, made)) {
        g_debug ("a word of %u letters put back", (guint) g_utf8_strlen (typed, -1));
        replace (self, n, typed);
        g_free (self->rejected);
        self->rejected = g_strdup (typed);
        update_shift (self, FALSE);
        return;
      }
    }
  }
  disarm_undo (self);

  len = self->chars->len;
  if (how == TACTUS_BACKSPACE_WORD && len > 0 && !self->selection && settled (self)) {
    guint i = len;

    /* The spaces after the last word, then the word */
    while (i > 0 && is_space (char_at (self, i - 1)->c))
      i--;
    if (i > 0 && char_at (self, i - 1)->c == '\n') {
      if (i == len)
        i--;
    } else {
      while (i > 0 && !is_space (char_at (self, i - 1)->c) && char_at (self, i - 1)->c != '\n')
        i--;
    }
    if (len - i > 1) {
      replace (self, len - i, NULL);
      update_shift (self, FALSE);
      return;
    }
  }

  if (self->selection) {
    /* It deletes what is selected; what is before stays */
    self->selection = FALSE;
    sent (self, TACTUS_OP_OTHER, TRUE);
  } else if (len > 0) {
    model_pop (self, 1);
    sent (self, TACTUS_OP_OTHER, TRUE);
  } else if (self->reporting) {
    sent (self, TACTUS_OP_OTHER, self->anchored);
  } else {
    /* There was text before the cursor that we knew nothing of */
    self->anchored = FALSE;
    sent (self, TACTUS_OP_OTHER, FALSE);
  }
  self->ops.key ("KEY_BACKSPACE", self->data);
  update_shift (self, FALSE);
}


static void
act_key (TactusTyper *self, const char *symbol, const TactusTap *tap)
{
  gunichar c;

  if (g_str_has_prefix (symbol, "KEY_")) {
    if (g_str_equal (symbol, "KEY_ENTER"))
      type_enter (self);
    else
      type_key (self, symbol);
    update_shift (self, FALSE);
    return;
  }
  if (*symbol == '\0')
    return;

  c = g_utf8_get_char (symbol);
  if (g_utf8_strlen (symbol, -1) == 1 && is_word_char (c))
    type_letter (self, symbol, tap);
  else if (g_str_equal (symbol, " "))
    type_space (self);
  else
    type_other (self, symbol, ends_word (symbol));

  update_shift (self, FALSE);
}


static void
act (TactusTyper *self, const TactusInput *in)
{
  switch (in->kind) {
  case TACTUS_IN_BACKSPACE:
    act_backspace (self, in->how);
    break;
  case TACTUS_IN_TEXT:
    type_other (self, in->text, in->ends_word);
    update_shift (self, FALSE);
    break;
  case TACTUS_IN_KEY:
  default:
    act_key (self, in->text, in->has_tap ? &in->tap : NULL);
    break;
  }
}

/* Whether @in may take text away */
static gboolean
may_replace (TactusTyper *self, const TactusInput *in)
{
  guint len = self->chars->len;
  gboolean word = word_start (self) < len;

  switch (in->kind) {
  case TACTUS_IN_BACKSPACE:
    if (in->how == TACTUS_BACKSPACE_TAP)
      return self->undo_armed;
    return in->how == TACTUS_BACKSPACE_WORD && len > 0 && !self->selection;
  case TACTUS_IN_TEXT:
    return in->ends_word && word;
  case TACTUS_IN_KEY:
  default:
    if (g_str_equal (in->text, "KEY_ENTER"))
      return word;
    if (g_str_has_prefix (in->text, "KEY_"))
      return FALSE;
    /* a word to correct, or the second of two spaces */
    if (g_str_equal (in->text, " "))
      return word || (len >= 2 && char_at (self, len - 1)->c == ' ' && char_at (self, len - 1)->time != 0);
    return ends_word (in->text) && word;
  }
}

/* Whether @in has to wait: it may take text away, and the text field has yet
 * to show what was sent before it */
static gboolean
must_wait (TactusTyper *self, const TactusInput *in)
{
  if (!self->reporting || self->no_delete || self->pending->len == 0)
    return FALSE;
  if (now_us (self) < self->no_hold_until)
    return FALSE;

  /* Not for a key whose outcome is the field's to tell: nothing is taken
   * away after one until the field has told, or the wait for it has run out */
  for (guint i = 0; i < self->pending->len; i++) {
    if (g_array_index (self->pending, TactusOp, i).kind == TACTUS_OP_OTHER)
      return FALSE;
  }
  return may_replace (self, in);
}


static void
input_clear (gpointer data)
{
  TactusInput *in = data;

  g_clear_pointer (&in->text, g_free);
}

/* A key comes in: its turn is now, or after those that wait */
static void
take (TactusTyper *self, const TactusInput *in)
{
  TactusInput keep;

  if (self->held->len == 0 && !must_wait (self, in)) {
    act (self, in);
    return;
  }

  if (self->held->len == 0) {
    self->held_since = now_us (self);
    note (self, "a key waits for the text field to show what was sent");
  }
  keep = *in;
  keep.text = g_strdup (in->text);
  g_array_append_val (self->held, keep);
  arm_wake (self);
}

/* The keys that waited, in their order */
static void
drain (TactusTyper *self)
{
  if (self->draining)
    return;

  self->draining = TRUE;
  while (self->held->len > 0) {
    TactusInput in = g_array_index (self->held, TactusInput, 0);
    gint64 now = now_us (self);

    if (must_wait (self, &in)) {
      if (now - self->held_since < HOLD_US)
        break;
      /* Too slow to wait for. On with it: nothing is taken away while the
       * field is behind, so the word stays as it was typed. */
      note (self, "the text field did not catch up in time: keys don't wait for it for a while");
      self->no_hold_until = now + HOLD_OFF_US;
    }

    /* Out of the line before its turn: what it sends may bring us back here */
    g_array_index (self->held, TactusInput, 0).text = NULL;
    g_array_remove_index (self->held, 0);
    act (self, &in);
    g_free (in.text);
    self->held_since = now;
  }
  self->draining = FALSE;
  if (self->held->len > 0)
    arm_wake (self);
}

/**
 * tactus_typer_key:
 * @self: The typer
 * @symbol: What the key types, or its name ("KEY_ENTER")
 * @tap:(nullable): Where in the key the finger was
 *
 * A key of the keyboard was typed.
 */
void
tactus_typer_key (TactusTyper *self, const char *symbol, const TactusTap *tap)
{
  TactusInput in = { .kind = TACTUS_IN_KEY };

  g_return_if_fail (self != NULL && symbol != NULL);

  if (g_str_equal (symbol, "KEY_BACKSPACE")) {
    tactus_typer_backspace (self, TACTUS_BACKSPACE_TAP);
    return;
  }

  in.text = (char *) symbol;
  if (tap) {
    in.tap = *tap;
    in.has_tap = TRUE;
  }
  tactus_typer_poll (self);
  take (self, &in);
}

/**
 * tactus_typer_text:
 * @self: The typer
 * @text: Text from elsewhere than a key: an emoji, the clipboard
 * @ends_word: Whether it ends the word before it the way a full stop does
 */
void
tactus_typer_text (TactusTyper *self, const char *text, gboolean ends_word)
{
  TactusInput in = { .kind = TACTUS_IN_TEXT, .ends_word = ends_word };

  g_return_if_fail (self != NULL);

  if (text == NULL || *text == '\0')
    return;

  in.text = (char *) text;
  tactus_typer_poll (self);
  take (self, &in);
}

/**
 * tactus_typer_backspace:
 * @self: The typer
 * @how: A tap, or the key being held
 */
void
tactus_typer_backspace (TactusTyper *self, TactusBackspace how)
{
  TactusInput in = { .kind = TACTUS_IN_BACKSPACE, .how = how };

  g_return_if_fail (self != NULL);

  tactus_typer_poll (self);
  take (self, &in);
}

/*
 * The text field
 */

static void
clear_pending (TactusTyper *self)
{
  g_array_set_size (self->pending, 0);
}

/* Answer the text field. The browser tells nothing more until what it last
 * told has been answered, and the compositor answers a text field only when
 * the keyboard sends something: left unanswered, the browser is one key
 * behind, and takes text away counting from where its cursor was then. An
 * answer with nothing in it changes nothing in a text field. */
static void
answer (TactusTyper *self)
{
  gint64 now = now_us (self);

  if (self->ops.ack == NULL || self->ack_muted)
    return;

  if (now - self->ack_second >= G_TIME_SPAN_SECOND) {
    self->ack_full_seconds = self->acks >= ACKS_A_SECOND ? self->ack_full_seconds + 1 : 0;
    self->ack_second = now;
    self->acks = 0;
  }
  if (self->acks >= ACKS_A_SECOND) {
    /* One that answers every answer: the two would go on for ever */
    if (self->ack_full_seconds >= ACK_SECONDS && !self->ack_muted) {
      self->ack_muted = TRUE;
      note (self, "the text field answers every answer: it gets no more");
    }
    return;
  }
  self->acks++;
  self->ops.ack (self->data);
}

/**
 * tactus_typer_poll:
 * @self: The typer
 *
 * Give up waiting for a text field to show what it was sent a while ago.
 */
void
tactus_typer_poll (TactusTyper *self)
{
  gint64 now;

  g_return_if_fail (self != NULL);

  now = now_us (self);
  for (guint i = 0; i < self->pending->len; i++) {
    TactusOp *op = &g_array_index (self->pending, TactusOp, i);

    if (op->kind != TACTUS_OP_OTHER) {
      /* Text that never showed keeps its place in the copy, and counts as
       * shown: what the field tells next is held against it */
      if (now - op->time >= INSERT_WAIT_US) {
        if (op->predicted) {
          g_free (self->acked);
          self->acked = g_steal_pointer (&op->predicted);
          self->acked_anchored = op->anchored;
        }
        g_array_remove_index (self->pending, i);
        i--;
      }
      continue;
    }
    if (now - op->time < OTHER_WAIT_US)
      continue;

    /* A key the field did not answer as foreseen (Backspace with nothing to
     * delete, an arrow at the end): what it last told stands */
    g_debug ("no answer to a key: back to what the field told");
    clear_pending (self);
    if (self->acked)
      model_adopt (self, self->acked, self->acked_anchored);
    disarm_undo (self);
    update_shift (self, TRUE);
    break;
  }
  drain (self);
  arm_wake (self);
}

/* The text before the cursor out of what a text field told. Returns: whether it made sense. */
static gboolean
read_report (const char *text, guint cursor, guint anchor,
             char **before, gboolean *anchored, gboolean *after_word, gboolean *selection)
{
  size_t len = strlen (text);
  size_t lo = MIN (MIN (cursor, anchor), len), hi = MIN (MAX (cursor, anchor), len);
  GString *out;
  glong n_chars;
  const char *p, *end;

  if (!g_utf8_validate (text, -1, NULL))
    return FALSE;

  while (lo > 0 && lo < len && (text[lo] & 0xc0) == 0x80)
    lo--;
  while (hi < len && (text[hi] & 0xc0) == 0x80)
    hi++;

  p = text;
  end = text + lo;
  n_chars = g_utf8_pointer_to_offset (p, end);
  *anchored = TRUE;
  if (n_chars > MODEL_MAX) {
    p = g_utf8_offset_to_pointer (p, n_chars - MODEL_MAX);
    *anchored = FALSE;
  }

  out = g_string_new (NULL);
  for (; p < end; p = g_utf8_next_char (p)) {
    gunichar c = g_utf8_get_char (p);

    g_string_append_unichar (out, c == 0xa0 ? ' ' : c);
  }
  *before = g_string_free (out, FALSE);
  *after_word = hi < len && is_word_char (g_utf8_get_char (text + hi));
  *selection = lo != hi;
  return TRUE;
}

/* A sign of life from a text field that tells nothing */
static void
silent_state (TactusTyper *self)
{
  gint64 now = now_us (self);
  gboolean echo = FALSE;

  if (self->reporting) {
    self->reporting = FALSE;
    g_clear_pointer (&self->acked, g_free);
    clear_pending (self);
  }

  /* The keyboard changed its height: the field moves, and says so */
  if (now < self->settle_until)
    return;

  /* The first sign of life after a key is that key's echo, and what follows
   * it closely (the text field settling) still is. Anything later is not:
   * a tap on the application's own Send button comes a moment after the
   * last key, and must not pass for its echo. */
  if (self->last_send) {
    if (!self->echo_seen)
      echo = now - self->last_send < ECHO_US;
    else
      echo = now - self->echo_time < ECHO_TAIL_US;
  }
  if (echo) {
    self->echo_seen = TRUE;
    self->echo_time = now;
    return;
  }

  /* No key of ours explains it: the cursor went elsewhere, or the text was sent off */
  g_debug ("the text field changed by itself: starting afresh");
  note (self, "the text field changed by itself (%u letters known before): starting afresh", self->chars->len);
  self->last_send = 0;
  model_reset (self, TRUE);
  disarm_undo (self);
  update_shift (self, TRUE);
}

/* A text field told its text */
static void
told (TactusTyper *self, char **told_before, gboolean anchored, gboolean after_word, gboolean selection)
{
  g_autofree char *before = g_steal_pointer (told_before);
  gboolean first = !self->reporting;

  self->reporting = TRUE;
  self->after_word = after_word;
  self->selection = selection;

  if (first) {
    g_autofree char *typed = NULL;

    note (self, "the text field tells its text");
    /* Keys went out before it first spoke, and it may be telling how things
     * were before them: one that speaks only when spoken to is a step behind */
    if (self->last_send && now_us (self) - self->last_send < INSERT_WAIT_US &&
        self->chars->len > 0 && self->chars->len <= FIRST_MAX)
      typed = model_dup (self, 0, self->chars->len);

    clear_pending (self);
    g_clear_pointer (&self->if_ignored, g_free);
    g_free (self->acked);
    self->acked = g_strdup (before);
    self->acked_anchored = anchored;

    if (typed && !g_str_has_suffix (before, typed)) {
      TactusOp op = { .kind = TACTUS_OP_INSERT, .time = self->last_send, .anchored = anchored };
      char *whole = g_strconcat (before, typed, NULL);

      note (self, "it tells of the time before the %u letters just sent: they stay", self->chars->len);
      model_adopt (self, whole, anchored);
      op.predicted = whole;
      g_array_append_val (self->pending, op);
      arm_wake (self);
    } else {
      model_adopt (self, before, anchored);
    }
    disarm_undo (self);
    update_shift (self, TRUE);
    return;
  }

  if (self->acked) {
    /* Is it what we foresaw for something we sent? The latest first. */
    for (guint k = self->pending->len; k >= 1; k--) {
      TactusOp *op = &g_array_index (self->pending, TactusOp, k - 1);

      if (op->predicted == NULL || !same_text (before, anchored, op->predicted, op->anchored))
        continue;

      g_array_remove_range (self->pending, 0, k);
      g_free (self->acked);
      self->acked = g_steal_pointer (&before);
      self->acked_anchored = anchored;
      g_clear_pointer (&self->if_ignored, g_free);
      if (self->pending->len == 0)
        model_adopt (self, self->acked, self->acked_anchored);
      return;
    }
    /* Nothing new */
    if (same_text (before, anchored, self->acked, self->acked_anchored))
      return;
  }

  /* The text field has it otherwise: it is right */
  if (self->acked && self->pending->len > 0)
    note (self, "the text field has it otherwise than foreseen (%u sent and unanswered)", self->pending->len);
  if (self->if_ignored && same_text (before, anchored, self->if_ignored, FALSE)) {
    g_warning ("This text field ignores requests to delete: using Backspace from now on");
    self->no_delete = TRUE;
  }
  g_clear_pointer (&self->if_ignored, g_free);

  g_free (self->acked);
  self->acked = g_steal_pointer (&before);
  self->acked_anchored = anchored;
  clear_pending (self);
  model_adopt (self, self->acked, self->acked_anchored);
  disarm_undo (self);
  update_shift (self, TRUE);
}

/**
 * tactus_typer_state:
 * @self: The typer
 * @text:(nullable): The text around the cursor as the text field tells it, or %NULL if it tells nothing
 * @cursor: Where in @text the cursor is, in bytes
 * @anchor: Where in @text the other end of the selection is
 *
 * The text field gave a sign of life (the input method's `done`).
 */
void
tactus_typer_state (TactusTyper *self, const char *text, guint cursor, guint anchor)
{
  g_autofree char *before = NULL;
  gboolean anchored, after_word, selection;

  g_return_if_fail (self != NULL);

  if (!self->active)
    return;

  if (text == NULL || !read_report (text, cursor, anchor, &before, &anchored, &after_word, &selection)) {
    silent_state (self);
    /* One that keeps its text back until it is answered tells it now */
    if (!self->greeted) {
      self->greeted = TRUE;
      answer (self);
    }
    return;
  }

  told (self, &before, anchored, after_word, selection);
  self->greeted = TRUE;
  answer (self);
  drain (self);
}

/**
 * tactus_typer_settle:
 * @self: The typer
 * @ms: How long things take to settle
 *
 * The keyboard is about to change its height. A text field that tells
 * nothing gives signs of life as it moves; for this long they mean nothing.
 */
void
tactus_typer_settle (TactusTyper *self, guint ms)
{
  g_return_if_fail (self != NULL);

  self->settle_until = now_us (self) + ms * G_TIME_SPAN_MILLISECOND;
}

/**
 * tactus_typer_set_language:
 * @self: The typer
 * @lang:(nullable): The language of the layout the keys are typed on ("en", "de")
 *
 * The dictionary is English. With another language's layout words are left as
 * they are typed; capitals at the start of a sentence stay.
 */
void
tactus_typer_set_language (TactusTyper *self, const char *lang)
{
  g_return_if_fail (self != NULL);

  self->foreign = lang != NULL && !g_str_has_prefix (lang, "en");
}

/**
 * tactus_typer_set_hints:
 * @self: The typer
 * @hints: What the text field says it is for (text-input's content hint)
 */
void
tactus_typer_set_hints (TactusTyper *self, guint hints)
{
  g_return_if_fail (self != NULL);

  if (self->hints == hints)
    return;
  note (self, "the text field's hints: 0x%x", hints);
  self->hints = hints;
  update_shift (self, TRUE);
}

/**
 * tactus_typer_focus:
 * @self: The typer
 * @active: Whether there is a text field to type into
 *
 * A text field came or went. A new one is taken to be empty until it tells
 * otherwise.
 */
void
tactus_typer_focus (TactusTyper *self, gboolean active)
{
  g_return_if_fail (self != NULL);

  note (self, active ? "a text field" : "no text field");
  self->active = active;
  self->reporting = FALSE;
  self->no_delete = FALSE;
  self->hints = 0;
  self->last_send = 0;
  self->echo_seen = FALSE;
  self->settle_until = 0;
  g_clear_pointer (&self->acked, g_free);
  g_clear_pointer (&self->if_ignored, g_free);
  g_clear_pointer (&self->rejected, g_free);
  clear_pending (self);
  /* keys that waited for a text field that is gone go nowhere */
  g_array_set_size (self->held, 0);
  self->held_since = 0;
  self->no_hold_until = 0;
  self->greeted = FALSE;
  self->ack_second = 0;
  self->acks = 0;
  self->ack_full_seconds = 0;
  self->ack_muted = FALSE;
  disarm_undo (self);
  model_reset (self, TRUE);

  if (!active)
    tactus_ac_save ();
  update_shift (self, TRUE);
}

/**
 * tactus_typer_dup_before:
 * @self: The typer
 *
 * Returns:(transfer full): The text before the cursor as the typer has it
 */
char *
tactus_typer_dup_before (TactusTyper *self)
{
  g_return_val_if_fail (self != NULL, NULL);

  return model_dup (self, 0, self->chars->len);
}


void
tactus_typer_set_clock (TactusTyper *self, gint64 (*now) (gpointer data), gpointer data)
{
  g_return_if_fail (self != NULL);

  self->now = now;
  self->now_data = data;
}


TactusTyper *
tactus_typer_new (const TactusTyperOps *ops, gpointer data)
{
  TactusTyper *self = g_new0 (TactusTyper, 1);

  g_return_val_if_fail (ops && ops->commit && ops->erase && ops->key, NULL);

  self->ops = *ops;
  self->data = data;
  self->trace = g_getenv ("TACTUS_TRACE") != NULL;
  self->chars = g_array_new (FALSE, TRUE, sizeof (TactusChar));
  self->pending = g_array_new (FALSE, TRUE, sizeof (TactusOp));
  g_array_set_clear_func (self->pending, op_clear);
  self->held = g_array_new (FALSE, TRUE, sizeof (TactusInput));
  g_array_set_clear_func (self->held, input_clear);
  self->anchored = TRUE;
  return self;
}


void
tactus_typer_free (TactusTyper *self)
{
  if (self == NULL)
    return;

  tactus_ac_save ();
  disarm_undo (self);
  g_free (self->acked);
  g_free (self->if_ignored);
  g_free (self->rejected);
  g_array_unref (self->pending);
  g_array_unref (self->held);
  g_array_unref (self->chars);
  g_free (self);
}
