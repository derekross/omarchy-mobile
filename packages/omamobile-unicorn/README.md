<!-- SPDX-License-Identifier: MIT -->
# omamobile-unicorn

[Unicorn](https://github.com/unicorn-engine/unicorn) 2.1.4, the CPU
emulator `tools/extract-camera-data` runs the camera HAL's table builders
in, built from upstream's source the way upstream's own Python wheel is
built, for the one package that needs it:
[omamobile-provision](../omamobile-provision/README.md), whose camera step
runs on the phone.

It has not run on a phone yet (below).

## Why the phone needs its own build

With Arch Linux ARM's `python-unicorn` 2.1.4-2 the camera step, and the
repository's `tests/extract-camera-sve.py`, end like this (exit 134):

```
qemu/target/arm/helper.c:5686: sve_zcr_get_valid_len: Assertion `end_len < start_len' failed.
```

With upstream's wheel of the same version the same test passes. The two
differ in one build setting:

| | The distribution's library | Upstream's wheel |
| --- | --- | --- |
| Build type | `-DCMAKE_BUILD_TYPE=None` (its PKGBUILD): no `-DNDEBUG`, so `assert()` stays | `Release` (`bindings/python/setup.py`, unless `DEBUG` is set): CMake's `-O3 -DNDEBUG`, so `assert()` is compiled out |
| `__assert_fail` among the library's imports | yes | no |
| The text `end_len < start_len` in the library | yes | no |

The assertion itself is a gap in Unicorn 2.1.4, not in the tool: the
emulated CPU's table of supported SVE vector lengths (`sve_vq_map`) is
never filled (`arm_cpu_sve_finalize` is commented out in
`qemu/target/arm/cpu.h`, and nothing else writes the table), so
`sve_zcr_get_valid_len()` finds no valid length and asserts on the first
instruction that needs one. With the assertion compiled out the function
returns the length `ZCR_EL1` asks for, which is what the wheel has always
done. Nothing in Unicorn's interface reaches that table, so the tool can't
avoid the assertion by a setting.

Checked on 2026-11-12 in the project's aarch64 build container (Arch
Linux ARM under qemu-user), from the same source tarball, with only the
build type changed (`-DUNICORN_ARCH=aarch64`, GCC 16.1.1):

| Build | `-DNDEBUG` | Assertion text in the library | `tests/extract-camera-sve.py` |
| --- | --- | --- | --- |
| `None` | no | yes | aborts, exit 134, the line above |
| `Release` | yes | no | 5 of 5 pass |
| The distribution's `python-unicorn` 2.1.4-2 | | yes | aborts, exit 134 |

## What it installs

| Path | What |
| --- | --- |
| `/usr/lib/omamobile-unicorn/python/unicorn/` | the Python binding, `bindings/python/unicorn` of the tarball unchanged (pure Python over `ctypes`; the same files as in the wheel) |
| `/usr/lib/omamobile-unicorn/python/unicorn/lib/libunicorn.so.2` | the library: a Release build with the AArch64 target only |
| `/usr/share/licenses/omamobile-unicorn/` | `COPYING` (GPL 2), `COPYING.LGPL2`, `COPYING_GLIB`, `AUTHORS.TXT`, `CREDITS.TXT` |
| `/usr/share/doc/omamobile-unicorn/README.md` | this file |

**Private.** Nothing is installed in Python's `site-packages`, in
`/usr/lib` itself, in `/usr/include` or for `pkg-config`; the package
provides, replaces and conflicts with nothing. The distribution's `unicorn`
and `python-unicorn` can be installed beside it, and every program other
than the camera step goes on finding those. A program gets this copy only
by putting `/usr/lib/omamobile-unicorn/python` first on its module path, as
`omamobile-provision` does for `extract-camera-data` (`PYTHONPATH`). The
binding looks for its library in its own `lib/` directory before the
system's; only `LIBUNICORN_PATH` in the environment comes before that, and
`omamobile-provision` gives its tools an environment without it.

No Python version is part of the path and no bytecode is shipped, so a
Python upgrade needs no rebuild.

**AArch64 only.** `-DUNICORN_ARCH=aarch64` leaves out the other nine
targets, which the tool never uses. Under qemu-user that is most of the
build's time and most of the library's size.

## Licence and source

Unicorn is GPL-2.0-only as a whole: it is built on QEMU's CPU emulation
(`qemu/` in the tarball, GPL 2 with LGPL parts) and a cut-down GLib
(`glib_compat/`, LGPL). The package is built from upstream's unmodified
release tarball, with no patch:

```
https://github.com/unicorn-engine/unicorn/archive/refs/tags/2.1.4.tar.gz
sha256 ea8863f095a0136388694e5a6063afd9bb7650e30243dd6251af59c5ce5601f4
```

That tarball and this directory's `PKGBUILD` are the complete corresponding
source of the binary. Whoever publishes the binary package should keep the
tarball available beside it for as long as the package is offered.

`tools/extract-camera-data` (MIT) imports the library into its own process,
as it did with the distribution's `python-unicorn` and with the wheel.

## Tests

`test/all` (offline, no phone, any machine) checks the package's shape: the
pinned tarball, the Release build type, the single target, that nothing is
installed outside the private directory, that nothing is provided or
conflicted with, and that `omamobile-provision` depends on this package and
names its directory.

`test/all --built DIR` runs the built copy, so it needs an aarch64 machine
(or the build container): `test/sve-check.py` (the binding and the library
are 2.1.4, both loaded from `DIR` and not from the system, and SVE
instructions of our own run on the `max` CPU), then the repository's
`tests/extract-camera-sve.py`, unchanged, with `DIR` first on the module
path. A SIGABRT there is reported as the abort coming back. The PKGBUILD's
`build()` ends with this, so a library that aborts is never packaged, with
`--nocheck` or without. `test/all --installed` is the same for the
installed package.

`./stage-tools` copies `tests/extract-camera-sve.py` and
`tools/extract-camera-data` into `test-staged/` (gitignored) for builds
that see this directory alone; `tools/build-packages`,
`tools/phone-install-package` and `tools/repo-build` run it first.

## Not yet done

- **A run on a phone.** Everything above ran under qemu-user. The wheel of
  the same version, built the same way, passed the same test natively on a
  Pixel 7 Pro on 2026-11-12; this package's own library has not run there.
- **Updating.** A new Unicorn release means a new `pkgver`, a new checksum
  and a rebuild; if upstream fills the vector length table, the
  distribution's package may do again and this one can go.
