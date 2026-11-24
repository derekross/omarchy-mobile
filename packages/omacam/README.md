# omacam

Omamobile's camera app, shown as "Camera": all four cameras on
libcamera directly, one zoom control from the ultrawide to the telephoto,
full-resolution photos, tap to focus ([CAMERA-APP-PLAN](../../docs/CAMERA-APP-PLAN.md)).
It lives in its own repository, [github.com/derekross/omacam](https://github.com/derekross/omacam)
(GPL-3.0-or-later); this package builds a release tag from there.
`omamobile-apps` depends on it.

- **A new release:** tag it in omacam (`vX.Y.Z`), set `pkgver` here, put
  the tarball's sha256 in `sha256sums`
  (`curl -sL https://github.com/derekross/omacam/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`),
  and run `tools/build-packages packages/omacam`.
- **Build time:** about 18 minutes under qemu-user in `tools/build-packages`
  (0.1.6 on the laptop, 2026-10-14). While developing omacam itself,
  cross-compile with its `bin/cross` (minutes, then seconds) and copy the
  binary to the phone; the package is for releases.
- `check()` runs omacam-core's tests (the camera logic) under qemu.
