// SPDX-License-Identifier: MIT
/*
 * omamobile-fp-shim: LD_PRELOAD library for the Android binaries in the
 * Omamobile fingerprint chroot (device/cheetah/FINGERPRINT-RESEARCH.md).
 *
 * The chroot runs Google's fingerprint, Gatekeeper and KeyMint HALs,
 * storageproxyd, trusty_apploader and the two service managers unmodified,
 * without Android's init, property service, logd or SELinux. This library
 * stands in for those, and nothing else:
 *
 *  - properties: a directory with one file per property (OMAMOBILE_FP_PROPS,
 *    default /dev/__omamobile_props__), shared by every process in the
 *    chroot. The runner fills it from build.prop and its overrides;
 *    property_set() writes a file. Reads never fail, they find nothing.
 *  - logging: liblog's entry points print to stderr, which the runner sends
 *    to the journal.
 *  - SELinux: the kernel has no SELinux, so contexts are a fixed string and
 *    every access check passes. The chroot itself is the trust boundary.
 *  - binder: no LSM provides security contexts, so a binder node that asks
 *    for its callers' context (FLAT_BINDER_FLAG_TXN_SECURITY_CTX) would fail
 *    every transaction. The context manager falls back to the plain ioctl,
 *    and nodes never ask. Callers' contexts then come back NULL, so
 *    IPCThreadState::getCallingSid() answers the fixed context too.
 *  - services that do not exist here (power, sensors, stats, vold, thermal,
 *    suspend, the Pixel display HAL): lookups return nothing at once
 *    instead of waiting several seconds each (OMAMOBILE_FP_NO_SERVICES adds
 *    more name prefixes, comma separated).
 *  - wake locks: accepted and dropped.
 *
 * Build with the Android NDK (bionic, aarch64), see fingerprint/Makefile.
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default")))

#define PROP_NAME_MAX	256	/* bionic allows long names for ro. props */
#define PROP_VALUE_MAX	92
#define FIXED_CONTEXT	"u:r:omamobile_fp:s0"

static const char *props_dir(void)
{
	const char *d = getenv("OMAMOBILE_FP_PROPS");

	return d && *d ? d : "/dev/__omamobile_props__";
}

/* ------------------------------------------------------------------ */
/* logging                                                             */

static int log_min_prio = -1;

static int min_prio(void)
{
	if (log_min_prio < 0) {
		const char *s = getenv("OMAMOBILE_FP_LOGLEVEL");

		/* android_LogPriority: 2 verbose .. 4 info .. 7 fatal */
		log_min_prio = s && *s ? atoi(s) : 3;
	}
	return log_min_prio;
}

static void log_line(int prio, const char *tag, const char *msg)
{
	static const char letters[] = "??VDIWEFS";
	char c = prio >= 0 && prio < (int)sizeof(letters) - 1 ? letters[prio] : '?';

	if (prio < min_prio())
		return;
	dprintf(STDERR_FILENO, "%c %s[%d]: %s\n", c, tag ? tag : "-", gettid(),
		msg ? msg : "");
}

struct __android_log_message {
	size_t struct_size;
	int32_t buffer_id;
	int32_t priority;
	const char *tag;
	const char *file;
	uint32_t line;
	const char *message;
};

EXPORT void __android_log_write_log_message(struct __android_log_message *m)
{
	if (m)
		log_line(m->priority, m->tag, m->message);
}

EXPORT int __android_log_write(int prio, const char *tag, const char *text)
{
	log_line(prio, tag, text);
	return 1;
}

EXPORT int __android_log_buf_write(int buf, int prio, const char *tag,
				   const char *text)
{
	(void)buf;
	log_line(prio, tag, text);
	return 1;
}

EXPORT int __android_log_vprint(int prio, const char *tag, const char *fmt,
				va_list ap)
{
	char buf[1024];

	if (prio < min_prio())
		return 0;
	vsnprintf(buf, sizeof(buf), fmt, ap);
	log_line(prio, tag, buf);
	return 1;
}

EXPORT int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = __android_log_vprint(prio, tag, fmt, ap);
	va_end(ap);
	return ret;
}

EXPORT int __android_log_buf_print(int buf, int prio, const char *tag,
				   const char *fmt, ...)
{
	va_list ap;
	int ret;

	(void)buf;
	va_start(ap, fmt);
	ret = __android_log_vprint(prio, tag, fmt, ap);
	va_end(ap);
	return ret;
}

EXPORT void __android_log_assert(const char *cond, const char *tag,
				 const char *fmt, ...)
{
	char buf[1024] = "assertion failed";
	va_list ap;

	if (fmt) {
		va_start(ap, fmt);
		vsnprintf(buf, sizeof(buf), fmt, ap);
		va_end(ap);
	} else if (cond) {
		snprintf(buf, sizeof(buf), "assertion failed: %s", cond);
	}
	log_line(7, tag, buf);
	abort();
}

EXPORT int __android_log_is_loggable(int prio, const char *tag, int def)
{
	(void)tag;
	(void)def;
	return prio >= min_prio();
}

EXPORT int __android_log_is_loggable_len(int prio, const char *tag,
					 size_t len, int def)
{
	(void)len;
	return __android_log_is_loggable(prio, tag, def);
}

/* ------------------------------------------------------------------ */
/* properties                                                          */

/*
 * prop_info is opaque to callers; ours holds just the name. Entries are
 * never freed, so pointers stay valid, as bionic's do.
 */
struct prop_info {
	struct prop_info *next;
	char name[PROP_NAME_MAX];
};

static struct prop_info *prop_cache;
static pthread_mutex_t prop_lock = PTHREAD_MUTEX_INITIALIZER;

static bool prop_name_ok(const char *name)
{
	size_t len = name ? strlen(name) : 0;

	if (!len || len >= PROP_NAME_MAX || name[0] == '.')
		return false;
	return !strchr(name, '/') && !strstr(name, "..");
}

static int prop_path(const char *name, char *path, size_t size)
{
	int n = snprintf(path, size, "%s/%s", props_dir(), name);

	return n > 0 && (size_t)n < size ? 0 : -1;
}

/* Value into value[PROP_VALUE_MAX]; length, or -1 if unset. */
static int prop_read(const char *name, char *value)
{
	char path[PATH_MAX];
	ssize_t n;
	int fd;

	value[0] = '\0';
	if (!prop_name_ok(name) || prop_path(name, path, sizeof(path)))
		return -1;
	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	n = read(fd, value, PROP_VALUE_MAX - 1);
	close(fd);
	if (n < 0)
		n = 0;
	value[n] = '\0';
	while (n > 0 && value[n - 1] == '\n')
		value[--n] = '\0';
	return (int)n;
}

static uint32_t prop_serial(const char *name)
{
	char path[PATH_MAX];
	struct stat st;

	if (!prop_name_ok(name) || prop_path(name, path, sizeof(path)) ||
	    stat(path, &st))
		return 0;
	/* changes whenever the file is rewritten */
	return (uint32_t)(st.st_mtim.tv_nsec ^ st.st_mtim.tv_sec ^ st.st_ino);
}

static const struct prop_info *prop_get_info(const char *name)
{
	struct prop_info *pi;

	pthread_mutex_lock(&prop_lock);
	for (pi = prop_cache; pi; pi = pi->next)
		if (!strcmp(pi->name, name))
			break;
	if (!pi) {
		pi = calloc(1, sizeof(*pi));
		if (pi) {
			snprintf(pi->name, sizeof(pi->name), "%s", name);
			pi->next = prop_cache;
			prop_cache = pi;
		}
	}
	pthread_mutex_unlock(&prop_lock);
	return pi;
}

EXPORT const struct prop_info *__system_property_find(const char *name)
{
	char value[PROP_VALUE_MAX];

	if (prop_read(name, value) < 0)
		return NULL;
	return prop_get_info(name);
}

EXPORT int __system_property_get(const char *name, char *value)
{
	int n = prop_read(name, value);

	return n < 0 ? 0 : n;
}

EXPORT int __system_property_read(const struct prop_info *pi, char *name,
				  char *value)
{
	if (name)
		snprintf(name, 32, "%s", pi->name);	/* legacy PROP_NAME_MAX */
	return __system_property_get(pi->name, value);
}

EXPORT void __system_property_read_callback(const struct prop_info *pi,
	void (*cb)(void *cookie, const char *name, const char *value,
		   uint32_t serial),
	void *cookie)
{
	char value[PROP_VALUE_MAX];

	prop_read(pi->name, value);
	cb(cookie, pi->name, value, prop_serial(pi->name));
}

EXPORT uint32_t __system_property_serial(const struct prop_info *pi)
{
	return prop_serial(pi->name);
}

EXPORT uint32_t __system_property_area_serial(void)
{
	struct stat st;

	if (stat(props_dir(), &st))
		return 0;
	return (uint32_t)(st.st_mtim.tv_nsec ^ st.st_mtim.tv_sec);
}

EXPORT int __system_property_foreach(void (*cb)(const struct prop_info *pi,
						void *cookie),
				     void *cookie)
{
	const struct prop_info *pi;
	struct dirent *de;
	DIR *dir = opendir(props_dir());

	if (!dir)
		return -1;
	while ((de = readdir(dir))) {
		if (de->d_name[0] == '.')
			continue;
		pi = prop_get_info(de->d_name);
		if (pi)
			cb(pi, cookie);
	}
	closedir(dir);
	return 0;
}

EXPORT int __system_property_set(const char *name, const char *value)
{
	char path[PATH_MAX], tmp[PATH_MAX];
	size_t len = value ? strlen(value) : 0;
	int fd;

	if (!prop_name_ok(name) || prop_path(name, path, sizeof(path)))
		return -1;
	/* ro. properties are write-once, as with Android's property service */
	if (!strncmp(name, "ro.", 3) && !access(path, F_OK))
		return -1;
	if (len >= PROP_VALUE_MAX && strncmp(name, "ro.", 3))
		return -1;
	if (snprintf(tmp, sizeof(tmp), "%s/.%s.%d", props_dir(), name,
		     getpid()) >= (int)sizeof(tmp))
		return -1;
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		return -1;
	if (len && write(fd, value, len) != (ssize_t)len) {
		close(fd);
		unlink(tmp);
		return -1;
	}
	close(fd);
	if (rename(tmp, path)) {
		unlink(tmp);
		return -1;
	}
	log_line(4, "omamobile-fp-shim", name);
	return 0;
}

/* Poll: property changes are rare and the waits are short. */
EXPORT bool __system_property_wait(const struct prop_info *pi,
				   uint32_t old_serial, uint32_t *new_serial,
				   const struct timespec *timeout)
{
	struct timespec end, now;
	uint32_t serial;

	clock_gettime(CLOCK_MONOTONIC, &end);
	if (timeout) {
		end.tv_sec += timeout->tv_sec;
		end.tv_nsec += timeout->tv_nsec;
		if (end.tv_nsec >= 1000000000L) {
			end.tv_sec++;
			end.tv_nsec -= 1000000000L;
		}
	}
	for (;;) {
		serial = pi ? prop_serial(pi->name) : __system_property_area_serial();
		if (serial != old_serial) {
			*new_serial = serial;
			return true;
		}
		clock_gettime(CLOCK_MONOTONIC, &now);
		if (timeout && (now.tv_sec > end.tv_sec ||
				(now.tv_sec == end.tv_sec && now.tv_nsec >= end.tv_nsec)))
			return false;
		usleep(20000);
	}
}

EXPORT uint32_t __system_property_wait_any(uint32_t old_serial)
{
	uint32_t serial;

	__system_property_wait(NULL, old_serial, &serial, NULL);
	return serial;
}

/* ------------------------------------------------------------------ */
/* SELinux (libselinux)                                                */

static int fixed_context(char **con)
{
	*con = strdup(FIXED_CONTEXT);
	return *con ? 0 : -1;
}

EXPORT int is_selinux_enabled(void) { return 0; }
EXPORT int security_getenforce(void) { return 0; }
EXPORT int getcon(char **con) { return fixed_context(con); }
EXPORT int getprevcon(char **con) { return fixed_context(con); }
EXPORT int getpidcon(pid_t pid, char **con) { (void)pid; return fixed_context(con); }
EXPORT int getpeercon(int fd, char **con) { (void)fd; return fixed_context(con); }
EXPORT int getfilecon(const char *path, char **con) { (void)path; return fixed_context(con); }
EXPORT int lgetfilecon(const char *path, char **con) { (void)path; return fixed_context(con); }
EXPORT int fgetfilecon(int fd, char **con) { (void)fd; return fixed_context(con); }
EXPORT void freecon(char *con) { free(con); }
EXPORT int setcon(const char *con) { (void)con; return 0; }
EXPORT int setexeccon(const char *con) { (void)con; return 0; }
EXPORT int setfscreatecon(const char *con) { (void)con; return 0; }
EXPORT int selinux_check_access(const char *scon, const char *tcon,
				const char *tclass, const char *perm,
				void *auditdata)
{
	(void)scon; (void)tcon; (void)tclass; (void)perm; (void)auditdata;
	return 0;
}
EXPORT int selinux_status_open(int fallback) { (void)fallback; return 0; }
EXPORT int selinux_status_updated(void) { return 0; }
EXPORT void selinux_status_close(void) { }
EXPORT int selinux_android_restorecon(const char *path, unsigned int flags)
{
	(void)path; (void)flags;
	return 0;
}

/* Opaque handles: callers only pass them back to selabel_lookup(). */
static char selabel_dummy;

EXPORT void *selinux_android_service_context_handle(void) { return &selabel_dummy; }
EXPORT void *selinux_android_hw_service_context_handle(void) { return &selabel_dummy; }
EXPORT void *selinux_android_vendor_service_context_handle(void) { return &selabel_dummy; }
EXPORT void *selinux_android_file_context_handle(void) { return &selabel_dummy; }
EXPORT void *selinux_android_prop_context_handle(void) { return &selabel_dummy; }
EXPORT void *selabel_open(unsigned int backend, const void *opts, unsigned int n)
{
	(void)backend; (void)opts; (void)n;
	return &selabel_dummy;
}
EXPORT void selabel_close(void *h) { (void)h; }
EXPORT int selabel_lookup(void *h, char **con, const char *key, int type)
{
	(void)h; (void)key; (void)type;
	return fixed_context(con);
}
EXPORT void selinux_set_callback(int type, void *cb) { (void)type; (void)cb; }

/* ------------------------------------------------------------------ */
/* binder                                                              */

/* _IOW('b', 13, struct flat_binder_object), 24 bytes on 64-bit */
#define BINDER_SET_CONTEXT_MGR_EXT	_IOW('b', 13, char[24])

typedef int (*ioctl_fn)(int, int, ...);

EXPORT int ioctl(int fd, int request, ...)
{
	static ioctl_fn real_ioctl;
	va_list ap;
	void *arg;

	va_start(ap, request);
	arg = va_arg(ap, void *);
	va_end(ap);

	/*
	 * Make the context manager use BINDER_SET_CONTEXT_MGR, without
	 * FLAT_BINDER_FLAG_TXN_SECURITY_CTX; libbinder falls back on error.
	 */
	if ((unsigned int)request == (unsigned int)BINDER_SET_CONTEXT_MGR_EXT) {
		errno = EINVAL;
		return -1;
	}
	if (!real_ioctl)
		real_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");
	return real_ioctl(fd, request, arg);
}

/*
 * android::IPCThreadState::getCallingSid() const. With no context in the
 * transaction it returns NULL, and the vendor service manager, inside a
 * synchronous call, aborts ("Did not get context from PID ...") instead of
 * asking getpidcon(). Answer with the same fixed context getpidcon() gives;
 * a real context, if one ever arrives, still wins.
 */
typedef const char *(*calling_sid_fn)(const void *self);

EXPORT const char *_ZNK7android14IPCThreadState13getCallingSidEv(const void *self)
{
	static calling_sid_fn real_calling_sid;
	const char *sid = NULL;

	if (!real_calling_sid)
		real_calling_sid = (calling_sid_fn)dlsym(RTLD_NEXT,
			"_ZNK7android14IPCThreadState13getCallingSidEv");
	if (real_calling_sid)
		sid = real_calling_sid(self);
	return sid ? sid : FIXED_CONTEXT;
}

struct AIBinder;

EXPORT void AIBinder_setRequestingSid(struct AIBinder *binder, bool requesting)
{
	(void)binder;
	(void)requesting;
}

/* android::BBinder::setRequestingSid(bool) */
EXPORT void bbinder_set_requesting_sid(void *self, bool requesting)
	__asm__("_ZN7android7BBinder17setRequestingSidEb");
void bbinder_set_requesting_sid(void *self, bool requesting)
{
	(void)self;
	(void)requesting;
}

/* ------------------------------------------------------------------ */
/* service lookups                                                     */

static const char *const absent_services[] = {
	"android.hardware.power.",
	"aidl.google.hardware.power.",
	"android.frameworks.sensorservice.",
	"android.frameworks.stats.",
	"android.system.vold.",
	"android.system.suspend.",
	"android.hardware.thermal.",
	"com.google.hardware.pixel.display.",
	"vold",
	NULL
};

static bool service_absent(const char *name)
{
	const char *extra = getenv("OMAMOBILE_FP_NO_SERVICES");
	size_t i;

	if (!name)
		return false;
	for (i = 0; absent_services[i]; i++)
		if (!strncmp(name, absent_services[i], strlen(absent_services[i])))
			return true;
	while (extra && *extra) {
		const char *end = strchr(extra, ',');
		size_t len = end ? (size_t)(end - extra) : strlen(extra);

		if (len && !strncmp(name, extra, len))
			return true;
		extra = end ? end + 1 : NULL;
	}
	return false;
}

/*
 * OMAMOBILE_FP_ABSENT_PARK=1: a lookup of an absent service from any thread
 * but the main one never returns, as on Android when a service never
 * registers. Broadcom's gpsd retries its sensor service from a new thread
 * each time a lookup fails, tens of thousands of times a minute; parked,
 * that retry thread just waits. The main thread still gets "no service" at
 * once (blocking it would stop gpsd before its event loop). Off unless set.
 */
static void absent_park(void)
{
	const char *s = getenv("OMAMOBILE_FP_ABSENT_PARK");

	if (!s || strcmp(s, "1") || gettid() == getpid())
		return;
	for (;;)
		pause();
}

typedef struct AIBinder *(*sm_get_fn)(const char *);
typedef bool (*sm_declared_fn)(const char *);

#define SM_FORWARD(fn, type, absent)					\
EXPORT type fn(const char *name)					\
{									\
	static type (*real)(const char *);				\
									\
	if (service_absent(name)) {					\
		log_line(4, "omamobile-fp-shim", name);			\
		absent_park();						\
		return absent;						\
	}								\
	if (!real)							\
		real = (type (*)(const char *))dlsym(RTLD_NEXT, #fn);	\
	return real ? real(name) : absent;				\
}

SM_FORWARD(AServiceManager_getService, struct AIBinder *, NULL)
SM_FORWARD(AServiceManager_checkService, struct AIBinder *, NULL)
SM_FORWARD(AServiceManager_waitForService, struct AIBinder *, NULL)
SM_FORWARD(AServiceManager_isDeclared, bool, false)

/* ------------------------------------------------------------------ */
/* wake locks (libhardware_legacy)                                     */

EXPORT int acquire_wake_lock(int lock, const char *id)
{
	(void)lock;
	(void)id;
	return 0;
}

EXPORT int release_wake_lock(const char *id)
{
	(void)id;
	return 0;
}
