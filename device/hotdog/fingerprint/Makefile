# SPDX-License-Identifier: MIT
# Builds the OnePlus 7T Pro (hotdog) fingerprint chroot's bionic (aarch64)
# programs on the computer, with the Android NDK alone (r27 or later):
#
#   out/omamobile-fp-ion-shim.so      the hotdog preload shim: /dev/ion on
#                                     our qseecom compat driver, sg for the
#                                     RPMB LU's bsg node, no privilege drops
#                                     (preloaded after fingerprint/shim's
#                                     omamobile-fp-shim.so)
#   out/omamobile-fp-hotdog-bridge    fprintd's way in: it loads OnePlus's
#                                     legacy HAL module itself (no HIDL)
#   out/omamobile-fp-shim.so          the Pixel stack's property shim, at
#                                     Android 10's API level
#
#   make NDK=~/Android/Sdk/ndk/<version> OUT=<checkout>/packages/omamobile-device-hotdog/prebuilt
#
# (omamobile-device-hotdog's install packages them from there)
#
# Nothing links against the vendor's C++: the bridge reaches the HAL
# through its C ABI (fingerprint_device_t) and Gatekeeper through plain
# pointers, so the NDK's static libc++ is enough. Tested 2026-11-04 with
# NDK r28c (README.md, FINGERPRINT-PLAN.md section 7).
API      ?= 29
OUT      ?= out
CFLAGS   ?= -O2
WARN     := -Wall -Wextra -Werror

ifndef NDK
$(error set NDK=<android-ndk>)
endif
BIN      := $(NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin
CC       := $(BIN)/aarch64-linux-android$(API)-clang
CXX      := $(BIN)/aarch64-linux-android$(API)-clang++

all: $(OUT)/omamobile-fp-ion-shim.so $(OUT)/omamobile-fp-hotdog-bridge $(OUT)/omamobile-fp-shim.so

$(OUT)/omamobile-fp-ion-shim.so: omamobile-fp-ion-shim.c
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(WARN) -fPIC -shared -o $@ $< -ldl

$(OUT)/omamobile-fp-hotdog-bridge: omamobile-fp-hotdog-bridge.cpp
	@mkdir -p $(OUT)
	$(CXX) -std=c++17 $(CFLAGS) $(WARN) -fno-exceptions -fno-rtti -static-libstdc++ \
		-o $@ $< -ldl

$(OUT)/omamobile-fp-shim.so: ../../../fingerprint/shim/omamobile-fp-shim.c
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(WARN) -fPIC -shared -o $@ $< -ldl

clean:
	rm -rf $(OUT)

.PHONY: all clean
