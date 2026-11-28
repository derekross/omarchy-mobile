/*
 * Tactus's trackpad, tried with make-believe fingers: how far the cursor
 * goes for slow and fast motion, and for a finger resting at a side.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "tactus-trackpad.h"

#include <glib.h>

#include <stdio.h>

#define LEFT  0.0
#define RIGHT 390.0

static int failed, checked;

static void
check (gboolean ok, const char *what, int got)
{
  checked++;
  if (!ok)
    failed++;
  printf ("%s %-58s %d\n", ok ? "  ok" : "FAIL", what, got);
}

/* Slide from @x0 to @x1 (points, scale @scale) at @speed points a second,
 * an event every 16 ms; the time goes on in @now. Returns the letters moved. */
static int
slide (TactusTrackpad *tp, double x0, double x1, double y, double speed, double scale, gint64 *now, int *lines)
{
  double dir = x1 > x0 ? 1.0 : -1.0, x = x0;
  int across = 0, down = 0, sum = 0, sum_down = 0;

  while (dir * (x1 - x) > 1e-9) {
    x += dir * MIN (speed * 0.016, dir * (x1 - x));
    *now += 16000;
    tactus_trackpad_move (tp, x * scale, y * scale, *now, &across, &down);
    sum += across;
    sum_down += down;
  }
  if (lines)
    *lines = sum_down;
  return sum;
}

/* Rest at where the finger is for @ms, the edge ticks coming on time */
static int
rest (TactusTrackpad *tp, guint ms, gint64 *now)
{
  int sum = 0;

  for (guint t = 0; t < ms; t += TACTUS_TRACKPAD_EDGE_EVERY_MS) {
    *now += TACTUS_TRACKPAD_EDGE_EVERY_MS * 1000;
    sum += tactus_trackpad_edge_steps (tp, *now);
  }
  return sum;
}


int
main (void)
{
  TactusTrackpad tp;
  gint64 now = 1000000;
  int n, back, fast;

  printf ("== motion\n");
  tactus_trackpad_begin (&tp, 150, 100, now, LEFT, RIGHT, 1.0);
  n = slide (&tp, 150, 240, 100, 60, 1.0, &now, NULL);
  check (n == 10, "90 points slowly: a letter for every 9", n);
  back = slide (&tp, 240, 150, 100, 60, 1.0, &now, NULL);
  check (back == -10, "and back: as many to the left", back);

  tactus_trackpad_begin (&tp, 150, 100, now, LEFT, RIGHT, 1.0);
  fast = slide (&tp, 150, 240, 100, 700, 1.0, &now, NULL);
  check (fast >= 4 * 10, "the same 90 points fast: four times as far or more", fast);
  check (fast <= 5 * 10 + 1, "and no more than five times", fast);

  tactus_trackpad_begin (&tp, 300, 200, now, 2 * LEFT, 2 * RIGHT, 2.0);
  n = slide (&tp, 150, 240, 100, 60, 2.0, &now, NULL);
  check (n == 10, "on a screen of twice the pixels, the same in points", n);

  tactus_trackpad_begin (&tp, 150, 50, now, LEFT, RIGHT, 1.0);
  {
    int across = 0, down = 0, sum = 0;
    double y = 50;

    while (y < 99) {
      y += 1;
      now += 16000;
      tactus_trackpad_move (&tp, 150, y, now, &across, &down);
      sum += down;
    }
    check (sum == 2, "49 points down slowly: two lines", sum);
  }

  printf ("== a finger resting at a side\n");
  tactus_trackpad_begin (&tp, 200, 100, now, LEFT, RIGHT, 1.0);
  slide (&tp, 200, 380, 100, 300, 1.0, &now, NULL);
  n = rest (&tp, 100, &now);
  check (n == 0, "at the right side, nothing before 150 ms", n);
  n = rest (&tp, 1000, &now);
  check (n >= 18 && n <= 21, "then a letter to the right every 50 ms", n);
  slide (&tp, 380, 372, 100, 40, 1.0, &now, NULL);
  n = rest (&tp, 500, &now);
  check (n > 0, "still at the side after a small move back", n);
  slide (&tp, 372, 340, 100, 100, 1.0, &now, NULL);
  n = rest (&tp, 500, &now);
  check (n == 0, "moved back from the side: it stops", n);
  slide (&tp, 340, 10, 100, 400, 1.0, &now, NULL);
  rest (&tp, 150, &now);
  n = rest (&tp, 500, &now);
  check (n <= -9 && n >= -11, "at the left side: to the left", n);

  tactus_trackpad_begin (&tp, 380, 100, now, LEFT, RIGHT, 1.0);
  n = rest (&tp, 1000, &now);
  check (n == 0, "a hold begun at a side doesn't set it going", n);
  slide (&tp, 380, 300, 100, 200, 1.0, &now, NULL);
  slide (&tp, 300, 385, 100, 200, 1.0, &now, NULL);
  rest (&tp, 150, &now);
  n = rest (&tp, 500, &now);
  check (n >= 9, "until the finger has been away from it", n);

  now += 2000000;
  n = tactus_trackpad_edge_steps (&tp, now);
  check (n == 4, "a late tick doesn't owe all it missed", n);

  printf ("%d of %d failed\n", failed, checked);
  return failed ? 1 : 0;
}
