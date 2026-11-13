# SPDX-License-Identifier: MIT
# omamobile-install-screen (docs/INSTALL-LINK-PLAN.md §3.3), and the test
# program that draws it into a PNG (never installed).
#
#   make [OUT=DIR] [VERSION=X]        the program, into OUT (default: .)
#   make OUT=DIR render-test          the test program, with zlib
#
# libdrm and freetype2 are in every root image (Mesa and fontconfig need
# them); the flags come from pkg-config.
OUT ?= .
VERSION ?= $(shell cat ../version 2>/dev/null || echo 0)
PKG_CONFIG ?= pkg-config
CC ?= cc
CFLAGS ?= -O2 -g
XCFLAGS = -std=gnu11 -Wall -Wextra -Wshadow -Wno-unused-parameter
XCPPFLAGS = -DVERSION='"$(VERSION)"' $(shell $(PKG_CONFIG) --cflags libdrm freetype2)
LDLIBS_SCREEN = $(shell $(PKG_CONFIG) --libs libdrm freetype2)

COMMON = model.c theme.c render.c
SCREEN = $(COMMON) main.c drm.c fb.c plymouth.c keys.c link.c

all: $(OUT)/omamobile-install-screen

$(OUT)/omamobile-install-screen: $(SCREEN) screen.h
	@mkdir -p $(OUT)
	$(CC) $(CPPFLAGS) $(XCPPFLAGS) $(CFLAGS) $(XCFLAGS) $(LDFLAGS) -o $@ $(SCREEN) $(LDLIBS_SCREEN)

render-test: $(OUT)/render-test
$(OUT)/render-test: $(COMMON) render-test.c screen.h
	@mkdir -p $(OUT)
	$(CC) $(CPPFLAGS) $(XCPPFLAGS) $(CFLAGS) $(XCFLAGS) $(LDFLAGS) -o $@ $(COMMON) render-test.c $(shell $(PKG_CONFIG) --libs freetype2 zlib)

.PHONY: all render-test
