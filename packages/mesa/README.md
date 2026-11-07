<!-- SPDX-License-Identifier: MIT -->
# mesa (Omarchy Mobile build)

Arch Linux's Mesa 26.2.4 package, rebuilt for the Pixel 7 Pro and the
Pixel 6 and 6 Pro, with additional Pixel 9a Mali-G715 support. Mali-G710
(gs201) and Mali-G78 (gs101, with upstream's G68 next to it) are added to
Panfrost's model table. Without an entry, Mesa
rejects the GPU (for the G710 even when Panthor is loaded): the Gallium
driver bails out on an unknown model, and PanVK returns
`VK_ERROR_INCOMPATIBLE_DRIVER`. See `device/cheetah/GPU-PLAN.md`, section 4.

| File | What it is |
| --- | --- |
| `PKGBUILD` | Arch's `mesa` PKGBUILD at tag `1-26.2.4-1`, trimmed for this phone (see its header) |
| `0001-panfrost-add-Mali-G710-to-the-model-table.patch` | The G710 entry, in `git format-patch` form |
| `0002-panfrost-don-t-make-image-BOs-private-on-panthor.patch` | Image BOs are always shareable: panthor can't export a BO private to one GPU VM, and GTK 4 exports GL textures made without `PIPE_BIND_SHARED` (GNOME Snapshot crashed after photos with "drmPrimeHandleToFD() failed (err=22)") |
| `0003-panfrost-Advertise-Mali-G68-support.patch` | Upstream's G68 entry (93d2c51f, Markuss Broks), backported to 26.2.4 |
| `0004-panfrost-add-Mali-G78-to-the-model-table.patch` | The G78 entry (Valhall v9), with the G68's tile-buffer sizes and rates and the G78 counter layout. Gallium only: PanVK still refuses the G78 |
| `0005-*` | Upstream G715 model entry, variant 4; the model entry alone is insufficient |
| `0006-*` | Upstream CSF NOP payload/type prerequisite |
| `0007-*` through `0010-*` | Upstream architecture 11 XML, shared build, Gallium and PanVK support |
| `UPSTREAM.md` | Merge request text for upstream Mesa |
| `.SRCINFO` | `makepkg --printsrcinfo` output |

## What differs from Arch Linux ARM's `mesa`

- The patches above.
- `arch=(aarch64)`.
- Only drivers this phone can use:
  - Gallium `panfrost` (which brings `kmsro`), `llvmpipe`, `softpipe` and `zink`.
  - Vulkan `panfrost` (PanVK).
  - The `device-select` and `anti-lag` layers.
- Only three split packages: `mesa`, `vulkan-panfrost` and
  `vulkan-mesa-implicit-layers` (which `vulkan-panfrost` depends on).
- `pkgrel=1.4`. makepkg only accepts `integer[.integer]`, so the Omarchy Mobile
  marker is in Mesa's version string instead: `26.2.4-arch1.1.4.omamobile4`.
  That string shows up in `GL_VERSION` and in the `libgallium-*.so` file name.

The other ALARM split packages (`vulkan-swrast`, `opencl-mesa` and so on)
don't depend on `mesa`'s exact version. They can stay installed at
`1:26.2.4-1`.

## Status

The earlier G715 backport package built natively on ARM64 with verified
source checksums/signature and zero-fuzz patch application. G715 GLES 3.1
offscreen pixel readback and the accelerated Omarchy desktop passed on
the private Pixel 9a kernel. This does not qualify Vulkan conformance,
suspend, DVFS or a public source-built tegu kernel.

This candidate preserves main's existing G68/G78 patches byte-for-byte
and adds the six G715 backports. All ten patches apply with zero fuzz to
the checksummed 26.2.4 source; SHA256 and BLAKE2 checksums, generated metadata
and shell syntax pass. The combined series builds all three packages
natively in the ARM64 build container, with the upstream source signature
verified. On 2026-10-23 the exact revised combined package was installed
on the Pixel 9a's private kernel. System-library GLES 3.1 pixel readback
passed on Mali-G715 MC7, returning RGBA (64, 128, 191, 255). Package file
verification passed; the phone smoke report has no required failures,
with the slot-suffix check and unavailable peripherals reported as skips.
The existing desktop session was not restarted for this test. Vulkan,
suspend and a public source-built tegu kernel remain untested.

The G710 and G78 build paths remain enabled. Their earlier hardware
results are unchanged; this combined package has not been retested on
those devices. The maintainer will check the G710 before publication.

Vulkan on the G715 is **off by default** upstream unless
`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` is set. Building PanVK's v11 path does
not establish working Vulkan or conformance; do not enable that override
as a package default.

### Upstream sources

| Patch | Upstream commit | Source merge request |
| --- | --- | --- |
| 0005, G715 model | [73210bf6](https://gitlab.freedesktop.org/mesa/mesa/-/commit/73210bf69dfa4cfb5d5c5b3b7c6c91a05209e2b6) | [41803](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/41803) |
| 0005, corrected rates | [b057153f](https://gitlab.freedesktop.org/mesa/mesa/-/commit/b057153fb11d130c5efe665cd0bc04bd1d9be737) | [44111](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44111) |
| 0006, CS NOP prerequisite | [13b01bef](https://gitlab.freedesktop.org/mesa/mesa/-/commit/13b01befb6083f435384ec547d9a8d8994bee741) | [43264](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/43264) |
| 0007, v11 XML | [06efd854](https://gitlab.freedesktop.org/mesa/mesa/-/commit/06efd8542f442e701685e26abe4d73c4ddf7b249) | 41803 |
| 0008, shared build | [9ff413aa](https://gitlab.freedesktop.org/mesa/mesa/-/commit/9ff413aa28e7d91b8b88a97adf439f252df72496) | 41803 |
| 0009, Gallium | [958205d6](https://gitlab.freedesktop.org/mesa/mesa/-/commit/958205d63ec535eb0ab48aaaea98a193f44389d3) | 41803 |
| 0010, PanVK | [c66177bd](https://gitlab.freedesktop.org/mesa/mesa/-/commit/c66177bdc90e06aa336357da2e4de0aec6d127d6) | 41803 |

Patch 0005 combines Erik Faye-Lund's G715 model and Marc Alcala Prieto's
rate fix, retaining their upstream review metadata separately. It omits
the G615 row and the model commit's documentation hunks. The PanVK patch
adjusts one context-only CSF filename for 26.2.4. Other upstream patch
contents and original authorship/review trailers are unchanged.
Keep the original project licenses. Drop backports when a packaged release
contains them; do not mistake a model string for working architecture support.

## Building on the phone

As a normal user in the Arch root, with internet:

```sh
sudo pacman -S --needed base-devel
gpg --recv-keys 57551DE15B968F6341C248F68D8E31AFC32428A6   # Eric Engestrom, signed 26.2.4
cd packages/mesa
makepkg -s                       # pulls the makedepends listed in the PKGBUILD
sudo pacman -U mesa-1:26.2.4-1.4-aarch64.pkg.tar.zst \
  vulkan-panfrost-1:26.2.4-1.4-aarch64.pkg.tar.zst \
  vulkan-mesa-implicit-layers-1:26.2.4-1.4-aarch64.pkg.tar.zst
```

Until Panthor exposes `/dev/dri/renderD128`, nothing changes visibly:
`kmsro` finds no render node and Mesa keeps using `kms_swrast`.

To stop `pacman -Syu` from replacing the build with ALARM's `mesa`, add this
line to `/etc/pacman.conf`:

```
IgnorePkg = mesa vulkan-panfrost vulkan-mesa-implicit-layers
```

Alternatively, publish the build in Omarchy Mobile's own repo listed ahead of
`[extra]`. Rebase on each new ALARM Mesa release:

1. Take the new Arch tag.
2. Re-apply the trimming.
3. Check that the patch still applies.

Drop the G710 and G78 patches once upstream Mesa ships their entries, and
the G68 backport (0003) once a Mesa release carries it.

On the Pixel 6 Pro (raven) the G78 patch runs GLES 3.1 with Hyprland on
top. It needs the kernel's AArch64 page-table quirk for gs101 in
Panfrost, or every fragment job faults.
