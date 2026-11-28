/*
 * Tactus's Paste key: whether there is anything to paste.
 *
 * Two things are watched, neither by a timer and neither read for what it
 * says:
 *
 * - the clipboard itself, through the compositor's data-control protocol: the
 *   kinds of data the current copy is offered as. Text of any kind or a
 *   picture counts; the data is never asked for.
 * - Omarchy's clipboard history, the file its shell keeps (a JSON list, the
 *   newest first, of {"type":"text","text":…} and {"type":"image","path":…,
 *   "mime":…} entries; older files have plain strings and "kind" for "type").
 *   A file monitor says when it changed; it is then read once, off the main
 *   loop, to see whether it has an entry the shell's list would show, and
 *   which is the newest.
 *
 * Where the compositor has no data-control protocol the clipboard can't be
 * seen, and it is taken to hold something: a Paste key that does nothing is
 * a smaller fault than none where there is something to paste.
 *
 * Copyright (C) 2026 W4HO
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#define G_LOG_DOMAIN "tactus-clipboard"

#include "tactus-clipboard.h"

#include "ext-data-control-v1-client-protocol.h"

#include <gio/gio.h>
#include <json-glib/json-glib.h>

struct _TactusClipboard {
  struct ext_data_control_device_v1 *device;
  struct ext_data_control_offer_v1  *selection;  /* the current copy's offer */
  gboolean                           seen;       /* the compositor told us what is copied */
  gboolean                           has_copy;

  char                              *history_path;
  GFileMonitor                      *monitor;
  GCancellable                      *cancel;
  gboolean                           loading, again;
  gboolean                           has_history;
  TactusClipEntry                    newest;

  GSourceFunc                        changed;
  gpointer                           data;
};

/* One copy as it is announced: is any of its kinds something a text field takes? */
typedef struct {
  gboolean pastes;
} Offer;

/*
 * On their own
 */

/**
 * tactus_clipboard_mime_pastes:
 * @mime: A kind of data a copy is offered as
 *
 * Text of any kind (and the two names X11 programs give it) or a picture.
 */
gboolean
tactus_clipboard_mime_pastes (const char *mime)
{
  if (mime == NULL)
    return FALSE;
  return g_str_has_prefix (mime, "text/") || g_str_has_prefix (mime, "image/") ||
         g_str_equal (mime, "UTF8_STRING") || g_str_equal (mime, "STRING");
}

/* Something other than white space, as the shell's list asks of a text */
static gboolean
not_blank (const char *text)
{
  if (text == NULL)
    return FALSE;
  for (const char *p = text; *p; p = g_utf8_next_char (p)) {
    gunichar c = g_utf8_get_char (p);

    if (!g_unichar_isspace (c) && c != 0xfeff)
      return TRUE;
  }
  return FALSE;
}

static const char *
member_string (JsonObject *object, const char *name)
{
  JsonNode *node = json_object_get_member (object, name);

  if (node == NULL || !JSON_NODE_HOLDS_VALUE (node) || json_node_get_value_type (node) != G_TYPE_STRING)
    return NULL;
  return json_node_get_string (node);
}

/**
 * tactus_clipboard_history_newest:
 * @json: The history file's contents
 * @len: Their length, or -1
 * @newest: (out) (nullable): The first entry the shell's list would show
 *
 * The rules are those of the shell's own reader (ClipboardHistory.js,
 * normalizeEntry): a text with something other than white space in it, or a
 * picture with a path.
 *
 * Returns: Whether the history has such an entry.
 */
gboolean
tactus_clipboard_history_newest (const char *json, gssize len, TactusClipEntry *newest)
{
  g_autoptr (JsonParser) parser = json_parser_new ();
  JsonNode *root;
  JsonArray *list;

  if (json == NULL || !json_parser_load_from_data (parser, json, len, NULL))
    return FALSE;
  root = json_parser_get_root (parser);
  if (root == NULL || !JSON_NODE_HOLDS_ARRAY (root))
    return FALSE;

  list = json_node_get_array (root);
  for (guint i = 0; i < json_array_get_length (list); i++) {
    JsonNode *node = json_array_get_element (list, i);
    JsonObject *object;
    const char *type;

    if (JSON_NODE_HOLDS_VALUE (node) && json_node_get_value_type (node) == G_TYPE_STRING) {
      if (!not_blank (json_node_get_string (node)))
        continue;
      if (newest)
        *newest = (TactusClipEntry) { .index = i };
      return TRUE;
    }
    if (!JSON_NODE_HOLDS_OBJECT (node))
      continue;

    object = json_node_get_object (node);
    type = member_string (object, "type") ?: member_string (object, "kind");
    if (g_strcmp0 (type, "text") == 0) {
      if (!not_blank (member_string (object, "text")))
        continue;
      if (newest)
        *newest = (TactusClipEntry) { .index = i };
      return TRUE;
    }
    if (g_strcmp0 (type, "image") == 0) {
      const char *path = member_string (object, "path");

      if (path == NULL || *path == '\0')
        continue;
      if (newest) {
        *newest = (TactusClipEntry) {
          .index = i, .image = TRUE, .path = g_strdup (path),
          .mime = g_strdup (member_string (object, "mime") ?: "image/png"),
        };
      }
      return TRUE;
    }
  }
  return FALSE;
}

/**
 * tactus_clipboard_history_path:
 *
 * Where Omarchy's shell keeps its clipboard history (Clipboard.qml's
 * historyPath: under the home directory, whatever XDG_STATE_HOME says).
 */
char *
tactus_clipboard_history_path (void)
{
  return g_build_filename (g_get_home_dir (), ".local", "state", "omarchy", "clipboard-history.json", NULL);
}

/*
 * The history file
 */

static void
entry_clear (TactusClipEntry *entry)
{
  g_free (entry->mime);
  g_free (entry->path);
  *entry = (TactusClipEntry) { .index = -1 };
}

typedef struct {
  gboolean        found;
  TactusClipEntry newest;
} Loaded;

static void
loaded_free (gpointer data)
{
  Loaded *loaded = data;

  entry_clear (&loaded->newest);
  g_free (loaded);
}

static void
load_thread (GTask *task, gpointer source, gpointer task_data, GCancellable *cancellable)
{
  const char *path = task_data;
  g_autofree char *contents = NULL;
  Loaded *loaded = g_new0 (Loaded, 1);
  gsize len = 0;

  loaded->newest.index = -1;
  /* No file is no history */
  if (g_file_get_contents (path, &contents, &len, NULL))
    loaded->found = tactus_clipboard_history_newest (contents, len, &loaded->newest);
  g_task_return_pointer (task, loaded, loaded_free);
}

static void history_load (TactusClipboard *self);

static void
on_loaded (GObject *source, GAsyncResult *res, gpointer data)
{
  TactusClipboard *self = data;
  g_autoptr (GError) err = NULL;
  Loaded *loaded = g_task_propagate_pointer (G_TASK (res), &err);
  gboolean before;

  /* Cancelled: the watcher is gone */
  if (loaded == NULL)
    return;

  self->loading = FALSE;
  before = tactus_clipboard_can_paste (self);
  self->has_history = loaded->found;
  entry_clear (&self->newest);
  self->newest = loaded->newest;
  loaded->newest = (TactusClipEntry) { .index = -1 };
  loaded_free (loaded);
  g_debug ("history: %s", self->has_history ? "has an entry" : "empty");

  if (self->again) {
    self->again = FALSE;
    history_load (self);
  }
  if (before != tactus_clipboard_can_paste (self) && self->changed)
    self->changed (self->data);
}

static void
history_load (TactusClipboard *self)
{
  g_autoptr (GTask) task = NULL;

  /* Changed while it was being read: once more when that is done */
  if (self->loading) {
    self->again = TRUE;
    return;
  }
  self->loading = TRUE;
  task = g_task_new (NULL, self->cancel, on_loaded, self);
  g_task_set_check_cancellable (task, TRUE);
  g_task_set_task_data (task, g_strdup (self->history_path), g_free);
  g_task_run_in_thread (task, load_thread);
}

static void
on_history_changed (GFileMonitor *monitor, GFile *file, GFile *other, GFileMonitorEvent event,
                    gpointer data)
{
  /* Written, replaced, made or removed; the writes in between say nothing yet */
  if (event == G_FILE_MONITOR_EVENT_CHANGED || event == G_FILE_MONITOR_EVENT_ATTRIBUTE_CHANGED)
    return;
  history_load (data);
}

/*
 * The clipboard
 */

static void
on_offer_mime (void *data, struct ext_data_control_offer_v1 *offer, const char *mime)
{
  Offer *o = data;

  if (tactus_clipboard_mime_pastes (mime))
    o->pastes = TRUE;
}

static const struct ext_data_control_offer_v1_listener offer_listener = {
  on_offer_mime,
};

static void
offer_destroy (struct ext_data_control_offer_v1 *offer)
{
  if (offer == NULL)
    return;
  g_free (ext_data_control_offer_v1_get_user_data (offer));
  ext_data_control_offer_v1_destroy (offer);
}

static void
on_device_offer (void *data, struct ext_data_control_device_v1 *device,
                 struct ext_data_control_offer_v1 *offer)
{
  ext_data_control_offer_v1_add_listener (offer, &offer_listener, g_new0 (Offer, 1));
}

static void
on_device_selection (void *data, struct ext_data_control_device_v1 *device,
                     struct ext_data_control_offer_v1 *offer)
{
  TactusClipboard *self = data;
  gboolean before = tactus_clipboard_can_paste (self);
  Offer *o = offer ? ext_data_control_offer_v1_get_user_data (offer) : NULL;

  offer_destroy (self->selection);
  self->selection = offer;
  self->seen = TRUE;
  self->has_copy = o && o->pastes;
  g_debug ("clipboard: %s", self->has_copy ? "text or a picture" : "nothing to paste");

  if (before != tactus_clipboard_can_paste (self) && self->changed)
    self->changed (self->data);
}

static void
on_device_finished (void *data, struct ext_data_control_device_v1 *device)
{
  TactusClipboard *self = data;

  gboolean before = tactus_clipboard_can_paste (self);

  /* The compositor took the device away: the clipboard can't be seen any more */
  offer_destroy (self->selection);
  self->selection = NULL;
  self->seen = FALSE;
  g_clear_pointer (&self->device, ext_data_control_device_v1_destroy);

  if (before != tactus_clipboard_can_paste (self) && self->changed)
    self->changed (self->data);
}

static void
on_device_primary (void *data, struct ext_data_control_device_v1 *device,
                   struct ext_data_control_offer_v1 *offer)
{
  /* What is merely marked is not what Paste pastes */
  offer_destroy (offer);
}

static const struct ext_data_control_device_v1_listener device_listener = {
  on_device_offer,
  on_device_selection,
  on_device_finished,
  on_device_primary,
};

/*
 * The watcher
 */

/**
 * tactus_clipboard_new:
 * @manager: (nullable): The compositor's data-control manager
 * @seat: (nullable): The seat whose clipboard it is
 * @history_path: (nullable): The clipboard history's file
 * @changed: (nullable): Called, on the main loop, when there came to be something to paste or nothing
 * @data: For @changed (its return value is not looked at)
 */
TactusClipboard *
tactus_clipboard_new (struct ext_data_control_manager_v1 *manager,
                      struct wl_seat                     *seat,
                      const char                         *history_path,
                      GSourceFunc                         changed,
                      gpointer                            data)
{
  TactusClipboard *self = g_new0 (TactusClipboard, 1);

  self->changed = changed;
  self->data = data;
  self->newest.index = -1;
  self->cancel = g_cancellable_new ();

  if (manager && seat) {
    self->device = ext_data_control_manager_v1_get_data_device (manager, seat);
    ext_data_control_device_v1_add_listener (self->device, &device_listener, self);
  }

  if (history_path) {
    g_autoptr (GFile) file = g_file_new_for_path (history_path);
    g_autoptr (GError) err = NULL;

    self->history_path = g_strdup (history_path);
    self->monitor = g_file_monitor_file (file, G_FILE_MONITOR_NONE, NULL, &err);
    if (self->monitor)
      g_signal_connect (self->monitor, "changed", G_CALLBACK (on_history_changed), self);
    else
      g_warning ("The clipboard history can't be watched: %s", err->message);
    history_load (self);
  }
  return self;
}

void
tactus_clipboard_free (TactusClipboard *self)
{
  if (self == NULL)
    return;

  /* A read still under way ends with nobody to tell */
  g_cancellable_cancel (self->cancel);
  g_clear_object (&self->cancel);
  if (self->monitor) {
    g_signal_handlers_disconnect_by_data (self->monitor, self);
    g_file_monitor_cancel (self->monitor);
    g_clear_object (&self->monitor);
  }
  offer_destroy (self->selection);
  g_clear_pointer (&self->device, ext_data_control_device_v1_destroy);
  entry_clear (&self->newest);
  g_free (self->history_path);
  g_free (self);
}

/**
 * tactus_clipboard_has_copy:
 *
 * Whether the clipboard holds text or a picture now. %TRUE too where the
 * compositor doesn't say (see the top of this file).
 */
gboolean
tactus_clipboard_has_copy (TactusClipboard *self)
{
  if (self == NULL)
    return FALSE;
  return self->seen ? self->has_copy : self->device == NULL;
}

/**
 * tactus_clipboard_has_history:
 *
 * Whether the clipboard history has an entry.
 */
gboolean
tactus_clipboard_has_history (TactusClipboard *self)
{
  return self && self->has_history;
}

/**
 * tactus_clipboard_newest:
 *
 * Returns: (nullable): The history's newest entry.
 */
const TactusClipEntry *
tactus_clipboard_newest (TactusClipboard *self)
{
  return self && self->has_history ? &self->newest : NULL;
}

/**
 * tactus_clipboard_can_paste:
 *
 * Whether there is anything to paste: a copy on the clipboard, or an entry in
 * the history.
 */
gboolean
tactus_clipboard_can_paste (TactusClipboard *self)
{
  return tactus_clipboard_has_copy (self) || tactus_clipboard_has_history (self);
}
