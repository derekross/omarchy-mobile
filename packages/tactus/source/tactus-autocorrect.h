/*
 * Tactus's autocorrection: which word the owner meant.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <glib.h>

G_BEGIN_DECLS

/* Where a finger landed, from the centre of the key it was read as: across in
 * key widths, down in row heights */
typedef struct {
  double   dx, dy;
  gboolean valid;
} TactusTap;

gboolean tactus_ac_available (void);
char    *tactus_ac_correct   (const char      *word,
                              const TactusTap *taps,
                              guint            n_taps,
                              gboolean         sentence_start);
char    *tactus_ac_correct_in (const char      *word,
                               const TactusTap *taps,
                               guint            n_taps,
                               gboolean         sentence_start,
                               const char      *before);
char    *tactus_ac_reconsider (const char      *word,
                               const TactusTap *taps,
                               guint            n_taps,
                               gboolean         sentence_start,
                               const char      *before,
                               const char      *after);
void     tactus_ac_set_typing (const char *before,
                               const char *prefix,
                               gboolean    sentence_start);
double   tactus_ac_tap_cost   (const char *symbol,
                               double      dx,
                               double      dy);
double   tactus_ac_tap_prior  (const char *symbol);
void     tactus_ac_learn     (const char *word);
void     tactus_ac_observe   (const char      *typed,
                              const char      *meant,
                              const TactusTap *taps,
                              guint            n_taps);
gboolean tactus_ac_get_bias  (double *dx, double *dy);
void     tactus_ac_save      (void);

G_END_DECLS
