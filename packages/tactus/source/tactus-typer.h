/*
 * Tactus's typing: what goes to the text field for each key.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include "tactus-autocorrect.h"

#include <glib.h>

G_BEGIN_DECLS

typedef struct _TactusTyper TactusTyper;

/* What the text field said it is for (the bits of text-input's content hint) */
#define TACTUS_HINT_COMPLETION 0x1
#define TACTUS_HINT_SPELLCHECK 0x2
#define TACTUS_HINT_AUTO_CAPS  0x4
#define TACTUS_HINT_LOWERCASE  0x8
#define TACTUS_HINT_UPPERCASE  0x10
#define TACTUS_HINT_TITLECASE  0x20
#define TACTUS_HINT_HIDDEN     0x40
#define TACTUS_HINT_SENSITIVE  0x80

typedef enum {
  TACTUS_BACKSPACE_TAP,     /* the key went down */
  TACTUS_BACKSPACE_REPEAT,  /* it is held: one more character */
  TACTUS_BACKSPACE_WORD,    /* it has been held for a while: one more word */
} TactusBackspace;

typedef struct {
  /* Put this text where the cursor is */
  void (*commit) (const char *text, gpointer data);
  /* Take away what is before the cursor: with the text field's own means (so
   * many bytes), or, where it has none, as so many presses of Backspace */
  void (*erase)  (guint n_chars, guint n_bytes, gboolean by_keys, gpointer data);
  /* Press a key: "KEY_BACKSPACE", "KEY_ENTER", "KEY_LEFT" … */
  void (*key)    (const char *symbol, gpointer data);
  /* Whether the next letter should be a capital; @context_changed when the
   * text or the cursor changed by other means than a key of ours */
  void (*shift)  (gboolean wanted, gboolean context_changed, gpointer data);
  /* Call tactus_typer_poll() in so many milliseconds */
  void (*wake)   (guint ms, gpointer data);
  /* Answer the text field with nothing (the input method's empty commit): a
   * field that waits for an answer before it tells more can go on. May be NULL. */
  void (*ack)    (gpointer data);
} TactusTyperOps;

TactusTyper *tactus_typer_new           (const TactusTyperOps *ops, gpointer data);
void         tactus_typer_free          (TactusTyper *self);
void         tactus_typer_set_clock     (TactusTyper *self, gint64 (*now) (gpointer data), gpointer data);

void         tactus_typer_focus         (TactusTyper *self, gboolean active);
void         tactus_typer_set_hints     (TactusTyper *self, guint hints);
void         tactus_typer_set_language  (TactusTyper *self, const char *lang);
void         tactus_typer_state         (TactusTyper *self, const char *text, guint cursor, guint anchor);

void         tactus_typer_key           (TactusTyper *self, const char *symbol, const TactusTap *tap);
void         tactus_typer_backspace     (TactusTyper *self, TactusBackspace how);
void         tactus_typer_text          (TactusTyper *self, const char *text, gboolean ends_word);
void         tactus_typer_poll          (TactusTyper *self);
void         tactus_typer_settle        (TactusTyper *self, guint ms);

gboolean     tactus_typer_wants_capital (TactusTyper *self);
/* For tests and logs: the text before the cursor as the typer has it */
char        *tactus_typer_dup_before    (TactusTyper *self);

G_END_DECLS
