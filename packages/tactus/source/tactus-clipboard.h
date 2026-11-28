/*
 * Tactus's Paste key: whether there is anything to paste.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <glib.h>

G_BEGIN_DECLS

struct ext_data_control_manager_v1;
struct wl_seat;

typedef struct _TactusClipboard TactusClipboard;

/* The newest entry of the phone's clipboard history */
typedef struct {
  int      index;      /* where it is in the file's list */
  gboolean image;
  char    *mime, *path; /* of an image */
} TactusClipEntry;

TactusClipboard *tactus_clipboard_new         (struct ext_data_control_manager_v1 *manager,
                                               struct wl_seat                     *seat,
                                               const char                         *history_path,
                                               GSourceFunc                         changed,
                                               gpointer                            data);
void             tactus_clipboard_free        (TactusClipboard *self);
gboolean         tactus_clipboard_has_copy    (TactusClipboard *self);
gboolean         tactus_clipboard_has_history (TactusClipboard *self);
gboolean         tactus_clipboard_can_paste   (TactusClipboard *self);
const TactusClipEntry *
                 tactus_clipboard_newest      (TactusClipboard *self);

/* What these go by, on their own */
gboolean         tactus_clipboard_mime_pastes (const char *mime);
gboolean         tactus_clipboard_history_newest (const char      *json,
                                                  gssize           len,
                                                  TactusClipEntry *newest);
char            *tactus_clipboard_history_path (void);

G_END_DECLS
