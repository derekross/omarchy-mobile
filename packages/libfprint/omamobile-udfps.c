/*
 * Omarchy Mobile under-display fingerprint sensor (Google Pixel 7 Pro and 9a)
 *
 * Copyright (C) 2026 Derek Ross <derekross@gmail.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/*
 * The sensor is a match-on-chip device of an unusual kind: capture,
 * template storage and matching run in a trusted application in the
 * phone's secure world, driven by the phone vendor's fingerprint HAL. On
 * Omarchy Mobile that HAL runs in a small container, next to a bridge daemon
 * that serves a line protocol on a Unix socket (root only):
 *
 *   -> ENROLL | AUTH | LIST | DELETE <id> | CANCEL
 *   <- READY <x> <y> <r>                    once, on connect
 *      FINGER NEEDED | FINGER DOWN | FINGER UP
 *      ACQUIRED <code> <vendor>
 *      PROGRESS <id> <remaining>
 *      ENROLLED <id> | MATCH <id> | NOMATCH | LIST <id>... | DELETED <id>
 *      LOCKOUT <ms> | ERROR <code>          (5: canceled)
 *
 * The device appears when FP_OMAMOBILE_UDFPS names the socket (fprintd's
 * environment). A print's data is the HAL's enrollment id; the templates
 * themselves never leave the secure world.
 */

#define FP_COMPONENT "omamobile_udfps"

#include "drivers_api.h"
/* FpMatchData and FpDevicePrivate, for identify_is_duplicate_check() */
#include "fp-device-private.h"

#include <gio/gunixsocketaddress.h>

/* Goodix's G7 counts an enrollment down by 2 per good touch from 40. */
#define OMAMOBILE_UDFPS_ENROLL_STAGES 20

/* android.hardware.biometrics.fingerprint Error and AcquiredInfo */
enum {
  HAL_ERROR_HW_UNAVAILABLE = 1,
  HAL_ERROR_UNABLE_TO_PROCESS = 2,
  HAL_ERROR_TIMEOUT = 3,
  HAL_ERROR_NO_SPACE = 4,
  HAL_ERROR_CANCELED = 5,
  HAL_ERROR_UNABLE_TO_REMOVE = 6,
};
enum {
  HAL_ACQUIRED_GOOD = 1,
  HAL_ACQUIRED_PARTIAL = 2,
  HAL_ACQUIRED_INSUFFICIENT = 3,
  HAL_ACQUIRED_SENSOR_DIRTY = 4,
  HAL_ACQUIRED_TOO_SLOW = 5,
  HAL_ACQUIRED_TOO_FAST = 6,
  HAL_ACQUIRED_TOO_DARK = 9,
  HAL_ACQUIRED_TOO_BRIGHT = 10,
  HAL_ACQUIRED_IMMOBILE = 11,
  HAL_ACQUIRED_LIFT_TOO_SOON = 13,
};

struct _FpiDeviceOmamobileUdfps
{
  FpDevice            parent;

  GSocketConnection  *connection;
  GDataInputStream   *input;
  GOutputStream      *output;
  GCancellable       *cancellable;

  gint                enroll_stages;
  gboolean            cancelling;
  guint               cancel_timeout_id;
  /* System sleep (dev_suspend): the HAL's capture is stopped, and the
   * ERROR 5 that answers the CANCEL hasn't arrived yet. */
  gboolean            asleep;
  gboolean            sleep_cancel_pending;
};

G_DECLARE_FINAL_TYPE (FpiDeviceOmamobileUdfps, fpi_device_omamobile_udfps, FPI,
                      DEVICE_OMAMOBILE_UDFPS, FpDevice);
G_DEFINE_TYPE (FpiDeviceOmamobileUdfps, fpi_device_omamobile_udfps, FP_TYPE_DEVICE);

static void read_next_line (FpiDeviceOmamobileUdfps *self);

/* --- prints --- */

static FpPrint *
print_new (FpDevice *dev, gint32 id)
{
  FpPrint *print = fp_print_new (dev);

  fpi_print_set_type (print, FPI_PRINT_RAW);
  fpi_print_set_device_stored (print, TRUE);
  g_object_set (print, "fpi-data", g_variant_new ("(i)", id), NULL);

  return print;
}

static gboolean
print_get_id (FpPrint *print, gint32 *id)
{
  g_autoptr(GVariant) data = NULL;

  g_object_get (print, "fpi-data", &data, NULL);
  if (!data || !g_variant_is_of_type (data, G_VARIANT_TYPE ("(i)")))
    return FALSE;
  g_variant_get (data, "(i)", id);

  return TRUE;
}

/* --- errors --- */

static GError *
hal_error (gint code)
{
  switch (code)
    {
    case HAL_ERROR_CANCELED:
      return g_error_new_literal (G_IO_ERROR, G_IO_ERROR_CANCELLED, "Operation was cancelled");

    case HAL_ERROR_NO_SPACE:
      return fpi_device_error_new (FP_DEVICE_ERROR_DATA_FULL);

    case HAL_ERROR_UNABLE_TO_REMOVE:
      return fpi_device_error_new (FP_DEVICE_ERROR_DATA_NOT_FOUND);

    case HAL_ERROR_TIMEOUT:
      return fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL, "The sensor timed out");

    case HAL_ERROR_HW_UNAVAILABLE:
      return fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL, "The sensor is unavailable");

    default:
      return fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                       "The fingerprint service failed (%d)", code);
    }
}

/* A capture the HAL rejected; NULL for codes that are not a retry. */
static GError *
acquired_retry (gint code)
{
  switch (code)
    {
    case HAL_ACQUIRED_PARTIAL:
      return fpi_device_retry_new (FP_DEVICE_RETRY_CENTER_FINGER);

    case HAL_ACQUIRED_INSUFFICIENT:
    case HAL_ACQUIRED_TOO_DARK:
    case HAL_ACQUIRED_TOO_BRIGHT:
    case HAL_ACQUIRED_IMMOBILE:
      return fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL);

    case HAL_ACQUIRED_SENSOR_DIRTY:
      return fpi_device_retry_new (FP_DEVICE_RETRY_REMOVE_FINGER);

    case HAL_ACQUIRED_TOO_FAST:
    case HAL_ACQUIRED_LIFT_TOO_SOON:
      return fpi_device_retry_new (FP_DEVICE_RETRY_TOO_SHORT);

    default:
      return NULL;
    }
}

/* --- the connection --- */

static gboolean
send_command (FpiDeviceOmamobileUdfps *self, const char *command, GError **error)
{
  g_autofree char *line = g_strconcat (command, "\n", NULL);

  if (!self->output)
    {
      g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_NOT_OPEN,
                           "Not connected to the fingerprint service");
      return FALSE;
    }
  fp_dbg ("-> %s", command);

  return g_output_stream_write_all (self->output, line, strlen (line), NULL,
                                    self->cancellable, error);
}

/* Starts an action with COMMAND, or fails it at once. */
static void
start_action (FpiDeviceOmamobileUdfps *self, const char *command)
{
  GError *error = NULL;

  self->cancelling = FALSE;
  self->asleep = FALSE;		/* libfprint starts nothing while suspended */
  g_clear_handle_id (&self->cancel_timeout_id, g_source_remove);
  if (!send_command (self, command, &error))
    fpi_device_action_error (FP_DEVICE (self), error);
}

static void
handle_enroll (FpiDeviceOmamobileUdfps *self, gchar **argv)
{
  FpDevice *dev = FP_DEVICE (self);
  FpPrint *print = NULL;
  gint32 id, remaining;

  fpi_device_get_enroll_data (dev, &print);

  if (g_str_equal (argv[0], "ACQUIRED") && argv[1])
    {
      GError *retry = acquired_retry (atoi (argv[1]));

      if (retry)
        fpi_device_enroll_progress (dev, self->enroll_stages, NULL, retry);
    }
  else if (g_str_equal (argv[0], "PROGRESS") && argv[1] && argv[2])
    {
      remaining = atoi (argv[2]);
      if (remaining > 0 && self->enroll_stages < OMAMOBILE_UDFPS_ENROLL_STAGES - 1)
        self->enroll_stages++;
      if (remaining > 0)
        fpi_device_enroll_progress (dev, self->enroll_stages, NULL, NULL);
    }
  else if (g_str_equal (argv[0], "ENROLLED") && argv[1])
    {
      id = atoi (argv[1]);
      fpi_print_set_type (print, FPI_PRINT_RAW);
      fpi_print_set_device_stored (print, TRUE);
      g_object_set (print, "fpi-data", g_variant_new ("(i)", id), NULL);
      fpi_device_enroll_progress (dev, OMAMOBILE_UDFPS_ENROLL_STAGES, NULL, NULL);
      fpi_device_enroll_complete (dev, g_object_ref (print), NULL);
    }
  else if (g_str_equal (argv[0], "LOCKOUT"))
    {
      fpi_device_enroll_complete (dev, NULL,
                                  fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                                            "Too many attempts, try again later"));
    }
  else if (g_str_equal (argv[0], "ERROR") && argv[1])
    {
      fpi_device_enroll_complete (dev, NULL, hal_error (atoi (argv[1])));
    }
}

/* MATCH <id>: the enrolled print with that id among PRINTS, or NULL. */
static FpPrint *
find_print (GPtrArray *prints, gint32 id)
{
  for (guint i = 0; prints && i < prints->len; i++)
    {
      FpPrint *print = g_ptr_array_index (prints, i);
      gint32 print_id;

      if (print_get_id (print, &print_id) && print_id == id)
        return print;
    }

  return NULL;
}

static void
handle_match (FpiDeviceOmamobileUdfps *self, gchar **argv)
{
  FpDevice *dev = FP_DEVICE (self);
  FpiDeviceAction action = fpi_device_get_current_action (dev);
  gboolean matched = g_str_equal (argv[0], "MATCH") && argv[1];
  gint32 id = matched ? atoi (argv[1]) : 0;
  FpPrint *scan = NULL;

  if (g_str_equal (argv[0], "LOCKOUT"))
    {
      fpi_device_action_error (dev,
                               fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                                         "Too many attempts, try again later"));
      return;
    }
  if (g_str_equal (argv[0], "ERROR") && argv[1])
    {
      fpi_device_action_error (dev, hal_error (atoi (argv[1])));
      return;
    }
  if (!matched && !g_str_equal (argv[0], "NOMATCH"))
    return;		/* ACQUIRED and the like: the HAL keeps capturing */

  if (matched)
    scan = print_new (dev, id);

  if (action == FPI_DEVICE_ACTION_VERIFY)
    {
      FpPrint *enrolled = NULL;
      gint32 enrolled_id;

      fpi_device_get_verify_data (dev, &enrolled);
      if (matched && print_get_id (enrolled, &enrolled_id) && enrolled_id == id)
        fpi_device_verify_report (dev, FPI_MATCH_SUCCESS, scan, NULL);
      else
        fpi_device_verify_report (dev, FPI_MATCH_FAIL, scan, NULL);
      fpi_device_verify_complete (dev, NULL);
    }
  else
    {
      GPtrArray *prints = NULL;

      fpi_device_get_identify_data (dev, &prints);
      fpi_device_identify_report (dev, matched ? find_print (prints, id) : NULL,
                                  scan, NULL);
      fpi_device_identify_complete (dev, NULL);
    }
}

static void
handle_list (FpiDeviceOmamobileUdfps *self, gchar **argv)
{
  FpDevice *dev = FP_DEVICE (self);
  g_autoptr(GPtrArray) prints = NULL;

  if (g_str_equal (argv[0], "ERROR") && argv[1])
    {
      fpi_device_list_complete (dev, NULL, hal_error (atoi (argv[1])));
      return;
    }
  if (!g_str_equal (argv[0], "LIST"))
    return;

  prints = g_ptr_array_new_with_free_func (g_object_unref);
  for (gint i = 1; argv[i]; i++)
    g_ptr_array_add (prints, g_object_ref_sink (print_new (dev, atoi (argv[i]))));
  fpi_device_list_complete (dev, g_steal_pointer (&prints), NULL);
}

static void
handle_delete (FpiDeviceOmamobileUdfps *self, gchar **argv)
{
  FpDevice *dev = FP_DEVICE (self);

  if (g_str_equal (argv[0], "DELETED"))
    fpi_device_delete_complete (dev, NULL);
  else if (g_str_equal (argv[0], "ERROR") && argv[1])
    fpi_device_delete_complete (dev, hal_error (atoi (argv[1])));
}

static void
handle_line (FpiDeviceOmamobileUdfps *self, const char *line)
{
  FpDevice *dev = FP_DEVICE (self);
  g_auto(GStrv) argv = g_strsplit (line, " ", -1);
  FpiDeviceAction action;

  fp_dbg ("<- %s", line);
  if (!argv[0])
    return;

  /* The ERROR 5 answering the CANCEL sent for sleep belongs to no action.
   * Any other end of that capture (a match racing the CANCEL) means no
   * ERROR 5 follows; asleep it is dropped below, and resume starts anew. */
  if (self->sleep_cancel_pending &&
      (g_str_equal (argv[0], "ERROR") || g_str_equal (argv[0], "MATCH") ||
       g_str_equal (argv[0], "NOMATCH") || g_str_equal (argv[0], "LOCKOUT") ||
       g_str_equal (argv[0], "ENROLLED")))
    {
      self->sleep_cancel_pending = FALSE;
      if (g_str_equal (argv[0], "ERROR") && argv[1] && atoi (argv[1]) == HAL_ERROR_CANCELED)
        return;
    }
  if (self->asleep)
    {
      fp_dbg ("asleep, ignored: %s", line);
      return;
    }

  /* finger status, for every capture */
  if (g_str_equal (argv[0], "FINGER") && argv[1])
    {
      if (g_str_equal (argv[1], "NEEDED"))
        fpi_device_report_finger_status_changes (dev, FP_FINGER_STATUS_NEEDED,
                                                 FP_FINGER_STATUS_NONE);
      else if (g_str_equal (argv[1], "DOWN"))
        fpi_device_report_finger_status_changes (dev, FP_FINGER_STATUS_PRESENT,
                                                 FP_FINGER_STATUS_NONE);
      else if (g_str_equal (argv[1], "UP"))
        fpi_device_report_finger_status_changes (dev, FP_FINGER_STATUS_NONE,
                                                 FP_FINGER_STATUS_PRESENT);
      return;
    }
  if (g_str_equal (argv[0], "READY"))
    return;

  action = fpi_device_get_current_action (dev);
  if (action == FPI_DEVICE_ACTION_ENROLL)
    handle_enroll (self, argv);
  else if (action == FPI_DEVICE_ACTION_VERIFY || action == FPI_DEVICE_ACTION_IDENTIFY)
    handle_match (self, argv);
  else if (action == FPI_DEVICE_ACTION_LIST)
    handle_list (self, argv);
  else if (action == FPI_DEVICE_ACTION_DELETE)
    handle_delete (self, argv);
  else
    fp_dbg ("ignored outside an action: %s", line);
}

static void
line_read_cb (GObject *source, GAsyncResult *res, gpointer user_data)
{
  FpiDeviceOmamobileUdfps *self = user_data;
  g_autoptr(GError) error = NULL;
  g_autofree char *line = NULL;
  FpDevice *dev;

  line = g_data_input_stream_read_line_finish (G_DATA_INPUT_STREAM (source), res, NULL, &error);
  if (g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    return;		/* closing; self may be going away */

  dev = FP_DEVICE (self);
  if (!line)
    {
      /* the bridge went away (the service restarts): fail the action */
      fp_warn ("lost the fingerprint service: %s", error ? error->message : "closed");
      g_clear_object (&self->input);
      self->output = NULL;
      g_clear_object (&self->connection);
      if (fpi_device_get_current_action (dev) != FPI_DEVICE_ACTION_NONE &&
          fpi_device_get_current_action (dev) != FPI_DEVICE_ACTION_CLOSE)
        fpi_device_action_error (dev, fpi_device_error_new (FP_DEVICE_ERROR_REMOVED));
      return;
    }

  handle_line (self, line);
  read_next_line (self);
}

static void
read_next_line (FpiDeviceOmamobileUdfps *self)
{
  if (!self->input)
    return;
  g_data_input_stream_read_line_async (self->input, G_PRIORITY_DEFAULT,
                                       self->cancellable, line_read_cb, self);
}

static void
connect_cb (GObject *source, GAsyncResult *res, gpointer user_data)
{
  FpiDeviceOmamobileUdfps *self = user_data;
  GError *error = NULL;
  GSocketConnection *connection;

  connection = g_socket_client_connect_finish (G_SOCKET_CLIENT (source), res, &error);
  if (!connection)
    {
      fpi_device_open_complete (FP_DEVICE (self), error);
      return;
    }
  self->connection = connection;
  self->input = g_data_input_stream_new (
    g_io_stream_get_input_stream (G_IO_STREAM (connection)));
  g_data_input_stream_set_newline_type (self->input, G_DATA_STREAM_NEWLINE_TYPE_LF);
  self->output = g_io_stream_get_output_stream (G_IO_STREAM (connection));
  read_next_line (self);
  fpi_device_open_complete (FP_DEVICE (self), NULL);
}

/* --- device operations --- */

static void
dev_probe (FpDevice *dev)
{
  /* one sensor per phone; a print is only valid on the HAL that made it */
  fpi_device_probe_complete (dev, "omamobile-udfps", NULL, NULL);
}

static void
dev_open (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);
  g_autoptr(GSocketClient) client = g_socket_client_new ();
  g_autoptr(GSocketAddress) address = NULL;
  const char *path = fpi_device_get_virtual_env (dev);

  g_clear_object (&self->cancellable);
  self->cancellable = g_cancellable_new ();
  address = g_unix_socket_address_new (path);
  g_socket_client_connect_async (client, G_SOCKET_CONNECTABLE (address),
                                 self->cancellable, connect_cb, self);
}

static void
disconnect (FpiDeviceOmamobileUdfps *self)
{
  g_clear_handle_id (&self->cancel_timeout_id, g_source_remove);
  self->asleep = FALSE;
  self->sleep_cancel_pending = FALSE;
  if (self->cancellable)
    g_cancellable_cancel (self->cancellable);
  g_clear_object (&self->cancellable);
  g_clear_object (&self->input);
  self->output = NULL;
  if (self->connection)
    g_io_stream_close (G_IO_STREAM (self->connection), NULL, NULL);
  g_clear_object (&self->connection);
}

static void
dev_close (FpDevice *dev)
{
  disconnect (FPI_DEVICE_OMAMOBILE_UDFPS (dev));
  fpi_device_close_complete (dev, NULL);
}

static void
dev_enroll (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);

  self->enroll_stages = 0;
  start_action (self, "ENROLL");
}

static void
dev_verify (FpDevice *dev)
{
  start_action (FPI_DEVICE_OMAMOBILE_UDFPS (dev), "AUTH");
}

/*
 * fprintd runs an identify before every enrollment, to refuse a finger that
 * is already enrolled. Here that is one more touch and, for a new finger, a
 * failed authentication, which the secure world counts toward its lockout
 * (five give a timed lockout, more a permanent one): enrolling a few fingers
 * locked the sensor out. Android does no such check. fprintd's check is the
 * only identify it starts without a match callback (VerifyStart passes one),
 * so that one is answered "no match" at once, without asking the HAL.
 *
 * libfprint has no driver API for the callback, so this reads the task data
 * the way fpi-device.c does (libfprint 1.94.x; the driver test covers it).
 */
static gboolean
identify_is_duplicate_check (FpDevice *dev)
{
  FpDeviceClass *dev_class = g_type_class_peek_static (FP_TYPE_DEVICE);
  FpDevicePrivate *priv = G_STRUCT_MEMBER_P (dev,
                                             g_type_class_get_instance_private_offset (dev_class));
  FpMatchData *data = priv->current_task ? g_task_get_task_data (priv->current_task) : NULL;

  return data && data->match_cb == NULL;
}

static void
dev_identify (FpDevice *dev)
{
  if (identify_is_duplicate_check (dev))
    {
      fp_dbg ("identify without a match callback (fprintd's duplicate check): no match");
      fpi_device_identify_report (dev, NULL, NULL, NULL);
      fpi_device_identify_complete (dev, NULL);
      return;
    }
  start_action (FPI_DEVICE_OMAMOBILE_UDFPS (dev), "AUTH");
}

static void
dev_list (FpDevice *dev)
{
  start_action (FPI_DEVICE_OMAMOBILE_UDFPS (dev), "LIST");
}

static void
dev_delete (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);
  g_autofree char *command = NULL;
  FpPrint *print = NULL;
  gint32 id;

  fpi_device_get_delete_data (dev, &print);
  if (!print_get_id (print, &id))
    {
      fpi_device_delete_complete (dev, fpi_device_error_new (FP_DEVICE_ERROR_DATA_INVALID));
      return;
    }
  command = g_strdup_printf ("DELETE %d", id);
  start_action (self, command);
}

/* No answer to CANCEL: complete the action as cancelled anyway, so fprintd
 * can release the device instead of holding the claim for good. */
static gboolean
cancel_timeout_cb (gpointer user_data)
{
  FpiDeviceOmamobileUdfps *self = user_data;
  FpDevice *dev = FP_DEVICE (self);
  FpiDeviceAction action = fpi_device_get_current_action (dev);

  self->cancel_timeout_id = 0;
  if (self->cancelling && action != FPI_DEVICE_ACTION_NONE &&
      action != FPI_DEVICE_ACTION_OPEN && action != FPI_DEVICE_ACTION_CLOSE)
    {
      fp_warn ("no answer to CANCEL: completing the action as cancelled");
      fpi_device_action_error (dev, g_error_new_literal (G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                                         "Operation was cancelled"));
    }
  return G_SOURCE_REMOVE;
}

/* The bridge ends the capture and answers ERROR 5, which completes the
 * action as cancelled; CANCEL_TIMEOUT_MS is the backstop if it never does
 * (the bridge gives the HAL 3 s). */
#define CANCEL_TIMEOUT_MS 5000

static void
dev_cancel (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);
  g_autoptr(GError) error = NULL;

  /* Asleep, the HAL's capture is already stopped: nothing to wait for.
   * libfprint then resumes without calling dev_resume (no action left). */
  if (self->asleep)
    {
      self->asleep = FALSE;
      fpi_device_action_error (dev, g_error_new_literal (G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                                         "Operation was cancelled"));
      return;
    }
  if (self->cancelling)
    return;
  self->cancelling = TRUE;
  if (!send_command (self, "CANCEL", &error))
    fp_warn ("cannot cancel: %s", error->message);
  g_clear_handle_id (&self->cancel_timeout_id, g_source_remove);
  self->cancel_timeout_id = g_timeout_add (CANCEL_TIMEOUT_MS, cancel_timeout_cb, self);
}

/*
 * System sleep: fprintd suspends the device on logind's PrepareForSleep and
 * resumes it after. A verify or identify (the lock screen's) stays open
 * across the sleep: the HAL's capture is stopped now and started again on
 * resume, so the client never sees an error. Without these, libfprint failed
 * the verify "while suspended", the client's Release failed as busy, and
 * fprintd dropped its claim on a device libfprint still held open, so every
 * later Claim failed until fprintd exited (the lock screen retrying kept it
 * running). An enrollment can't pick up midway, so it is held the same
 * way and failed on resume: the client's Release then comes after the sleep,
 * when libfprint can close the device.
 */
static void
dev_suspend (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);
  FpiDeviceAction action = fpi_device_get_current_action (dev);
  g_autoptr(GError) error = NULL;

  if (action != FPI_DEVICE_ACTION_VERIFY && action != FPI_DEVICE_ACTION_IDENTIFY &&
      action != FPI_DEVICE_ACTION_ENROLL)
    {
      fpi_device_suspend_complete (dev, fpi_device_error_new (FP_DEVICE_ERROR_NOT_SUPPORTED));
      return;
    }

  self->asleep = TRUE;
  if (send_command (self, "CANCEL", &error))
    self->sleep_cancel_pending = TRUE;
  else
    fp_warn ("cannot stop the capture for sleep: %s", error->message);
  fpi_device_suspend_complete (dev, NULL);
}

static void
dev_resume (FpDevice *dev)
{
  FpiDeviceOmamobileUdfps *self = FPI_DEVICE_OMAMOBILE_UDFPS (dev);
  FpiDeviceAction action = fpi_device_get_current_action (dev);
  gboolean was_asleep = self->asleep;
  GError *error = NULL;

  self->asleep = FALSE;
  fpi_device_resume_complete (dev, NULL);

  if (!was_asleep)
    return;
  if (action == FPI_DEVICE_ACTION_ENROLL)
    {
      fpi_device_action_error (dev,
                               fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                                         "Enrollment was interrupted by sleep, start again"));
      return;
    }
  if (action != FPI_DEVICE_ACTION_VERIFY && action != FPI_DEVICE_ACTION_IDENTIFY)
    return;
  if (!send_command (self, "AUTH", &error))
    fpi_device_action_error (dev, error);
}

static void
fpi_device_omamobile_udfps_init (FpiDeviceOmamobileUdfps *self)
{
}

static void
fpi_device_omamobile_udfps_finalize (GObject *object)
{
  disconnect (FPI_DEVICE_OMAMOBILE_UDFPS (object));
  G_OBJECT_CLASS (fpi_device_omamobile_udfps_parent_class)->finalize (object);
}

static const FpIdEntry id_table[] = {
  { .virtual_envvar = "FP_OMAMOBILE_UDFPS" },
  { .virtual_envvar = NULL }
};

static void
fpi_device_omamobile_udfps_class_init (FpiDeviceOmamobileUdfpsClass *klass)
{
  FpDeviceClass *dev_class = FP_DEVICE_CLASS (klass);
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->finalize = fpi_device_omamobile_udfps_finalize;

  dev_class->id = FP_COMPONENT;
  dev_class->full_name = "Under-display fingerprint sensor (Omarchy Mobile)";
  dev_class->type = FP_DEVICE_TYPE_VIRTUAL;
  dev_class->id_table = id_table;
  dev_class->nr_enroll_stages = OMAMOBILE_UDFPS_ENROLL_STAGES;
  dev_class->scan_type = FP_SCAN_TYPE_PRESS;
  /* the sensor only runs while a finger is on it; no thermal model needed */
  dev_class->temp_hot_seconds = -1;

  dev_class->probe = dev_probe;
  dev_class->open = dev_open;
  dev_class->close = dev_close;
  dev_class->enroll = dev_enroll;
  dev_class->verify = dev_verify;
  dev_class->identify = dev_identify;
  dev_class->list = dev_list;
  dev_class->delete = dev_delete;
  dev_class->cancel = dev_cancel;
  dev_class->suspend = dev_suspend;
  dev_class->resume = dev_resume;

  fpi_device_class_auto_initialize_features (dev_class);
}
