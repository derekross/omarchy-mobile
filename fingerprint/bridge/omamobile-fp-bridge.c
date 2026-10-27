// SPDX-License-Identifier: MIT
/*
 * omamobile-fp-bridge: the client of Google's fingerprint HAL in the
 * Omarchy Mobile fingerprint chroot (device/cheetah/FINGERPRINT-PLAN.md).
 *
 * On Android, FingerprintService, keystore, LockSettingsService and SystemUI
 * drive the HAL. Here this one program does their part, and serves a small
 * line protocol on a Unix socket to the libfprint driver omamobile_udfps
 * (fprintd), which is what Omarchy's lock screen and sudo use:
 *
 *   -> ENROLL | AUTH | LIST | DELETE <id> | CANCEL | RESETLOCKOUT | STATUS
 *   <- READY <x> <y> <radius>              on connect: the sensor, panel pixels
 *      FINGER NEEDED | FINGER DOWN | FINGER UP
 *      ACQUIRED <code> <vendor>
 *      PROGRESS <id> <remaining>
 *      ENROLLED <id>                       ENROLL done
 *      MATCH <id> | NOMATCH                AUTH done
 *      LIST [<id>...]                      LIST done
 *      DELETED <id>                        DELETE done
 *      LOCKOUT <ms>                        AUTH or ENROLL done; -1: permanent
 *      ERROR <code>                        the operation ended; the HAL's
 *                                          Error codes (5: canceled)
 *      OK                                  RESETLOCKOUT, STATUS done
 *
 * One operation at a time; one client at a time (a new connection replaces
 * the old one and cancels its operation). The socket is root-only.
 *
 * What the bridge does for the HAL:
 *  - holds the one session the HAL allows (user 0) for its whole life;
 *  - agrees the auth-token key once (ISharedSecret, Trusty KeyMint only),
 *    which keystore does at boot on Android;
 *  - gets the auth token enrollment needs from Trusty's Gatekeeper, for a
 *    random secret of its own (STATE_DIR/secret), enrolled once. That secret
 *    is not the user's password: fprintd's own polkit check is what guards
 *    enrollment;
 *  - reads the touchscreen while an operation runs: a finger inside the
 *    sensor circle lights the circle (the panel's local_hbm_mode), then
 *    onPointerDownWithContext and, a frame later, onUiReady; lifting the
 *    finger reverses that. The HAL reports halHandlesDisplayTouches and
 *    halControlsIllumination false, so both are the client's job.
 *
 * For the desktop, the bridge also publishes its state in a small JSON file
 * (--ui-state; the runner puts it at /run/omamobile-fp-ui/state.json on the
 * host, world-readable): which operation captures, whether a finger is on
 * the sensor, and the sensor circle. omamobile-shell's omamobile.fingerprint
 * plugin draws the target from it and keeps shell gestures off the circle:
 *
 *   {"op":"idle|enroll|auth","finger":false,"x":717,"y":2360,"r":121,
 *    "w":1440,"h":3120,"seq":7,"acquired":1,"remaining":24,"error":0,
 *    "last":"none|enrolled|match|nomatch|lockout|error","contact":false}
 *
 * acquired, remaining and error are the last ACQUIRED code, PROGRESS
 * remaining (-1: none yet) and ERROR code of the current or last ENROLL or
 * AUTH; seq counts those events. contact: a touch that reached the sensor
 * is still down (captured or not).
 *
 * Plain C on libbinder_ndk, without generated code: parcels are written as
 * the NDK backend writes them (a parcelable is a non-null marker, its size,
 * then its fields) and transaction numbers are the methods' order in the
 * frozen AIDL (fingerprint V3, hash 637371b53fb7faf9bd43aa51b72c23852d6e6d96).
 *
 * A bionic executable built without Android's build system: _start hands the
 * arguments to __libc_init() as bionic's crtbegin does. fingerprint/Makefile
 * builds it against the extracted chroot's libc and libbinder_ndk.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

/* --- bionic start-up --- */

typedef struct {
	void (**preinit_array)(void);
	void (**init_array)(void);
	void (**fini_array)(void);
	size_t preinit_array_count;
	size_t init_array_count;
	size_t fini_array_count;
} structors_array_t;

extern void __libc_init(void *raw_args, void (*onexit)(void),
			int (*slingshot)(int, char **, char **),
			structors_array_t const *const structors)
	__attribute__((noreturn));
int main(int argc, char **argv, char **envp);

/* The linker runs DT_INIT_ARRAY itself for a dynamic executable. */
static const structors_array_t structors;

__attribute__((used, noreturn)) void omamobile_start_main(void *raw_args)
{
	__libc_init(raw_args, NULL, main, &structors);
}

__asm__(".text\n"
	".global _start\n"
	".type _start, %function\n"
	"_start:\n"
	"	mov x0, sp\n"
	"	b omamobile_start_main\n");

/* --- libbinder_ndk --- */

typedef struct AIBinder AIBinder;
typedef struct AIBinder_Class AIBinder_Class;
typedef struct AParcel AParcel;
typedef struct AStatus AStatus;
typedef int32_t binder_status_t;
typedef uint32_t transaction_code_t;

AIBinder_Class *AIBinder_Class_define(const char *descriptor,
				      void *(*on_create)(void *),
				      void (*on_destroy)(void *),
				      binder_status_t (*on_transact)(AIBinder *, transaction_code_t,
								     const AParcel *, AParcel *));
AIBinder *AIBinder_new(const AIBinder_Class *clazz, void *args);
bool AIBinder_associateClass(AIBinder *binder, const AIBinder_Class *clazz);
void AIBinder_markVintfStability(AIBinder *binder);
void AIBinder_decStrong(AIBinder *binder);
binder_status_t AIBinder_prepareTransaction(AIBinder *binder, AParcel **in);
binder_status_t AIBinder_transact(AIBinder *binder, transaction_code_t code, AParcel **in,
				  AParcel **out, uint32_t flags);
AIBinder *AServiceManager_waitForService(const char *instance);
void ABinderProcess_startThreadPool(void);
bool ABinderProcess_setThreadPoolMaxThreadCount(uint32_t threads);
void AParcel_delete(AParcel *parcel);
binder_status_t AParcel_readStatusHeader(const AParcel *parcel, AStatus **status);
binder_status_t AParcel_writeStatusHeader(AParcel *parcel, const AStatus *status);
AStatus *AStatus_newOk(void);
bool AStatus_isOk(const AStatus *status);
const char *AStatus_getDescription(const AStatus *status);
void AStatus_deleteDescription(const char *description);
void AStatus_delete(AStatus *status);
int32_t AStatus_getServiceSpecificError(const AStatus *status);
int32_t AParcel_getDataPosition(const AParcel *parcel);
binder_status_t AParcel_setDataPosition(const AParcel *parcel, int32_t position);
int32_t AParcel_getDataSize(const AParcel *parcel);
binder_status_t AParcel_writeInt32(AParcel *parcel, int32_t value);
binder_status_t AParcel_writeInt64(AParcel *parcel, int64_t value);
binder_status_t AParcel_writeFloat(AParcel *parcel, float value);
binder_status_t AParcel_writeBool(AParcel *parcel, bool value);
binder_status_t AParcel_writeString(AParcel *parcel, const char *string, int32_t length);
binder_status_t AParcel_writeByteArray(AParcel *parcel, const int8_t *array, int32_t length);
binder_status_t AParcel_writeInt32Array(AParcel *parcel, const int32_t *array, int32_t length);
binder_status_t AParcel_writeStrongBinder(AParcel *parcel, AIBinder *binder);
binder_status_t AParcel_readInt32(const AParcel *parcel, int32_t *value);
binder_status_t AParcel_readInt64(const AParcel *parcel, int64_t *value);
binder_status_t AParcel_readStrongBinder(const AParcel *parcel, AIBinder **binder);
binder_status_t AParcel_readByteArray(const AParcel *parcel, void *data,
				      bool (*allocator)(void *data, int32_t length,
							int8_t **buffer));

#define STATUS_OK			0
#define STATUS_UNKNOWN_TRANSACTION	(-74)	/* -EBADMSG */
#define STATUS_DEAD_OBJECT		(-32)	/* -EPIPE */
#define FLAG_ONEWAY			0x01
#define GET_INTERFACE_VERSION		0x00ffffffu
#define GET_INTERFACE_HASH		0x00fffffeu

#define AIDL_VERSION	3
#define AIDL_HASH	"637371b53fb7faf9bd43aa51b72c23852d6e6d96"
#define FINGERPRINT	"android.hardware.biometrics.fingerprint.IFingerprint"
#define SESSION		"android.hardware.biometrics.fingerprint.ISession"
#define CALLBACK	"android.hardware.biometrics.fingerprint.ISessionCallback"
#define CANCELLATION	"android.hardware.biometrics.common.ICancellationSignal"
#define SHARED_SECRET	"android.hardware.security.sharedsecret.ISharedSecret"
#define GATEKEEPER	"android.hardware.gatekeeper.IGatekeeper"

enum {	/* IFingerprint */
	FP_GET_SENSOR_PROPS = 1, FP_CREATE_SESSION,
};
enum {	/* ISession */
	S_GENERATE_CHALLENGE = 1, S_REVOKE_CHALLENGE, S_ENROLL, S_AUTHENTICATE,
	S_DETECT_INTERACTION, S_ENUMERATE_ENROLLMENTS, S_REMOVE_ENROLLMENTS,
	S_GET_AUTHENTICATOR_ID, S_INVALIDATE_AUTHENTICATOR_ID, S_RESET_LOCKOUT, S_CLOSE,
	S_ON_POINTER_DOWN, S_ON_POINTER_UP, S_ON_UI_READY, S_AUTHENTICATE_WITH_CONTEXT,
	S_ENROLL_WITH_CONTEXT, S_DETECT_INTERACTION_WITH_CONTEXT,
	S_ON_POINTER_DOWN_WITH_CONTEXT, S_ON_POINTER_UP_WITH_CONTEXT,
};
enum {	/* ISessionCallback */
	CB_CHALLENGE_GENERATED = 1, CB_CHALLENGE_REVOKED, CB_ACQUIRED, CB_ERROR,
	CB_ENROLLMENT_PROGRESS, CB_AUTHENTICATION_SUCCEEDED, CB_AUTHENTICATION_FAILED,
	CB_LOCKOUT_TIMED, CB_LOCKOUT_PERMANENT, CB_LOCKOUT_CLEARED, CB_INTERACTION_DETECTED,
	CB_ENROLLMENTS_ENUMERATED, CB_ENROLLMENTS_REMOVED, CB_AUTHENTICATOR_ID_RETRIEVED,
	CB_AUTHENTICATOR_ID_INVALIDATED, CB_SESSION_CLOSED,
};
#define CANCEL		1	/* ICancellationSignal.cancel, oneway */
enum {	/* ISharedSecret */
	SS_GET_PARAMETERS = 1, SS_COMPUTE,
};
enum {	/* IGatekeeper */
	GK_DELETE_ALL_USERS = 1, GK_DELETE_USER, GK_ENROLL, GK_VERIFY,
};
#define GK_STATUS_OK		0
#define GK_STATUS_REENROLL	1
#define GK_ERROR_RETRY_TIMEOUT	(-2)

/* android.hardware.biometrics.fingerprint.Error */
#define ERR_HW_UNAVAILABLE	1
#define ERR_UNABLE_TO_PROCESS	2
#define ERR_TIMEOUT		3
#define ERR_CANCELED		5

/* --- configuration --- */

static const char *socket_path = "/dev/socket/omamobile-fp/bridge.sock";
static const char *state_dir = "/data/vendor/omamobile-fp";
static const char *touch_path = "/dev/input/touchscreen";
static const char *lhbm_path = "/sys/class/backlight/panel0-backlight/local_hbm_mode";
static const char *ui_state_path;	/* --ui-state: off unless given */
static const char *inhibit_dir;		/* --inhibit: off unless given */
/* An inhibit file counts while its mtime is this fresh (the shell touches
 * it every few seconds while the on-screen keyboard is up). */
#define INHIBIT_FRESH_S	15
/* The panel takes the circle at its next frame; a frame and a half at 60 Hz
 * would do, an idle panel may run at 10 Hz. Tuned in FINGERPRINT-PLAN F8. */
static int lhbm_settle_ms = 120;
/* The panel driver turns LHBM off after at most 3 s; refresh it meanwhile. */
#define LHBM_REFRESH_MS	2000
/* Sensor defaults (stock cheetah); getSensorProps() replaces them. */
static int32_t sensor_x = 720, sensor_y = 2360, sensor_r = 120;
/* The panel in pixels, the frame of the HAL's sensor location (--panel;
 * the Pixel 7 Pro's by default, the Pixel 9a is 1080x2424). */
static int32_t panel_w = 1440, panel_h = 3120;

/* --- logging --- */

static void say(const char *format, ...)
{
	char line[512];
	va_list args;
	int n;

	va_start(args, format);
	n = vsnprintf(line, sizeof(line) - 1, format, args);
	va_end(args);
	if (n < 0)
		return;
	if (n > (int)sizeof(line) - 2)
		n = sizeof(line) - 2;
	line[n++] = '\n';
	(void)!write(2, line, n);
}

static int64_t now_ms(void)
{
	struct timespec now;

	clock_gettime(CLOCK_MONOTONIC, &now);
	return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

/* --- callback events: binder thread -> main loop --- */

struct event {
	int32_t code;		/* ISessionCallback transaction */
	int32_t a, b;
	int64_t c;
	int32_t count;		/* enumerated/removed ids */
	int32_t ids[16];
};

static int events[2];

static void post(const struct event *e)
{
	(void)!write(events[1], e, sizeof(*e));
}

struct bytes {
	int32_t length;		/* -1: null */
	int8_t data[256];
};

static bool bytes_allocator(void *data, int32_t length, int8_t **buffer)
{
	struct bytes *b = data;

	if (length > (int32_t)sizeof(b->data))
		return false;
	b->length = length;
	*buffer = length > 0 ? b->data : NULL;
	return true;
}

static bool read_bytes(const AParcel *in, struct bytes *b)
{
	b->length = -1;
	return AParcel_readByteArray(in, b, bytes_allocator) == STATUS_OK;
}

/* HardwareAuthToken (keymaster and keymint: the same parcel) */
struct hat {
	int64_t challenge, user, authenticator, timestamp;
	int32_t type;
	struct bytes mac;
};

/* A parcelable's non-null marker and size; returns where it ends, or -1. */
static int32_t parcelable_begin(const AParcel *in)
{
	int32_t marker = 0, size = 0, start;

	if (AParcel_readInt32(in, &marker) != STATUS_OK || !marker)
		return -1;
	start = AParcel_getDataPosition(in);
	if (AParcel_readInt32(in, &size) != STATUS_OK || size < 4)
		return -1;
	return start + size;
}

static bool read_hat(const AParcel *in, struct hat *hat)
{
	int32_t end, ts_end;

	memset(hat, 0, sizeof(*hat));
	end = parcelable_begin(in);
	if (end < 0)
		return false;
	AParcel_readInt64(in, &hat->challenge);
	AParcel_readInt64(in, &hat->user);
	AParcel_readInt64(in, &hat->authenticator);
	AParcel_readInt32(in, &hat->type);
	ts_end = parcelable_begin(in);
	AParcel_readInt64(in, &hat->timestamp);
	if (ts_end >= 0)
		AParcel_setDataPosition(in, ts_end);
	read_bytes(in, &hat->mac);
	AParcel_setDataPosition(in, end);
	return hat->mac.length > 0;
}

static void read_ids(const AParcel *in, struct event *e)
{
	int32_t count = 0, id;

	AParcel_readInt32(in, &count);
	e->a = count;
	for (int32_t i = 0; i < count; i++) {
		if (AParcel_readInt32(in, &id) != STATUS_OK)
			break;
		if (i < (int32_t)(sizeof(e->ids) / sizeof(*e->ids)))
			e->ids[e->count++] = id;
	}
}

static void *no_data(void *args)
{
	return args;
}

static void no_destroy(void *data)
{
	(void)data;
}

static binder_status_t not_local(AIBinder *binder, transaction_code_t code,
				 const AParcel *in, AParcel *out)
{
	(void)binder, (void)code, (void)in, (void)out;
	return STATUS_UNKNOWN_TRANSACTION;
}

/* ISessionCallback, called on a binder thread: hand everything to main. */
static binder_status_t callback(AIBinder *binder, transaction_code_t code,
				const AParcel *in, AParcel *out)
{
	struct event e = { .code = (int32_t)code };
	struct hat hat;
	AStatus *ok;

	(void)binder;
	ok = AStatus_newOk();
	AParcel_writeStatusHeader(out, ok);
	AStatus_delete(ok);
	switch (code) {
	case GET_INTERFACE_VERSION:
		AParcel_writeInt32(out, AIDL_VERSION);
		return STATUS_OK;
	case GET_INTERFACE_HASH:
		AParcel_writeString(out, AIDL_HASH, sizeof(AIDL_HASH) - 1);
		return STATUS_OK;
	case CB_CHALLENGE_GENERATED:
	case CB_CHALLENGE_REVOKED:
	case CB_LOCKOUT_TIMED:
	case CB_AUTHENTICATOR_ID_RETRIEVED:
	case CB_AUTHENTICATOR_ID_INVALIDATED:
		AParcel_readInt64(in, &e.c);
		break;
	case CB_ACQUIRED:
	case CB_ERROR:
	case CB_ENROLLMENT_PROGRESS:
		AParcel_readInt32(in, &e.a);
		AParcel_readInt32(in, &e.b);
		break;
	case CB_AUTHENTICATION_SUCCEEDED:
		AParcel_readInt32(in, &e.a);
		/* the token unlocks KeyMint keys on Android; nothing here needs it */
		e.b = read_hat(in, &hat);
		break;
	case CB_ENROLLMENTS_ENUMERATED:
	case CB_ENROLLMENTS_REMOVED:
		read_ids(in, &e);
		break;
	case CB_AUTHENTICATION_FAILED:
	case CB_LOCKOUT_PERMANENT:
	case CB_LOCKOUT_CLEARED:
	case CB_INTERACTION_DETECTED:
	case CB_SESSION_CLOSED:
		break;
	default:
		say("unknown callback %u", code);
		return STATUS_OK;
	}
	post(&e);
	return STATUS_OK;
}

/* --- calls --- */

static AIBinder_Class *fingerprint_class, *session_class, *cancel_class, *callback_class;
static AIBinder_Class *shared_secret_class, *gatekeeper_class;
static AIBinder *session, *cancel_signal;
static int32_t last_service_error;

static AParcel *begin(AIBinder *binder)
{
	AParcel *in = NULL;

	if (AIBinder_prepareTransaction(binder, &in) != STATUS_OK) {
		say("prepareTransaction failed");
		exit(1);
	}
	return in;
}

/* Returns the reply after its status, or NULL. A dead HAL ends the bridge:
 * the runner then stops the stack and systemd restarts it. */
static AParcel *call(AIBinder *binder, transaction_code_t code, AParcel *in,
		     const char *what)
{
	AParcel *out = NULL;
	AStatus *status = NULL;
	binder_status_t result;

	last_service_error = 0;
	result = AIBinder_transact(binder, code, &in, &out, 0);
	if (result == STATUS_DEAD_OBJECT) {
		say("%s: the service died", what);
		exit(3);
	}
	if (result != STATUS_OK) {
		say("%s: transaction failed (%d)", what, result);
		return NULL;
	}
	result = AParcel_readStatusHeader(out, &status);
	if (result != STATUS_OK || !AStatus_isOk(status)) {
		const char *text = status ? AStatus_getDescription(status) : NULL;

		say("%s: %s (%d)", what, text ? text : "bad reply", result);
		if (text)
			AStatus_deleteDescription(text);
		if (status) {
			last_service_error = AStatus_getServiceSpecificError(status);
			AStatus_delete(status);
		}
		AParcel_delete(out);
		return NULL;
	}
	AStatus_delete(status);
	return out;
}

static bool call_void(AIBinder *binder, transaction_code_t code, AParcel *in,
		      const char *what)
{
	AParcel *out = call(binder, code, in, what);

	if (out)
		AParcel_delete(out);
	return out != NULL;
}

static void call_oneway(AIBinder *binder, transaction_code_t code, AParcel *in,
			const char *what)
{
	AParcel *out = NULL;

	if (AIBinder_transact(binder, code, &in, &out, FLAG_ONEWAY) != STATUS_OK)
		say("%s: transaction failed", what);
	if (out)
		AParcel_delete(out);
}

static int32_t parcelable_open(AParcel *in)
{
	int32_t start;

	AParcel_writeInt32(in, 1);
	start = AParcel_getDataPosition(in);
	AParcel_writeInt32(in, 0);
	return start;
}

static void parcelable_close(AParcel *in, int32_t start)
{
	int32_t end = AParcel_getDataPosition(in);

	AParcel_setDataPosition(in, start);
	AParcel_writeInt32(in, end - start);
	AParcel_setDataPosition(in, end);
}

static void write_hat(AParcel *in, const struct hat *hat)
{
	int32_t start = parcelable_open(in), timestamp;

	AParcel_writeInt64(in, hat->challenge);
	AParcel_writeInt64(in, hat->user);
	AParcel_writeInt64(in, hat->authenticator);
	AParcel_writeInt32(in, hat->type);
	timestamp = parcelable_open(in);
	AParcel_writeInt64(in, hat->timestamp);
	parcelable_close(in, timestamp);
	AParcel_writeByteArray(in, hat->mac.data, hat->mac.length);
	parcelable_close(in, start);
}

/* PointerContext: one finger, in panel pixels. */
static void write_pointer(AParcel *in, float x, float y, int64_t time, int64_t start)
{
	int32_t p = parcelable_open(in);

	AParcel_writeInt32(in, 0);		/* pointerId */
	AParcel_writeFloat(in, x);
	AParcel_writeFloat(in, y);
	AParcel_writeFloat(in, 60);		/* minor: not reported by the panel */
	AParcel_writeFloat(in, 60);		/* major */
	AParcel_writeFloat(in, 0);		/* orientation */
	AParcel_writeBool(in, false);		/* isAod */
	AParcel_writeInt64(in, time);
	AParcel_writeInt64(in, start);		/* gestureStart */
	parcelable_close(in, p);
}

static AIBinder *find(const char *instance, const AIBinder_Class *clazz)
{
	AIBinder *binder = AServiceManager_waitForService(instance);

	if (!binder || !AIBinder_associateClass(binder, clazz)) {
		say("no %s", instance);
		exit(1);
	}
	return binder;
}

/* Sensor location from getSensorProps(): SensorProps[] -> the first one's
 * sensorLocations[0] {displayId, x, y, radius, display, shape}. Anything
 * unexpected keeps the defaults. */
static void sensor_props(AIBinder *fingerprint)
{
	AParcel *out = call(fingerprint, FP_GET_SENSOR_PROPS, begin(fingerprint),
			    "getSensorProps");
	int32_t count = 0, end, common_end, type, locations = 0, loc_end;
	int32_t display, x, y, r;

	if (!out)
		return;
	if (AParcel_readInt32(out, &count) != STATUS_OK || count < 1)
		goto out;
	end = parcelable_begin(out);		/* SensorProps */
	common_end = parcelable_begin(out);	/* CommonProps */
	if (end < 0 || common_end < 0)
		goto out;
	AParcel_setDataPosition(out, common_end);
	AParcel_readInt32(out, &type);		/* FingerprintSensorType (byte) */
	if (AParcel_readInt32(out, &locations) != STATUS_OK || locations < 1)
		goto out;
	loc_end = parcelable_begin(out);
	if (loc_end < 0 || loc_end > end)
		goto out;
	AParcel_readInt32(out, &display);
	AParcel_readInt32(out, &x);
	AParcel_readInt32(out, &y);
	AParcel_readInt32(out, &r);
	if (x > 0 && x < panel_w && y > 0 && y < panel_h && r > 10 && r < 400) {
		sensor_x = x;
		sensor_y = y;
		sensor_r = r;
	} else {
		say("getSensorProps: odd location (%d, %d) r %d, kept the defaults", x, y, r);
	}
	say("sensor: type %d at (%d, %d), radius %d", type, sensor_x, sensor_y, sensor_r);
out:
	AParcel_delete(out);
}

static void open_session(void)
{
	AIBinder *fingerprint = find(FINGERPRINT "/default", fingerprint_class), *cb;
	AParcel *in, *out;

	sensor_props(fingerprint);
	cb = AIBinder_new(callback_class, NULL);
	AIBinder_markVintfStability(cb);
	in = begin(fingerprint);
	AParcel_writeInt32(in, 0);		/* sensorId */
	AParcel_writeInt32(in, 0);		/* userId */
	AParcel_writeStrongBinder(in, cb);
	out = call(fingerprint, FP_CREATE_SESSION, in, "createSession");
	if (!out || AParcel_readStrongBinder(out, &session) != STATUS_OK || !session ||
	    !AIBinder_associateClass(session, session_class)) {
		say("no session");
		exit(1);
	}
	AParcel_delete(out);
	say("session open");
}

static void take_cancel_signal(AParcel *out)
{
	cancel_signal = NULL;
	if (AParcel_readStrongBinder(out, &cancel_signal) == STATUS_OK && cancel_signal)
		AIBinder_associateClass(cancel_signal, cancel_class);
	AParcel_delete(out);
}

static void cancel_operation(void)
{
	if (!cancel_signal)
		return;
	call_oneway(cancel_signal, CANCEL, begin(cancel_signal), "cancel");
}

static void drop_cancel_signal(void)
{
	if (cancel_signal)
		AIBinder_decStrong(cancel_signal);
	cancel_signal = NULL;
}

/* Waits for one of CODES from the HAL, discarding others (used only while
 * no capture runs: no touches to handle). Returns the code or 0. */
static int32_t wait_for(int timeout_ms, const int32_t *codes, size_t count, struct event *got)
{
	int64_t deadline = now_ms() + timeout_ms;

	for (;;) {
		struct pollfd fd = { events[0], POLLIN, 0 };
		int64_t left = deadline - now_ms();
		struct event e;

		if (left <= 0)
			return 0;
		if (poll(&fd, 1, (int)left) <= 0)
			continue;
		if (read(events[0], &e, sizeof(e)) != sizeof(e))
			continue;
		for (size_t i = 0; i < count; i++)
			if (e.code == codes[i]) {
				if (got)
					*got = e;
				return e.code;
			}
	}
}

/* --- the auth-token key and Gatekeeper --- */

/* Keystore's job at boot: Trusty KeyMint, Gatekeeper and the fingerprint TA
 * agree on the HMAC key of auth tokens. Until then the TA refuses every
 * token. Only Trusty's KeyMint takes part (stock adds the Titan M2). */
static bool shared_secret(void)
{
	AIBinder *ss = find(SHARED_SECRET "/default", shared_secret_class);
	struct bytes seed, nonce, check;
	AParcel *in, *out;
	int32_t start;

	out = call(ss, SS_GET_PARAMETERS, begin(ss), "getSharedSecretParameters");
	if (!out)
		return false;
	if (parcelable_begin(out) < 0 || !read_bytes(out, &seed) || !read_bytes(out, &nonce)) {
		say("getSharedSecretParameters: bad reply");
		AParcel_delete(out);
		return false;
	}
	AParcel_delete(out);
	in = begin(ss);
	AParcel_writeInt32(in, 1);		/* one participant */
	start = parcelable_open(in);
	AParcel_writeByteArray(in, seed.data, seed.length);
	AParcel_writeByteArray(in, nonce.data, nonce.length);
	parcelable_close(in, start);
	out = call(ss, SS_COMPUTE, in, "computeSharedSecret");
	if (!out)
		return false;
	read_bytes(out, &check);
	AParcel_delete(out);
	say("auth-token key agreed");
	return check.length > 0;
}

static char path_secret[256], path_handle[256];

static int read_file(const char *path, void *buf, size_t size)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC), n;

	if (fd < 0)
		return -1;
	n = read(fd, buf, size);
	close(fd);
	return n;
}

static bool write_file(const char *path, const void *buf, size_t size)
{
	char tmp[300];
	int fd;
	bool ok;

	snprintf(tmp, sizeof(tmp), "%s.new", path);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (fd < 0)
		return false;
	ok = write(fd, buf, size) == (ssize_t)size && !fsync(fd);
	ok = !close(fd) && ok;
	return ok && !rename(tmp, path);
}

/* The bridge's Gatekeeper secret: 32 random bytes, made once. */
static bool load_secret(struct bytes *secret)
{
	int fd;

	secret->length = read_file(path_secret, secret->data, 32);
	if (secret->length == 32)
		return true;
	fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
	if (fd < 0 || read(fd, secret->data, 32) != 32) {
		if (fd >= 0)
			close(fd);
		return false;
	}
	close(fd);
	secret->length = 32;
	return write_file(path_secret, secret->data, 32);
}

/* Enrolls the secret for user 0 once (the handle is kept). */
static bool gk_enroll(const struct bytes *secret, struct bytes *handle)
{
	AIBinder *gk = find(GATEKEEPER "/default", gatekeeper_class);
	int32_t status = -1, timeout = 0;
	int64_t sid = 0;
	AParcel *in = begin(gk), *out;

	static const int8_t none[1];

	/*
	 * IGatekeeper's arrays are not @nullable: "no current handle or
	 * password" is an empty array. A null one (length -1) fails the call
	 * with UNEXPECTED_NULL before it reaches Trusty.
	 */
	AParcel_writeInt32(in, 0);			/* uid */
	AParcel_writeByteArray(in, none, 0);		/* no current handle */
	AParcel_writeByteArray(in, none, 0);		/* no current password */
	AParcel_writeByteArray(in, secret->data, secret->length);
	out = call(gk, GK_ENROLL, in, "gatekeeper enroll");
	if (!out)
		return false;
	if (parcelable_begin(out) >= 0) {
		AParcel_readInt32(out, &status);
		AParcel_readInt32(out, &timeout);
		AParcel_readInt64(out, &sid);
		read_bytes(out, handle);
	}
	AParcel_delete(out);
	if (status != GK_STATUS_OK || handle->length <= 0) {
		say("gatekeeper enroll: status %d", status);
		return false;
	}
	if (!write_file(path_handle, handle->data, handle->length)) {
		say("gatekeeper enroll: cannot save the handle");
		return false;
	}
	say("gatekeeper: enrolled");
	return true;
}

/* An auth token for CHALLENGE from Gatekeeper. */
static bool gk_token(int64_t challenge, struct hat *hat)
{
	AIBinder *gk = find(GATEKEEPER "/default", gatekeeper_class);
	struct bytes secret, handle;
	int32_t status = -1, timeout = 0;
	AParcel *in, *out;
	bool ok;

	if (!load_secret(&secret)) {
		say("no gatekeeper secret");
		return false;
	}
	handle.length = read_file(path_handle, handle.data, sizeof(handle.data));
	if (handle.length <= 0 && !gk_enroll(&secret, &handle))
		return false;
	in = begin(gk);
	AParcel_writeInt32(in, 0);
	AParcel_writeInt64(in, challenge);
	AParcel_writeByteArray(in, handle.data, handle.length);
	AParcel_writeByteArray(in, secret.data, secret.length);
	out = call(gk, GK_VERIFY, in, "gatekeeper verify");
	if (!out)
		return false;
	ok = parcelable_begin(out) >= 0;
	AParcel_readInt32(out, &status);
	AParcel_readInt32(out, &timeout);
	ok = ok && read_hat(out, hat);
	AParcel_delete(out);
	if (status != GK_STATUS_OK && status != GK_STATUS_REENROLL)
		say("gatekeeper verify: status %d, timeout %d ms", status, timeout);
	return ok && (status == GK_STATUS_OK || status == GK_STATUS_REENROLL);
}

/* --- the client --- */

static int listen_fd = -1, client_fd = -1;
static char client_buf[256];
static size_t client_used;

/*
 * What the desktop is told beyond the operation (publish()): the last
 * acquired hint, the enrollment steps left and how the last operation ended,
 * with a counter that moves on every such event, so a repeated hint still
 * reads as new. Taken from the lines the client gets, so both always agree.
 */
static unsigned int ui_seq;
static int32_t ui_acquired, ui_remaining = -1, ui_error;
static char ui_last[16] = "none";

static void ui_note(const char *line)
{
	int32_t a, b;

	if (!strcmp(line, "FINGER NEEDED")) {	/* an ENROLL or AUTH started */
		ui_acquired = 0;
		ui_remaining = -1;
		ui_error = 0;
		strcpy(ui_last, "none");
	} else if (sscanf(line, "ACQUIRED %d %d", &a, &b) == 2) {
		ui_acquired = a;
	} else if (sscanf(line, "PROGRESS %d %d", &a, &b) == 2) {
		ui_remaining = b;
	} else if (!strncmp(line, "ENROLLED ", 9)) {
		strcpy(ui_last, "enrolled");
	} else if (!strncmp(line, "MATCH ", 6)) {
		strcpy(ui_last, "match");
	} else if (!strcmp(line, "NOMATCH")) {
		strcpy(ui_last, "nomatch");
	} else if (!strncmp(line, "LOCKOUT ", 8)) {
		strcpy(ui_last, "lockout");
	} else if (sscanf(line, "ERROR %d", &a) == 1) {
		ui_error = a;
		strcpy(ui_last, "error");
	} else {
		return;
	}
	ui_seq++;
}

static void reply(const char *format, ...)
{
	char line[256];
	va_list args;
	int n;

	va_start(args, format);
	n = vsnprintf(line, sizeof(line) - 1, format, args);
	va_end(args);
	if (n < 0)
		return;
	if (n > (int)sizeof(line) - 2)
		n = sizeof(line) - 2;
	say("-> %.*s", n, line);
	line[n] = '\0';
	ui_note(line);
	line[n++] = '\n';
	if (client_fd >= 0 && send(client_fd, line, n, MSG_NOSIGNAL) != n) {
		close(client_fd);
		client_fd = -1;
	}
}

/* --- the touchscreen and the circle --- */

static int touch_fd = -1;
static int32_t touch_x = -1, touch_y = -1, touch_slot, touch_tracking = -1;
static int32_t ignored_tracking = -1;	/* a contact that began while inhibited */
/* A contact that has been on the sensor and is not lifted yet, captured or
 * not: published, so the desktop can keep a touch that unlocked the phone
 * from going on as a long press on the wallpaper. */
static bool sensor_contact;
static bool finger;		/* the HAL was told a finger is down */
static int64_t finger_since, lhbm_at;
static bool lhbm_lit;

static void lhbm(bool on)
{
	int fd = open(lhbm_path, O_WRONLY | O_CLOEXEC);
	bool ok = fd >= 0 && write(fd, on ? "1" : "0", 1) == 1;

	if (!ok && on)
		say("LHBM on refused (%s): screen dark, brightness 0 or allow_lhbm=0?",
		    strerror(errno));
	if (fd >= 0)
		close(fd);
	lhbm_lit = on && ok;
	lhbm_at = now_ms();
}

static void pointer(bool down)
{
	AParcel *in = begin(session);
	int64_t time = now_ms();

	if (down)
		finger_since = time;
	write_pointer(in, touch_x, touch_y, time, finger_since);
	if (down) {
		reply("FINGER DOWN");
		call_void(session, S_ON_POINTER_DOWN_WITH_CONTEXT, in, "onPointerDown");
		lhbm(true);
		if (lhbm_lit)
			usleep(lhbm_settle_ms * 1000);
		call_void(session, S_ON_UI_READY, begin(session), "onUiReady");
	} else {
		call_void(session, S_ON_POINTER_UP_WITH_CONTEXT, in, "onPointerUp");
		lhbm(false);
		reply("FINGER UP");
	}
	finger = down;
}

/*
 * The desktop's on-screen keyboard can cover the sensor (on the lock screen
 * a password is typed while the fingerprint conversation runs): its keys
 * there are not a finger on the sensor. While it is up the shell keeps a
 * file fresh in --inhibit DIR (omamobile-shell, osk-<user>); touches that
 * start then get no LHBM, no pointer events and so no capture or failed
 * attempt. A file older than INHIBIT_FRESH_S is stale (a shell that died).
 * Anyone who can write DIR can only turn fingerprint captures off, never
 * on: the PIN still unlocks.
 */
static bool inhibited(void)
{
	static int64_t checked_at = -1000;
	static bool cached;
	int64_t now_check = now_ms();
	struct dirent *entry;
	struct stat st;
	time_t now;
	DIR *dir;

	if (!inhibit_dir)
		return false;
	if (now_check - checked_at < 250)
		return cached;
	checked_at = now_check;
	cached = false;
	dir = opendir(inhibit_dir);
	if (!dir)
		return false;
	now = time(NULL);
	while ((entry = readdir(dir))) {
		if (entry->d_name[0] == '.')
			continue;
		if (fstatat(dirfd(dir), entry->d_name, &st, AT_SYMLINK_NOFOLLOW) ||
		    !S_ISREG(st.st_mode))
			continue;
		if (st.st_mtime <= now + INHIBIT_FRESH_S &&
		    now - st.st_mtime <= INHIBIT_FRESH_S) {
			cached = true;
			break;
		}
	}
	closedir(dir);
	return cached;
}

/* evdev, multitouch protocol B; slot 0's finger only. */
struct input_event_ {
	int64_t sec, usec;
	uint16_t type, code;
	int32_t value;
};

#define EV_SYN_			0
#define EV_ABS_			3
#define ABS_MT_SLOT_		0x2f
#define ABS_MT_POSITION_X_	0x35
#define ABS_MT_POSITION_Y_	0x36
#define ABS_MT_TRACKING_ID_	0x39

/*
 * The touchscreen's own coordinate range: a touchscreen may report finer
 * than the panel's pixels (the Pixel 9a's reports ten times finer), so
 * positions are scaled to the panel before they meet the sensor location.
 */
struct input_absinfo_ {
	int32_t value, minimum, maximum, fuzz, flat, resolution;
};
#define EVIOCGABS_(abs)	_IOR('E', 0x40 + (abs), struct input_absinfo_)
static int32_t touch_max_x, touch_max_y;	/* 0: unknown, no scaling */

static void touch_range(void)
{
	struct input_absinfo_ info;

	if (!ioctl(touch_fd, EVIOCGABS_(ABS_MT_POSITION_X_), &info))
		touch_max_x = info.maximum;
	if (!ioctl(touch_fd, EVIOCGABS_(ABS_MT_POSITION_Y_), &info))
		touch_max_y = info.maximum;
	say("touchscreen range %d x %d for a %d x %d panel", touch_max_x + 1, touch_max_y + 1,
	    panel_w, panel_h);
}

static int32_t scale(int32_t v, int32_t max, int32_t panel)
{
	return max > 0 ? (int32_t)((int64_t)v * panel / (max + 1)) : v;
}

static void touch_events(bool capturing)
{
	struct input_event_ ev[32];
	ssize_t n = read(touch_fd, ev, sizeof(ev));

	for (ssize_t i = 0; i < n / (ssize_t)sizeof(*ev); i++) {
		if (ev[i].type == EV_ABS_) {
			if (ev[i].code == ABS_MT_SLOT_)
				touch_slot = ev[i].value;
			else if (touch_slot)
				continue;
			else if (ev[i].code == ABS_MT_POSITION_X_)
				touch_x = ev[i].value;
			else if (ev[i].code == ABS_MT_POSITION_Y_)
				touch_y = ev[i].value;
			else if (ev[i].code == ABS_MT_TRACKING_ID_)
				touch_tracking = ev[i].value;
		} else if (ev[i].type == EV_SYN_ && ev[i].code == 0) {
			int64_t dx = scale(touch_x, touch_max_x, panel_w) - sensor_x;
			int64_t dy = scale(touch_y, touch_max_y, panel_h) - sensor_y;
			int64_t r = sensor_r * 3 / 2;	/* some slack at the rim */
			bool inside = dx * dx + dy * dy <= r * r;
			bool on = capturing && touch_tracking >= 0 && inside;

			sensor_contact = touch_tracking >= 0 && (sensor_contact || inside);

			/* the whole contact is a key on the on-screen keyboard */
			if (on && touch_tracking == ignored_tracking)
				on = false;
			if (on && !finger && inhibited()) {
				say("touch on the sensor ignored: the on-screen keyboard is up");
				ignored_tracking = touch_tracking;
				on = false;
			}
			if (on != finger)
				pointer(on);
		}
	}
}

/* --- operations --- */

enum op { OP_NONE, OP_ENROLL, OP_AUTH, OP_LIST, OP_DELETE };
static enum op op;
static bool op_ending;		/* cancel sent, waiting for the HAL's end */
static bool ending_reply;	/* report the end as ERROR 5 (CANCEL asked) */
static int64_t op_ending_since;
static int32_t enrolled_id;
static int64_t enroll_challenge;	/* revoked when the enrollment ends */
static char pending[64];	/* a command that waits for op_ending */

static bool capturing(void)
{
	return (op == OP_ENROLL || op == OP_AUTH) && !op_ending;
}

/*
 * The desktop's view of the bridge (--ui-state): written whenever it
 * changes, as a whole new file renamed over the old one, so a reader never
 * sees half of it. World-readable: it holds nothing but the sensor's place
 * and whether a capture runs.
 */
static void publish(void)
{
	static char last[300];
	char line[300], tmp[300];
	const char *what = !capturing() ? "idle" : op == OP_ENROLL ? "enroll" : "auth";
	int fd, n;
	bool ok;

	if (!ui_state_path)
		return;
	n = snprintf(line, sizeof(line),
		     "{\"op\":\"%s\",\"finger\":%s,\"x\":%d,\"y\":%d,\"r\":%d,"
		     "\"w\":%d,\"h\":%d,\"seq\":%u,\"acquired\":%d,\"remaining\":%d,"
		     "\"error\":%d,\"last\":\"%s\",\"contact\":%s}\n",
		     what, finger && capturing() ? "true" : "false",
		     sensor_x, sensor_y, sensor_r, panel_w, panel_h,
		     ui_seq, ui_acquired, ui_remaining, ui_error, ui_last,
		     sensor_contact ? "true" : "false");
	if (n < 0 || n >= (int)sizeof(line) || !strcmp(line, last))
		return;
	snprintf(tmp, sizeof(tmp), "%s.new", ui_state_path);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) {
		say("ui state: %s: %s", tmp, strerror(errno));
		ui_state_path = NULL;	/* say it once */
		return;
	}
	ok = !fchmod(fd, 0644) && write(fd, line, n) == n;
	ok = !close(fd) && ok;
	if (ok && !rename(tmp, ui_state_path))
		strcpy(last, line);
	else
		unlink(tmp);
}

static void op_done(void)
{
	if (finger)
		pointer(false);
	if (lhbm_lit)
		lhbm(false);
	drop_cancel_signal();
	if (op == OP_ENROLL) {
		AParcel *in = begin(session);

		/* as FingerprintService: the challenge is single-use */
		AParcel_writeInt64(in, enroll_challenge);
		call_void(session, S_REVOKE_CHALLENGE, in, "revokeChallenge");
	}
	op = OP_NONE;
	op_ending = false;
	ending_reply = false;
}

/* Cancel a capture; REPORT: answer ERROR 5 when it has ended. */
static void end_capture(bool report)
{
	if (op != OP_ENROLL && op != OP_AUTH)
		return;
	ending_reply = ending_reply || report;
	if (op_ending)
		return;
	cancel_operation();
	op_ending = true;
	op_ending_since = now_ms();
}

static void start_enroll(void)
{
	static const int32_t challenge[] = { CB_CHALLENGE_GENERATED, CB_ERROR };
	struct event e = { 0 };
	struct hat hat;
	AParcel *in, *out;

	if (!call_void(session, S_GENERATE_CHALLENGE, begin(session), "generateChallenge") ||
	    wait_for(3000, challenge, 2, &e) != CB_CHALLENGE_GENERATED) {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	if (!gk_token(e.c, &hat)) {
		in = begin(session);
		AParcel_writeInt64(in, e.c);
		call_void(session, S_REVOKE_CHALLENGE, in, "revokeChallenge");
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	in = begin(session);
	write_hat(in, &hat);
	out = call(session, S_ENROLL, in, "enroll");
	if (!out) {
		in = begin(session);
		AParcel_writeInt64(in, e.c);
		call_void(session, S_REVOKE_CHALLENGE, in, "revokeChallenge");
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	take_cancel_signal(out);
	op = OP_ENROLL;
	enrolled_id = 0;
	enroll_challenge = e.c;
	reply("FINGER NEEDED");
}

static void start_auth(void)
{
	AParcel *in = begin(session), *out;

	AParcel_writeInt64(in, 0);		/* operationId: an unlock, no crypto op */
	out = call(session, S_AUTHENTICATE, in, "authenticate");
	if (!out) {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	take_cancel_signal(out);
	op = OP_AUTH;
	reply("FINGER NEEDED");
}

/* resetLockout needs a fresh auth token; ours comes from Gatekeeper with
 * the bridge's own secret. Only root can ask (the socket), and only after
 * the user unlocked with the password (FINGERPRINT-PLAN, section 5). */
static void reset_lockout(void)
{
	static const int32_t challenge[] = { CB_CHALLENGE_GENERATED, CB_ERROR };
	static const int32_t cleared[] = { CB_LOCKOUT_CLEARED, CB_ERROR };
	struct event e = { 0 };
	struct hat hat;
	AParcel *in;

	if (!call_void(session, S_GENERATE_CHALLENGE, begin(session), "generateChallenge") ||
	    wait_for(3000, challenge, 2, &e) != CB_CHALLENGE_GENERATED ||
	    !gk_token(e.c, &hat)) {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	in = begin(session);
	write_hat(in, &hat);
	if (!call_void(session, S_RESET_LOCKOUT, in, "resetLockout") ||
	    wait_for(3000, cleared, 2, NULL) != CB_LOCKOUT_CLEARED) {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	in = begin(session);
	AParcel_writeInt64(in, e.c);
	call_void(session, S_REVOKE_CHALLENGE, in, "revokeChallenge");
	reply("OK");
}

static void command(const char *line)
{
	int32_t id;

	say("<- %s", line);
	if (!strcmp(line, "CANCEL")) {
		pending[0] = '\0';
		if (op == OP_ENROLL || op == OP_AUTH)
			end_capture(true);
		else if (op == OP_NONE)
			reply("ERROR %d", ERR_CANCELED);
		return;
	}
	if (op != OP_NONE) {
		if (op_ending && strlen(line) < sizeof(pending)) {
			strcpy(pending, line);	/* runs once the HAL has ended the last one */
			return;
		}
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	if (!strcmp(line, "ENROLL")) {
		start_enroll();
	} else if (!strcmp(line, "AUTH")) {
		start_auth();
	} else if (!strcmp(line, "LIST")) {
		if (call_void(session, S_ENUMERATE_ENROLLMENTS, begin(session),
			      "enumerateEnrollments"))
			op = OP_LIST;
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	} else if (sscanf(line, "DELETE %d", &id) == 1) {
		AParcel *in = begin(session);

		AParcel_writeInt32Array(in, &id, 1);
		if (call_void(session, S_REMOVE_ENROLLMENTS, in, "removeEnrollments"))
			op = OP_DELETE;
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	} else if (!strcmp(line, "RESETLOCKOUT")) {
		reset_lockout();
	} else if (!strcmp(line, "STATUS")) {
		reply("READY %d %d %d", sensor_x, sensor_y, sensor_r);
		reply("OK");
	} else {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	}
}

static void hal_event(const struct event *e)
{
	char list[200];
	size_t n = 0;

	switch (e->code) {
	case CB_ACQUIRED:
		if (capturing())
			reply("ACQUIRED %d %d", e->a, e->b);
		return;
	case CB_ENROLLMENT_PROGRESS:
		if (op != OP_ENROLL)
			return;
		enrolled_id = e->a;
		reply("PROGRESS %d %d", e->a, e->b);
		if (e->b == 0) {
			reply("ENROLLED %d", e->a);
			op_done();
		}
		return;
	case CB_AUTHENTICATION_SUCCEEDED:
		if (op != OP_AUTH)
			return;
		/*
		 * A match that lands after our cancel (the finger down as the
		 * client's wait ran out) ends the operation; the HAL's ERROR 5
		 * then comes with op NONE and is dropped. Answer the CANCEL
		 * here, or the client waits for it forever (fprintd kept the
		 * device claimed and every later Claim failed).
		 */
		if (!op_ending)
			reply("MATCH %d", e->a);
		else if (ending_reply)
			reply("ERROR %d", ERR_CANCELED);
		op_done();
		return;
	case CB_AUTHENTICATION_FAILED:
		/* the HAL keeps capturing; the client decides on retries */
		if (op == OP_AUTH && !op_ending) {
			reply("NOMATCH");
			end_capture(false);
		}
		return;
	case CB_LOCKOUT_TIMED:
	case CB_LOCKOUT_PERMANENT:
		if (op == OP_AUTH || op == OP_ENROLL) {
			if (!op_ending)
				reply("LOCKOUT %lld", e->code == CB_LOCKOUT_TIMED ?
				      (long long)e->c : -1LL);
			else if (ending_reply)
				reply("ERROR %d", ERR_CANCELED);	/* as above */
			op_done();
		}
		return;
	case CB_ERROR:
		say("HAL error %d (vendor %d)", e->a, e->b);
		if (op == OP_NONE)
			return;
		/* a cancel we sent: report it only if the client asked for it */
		if (!op_ending || e->a != ERR_CANCELED || ending_reply)
			reply("ERROR %d", e->a);
		op_done();
		return;
	case CB_ENROLLMENTS_ENUMERATED:
		if (op != OP_LIST)
			return;
		for (int32_t i = 0; i < e->count && n < sizeof(list) - 12; i++)
			n += snprintf(list + n, sizeof(list) - n, " %d", e->ids[i]);
		list[n] = '\0';
		reply("LIST%s", list);
		op_done();
		return;
	case CB_ENROLLMENTS_REMOVED:
		if (op != OP_DELETE)
			return;
		if (e->count > 0)
			reply("DELETED %d", e->ids[0]);
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		op_done();
		return;
	case CB_SESSION_CLOSED:
		say("the HAL closed the session");
		exit(3);
	default:
		return;
	}
}

static void new_client(void)
{
	int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC);

	if (fd < 0)
		return;
	if (client_fd >= 0) {
		say("new client: dropping the old one");
		close(client_fd);
		end_capture(false);
		pending[0] = '\0';
	}
	client_fd = fd;
	client_used = 0;
	reply("READY %d %d %d", sensor_x, sensor_y, sensor_r);
}

static void client_input(void)
{
	ssize_t n = recv(client_fd, client_buf + client_used,
			 sizeof(client_buf) - 1 - client_used, 0);
	char *line, *nl;

	if (n <= 0) {
		close(client_fd);
		client_fd = -1;
		pending[0] = '\0';
		end_capture(false);
		return;
	}
	client_used += n;
	client_buf[client_used] = '\0';
	line = client_buf;
	while ((nl = strchr(line, '\n'))) {
		*nl = '\0';
		if (nl > line && nl[-1] == '\r')
			nl[-1] = '\0';
		if (*line)
			command(line);
		line = nl + 1;
	}
	client_used = strlen(line);
	memmove(client_buf, line, client_used);
	if (client_used == sizeof(client_buf) - 1)
		client_used = 0;	/* overlong line: drop it */
}

static int open_listener(void)
{
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	int fd;

	if (strlen(socket_path) >= sizeof(addr.sun_path))
		return -1;
	strcpy(addr.sun_path, socket_path);
	unlink(socket_path);
	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	umask(0077);
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || chmod(socket_path, 0600) ||
	    listen(fd, 2)) {
		close(fd);
		return -1;
	}
	return fd;
}

static void usage(void)
{
	say("usage: omamobile-fp-bridge [--socket PATH] [--state DIR] [--touch EVDEV]\n"
	    "                           [--lhbm PATH] [--settle MS] [--ui-state PATH]\n"
	    "                           [--inhibit DIR] [--panel WxH]");
	exit(2);
}

int main(int argc, char **argv, char **envp)
{
	(void)envp;
	for (int i = 1; i < argc; i += 2) {
		const char *v = i + 1 < argc ? argv[i + 1] : NULL;

		if (!v)
			usage();
		if (!strcmp(argv[i], "--socket"))
			socket_path = v;
		else if (!strcmp(argv[i], "--state"))
			state_dir = v;
		else if (!strcmp(argv[i], "--touch"))
			touch_path = v;
		else if (!strcmp(argv[i], "--lhbm"))
			lhbm_path = v;
		else if (!strcmp(argv[i], "--settle"))
			lhbm_settle_ms = atoi(v);
		else if (!strcmp(argv[i], "--ui-state"))
			ui_state_path = v;
		else if (!strcmp(argv[i], "--inhibit"))
			inhibit_dir = v;
		else if (!strcmp(argv[i], "--panel")) {
			if (sscanf(v, "%dx%d", &panel_w, &panel_h) != 2 ||
			    panel_w < 100 || panel_h < 100)
				usage();
		} else
			usage();
	}
	signal(SIGPIPE, SIG_IGN);
	snprintf(path_secret, sizeof(path_secret), "%s/secret", state_dir);
	snprintf(path_handle, sizeof(path_handle), "%s/gatekeeper-handle", state_dir);
	mkdir(state_dir, 0700);

	if (pipe2(events, O_CLOEXEC)) {
		say("pipe: %s", strerror(errno));
		return 1;
	}
	fingerprint_class = AIBinder_Class_define(FINGERPRINT, no_data, no_destroy, not_local);
	session_class = AIBinder_Class_define(SESSION, no_data, no_destroy, not_local);
	cancel_class = AIBinder_Class_define(CANCELLATION, no_data, no_destroy, not_local);
	callback_class = AIBinder_Class_define(CALLBACK, no_data, no_destroy, callback);
	shared_secret_class = AIBinder_Class_define(SHARED_SECRET, no_data, no_destroy, not_local);
	gatekeeper_class = AIBinder_Class_define(GATEKEEPER, no_data, no_destroy, not_local);
	ABinderProcess_setThreadPoolMaxThreadCount(1);
	ABinderProcess_startThreadPool();

	if (!shared_secret())
		say("warning: no auth-token key; enrollment will be refused");
	open_session();

	touch_fd = open(touch_path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (touch_fd < 0)
		say("no touchscreen at %s (%s): captures will not start", touch_path,
		    strerror(errno));
	else
		touch_range();
	listen_fd = open_listener();
	if (listen_fd < 0) {
		say("cannot listen on %s: %s", socket_path, strerror(errno));
		return 1;
	}
	say("ready on %s", socket_path);
	publish();

	for (;;) {
		struct pollfd fds[4] = {
			{ events[0], POLLIN, 0 }, { listen_fd, POLLIN, 0 },
			{ client_fd, POLLIN, 0 }, { touch_fd, POLLIN, 0 },
		};
		int timeout = 500;
		struct event e;

		if (poll(fds, 4, timeout) < 0 && errno != EINTR)
			return 1;
		if (fds[0].revents & POLLIN && read(events[0], &e, sizeof(e)) == sizeof(e))
			hal_event(&e);
		if (fds[3].revents & POLLIN)
			touch_events(capturing());
		if (fds[1].revents & POLLIN)
			new_client();
		if (client_fd >= 0 && fds[2].revents & (POLLIN | POLLHUP | POLLERR))
			client_input();
		/* the finger still down: keep the circle lit past the panel's cap */
		if (finger && lhbm_lit && now_ms() - lhbm_at > LHBM_REFRESH_MS)
			lhbm(true);
		/* a cancel the HAL never answered */
		if (op_ending && now_ms() - op_ending_since > 3000) {
			say("no answer to cancel");
			if (ending_reply)
				reply("ERROR %d", ERR_CANCELED);
			op_done();
		}
		if (op == OP_NONE && pending[0]) {
			char line[sizeof(pending)];

			strcpy(line, pending);
			pending[0] = '\0';
			command(line);
		}
		publish();
	}
}
