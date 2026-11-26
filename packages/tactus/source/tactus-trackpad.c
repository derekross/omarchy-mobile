/*
 * Tactus's trackpad: the space bar held, the finger moves the cursor.
 *
 * Once the hold has begun the whole keyboard is the pad, and the finger may
 * go anywhere over it. The cursor follows the finger's motion, not where it
 * is: slow motion moves it a letter at a time, fast motion further for the
 * same distance, so a long text can be crossed in one sweep. A finger that
 * rests at the keyboard's left or right side keeps the cursor going that way,
 * a step at a time, until it moves back: the side of the keyboard is no end
 * to how far the cursor can go. Up and down move it a line.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-trackpad.h"

#include <math.h>

/* A letter's step and a line's, at slow speed, in points */
#define STEP_X      9.0
#define STEP_Y      24.0
/* Faster than this (points a second) the same motion goes further: twice as
 * far at SLOW + RAMP, at most GAIN times; a line at most GAIN_Y times */
#define SLOW        120.0
#define RAMP        120.0
#define GAIN        5.0
#define GAIN_Y      2.0
/* The sides where a resting finger keeps the cursor going, in points from
 * the keyboard's edge, and how far back it must come to stop it */
#define EDGE        22.0
#define EDGE_LEAVE  30.0
/* How long a finger rests at a side before the cursor goes on by itself */
#define EDGE_DELAY_MS 150
/* No more steps than this at once, after a late tick */
#define EDGE_BURST  4


/**
 * tactus_trackpad_begin:
 * @tp: The trackpad
 * @x: @y: Where the finger is
 * @now: The time, in microseconds
 * @left: @right: Where the keyboard's sides are
 * @scale: Pixels to a point
 *
 * The space bar has been held long enough: from here on the finger's motion
 * moves the cursor.
 */
void
tactus_trackpad_begin (TactusTrackpad *tp, double x, double y, gint64 now, double left, double right,
                       double scale)
{
  *tp = (TactusTrackpad) {
    .x = x, .y = y, .time = now,
    .left = left, .right = right,
    .scale = scale > 0.0 ? scale : 1.0,
  };
  /* A hold that begins at a side doesn't set the cursor going: the finger has
   * to come away from it first */
  tp->edge_armed = x - left > EDGE * tp->scale && right - x > EDGE * tp->scale;
}

/* Which side the finger rests at, given which it rested at before */
static int
edge_at (TactusTrackpad *tp, double x)
{
  double reach = (tp->edge != 0 ? EDGE_LEAVE : EDGE) * tp->scale;

  if (x - tp->left <= reach && tp->edge != 1)
    return -1;
  if (tp->right - x <= reach && tp->edge != -1)
    return 1;
  return 0;
}

/**
 * tactus_trackpad_move:
 * @tp: The trackpad
 * @x: @y: Where the finger is now
 * @now: The time, in microseconds
 * @across:(out): How many letters to move the cursor: to the right if more than 0
 * @down:(out): How many lines: down if more than 0
 */
void
tactus_trackpad_move (TactusTrackpad *tp, double x, double y, gint64 now, int *across, int *down)
{
  double dx = (x - tp->x) / tp->scale, dy = (y - tp->y) / tp->scale;
  double dt = MAX (now - tp->time, 4000) / 1e6;
  double speed = sqrt (dx * dx + dy * dy) / dt;
  double gain = CLAMP (1.0 + (speed - SLOW) / RAMP, 1.0, GAIN);
  int edge;

  tp->acc_x += dx * gain / STEP_X;
  tp->acc_y += dy * MIN (gain, GAIN_Y) / STEP_Y;
  *across = (int) trunc (tp->acc_x);
  *down = (int) trunc (tp->acc_y);
  tp->acc_x -= *across;
  tp->acc_y -= *down;
  tp->x = x;
  tp->y = y;
  tp->time = now;

  edge = edge_at (tp, x);
  if (edge == 0)
    tp->edge_armed = TRUE;
  if (!tp->edge_armed)
    edge = 0;
  if (edge != tp->edge) {
    tp->edge = edge;
    tp->edge_next = now + EDGE_DELAY_MS * 1000;
  }
}

/**
 * tactus_trackpad_edge_steps:
 * @tp: The trackpad
 * @now: The time, in microseconds
 *
 * Call it every %TACTUS_TRACKPAD_EDGE_EVERY_MS while the finger rests at a side.
 *
 * Returns: How many letters to move the cursor for a finger resting at a
 *   side: to the right if more than 0; 0 where it rests at none
 */
int
tactus_trackpad_edge_steps (TactusTrackpad *tp, gint64 now)
{
  int n = 0;

  if (tp->edge == 0)
    return 0;
  while (now >= tp->edge_next && n < EDGE_BURST) {
    n++;
    tp->edge_next += TACTUS_TRACKPAD_EDGE_EVERY_MS * 1000;
  }
  /* A tick that came late doesn't owe what it missed */
  if (now >= tp->edge_next)
    tp->edge_next = now + TACTUS_TRACKPAD_EDGE_EVERY_MS * 1000;
  return n * tp->edge;
}
