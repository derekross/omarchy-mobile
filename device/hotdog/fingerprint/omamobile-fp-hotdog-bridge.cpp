// SPDX-License-Identifier: MIT
/*
 * omamobile-fp-hotdog-bridge: the client of OnePlus's Goodix fingerprint
 * HAL in the OnePlus 7T Pro (hotdog) fingerprint chroot
 * (device/hotdog/FINGERPRINT-PLAN.md). In use on the owner's phone since
 * 2026-11-04 (FINGERPRINT-PLAN.md section 7).
 *
 * It serves exactly the line protocol and the --ui-state file of the Pixel
 * bridge (fingerprint/bridge/omamobile-fp-bridge.c), so libfprint's
 * omamobile_udfps driver (fprintd) and omamobile-shell's
 * omamobile.fingerprint plugin work unchanged:
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
 *      ERROR <code>                        the operation ended (5: canceled)
 *      OK                                  RESETLOCKOUT, STATUS done
 *
 * ACQUIRED and ERROR codes are the AIDL ones the protocol has always
 * carried (android.hardware.biometrics.fingerprint AcquiredInfo, Error);
 * the HIDL 2.1 values are mapped (acquired_code(), below).
 *
 * The HAL is HIDL android.hardware.biometrics.fingerprint@2.1
 * IBiometricsFingerprint/default, as an Android 10/11 vendor serves it. On
 * Android, FingerprintService, keystore and SystemUI drive it. Here:
 *
 *  - setNotify() once, setActiveGroup(0, --state DIR) once;
 *  - ENROLL: preEnroll() for a challenge, a hw_auth_token for it (see
 *    --hat-mode), enroll(hat, 0, 60), postEnroll() at the end;
 *  - AUTH: authenticate(0, 0); a rejected finger (onAuthenticated with
 *    fingerId 0) answers NOMATCH and cancels, as the Pixel bridge does;
 *  - LIST: enumerate(), collected until remaining reaches 0;
 *  - DELETE: remove(0, id);
 *  - CANCEL: cancel(); the HAL answers ERROR_CANCELED.
 *
 * The under-display sensor is optical: it sees a finger only while the
 * panel lights it. HIDL 2.1 has no onPointerDown or onUiReady, so the
 * OnePlus HAL learns both from the kernel, as netlink events of
 * /dev/goodix_fp (stock: the touch driver and the display driver raised
 * them). Our kernel's goodix-fp driver sends them when its sysfs attribute
 * "notify" is written (touchdown, touchup, ui_ready, fb_black,
 * fb_unblack). So the bridge reads the touchscreen while a capture runs,
 * and for a finger inside the sensor circle:
 *
 *   notify touchdown -> panel hbm 1 -> --hbm-settle-ms -> notify ui_ready
 *
 * (--hbm-first 1: hbm, settle, touchdown, ui_ready), and on lift: notify
 * touchup, hbm 0. The panel's HBM is global, the whole panel's high
 * brightness (the stock "hbm-on-command-5"); the shell draws the bright
 * target from the ui-state file. VERIFY in the owner's HAL that it waits
 * for touchdown and ui_ready and in which order (FINGERPRINT-PLAN).
 *
 * HBM is never left on: the bridge turns it off at start, at every
 * operation's end, at a client's disconnect and at SIGTERM/SIGINT, and the
 * panel driver turns it off by itself 3 s after the last write (the bridge
 * refreshes it every 2 s while the finger stays).
 *
 * The hw_auth_token (--hat-mode), enroll()'s proof that the user just
 * confirmed their credential. On Android Gatekeeper signs it with the
 * auth-token key of QSEE's keymaster app, and OnePlus's HAL hands that
 * key to the fingerprint TA at start (fetchHmacKeyFromKeyMaster,
 * sendHmacKey), so the TA checks the HMAC:
 *
 *  - gatekeeper (default): QSEE's Gatekeeper signs it (gk_token(), below);
 *    the key itself never leaves QSEE (keymaster hands it to the TA only
 *    encapsulated, 152 bytes). The desktop's own unlock (fprintd's enroll
 *    needs the user's session) stands in for the password Gatekeeper
 *    would have checked on Android.
 *  - zero: the same token with an all-zero HMAC, for a TA that does not
 *    check it.
 *
 * RESETLOCKOUT: HIDL 2.1 has no resetLockout; the HAL's timed lockout
 * (ERROR_LOCKOUT, 30 s on AOSP) ends on its own. The bridge answers
 * "ERROR 2" so no client believes a lockout was cleared.
 *
 * One operation at a time; one client at a time (a new connection replaces
 * the old one and cancels its operation). The socket is root-only.
 *
 * Sensor circle: x 720, y 2700, r 110 in panel pixels of 1440x3120 are
 * PLACEHOLDERS. HIDL 2.1 cannot tell where the sensor is. Measure it in the
 * plan's calibration step and pass --sensor X,Y,R; until then a finger may
 * miss the sensor while the bridge thinks it is on it.
 *
 * No HIDL in the end: OnePlus's android.hardware.biometrics.fingerprint@2.1-
 * service is only a wrapper around the legacy HAL module (its
 * hw_get_module("goodix.fod"), open(module, NULL), version 0x201 and the
 * standard fingerprint_device_t offsets, read from its disassembly), so
 * the bridge loads hw/goodix.fod.msmnile.so itself and calls the same
 * functions in the same order; the "HIDL 2.1" calls above are its device
 * functions (pre_enroll, enroll, ...). No hwservicemanager, and no system
 * libc++ objects cross into the vendor's code, so the NDK builds it (its
 * static libc++) against the chroot's libc and libdl. The module's
 * callbacks come on the HAL's own threads, into the same event pipe.
 */

#include <dlfcn.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
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

/*
 * The legacy HAL ABI on arm64 (libhardware's hw_module_t/hw_device_t and
 * fingerprint.h, module API 2.1), written out here because the NDK has no
 * libhardware headers. Offsets: notify 0x78, set_notify 0x80 ... the
 * service calls set_notify at 0x80 and set_active_group at 0xc0.
 */
struct hw_module_t;
struct hw_device_t;
struct hw_module_methods_t {
	int (*open)(const struct hw_module_t *module, const char *id, struct hw_device_t **device);
};
struct hw_module_t {
	uint32_t tag;
	uint16_t module_api_version;
	uint16_t hal_api_version;
	const char *id;
	const char *name;
	const char *author;
	struct hw_module_methods_t *methods;
	void *dso;
	uint64_t reserved[32 - 7];
};
struct hw_device_t {
	uint32_t tag;
	uint32_t version;
	struct hw_module_t *module;
	uint64_t reserved[12];
	int (*close)(struct hw_device_t *device);
};
static_assert(sizeof(struct hw_device_t) == 0x78, "hw_device_t");

#define FINGERPRINT_MODULE_API_VERSION_2_1	0x201
#define HAT_SIZE	69

enum fp_msg_type {
	FP_ERROR = -1, FP_ACQUIRED = 1, FP_TEMPLATE_ENROLLING = 3, FP_TEMPLATE_REMOVED = 4,
	FP_AUTHENTICATED = 5, FP_TEMPLATE_ENUMERATING = 6,
};
#define FP_ERROR_VENDOR_BASE	1000
#define FP_ACQUIRED_VENDOR_BASE	1000
struct fp_finger_id { uint32_t gid, fid; };
struct fp_msg {
	int32_t type;
	union {
		int32_t error;
		struct { struct fp_finger_id finger; uint32_t samples_remaining; uint64_t msg; } enroll;
		struct { struct fp_finger_id finger; uint32_t remaining_templates; } iter;
		struct { int32_t acquired_info; } acquired;
		struct { struct fp_finger_id finger; uint8_t hat[HAT_SIZE]; } authenticated;
	} data;
};
typedef void (*fp_notify_t)(const struct fp_msg *msg);
struct fingerprint_device_t {
	struct hw_device_t common;
	fp_notify_t notify;
	int (*set_notify)(struct fingerprint_device_t *dev, fp_notify_t notify);
	uint64_t (*pre_enroll)(struct fingerprint_device_t *dev);
	int (*enroll)(struct fingerprint_device_t *dev, const uint8_t *hat, uint32_t gid,
		      uint32_t timeout_sec);
	int (*post_enroll)(struct fingerprint_device_t *dev);
	uint64_t (*get_authenticator_id)(struct fingerprint_device_t *dev);
	int (*cancel)(struct fingerprint_device_t *dev);
	int (*enumerate)(struct fingerprint_device_t *dev);
	int (*remove)(struct fingerprint_device_t *dev, uint32_t gid, uint32_t fid);
	int (*set_active_group)(struct fingerprint_device_t *dev, uint32_t gid, const char *path);
	int (*authenticate)(struct fingerprint_device_t *dev, uint64_t operation_id, uint32_t gid);
	void *reserved[4];
};
static_assert(offsetof(struct fingerprint_device_t, set_notify) == 0x80, "set_notify");
static_assert(offsetof(struct fingerprint_device_t, set_active_group) == 0xc0, "set_active_group");

static const char *module_path = "/vendor/lib64/hw/goodix.fod.msmnile.so";

/* The protocol's codes: android.hardware.biometrics.fingerprint (AIDL) Error */
#define ERR_HW_UNAVAILABLE	1
#define ERR_UNABLE_TO_PROCESS	2
#define ERR_TIMEOUT		3
#define ERR_CANCELED		5
#define ERR_VENDOR		7
/* HIDL 2.1 ERROR_LOCKOUT: AOSP's timed lockout */
#define LOCKOUT_MS		30000

/* --- configuration --- */

static const char *socket_path = "/dev/socket/omamobile-fp/bridge.sock";
static const char *state_dir = "/data/vendor/omamobile-fp";
static const char *touch_path = "/dev/input/touchscreen";
/* the runner binds the panel's and the sensor driver's attributes here */
static const char *hbm_path = "/sys/omamobile/hbm";
static const char *notify_path = "/sys/omamobile/fp_notify";
static const char *ui_state_path;	/* --ui-state: off unless given */
static const char *inhibit_dir;		/* --inhibit: off unless given */
#define INHIBIT_FRESH_S	15
/* From the HBM write to a lit frame: the panel's command takes a frame or
 * two at 60 Hz (stock waits 12-16 ms inside the sequence). Tuned in the
 * plan. */
static int hbm_settle_ms = 150;
/* --hbm-first 1: HBM before touchdown */
static bool hbm_first;
/* --illuminate 0|1: the panel has no LHBM, so the shell must draw the
 * light under the finger (a white disc, omamobile.fingerprint); default on */
static bool illuminate = true;
/* The panel driver turns HBM off 3 s after the last write. */
#define HBM_REFRESH_MS	2000
/* PLACEHOLDERS until the plan's calibration step (--sensor X,Y,R). */
static int32_t sensor_x = 720, sensor_y = 2700, sensor_r = 110;
static int32_t panel_w = 1440, panel_h = 3120;
enum hat_mode { HAT_ZERO, HAT_GATEKEEPER };
static enum hat_mode hat_mode = HAT_GATEKEEPER;
static uint32_t enroll_timeout_s = 60;

/* --- logging --- */

static void say(const char *format, ...) __attribute__((format(printf, 1, 2)));
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

/* --- callback events: hwbinder thread -> main loop --- */

enum ev_code {
	EV_ENROLL, EV_ACQUIRED, EV_AUTHENTICATED, EV_ERROR, EV_REMOVED, EV_ENUMERATE,
};

struct event {
	int32_t code;
	int32_t a, b, c;	/* per code, below */
};

static int events[2];

static void post(const struct event &e)
{
	(void)!write(events[1], &e, sizeof(e));
}

/* Legacy acquired_info -> AIDL AcquiredInfo (the protocol's): GOOD 0..
 * TOO_FAST 5 are AIDL 1..6; VENDOR_BASE + n is AIDL VENDOR 7, vendor n. */
static void acquired_code(int32_t v, int32_t *code, int32_t *vendor)
{
	*vendor = 0;
	if (v >= FP_ACQUIRED_VENDOR_BASE) {
		*code = 7;
		*vendor = v - FP_ACQUIRED_VENDOR_BASE;
	} else {
		*code = v >= 0 && v <= 5 ? v + 1 : 0;
	}
}

/* Legacy error -> AIDL Error, LOCKOUT apart (-1 here); the numbers 1-6
 * are the same, LOCKOUT is 7, VENDOR_BASE + n is a vendor error. */
static void error_code(int32_t error, int32_t *code, int32_t *vendor)
{
	*vendor = 0;
	if (error >= FP_ERROR_VENDOR_BASE) {
		*code = ERR_VENDOR;
		*vendor = error - FP_ERROR_VENDOR_BASE;
	} else if (error == 7) {
		*code = -1;
	} else {
		*code = error >= 1 && error <= 6 ? error : ERR_UNABLE_TO_PROCESS;
	}
}

/* The module's callback, on one of its threads. fid 0 on authenticated: a
 * finger that matched none. The token would unlock keystore keys on
 * Android; nothing here needs it. */
static void on_notify(const struct fp_msg *m)
{
	struct event e = {};

	switch (m->type) {
	case FP_TEMPLATE_ENROLLING:
		e = { EV_ENROLL, (int32_t)m->data.enroll.finger.fid,
		      (int32_t)m->data.enroll.samples_remaining, 0 };
		break;
	case FP_ACQUIRED:
		e.code = EV_ACQUIRED;
		acquired_code(m->data.acquired.acquired_info, &e.a, &e.b);
		break;
	case FP_AUTHENTICATED:
		e = { EV_AUTHENTICATED, (int32_t)m->data.authenticated.finger.fid, HAT_SIZE, 0 };
		break;
	case FP_ERROR:
		e.code = EV_ERROR;
		error_code(m->data.error, &e.a, &e.b);
		break;
	case FP_TEMPLATE_REMOVED:
		e = { EV_REMOVED, (int32_t)m->data.iter.finger.fid,
		      (int32_t)m->data.iter.remaining_templates, 0 };
		break;
	case FP_TEMPLATE_ENUMERATING:
		e = { EV_ENUMERATE, (int32_t)m->data.iter.finger.fid,
		      (int32_t)m->data.iter.remaining_templates, 0 };
		break;
	default:
		say("HAL message type %d ignored", m->type);
		return;
	}
	post(e);
}

static struct fingerprint_device_t *hal;

/* The HAL's device functions answer 0 for success. A HAL that crashes
 * takes the bridge with it (one process), and the runner stops the stack
 * (one start per boot: a reboot starts it again). */
static bool request_ok(int ret, const char *what)
{
	if (ret) {
		say("%s: %d", what, ret);
		return false;
	}
	return true;
}

/* The module, as the service opens it: dlopen, HMI, open(module, NULL). */
static bool open_hal(void)
{
	void *dso = dlopen(module_path, RTLD_NOW);
	struct hw_module_t *module;
	struct hw_device_t *device = NULL;
	int ret;

	if (!dso) {
		say("dlopen %s: %s", module_path, dlerror());
		return false;
	}
	module = (struct hw_module_t *)dlsym(dso, "HMI");
	if (!module || !module->methods || !module->methods->open) {
		say("%s: no HAL module (HMI)", module_path);
		return false;
	}
	module->dso = dso;
	say("module %s \"%s\" by %s, api %#x", module->id ? module->id : "?",
	    module->name ? module->name : "?", module->author ? module->author : "?",
	    module->module_api_version);
	ret = module->methods->open(module, NULL, &device);
	if (ret || !device) {
		say("open: %d", ret);
		return false;
	}
	if (device->version != FINGERPRINT_MODULE_API_VERSION_2_1) {
		say("device version %#x, expected %#x", device->version,
		    FINGERPRINT_MODULE_API_VERSION_2_1);
		return false;
	}
	hal = (struct fingerprint_device_t *)device;
	/* as the service does once the module is open */
	void *cutils = dlopen("libcutils.so", RTLD_NOW);
	int (*set_prop)(const char *, const char *) =
		cutils ? (int (*)(const char *, const char *))dlsym(cutils, "property_set") : NULL;
	if (!set_prop || set_prop("persist.vendor.oem.fp.version", "4"))
		say("persist.vendor.oem.fp.version: not set");
	return true;
}

/* --- the hw_auth_token --- */

/* hw_auth_token_t: packed, 69 bytes; type and timestamp big-endian */
#define HW_AUTH_PASSWORD 1

static void put_be(uint8_t *p, uint64_t v, int bytes)
{
	for (int i = bytes - 1; i >= 0; i--, v >>= 8)
		p[i] = (uint8_t)v;
}

static void put_le64(uint8_t *p, uint64_t v)
{
	for (int i = 0; i < 8; i++, v >>= 8)
		p[i] = (uint8_t)v;
}

/*
 * --hat-mode gatekeeper: a token signed in QSEE, as on Android. The
 * fingerprint TA checks the token's HMAC with the auth-token key it gets
 * from the keymaster app at start (libgf_ud_hal's fetchHmacKeyFromKeyMaster
 * and sendHmacKey: the key leaves keymaster only encapsulated for the TA),
 * so only keymaster's Gatekeeper can sign one. QTI's Gatekeeper is
 * GatekeeperHalDevice in android.hardware.gatekeeper@1.0-impl-qti.so, on
 * libkeymasterdeviceutils' KeymasterUtils; its enroll() and verify() take
 * plain pointers, so the bridge calls them itself (no HIDL, no C++ objects
 * of the platform crossing). HIDL_FETCH_IGatekeeper builds the 0x18-byte
 * object inline, the same way it is built here: the vtable, a
 * KeymasterUtils(level) and the level; level 1 is the TEE (the keymaster64
 * app, commands 0x1001 enroll, 0x1002 verify), 2 the secure processor,
 * which does not run here (stock picks 1 when vendor.gatekeeper.disable_spu
 * is true).
 *
 * Once, the bridge enrolls a random secret of its own (STATE/gk_secret,
 * root only; the password handle in STATE/gk_handle); for each ENROLL it
 * verifies that secret with the pre_enroll challenge and gets the 69-byte
 * token back. The desktop's own unlock stands in for the password the user
 * would have typed on Android.
 */
#define GK_LIB	"/vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so"
#define KMU_LIB	"libkeymasterdeviceutils.so"
#define GK_SECRET_LEN	32

typedef int (*gk_enroll_fn)(void *self, uint32_t uid, const uint8_t *cur_handle,
			    uint32_t cur_handle_len, const uint8_t *cur_pw, uint32_t cur_pw_len,
			    const uint8_t *pw, uint32_t pw_len, uint8_t **handle,
			    uint32_t *handle_len);
typedef int (*gk_verify_fn)(void *self, uint32_t uid, uint64_t challenge, const uint8_t *handle,
			    uint32_t handle_len, const uint8_t *pw, uint32_t pw_len,
			    uint8_t **token, uint32_t *token_len, bool *reenroll);

static void *gk_dev;
static gk_enroll_fn gk_enroll;
static gk_verify_fn gk_verify;

static bool gk_open(void)
{
	void *gk, *kmu, *vtable, *utils;
	void (*kmu_ctor)(void *, int);

	if (gk_dev)
		return true;
	kmu = dlopen(KMU_LIB, RTLD_NOW);
	gk = dlopen(GK_LIB, RTLD_NOW);
	if (!kmu || !gk) {
		say("gatekeeper: dlopen: %s", dlerror());
		return false;
	}
	kmu_ctor = (void (*)(void *, int))dlsym(kmu,
		"_ZN14keymasterutils14KeymasterUtilsC1E26keymaster_security_level_t");
	vtable = dlsym(gk, "_ZTV19GatekeeperHalDevice");
	gk_enroll = (gk_enroll_fn)dlsym(gk, "_ZN19GatekeeperHalDevice6enrollEjPKhjS1_jS1_jPPhPj");
	gk_verify = (gk_verify_fn)dlsym(gk, "_ZN19GatekeeperHalDevice6verifyEjmPKhjS1_jPPhPjPb");
	if (!kmu_ctor || !vtable || !gk_enroll || !gk_verify) {
		say("gatekeeper: symbols missing in %s or %s", GK_LIB, KMU_LIB);
		return false;
	}
	utils = calloc(1, 0x10);
	gk_dev = calloc(1, 0x18);
	if (!utils || !gk_dev)
		return false;
	kmu_ctor(utils, 1);		/* KM_SECURITY_LEVEL_TRUSTED_ENVIRONMENT */
	*(void **)gk_dev = (uint8_t *)vtable + 0x10;
	*(void **)((uint8_t *)gk_dev + 0x8) = utils;
	*(uint32_t *)((uint8_t *)gk_dev + 0x10) = 1;
	return true;
}

static int read_state(const char *name, uint8_t *buf, size_t size)
{
	char path[512];
	int fd, n;

	snprintf(path, sizeof(path), "%s/%s", state_dir, name);
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	n = (int)read(fd, buf, size);
	close(fd);
	return n;
}

static bool write_state(const char *name, const uint8_t *buf, size_t size)
{
	char path[512], tmp[520];
	int fd;
	bool ok;

	snprintf(path, sizeof(path), "%s/%s", state_dir, name);
	snprintf(tmp, sizeof(tmp), "%s.new", path);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (fd < 0)
		return false;
	ok = write(fd, buf, size) == (ssize_t)size;
	ok = !fsync(fd) && ok;
	ok = !close(fd) && ok;
	if (ok && !rename(tmp, path))
		return true;
	unlink(tmp);
	return false;
}

static uint8_t gk_secret[GK_SECRET_LEN];
static uint8_t gk_handle[512];
static int gk_handle_len = -1;

static bool gk_ready(void)
{
	uint8_t *handle = NULL;
	uint32_t len = 0;
	int ret, fd;

	if (!gk_open())
		return false;
	if (gk_handle_len > 0)
		return true;
	if (read_state("gk_secret", gk_secret, sizeof(gk_secret)) == GK_SECRET_LEN) {
		gk_handle_len = read_state("gk_handle", gk_handle, sizeof(gk_handle));
		if (gk_handle_len > 0)
			return true;
	}
	/* first use: a random secret, enrolled once */
	fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
	if (fd < 0 || read(fd, gk_secret, sizeof(gk_secret)) != (ssize_t)sizeof(gk_secret)) {
		if (fd >= 0)
			close(fd);
		say("gatekeeper: no random secret");
		return false;
	}
	close(fd);
	ret = gk_enroll(gk_dev, 0, NULL, 0, NULL, 0, gk_secret, sizeof(gk_secret), &handle, &len);
	if (ret || !handle || !len || len > sizeof(gk_handle)) {
		say("gatekeeper: enroll: %d (handle %u bytes)", ret, len);
		free(handle);
		return false;
	}
	memcpy(gk_handle, handle, len);
	free(handle);
	if (!write_state("gk_secret", gk_secret, sizeof(gk_secret)) ||
	    !write_state("gk_handle", gk_handle, len)) {
		say("gatekeeper: cannot save the secret in %s", state_dir);
		return false;
	}
	gk_handle_len = (int)len;
	say("gatekeeper: bridge secret enrolled (handle %u bytes)", len);
	return true;
}

static bool gk_token(uint64_t challenge, uint8_t *hat)
{
	uint8_t *token = NULL;
	uint32_t len = 0;
	bool reenroll = false;
	int ret;

	if (!gk_ready())
		return false;
	ret = gk_verify(gk_dev, 0, challenge, gk_handle, (uint32_t)gk_handle_len, gk_secret,
			sizeof(gk_secret), &token, &len, &reenroll);
	if (ret || !token || len != HAT_SIZE) {
		say("gatekeeper: verify: %d (token %u bytes)", ret, len);
		free(token);
		return false;
	}
	memcpy(hat, token, HAT_SIZE);
	free(token);
	if (reenroll)
		say("gatekeeper: asks for a re-enroll of the bridge secret");
	return true;
}

static bool make_hat(uint64_t challenge, uint8_t *p)
{
	memset(p, 0, HAT_SIZE);
	switch (hat_mode) {
	case HAT_GATEKEEPER:
		return gk_token(challenge, p);
	case HAT_ZERO:
		p[0] = 0;				/* version */
		put_le64(p + 1, challenge);		/* challenge, host order */
		put_le64(p + 9, 0);			/* user_id */
		put_le64(p + 17, 0);			/* authenticator_id */
		put_be(p + 25, HW_AUTH_PASSWORD, 4);	/* authenticator_type */
		put_be(p + 29, (uint64_t)now_ms(), 8);	/* timestamp */
		/* p + 37: hmac[32], zero: unsigned */
		return true;
	}
	return false;
}

/* --- the client --- */

static int listen_fd = -1, client_fd = -1;
static char client_buf[256];
static size_t client_used;

/* What the desktop shows (--ui-state); see publish(). */
static unsigned int ui_seq;
static int32_t ui_acquired, ui_remaining = -1, ui_error;
static char ui_last[16] = "none";

static void ui_note(const char *line)
{
	int32_t a, b;

	if (!strcmp(line, "FINGER NEEDED")) {
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

static void reply(const char *format, ...) __attribute__((format(printf, 1, 2)));
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

/* --- the panel's HBM and the sensor driver's events --- */

static bool hbm_lit;
static int64_t hbm_at;

static bool write_attr(const char *path, const char *value)
{
	int fd = open(path, O_WRONLY | O_CLOEXEC);
	ssize_t len = (ssize_t)strlen(value);
	bool ok = fd >= 0 && write(fd, value, len) == len;
	int err = errno;

	if (fd >= 0)
		close(fd);
	errno = err;
	return ok;
}

static void hbm(bool on)
{
	bool ok = write_attr(hbm_path, on ? "1" : "0");

	if (!ok && on)
		say("HBM on refused (%s): %s: screen dark or the panel driver lacks hbm?",
		    hbm_path, strerror(errno));
	else if (!ok)
		say("HBM off failed (%s): %s", hbm_path, strerror(errno));
	hbm_lit = on && ok;
	hbm_at = now_ms();
}

static void notify(const char *event)
{
	if (!write_attr(notify_path, event))
		say("goodix-fp notify %s: %s: %s", event, notify_path, strerror(errno));
}

/* --- the touchscreen --- */

static int touch_fd = -1;
static int32_t touch_x = -1, touch_y = -1, touch_slot, touch_tracking = -1;
static int32_t ignored_tracking = -1;
static bool sensor_contact;
static bool finger;
static int32_t touch_max_x, touch_max_y;

static int32_t scale(int32_t v, int32_t max, int32_t panel)
{
	return max > 0 ? (int32_t)((int64_t)v * panel / (max + 1)) : v;
}

static void publish(void);

static void pointer(bool down)
{
	if (down) {
		reply("FINGER DOWN");
		/* the shell draws the white disc from this (illuminate) before
		 * the settle below ends and the HAL is told the frame is lit */
		finger = true;
		publish();
		if (hbm_first) {
			hbm(true);
			if (hbm_lit)
				usleep(hbm_settle_ms * 1000);
			notify("touchdown");
		} else {
			notify("touchdown");
			hbm(true);
			if (hbm_lit)
				usleep(hbm_settle_ms * 1000);
		}
		/* the frame above the sensor is lit (or HBM was refused: the
		 * HAL then sees a dark finger and says so) */
		notify("ui_ready");
	} else {
		notify("touchup");
		hbm(false);
		reply("FINGER UP");
	}
	finger = down;
}

/* As the Pixel bridge: the on-screen keyboard can cover the sensor. */
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
struct input_absinfo_ {
	int32_t value, minimum, maximum, fuzz, flat, resolution;
};
#define EVIOCGABS_(abs)	_IOR('E', 0x40 + (abs), struct input_absinfo_)

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
			int64_t r = sensor_r * 3 / 2;
			bool inside = dx * dx + dy * dy <= r * r;
			bool on = capturing && touch_tracking >= 0 && inside;

			sensor_contact = touch_tracking >= 0 && (sensor_contact || inside);
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
static int32_t delete_id;
static int64_t op_since;	/* LIST, DELETE: a HAL that never answers */
#define OP_ANSWER_MS	3000
static char pending[64];
static char list[200];
static size_t list_len;

static bool capturing(void)
{
	return (op == OP_ENROLL || op == OP_AUTH) && !op_ending;
}

/* The desktop's view, as the Pixel bridge writes it. */
static void publish(void)
{
	static char last[400];
	char line[400], tmp[400];
	const char *what = !capturing() ? "idle" : op == OP_ENROLL ? "enroll" : "auth";
	int fd, n;
	bool ok;

	if (!ui_state_path)
		return;
	n = snprintf(line, sizeof(line),
		     "{\"op\":\"%s\",\"finger\":%s,\"x\":%d,\"y\":%d,\"r\":%d,"
		     "\"w\":%d,\"h\":%d,\"seq\":%u,\"acquired\":%d,\"remaining\":%d,"
		     "\"error\":%d,\"last\":\"%s\",\"contact\":%s,\"illuminate\":%s}\n",
		     what, finger && capturing() ? "true" : "false",
		     sensor_x, sensor_y, sensor_r, panel_w, panel_h,
		     ui_seq, ui_acquired, ui_remaining, ui_error, ui_last,
		     sensor_contact ? "true" : "false", illuminate ? "true" : "false");
	if (n < 0 || n >= (int)sizeof(line) || !strcmp(line, last))
		return;
	snprintf(tmp, sizeof(tmp), "%s.new", ui_state_path);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) {
		say("ui state: %s: %s", tmp, strerror(errno));
		ui_state_path = NULL;
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
	if (hbm_lit)
		hbm(false);
	if (op == OP_ENROLL)
		request_ok(hal->post_enroll(hal), "postEnroll");	/* the challenge is single-use */
	op = OP_NONE;
	op_ending = false;
	ending_reply = false;
}

static void end_capture(bool report)
{
	if (op != OP_ENROLL && op != OP_AUTH)
		return;
	ending_reply = ending_reply || report;
	if (op_ending)
		return;
	request_ok(hal->cancel(hal), "cancel");
	op_ending = true;
	op_ending_since = now_ms();
}

static void start_enroll(void)
{
	uint8_t hat[HAT_SIZE];
	uint64_t challenge = hal->pre_enroll(hal);

	if (!challenge)
		say("preEnroll gave challenge 0");
	if (!make_hat(challenge, hat) ||
	    !request_ok(hal->enroll(hal, hat, 0, enroll_timeout_s), "enroll")) {
		request_ok(hal->post_enroll(hal), "postEnroll");
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	op = OP_ENROLL;
	reply("FINGER NEEDED");
}

static void start_auth(void)
{
	/* operationId 0: an unlock, no crypto operation */
	if (!request_ok(hal->authenticate(hal, 0, 0), "authenticate")) {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		return;
	}
	op = OP_AUTH;
	reply("FINGER NEEDED");
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
			strcpy(pending, line);
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
		list_len = 0;
		list[0] = '\0';
		if (request_ok(hal->enumerate(hal), "enumerate")) {
			op = OP_LIST;
			op_since = now_ms();
		}
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	} else if (sscanf(line, "DELETE %d", &id) == 1 && id != 0) {
		/* OnePlus's HAL hands out 32-bit ids; the protocol carries them as
		 * int32 (libfprint's driver atoi()s them), so they can be negative */
		/* remove(gid, 0) would remove every finger: never from here */
		delete_id = id;
		if (request_ok(hal->remove(hal, 0, (uint32_t)id), "remove")) {
			op = OP_DELETE;
			op_since = now_ms();
		}
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	} else if (!strcmp(line, "RESETLOCKOUT")) {
		say("RESETLOCKOUT: HAL 2.1 has no resetLockout; the lockout ends on its own");
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	} else if (!strcmp(line, "STATUS")) {
		reply("READY %d %d %d", sensor_x, sensor_y, sensor_r);
		reply("OK");
	} else {
		reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
	}
}

static void hal_event(const struct event &e)
{
	switch (e.code) {
	case EV_ACQUIRED:
		if (capturing())
			reply("ACQUIRED %d %d", e.a, e.b);
		return;
	case EV_ENROLL:
		if (op != OP_ENROLL)
			return;
		reply("PROGRESS %d %d", e.a, e.b);
		if (e.b == 0) {
			reply("ENROLLED %d", e.a);
			op_done();
		}
		return;
	case EV_AUTHENTICATED:
		if (op != OP_AUTH)
			return;
		if (e.a == 0) {
			/* rejected; the HAL keeps capturing, the client decides */
			if (!op_ending) {
				reply("NOMATCH");
				end_capture(false);
			}
			return;
		}
		/* a match after our cancel: answer the CANCEL here (as the
		 * Pixel bridge, so fprintd is never left waiting) */
		if (!op_ending)
			reply("MATCH %d", e.a);
		else if (ending_reply)
			reply("ERROR %d", ERR_CANCELED);
		op_done();
		return;
	case EV_ERROR:
		say("HAL error %d (vendor %d)", e.a, e.b);
		if (op == OP_NONE)
			return;
		/* Vendor error 6 is one bad capture (preprocessing failed, a
		 * dirty or partial image): the HAL keeps the operation going, and
		 * the in-screen fingerprint code on Android ignores it
		 * (LineageOS's OnePlus FingerprintInscreen::handleError). Pass it
		 * on as a "try again" hint, not as the operation's end. */
		if (e.a == ERR_VENDOR && e.b == 6 && (op == OP_ENROLL || op == OP_AUTH) && !op_ending) {
			reply("ACQUIRED 2 0");	/* AIDL INSUFFICIENT */
			return;
		}
		if (e.a < 0) {	/* ERROR_LOCKOUT */
			if (op == OP_AUTH || op == OP_ENROLL) {
				if (!op_ending)
					reply("LOCKOUT %d", LOCKOUT_MS);
				else if (ending_reply)
					reply("ERROR %d", ERR_CANCELED);
			} else {
				reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
			}
			op_done();
			return;
		}
		if (!op_ending || e.a != ERR_CANCELED || ending_reply)
			reply("ERROR %d", e.a);
		op_done();
		return;
	case EV_ENUMERATE:
		if (op != OP_LIST)
			return;
		/* fingerId 0 with remaining 0: no fingers at all */
		if (e.a != 0 && list_len < sizeof(list) - 12)
			list_len += snprintf(list + list_len, sizeof(list) - list_len, " %d", e.a);
		if (e.b == 0) {
			reply("LIST%s", list);
			op_done();
		}
		return;
	case EV_REMOVED:
		if (op != OP_DELETE)
			return;
		if (e.b != 0)
			return;		/* more to come */
		if (e.a == delete_id)
			reply("DELETED %d", e.a);
		else
			reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
		op_done();
		return;
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
		if (hbm_lit)
			hbm(false);
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
		client_used = 0;
}

static int open_listener(void)
{
	struct sockaddr_un addr = {};
	int fd;

	addr.sun_family = AF_UNIX;
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

/* SIGTERM/SIGINT: the main loop turns HBM off and exits. */
static volatile sig_atomic_t quit;
static void on_signal(int sig)
{
	(void)sig;
	quit = 1;
}

static void usage(void)
{
	say("usage: omamobile-fp-hotdog-bridge [--socket PATH] [--state DIR] [--touch EVDEV]\n"
	    "         [--hbm PATH] [--notify PATH] [--hbm-settle-ms MS] [--hbm-first 0|1] [--illuminate 0|1]\n"
	    "         [--ui-state PATH] [--inhibit DIR] [--panel WxH] [--sensor X,Y,R]\n"
	    "         [--hat-mode gatekeeper|zero] [--enroll-timeout S] [--module SO]");
	exit(2);
}

int main(int argc, char **argv)
{
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
		else if (!strcmp(argv[i], "--hbm"))
			hbm_path = v;
		else if (!strcmp(argv[i], "--notify"))
			notify_path = v;
		else if (!strcmp(argv[i], "--hbm-settle-ms"))
			hbm_settle_ms = atoi(v);
		else if (!strcmp(argv[i], "--hbm-first"))
			hbm_first = atoi(v) != 0;
		else if (!strcmp(argv[i], "--illuminate"))
			illuminate = atoi(v) != 0;
		else if (!strcmp(argv[i], "--ui-state"))
			ui_state_path = v;
		else if (!strcmp(argv[i], "--inhibit"))
			inhibit_dir = v;
		else if (!strcmp(argv[i], "--module"))
			module_path = v;
		else if (!strcmp(argv[i], "--enroll-timeout"))
			enroll_timeout_s = (uint32_t)atoi(v);
		else if (!strcmp(argv[i], "--hat-mode")) {
			if (!strcmp(v, "zero"))
				hat_mode = HAT_ZERO;
			else if (!strcmp(v, "gatekeeper"))
				hat_mode = HAT_GATEKEEPER;
			else
				usage();
		} else if (!strcmp(argv[i], "--panel")) {
			if (sscanf(v, "%dx%d", &panel_w, &panel_h) != 2 ||
			    panel_w < 100 || panel_h < 100)
				usage();
		} else if (!strcmp(argv[i], "--sensor")) {
			if (sscanf(v, "%d,%d,%d", &sensor_x, &sensor_y, &sensor_r) != 3 ||
			    sensor_x <= 0 || sensor_y <= 0 || sensor_r < 10 || sensor_r > 400)
				usage();
		} else
			usage();
	}
	if (hbm_settle_ms < 0 || hbm_settle_ms > 1000)
		usage();
	signal(SIGPIPE, SIG_IGN);
	struct sigaction sa = {};
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	mkdir(state_dir, 0700);

	/* a bridge that died with the panel lit leaves no HBM behind */
	hbm(false);

	if (pipe2(events, O_CLOEXEC)) {
		say("pipe: %s", strerror(errno));
		return 1;
	}
	if (!open_hal())
		return 1;
	if (!request_ok(hal->set_notify(hal, on_notify), "setNotify"))
		return 1;
	if (access(state_dir, W_OK)) {
		say("%s: not writable", state_dir);
		return 1;
	}
	if (!request_ok(hal->set_active_group(hal, 0, state_dir), "setActiveGroup"))
		return 1;
	say("HAL ready; sensor (%d, %d) r %d (placeholders unless --sensor)", sensor_x,
	    sensor_y, sensor_r);

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

	while (!quit) {
		struct pollfd fds[4] = {
			{ events[0], POLLIN, 0 }, { listen_fd, POLLIN, 0 },
			{ client_fd, POLLIN, 0 }, { touch_fd, POLLIN, 0 },
		};
		struct event e;

		if (poll(fds, 4, 500) < 0 && errno != EINTR)
			break;
		if (quit)
			break;
		if (fds[0].revents & POLLIN && read(events[0], &e, sizeof(e)) == sizeof(e))
			hal_event(e);
		if (fds[3].revents & POLLIN)
			touch_events(capturing());
		if (fds[1].revents & POLLIN)
			new_client();
		if (client_fd >= 0 && fds[2].revents & (POLLIN | POLLHUP | POLLERR))
			client_input();
		/* the finger still down: keep HBM past the panel's 3 s cap */
		if (finger && hbm_lit && now_ms() - hbm_at > HBM_REFRESH_MS)
			hbm(true);
		/* a LIST or DELETE the HAL never answered (some 2.1 HALs send
		 * no onEnumerate at all for an empty group) */
		if ((op == OP_LIST || op == OP_DELETE) && now_ms() - op_since > OP_ANSWER_MS) {
			say("no answer to %s", op == OP_LIST ? "enumerate" : "remove");
			if (op == OP_LIST)
				reply("LIST%s", list);
			else
				reply("ERROR %d", ERR_UNABLE_TO_PROCESS);
			op_done();
		}
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
	say("stopping");
	if (op == OP_ENROLL || op == OP_AUTH)
		(void)hal->cancel(hal);
	if (finger)
		notify("touchup");
	hbm(false);
	if (ui_state_path)
		unlink(ui_state_path);
	unlink(socket_path);
	return 0;
}
