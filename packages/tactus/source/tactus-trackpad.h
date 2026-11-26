/*
 * Tactus's trackpad: the space bar held, the finger moves the cursor.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <glib.h>

G_BEGIN_DECLS

/* How often a finger resting at an edge moves the cursor one more step */
#define TACTUS_TRACKPAD_EDGE_EVERY_MS 50

typedef struct {
  double   x, y;         /* where the finger was last */
  gint64   time;         /* when, in microseconds */
  double   left, right;  /* the keyboard's sides */
  double   scale;        /* pixels to a point */
  double   acc_x, acc_y; /* motion that isn't a whole step yet, in steps */
  int      edge;         /* -1 resting at the left edge, 1 at the right, 0 neither */
  gboolean edge_armed;   /* the finger has been away from the edges since the hold began */
  gint64   edge_next;    /* when the next step of a resting finger is due */
} TactusTrackpad;

void tactus_trackpad_begin      (TactusTrackpad *tp,
                                 double          x,
                                 double          y,
                                 gint64          now,
                                 double          left,
                                 double          right,
                                 double          scale);
void tactus_trackpad_move       (TactusTrackpad *tp,
                                 double          x,
                                 double          y,
                                 gint64          now,
                                 int            *across,
                                 int            *down);
int  tactus_trackpad_edge_steps (TactusTrackpad *tp,
                                 gint64          now);

G_END_DECLS
