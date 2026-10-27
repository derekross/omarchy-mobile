// SPDX-License-Identifier: MIT
/*
 * omamobile-gnss-client: the smallest client of a GNSS AIDL HAL
 * (android.hardware.gnss.IGnss, version 3), for vendor chroots without the
 * Android framework. It registers a callback, sets standalone positioning
 * at one fix a second, starts the HAL and its NMEA output, and writes every
 * NMEA sentence the HAL reports to stdout (or to the file in argv[1], a FIFO
 * that omamobile-gnss-nmea reads). Positions are logged to stderr.
 *
 * Built with the NDK against libbinder_ndk only; the service manager and
 * VINTF calls are platform (LLNDK) symbols, looked up at run time. The
 * transactions are
 * written by hand from the frozen AIDL (hardware/interfaces gnss/aidl,
 * aidl_api/android.hardware.gnss/3): method codes are FIRST_CALL_TRANSACTION
 * plus the declaration order, parcelables are a present flag, a size and the
 * fields in order.
 *
 * Usage: omamobile-gnss-client [NMEA-OUT] [SERVICE]
 *   SERVICE defaults to android.hardware.gnss.IGnss/default
 */
#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define GNSS_DESC	"android.hardware.gnss.IGnss"
#define CB_DESC		"android.hardware.gnss.IGnssCallback"
#define CB_VERSION	3
#define CB_HASH		"747fa8b8b4bb55d21f2c42446dd1b31de1dfbeaa"

/* IGnss, in declaration order from FIRST_CALL_TRANSACTION (1) */
enum {
	IGNSS_SET_CALLBACK = 1,
	IGNSS_CLOSE = 2,
	IGNSS_START = 14,
	IGNSS_STOP = 15,
	IGNSS_SET_POSITION_MODE = 20,
	IGNSS_START_NMEA = 25,
	IGNSS_STOP_NMEA = 26,
};

/* IGnssCallback */
enum {
	CB_SET_CAPABILITIES = 1,
	CB_STATUS = 2,
	CB_SV_STATUS = 3,
	CB_LOCATION = 4,
	CB_NMEA = 5,
	CB_ACQUIRE_WAKELOCK = 6,
	CB_RELEASE_WAKELOCK = 7,
	CB_SET_SYSTEM_INFO = 8,
	CB_REQUEST_TIME = 9,
	CB_REQUEST_LOCATION = 10,
	CB_SET_SIGNAL_TYPE_CAPS = 11,
	CB_GET_INTERFACE_HASH = 0xfffffd,
	CB_GET_INTERFACE_VERSION = 0xfffffe,
};

static FILE *nmea_out;
static AIBinder *gnss;
static volatile sig_atomic_t stopping;

static bool string_alloc(void *data, int32_t len, char **buf)
{
	char **out = data;

	if (len < 0) {
		*out = NULL;
		*buf = NULL;
		return true;
	}
	*out = malloc(len > 0 ? (size_t)len : 1);
	*buf = *out;
	return *out != NULL;
}

static void *cb_create(void *args)
{
	return args;
}

static void cb_destroy(void *data)
{
	(void)data;
}

static void read_location(const AParcel *in)
{
	int32_t present = 0, size = 0, flags = 0;
	double lat = 0, lon = 0, alt = 0, speed = 0, bearing = 0, hacc = 0;
	int64_t ts = 0;

	if (AParcel_readInt32(in, &present) || !present ||
	    AParcel_readInt32(in, &size) || AParcel_readInt32(in, &flags) ||
	    AParcel_readDouble(in, &lat) || AParcel_readDouble(in, &lon) ||
	    AParcel_readDouble(in, &alt) || AParcel_readDouble(in, &speed) ||
	    AParcel_readDouble(in, &bearing) || AParcel_readDouble(in, &hacc))
		return;
	/* vertical, speed and bearing accuracy, then the UTC time */
	for (int i = 0; i < 3; i++) {
		double skip;

		if (AParcel_readDouble(in, &skip))
			return;
	}
	AParcel_readInt64(in, &ts);
	fprintf(stderr, "omamobile-gnss-client: fix flags %#x lat %.7f lon %.7f alt %.1f m acc %.1f m speed %.1f m/s time %lld\n",
		flags, lat, lon, alt, hacc, speed, (long long)ts);
}

static binder_status_t cb_transact(AIBinder *binder, transaction_code_t code,
				   const AParcel *in, AParcel *out)
{
	int32_t i32 = 0;
	int64_t ts = 0;
	char *s = NULL;

	(void)binder;
	switch (code) {
	case CB_GET_INTERFACE_VERSION:
		AParcel_writeStatusHeader(out, AStatus_newOk());
		return AParcel_writeInt32(out, CB_VERSION);
	case CB_GET_INTERFACE_HASH:
		AParcel_writeStatusHeader(out, AStatus_newOk());
		return AParcel_writeString(out, CB_HASH, sizeof(CB_HASH) - 1);
	case CB_SET_CAPABILITIES:
		AParcel_readInt32(in, &i32);
		fprintf(stderr, "omamobile-gnss-client: capabilities %#x\n", i32);
		break;
	case CB_STATUS:
		AParcel_readInt32(in, &i32);
		fprintf(stderr, "omamobile-gnss-client: status %d\n", i32);
		break;
	case CB_LOCATION:
		read_location(in);
		break;
	case CB_NMEA:
		if (AParcel_readInt64(in, &ts) == STATUS_OK &&
		    AParcel_readString(in, &s, string_alloc) == STATUS_OK && s) {
			size_t n = strlen(s);

			fputs(s, nmea_out);
			if (n == 0 || s[n - 1] != '\n')
				fputc('\n', nmea_out);
			fflush(nmea_out);
		}
		free(s);
		break;
	case CB_REQUEST_TIME:
		fprintf(stderr, "omamobile-gnss-client: the HAL asks for the time\n");
		break;
	case CB_REQUEST_LOCATION:
		fprintf(stderr, "omamobile-gnss-client: the HAL asks for a location\n");
		break;
	case CB_SV_STATUS:
	case CB_ACQUIRE_WAKELOCK:
	case CB_RELEASE_WAKELOCK:
	case CB_SET_SYSTEM_INFO:
	case CB_SET_SIGNAL_TYPE_CAPS:
		break;
	default:
		return STATUS_UNKNOWN_TRANSACTION;
	}
	return AParcel_writeStatusHeader(out, AStatus_newOk());
}

/* One call into IGnss; prints the HAL's answer when it isn't OK. */
static int gnss_call(transaction_code_t code, const char *name,
		     binder_status_t (*args)(AParcel *in, void *ctx), void *ctx)
{
	AParcel *in = NULL, *out = NULL;
	AStatus *st = NULL;
	binder_status_t ret;

	ret = AIBinder_prepareTransaction(gnss, &in);
	if (ret == STATUS_OK && args)
		ret = args(in, ctx);
	if (ret == STATUS_OK)
		ret = AIBinder_transact(gnss, code, &in, &out, 0);
	if (ret == STATUS_OK)
		ret = AParcel_readStatusHeader(out, &st);
	if (ret != STATUS_OK) {
		fprintf(stderr, "omamobile-gnss-client: %s: transaction failed (%d)\n", name, ret);
	} else if (!AStatus_isOk(st)) {
		fprintf(stderr, "omamobile-gnss-client: %s: %s\n", name, AStatus_getDescription(st));
		ret = STATUS_FAILED_TRANSACTION;
	} else {
		fprintf(stderr, "omamobile-gnss-client: %s ok\n", name);
	}
	if (st)
		AStatus_delete(st);
	if (out)
		AParcel_delete(out);
	return ret;
}

static binder_status_t arg_binder(AParcel *in, void *ctx)
{
	return AParcel_writeStrongBinder(in, ctx);
}

/* PositionModeOptions: STANDALONE, PERIODIC, 1000 ms, 0 m, 0 ms, no low power */
static binder_status_t arg_position_mode(AParcel *in, void *ctx)
{
	int32_t start, end;
	binder_status_t ret;

	(void)ctx;
	ret = AParcel_writeInt32(in, 1);	/* present */
	if (ret)
		return ret;
	start = AParcel_getDataPosition(in);
	ret = AParcel_writeInt32(in, 0);	/* size, patched below */
	ret = ret ?: AParcel_writeInt32(in, 0);	/* mode: STANDALONE */
	ret = ret ?: AParcel_writeInt32(in, 0);	/* recurrence: PERIODIC */
	ret = ret ?: AParcel_writeInt32(in, 1000);	/* minIntervalMs */
	ret = ret ?: AParcel_writeInt32(in, 0);	/* preferredAccuracyMeters */
	ret = ret ?: AParcel_writeInt32(in, 0);	/* preferredTimeMs */
	ret = ret ?: AParcel_writeBool(in, false);	/* lowPowerMode */
	if (ret)
		return ret;
	end = AParcel_getDataPosition(in);
	AParcel_setDataPosition(in, start);
	AParcel_writeInt32(in, end - start);
	AParcel_setDataPosition(in, end);
	return STATUS_OK;
}

/* The proxy class for the remote IGnss: it carries the descriptor */
static binder_status_t proxy_transact(AIBinder *binder, transaction_code_t code,
				      const AParcel *in, AParcel *out)
{
	(void)binder;
	(void)code;
	(void)in;
	(void)out;
	return STATUS_UNKNOWN_TRANSACTION;
}

static void on_signal(int sig)
{
	(void)sig;
	stopping = 1;
}

int main(int argc, char **argv)
{
	const char *service = argc > 2 ? argv[2] : GNSS_DESC "/default";
	void (*mark_vintf)(AIBinder *);
	AIBinder *(*wait_for_service)(const char *);
	bool (*set_threads)(uint32_t);
	void (*start_threads)(void);
	AIBinder_Class *cls;
	AIBinder *cb;
	void *ndk;

	nmea_out = stdout;
	if (argc > 1 && strcmp(argv[1], "-")) {
		nmea_out = fopen(argv[1], "w");
		if (!nmea_out) {
			fprintf(stderr, "omamobile-gnss-client: %s: %s\n", argv[1], strerror(errno));
			return 1;
		}
	}
	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	ndk = dlopen("libbinder_ndk.so", RTLD_NOW);
	wait_for_service = ndk ? (AIBinder *(*)(const char *))dlsym(ndk, "AServiceManager_waitForService") : NULL;
	mark_vintf = ndk ? (void (*)(AIBinder *))dlsym(ndk, "AIBinder_markVintfStability") : NULL;
	set_threads = ndk ? (bool (*)(uint32_t))dlsym(ndk, "ABinderProcess_setThreadPoolMaxThreadCount") : NULL;
	start_threads = ndk ? (void (*)(void))dlsym(ndk, "ABinderProcess_startThreadPool") : NULL;
	if (!wait_for_service || !set_threads || !start_threads) {
		fprintf(stderr, "omamobile-gnss-client: libbinder_ndk lacks the platform calls\n");
		return 1;
	}
	set_threads(2);
	start_threads();

	gnss = wait_for_service(service);
	if (!gnss) {
		fprintf(stderr, "omamobile-gnss-client: no %s\n", service);
		return 1;
	}
	if (!AIBinder_associateClass(gnss, AIBinder_Class_define(GNSS_DESC, cb_create,
								 cb_destroy, proxy_transact))) {
		fprintf(stderr, "omamobile-gnss-client: %s is not an %s\n", service, GNSS_DESC);
		return 1;
	}
	fprintf(stderr, "omamobile-gnss-client: connected to %s\n", service);

	cls = AIBinder_Class_define(CB_DESC, cb_create, cb_destroy, cb_transact);
	cb = AIBinder_new(cls, NULL);
	/*
	 * The HAL's interface is @VintfStability, so it accepts only VINTF
	 * callbacks; the marker is LLNDK, not in the NDK stubs.
	 */
	if (mark_vintf)
		mark_vintf(cb);
	else
		fprintf(stderr, "omamobile-gnss-client: no AIBinder_markVintfStability\n");

	if (gnss_call(IGNSS_SET_CALLBACK, "setCallback", arg_binder, cb))
		return 1;
	gnss_call(IGNSS_SET_POSITION_MODE, "setPositionMode", arg_position_mode, NULL);
	if (gnss_call(IGNSS_START, "start", NULL, NULL))
		return 1;
	gnss_call(IGNSS_START_NMEA, "startNmea", NULL, NULL);

	while (!stopping)
		pause();

	gnss_call(IGNSS_STOP_NMEA, "stopNmea", NULL, NULL);
	gnss_call(IGNSS_STOP, "stop", NULL, NULL);
	return 0;
}
