<!-- SPDX-License-Identifier: MIT -->
# libcamera (Omarchy Mobile build)

This is Arch Linux's libcamera 0.7.2-4, rebuilt for the Pixel 7 Pro. The main
change: the simple pipeline handler learns the `gs201-csis` camera receiver,
with the software ISP on. The other patches add the phone's sensors, contrast
autofocus through the cameras' AK7375 lenses, low-light digital gain and
tuning for the software ISP. libcamera matches the simple pipeline handler only
against a fixed table of media-device driver names. So without the entry,
stock libcamera ignores our receiver, even though the soft ISP is already
built into Arch Linux ARM's package. A `configuration.yaml` can't add a
driver in 0.7.2: it can only switch the soft ISP for a driver that is already
in the table. See `device/cheetah/CAMERA-PLAN.md`, section 5.2.

| File | What it is |
| --- | --- |
| `PKGBUILD` | Arch's `libcamera` PKGBUILD at tag `0.7.2-4`, trimmed for this phone (see its header) |
| `0001-pipeline-simple-Add-the-Google-gs201-CSIS-receiver.patch` | The libcamera change, in `git format-patch` form; it also applies to upstream master |
| `0002-libcamera-Add-the-Sony-IMX386-sensor.patch` | The IMX386 sensor helper, properties and tuning stub |
| `0003-ipa-simple-agc-Step-faster-when-far-from-the-target-.patch` | Faster AGC steps far from the target |
| `0004-libcamera-Add-the-Samsung-S5KGN1-sensor.patch` | The S5KGN1 (main camera) sensor helper, properties and tuning stub |
| `0005-libcamera-software_isp-add-contrast-autofocus.patch` | Contrast autofocus in the simple IPA, and the lens plumbing in the simple pipeline (Robin Snyders) |
| `0006-software_isp-Focus-on-the-frame-centre-with-statisti.patch` | Sharpness over the frame centre, statistics every frame on cameras with a lens, lens writes only while Af runs and on a change, scan steps from tuning |
| `0007-software_isp-Steadier-contrast-autofocus.patch` | Lens settling, peak fit, a continuous mode that doesn't hunt, scans on settled exposure (cube oakley) |
| `0008-software_isp-Keep-exposure-white-balance-and-focus-a.patch` | AGC, AWB and focus survive a reconfiguration of the same mode (cube oakley) |
| `0009-software_isp-Take-contrast-and-saturation-defaults-f.patch` | Contrast and saturation defaults from the tuning file (cube oakley) |
| `0010-software_isp-Gather-GPU-statistics-over-the-visible-.patch` | GPU debayer: 3A statistics over the whole visible frame, not its top-left corner (cube oakley) |
| `0011-ipa-simple-agc-Add-digital-gain-past-the-sensor-s-li.patch` | Up to 4x digital gain once exposure and analogue gain are at their limits |
| `0012-ipa-simple-Tune-the-Pixel-7-Pro-s-ultrawide-and-main.patch` | Af on both cameras, a stand-in colour matrix for the IMX386, contrast and saturation defaults |
| `0013-libcamera-Add-the-Samsung-S5K3J1-and-S5KGM5-sensors.patch` | The front and telephoto sensors: helpers (black level 64, gain code / 32), properties, tuning files (identity matrix, Af on the telephoto) |
| `0014-pipeline-simple-Accept-a-sensor-configuration-within.patch` | A sensor mode within 1% of the stream qualifies: the front camera's 1080p runs its binned mode |
| `0015-ipa-simple-agc-Step-out-of-a-pinned-histogram-quickl.patch` | While nearly every pixel is in the darkest or brightest bin, the AGC doubles or halves the exposure each step instead of 15% |
| `0016-software_isp-debayer_egl-Destroy-the-EGL-context-whe.patch` | The GPU debayer destroys its EGL context at stop: abandoned contexts kept their last buffers imported, and a long-running camera app leaked contiguous memory until starts failed |
| `0017-ipa-simple-agc-Judge-only-frames-taken-with-the-last.patch` | The AGC judges only frames taken with its last request (plus one frame), corrects the total exposure in one step, and moves a pinned histogram by x8 or 1/16: no white/black strobing outdoors |
| `0018-ipa-simple-Carry-the-exposure-over-to-another-mode-o.patch` | A switch to another mode of the same sensor (a still from a binned preview) keeps the converged exposure and white balance instead of starting at the new mode's longest exposure |
| `0019-ipa-simple-agc-Report-the-AE-state.patch` | AeState: searching, or converged (also once every limit is reached) |
| `0020-ipa-simple-agc-Add-exposure-compensation.patch` | ExposureValue, -2 to +2 stops |
| `0021-ipa-simple-Take-the-sensor-mode-s-timings-at-configu.patch` | The IPA takes each configured mode's line length and pixel rate, not the one from camera creation |
| `0022-ipa-simple-agc-Support-manual-exposure-time-and-anal.patch` | ExposureTimeMode, AnalogueGainMode, ExposureTime, AnalogueGain, AeEnable |
| `0023-ipa-simple-awb-Support-manual-white-balance.patch` | AwbEnable, ColourGains, and ColourTemperature where the tuning file has a `ctCurve` |
| `0024-software_isp-Gather-focus-statistics-over-a-window-t.patch` | A movable focus window in the debayer parameters, and a luminance histogram over it |
| `0025-ipa-simple-Focus-and-meter-on-the-application-s-wind.patch` | AfMetering and AfWindows (tap to focus), AeMeteringMode on the window |
| `0026-ipa-simple-af-Support-pausing-continuous-autofocus.patch` | AfPause in continuous autofocus |
| `0027-ipa-simple-Support-FrameDurationLimits.patch` | FrameDurationLimits per configured mode through VBLANK, FrameDuration in metadata; the camera's controls follow the configured mode |
| `0028-software_isp-Correct-lens-shading-with-a-radial-mode.patch` | Radial lens shading correction in the GPU debayer, coefficients from the tuning file's `LensShading` |
| `0029-software_isp-debayer_egl-Add-a-noise-reduction-and-s.patch` | A second GPU pass: bilateral luma noise reduction and an unsharp mask with coring |
| `0030-ipa-simple-Add-noise-reduction-and-sharpening.patch` | The `Detail` algorithm drives that pass from the gain; the Sharpness control |
| `0031-software_isp-Gather-grey-candidates-for-white-balanc.patch` | Statistics: sums of samples that may be grey at the current white point |
| `0032-ipa-simple-awb-Use-the-grey-candidates-and-smooth-th.patch` | Grey world over the grey candidates, and gains smoothed over frames |
| `0033-ipa-simple-agc-Protect-the-highlights.patch` | The AGC keeps clipped highlights to about 2% of the picture (10% backlit) |
| `0034-software_isp-debayer_egl-Clip-highlights-to-neutral.patch` | Highlights near clipping fade to neutral: no cyan skies |
| `0035-ipa-simple-af-Scan-less.patch` | Autofocus stops the coarse scan past the peak, narrows the fine scan, and rescans locally in continuous mode |
| `0036-ipa-simple-agc-Aim-the-mean-luminance-at-20.patch` | The AGC aims the mean linear luminance at 20% of full scale |
| `0037-ipa-simple-agc-Count-highlights-as-they-come-out.patch` | The highlight cap counts what comes out clipped after the gains and tone curve |
| `0038-ipa-simple-agc-Take-a-mode-change-gently.patch` | After a mode change the AGC waits two frames more and moves a stop at most at first |
| `0039-ipa-simple-Hand-tune-the-Pixel-7-Pro-s-Samsung-senso.patch` | A hand-tuned colour matrix for the main, telephoto and front cameras (no chart) |
| `0040-ipa-simple-af-Settle-less-for-fine-steps.patch` | Fine autofocus steps settle three frames, the jump to them four |
| `0041-ipa-simple-agc-Don-t-climb-back-into-the-clipping.patch` | After a highlight cut, the exposure stays under 85% of the one that clipped |
| `0042-ipa-simple-Start-a-new-configuration-at-the-carried-.patch` | A new configuration sets the carried exposure on the sensor before streaming |
| `0043-software_isp-debayer_egl-Roll-highlights-off-and-kee.patch` | A highlight shoulder, and hue-preserving gamut mapping instead of per-channel clipping |
| `0044-ipa-simple-agc-Count-clipping-through-the-highlight-.patch` | The highlight cap counts clipping through the shoulder |
| `0045-ipa-simple-Soften-the-Samsung-sensors-hand-tuned-col.patch` | The hand-tuned Samsung matrix softened by 30% |
| `0046-software_isp-Count-the-samples-the-sensor-saturated.patch` | The statistics count the samples the sensor saturated |
| `0047-ipa-simple-agc-Mind-what-the-sensor-saturates-and-th.patch` | The highlight cap counts sensor saturation and sRGB 240, graded by the rest of the picture |
| `0048-software_isp-debayer_egl-Fade-sensor-clipped-highlig.patch` | Sensor-clipped highlights fade to neutral gently, from 80% |
| `0049-software_isp-Gather-a-histogram-of-each-sample-s-bri.patch` | A histogram of each sample's brightest colour |
| `0050-ipa-simple-agc-Choose-the-exposure-on-the-predicted-.patch` | The AGC chooses the exposure on the predicted output |
| `0051-software_isp-debayer_egl-Add-hue-vibrance-and-a-tone.patch` | Hue, vibrance and a tone curve in the GPU debayer |
| `0052-ipa-simple-Add-the-Look-algorithm-and-tune-it-on-the.patch` | The Look algorithm and its tuning for the four cameras |
| `0053-software_isp-debayer_egl-Smooth-the-chroma.patch` | Chroma noise reduction in the GPU's second pass: colour differences averaged over a 9x9 footprint, guided by luma and chroma; `chromaDenoise` in each camera's `Detail` tuning |
| `0054-pipeline-simple-Pass-the-start-controls-to-the-softw.patch` | The simple pipeline hands `Camera::start()`'s controls to the software ISP's IPA with the first request; without it a restarted camera kept the previous session's manual exposure mode |
| `0055-software_isp-debayer_egl-Correct-defective-pixels-be.patch` | Defective pixel correction in a pass before the debayer, on the packed bytes: a sample beyond its eight same-colour neighbours' range is clamped to it. `LIBCAMERA_SOFTISP_NO_DPC` turns it off |
| `0056-libcamera-Add-the-Samsung-S5KGN8-sensor.patch` | The S5KGN8 (the Pixel 9a's main camera) sensor helper, with the black level measured on the phone (64 at 10 bits) and the code / 32 gain, its properties, and an uncalibrated tuning file without a colour matrix or autofocus |
| `libcamera-fix-python3.14-macro-redefinition.patch` | Arch's patch, unchanged (sha512 `8b54cbdf…`) |
| `.SRCINFO` | `makepkg --printsrcinfo` output |

## What differs from Arch Linux ARM's `libcamera` 0.7.2-4

- The patches above.
- `arch=(aarch64)`.
- Only the `simple` and `uvcvideo` pipelines (the second is for USB cameras
  on the USB-C port), and only the `simple` IPA. The other aarch64 pipelines
  (`rkisp1`, `rpi/*`, `imx8-isi`, `mali-c55`) can't match on this phone.
- `softisp-gpu=enabled`, so the build fails if EGL is missing instead of
  quietly leaving out the GPU debayer. At runtime libcamera tries the GPU
  first and falls back to the CPU.
- No documentation and no test suite. There is no `libcamera-docs` split;
  ALARM's `libcamera-docs` 0.7.2-4 can stay installed.
- `pkgrel=4.6`, so it sorts above ALARM's 0.7.2-4.

## What the kernel side must provide

The full checklist, with `file:line` references into libcamera 0.7.2,
belongs in CAMERA-PLAN section 5.2. In short:

- The media device's driver name is `gs201-csis`.
- The sensor entity is `MEDIA_ENT_F_CAM_SENSOR`.
- The CSIS subdev passes the sink format through to its source pad, for both
  TRY and ACTIVE formats.
- The video node has `V4L2_CAP_IO_MC`, `ENUM_FMT` filtered by mbus code, and
  `ENUM_FRAMESIZES`. Its buffers are vb2 MMAP and DMABUF, with EXPBUF.
- The sensor has the `ANALOGUE_GAIN`, `EXPOSURE`, `HBLANK`, `VBLANK` and
  `PIXEL_RATE` controls.
- The kernel has a dma-buf heap (`/dev/dma_heap/*` or `/dev/udmabuf`), or
  the soft ISP isn't created.

Both debayers take CSI-2 packed RAW10 and RAW12 and 8-bit RAW. The GPU path
doesn't take unpacked 12-bit.

`0002-libcamera-Add-the-Sony-IMX386-sensor.patch` adds the IMX386's
`CameraSensorHelper` (black level 64 at 10 bits, measured on the phone in
CAM4.3; the analogue gain model of the IMX258, code 0-480 for 1x-16x,
confirmed by the CAM4.3c gain sweep), its sensor properties (1.25 um
unit cell, the driver's CCS test pattern numbers, two-frame delays) and
`imx386.yaml`, an uncalibrated tuning file for the simple IPA. The sweep
showed the register is 9 bits wide (codes from 512 wrap), so 480 stays the
top.

`0003-ipa-simple-agc-Step-faster-when-far-from-the-target-.patch` makes the
simple IPA's AGC take larger steps (proportional gain 0.1, still at most 15%)
while the exposure error is above 1.0; near the target it keeps upstream's
0.04. Indoors the first frames otherwise stayed black for seconds.

## Autofocus, low light and colour (0004-0012)

The simple IPA gets contrast autofocus. The simple pipeline finds a lens
through the sensor's media ancillary link (the DT `lens-focus` property; the
`ak7375` driver gives `V4L2_CID_FOCUS_ABSOLUTE` 0-4095) and passes its
controls to the IPA, which runs a coarse scan over the range, a fine scan
around the sharpest coarse sample and a parabola fit of the peak, and then
watches the sharpness in continuous mode. The sharpness is the squared
difference of neighbouring green samples over the centre half of the frame,
divided by their sum. It needs a lens and an `Af` entry in the tuning file:
without either, nothing writes to a lens and no autofocus metadata is
reported. `coarseSteps`, `fineSteps` and `range: [ min, max ]` in the `Af`
entry set the scan; restricting `range` to the lens's useful travel, once it
is measured, makes scans shorter. On a camera with a lens, statistics run
every frame instead of every fourth: more CPU time per frame for the
statistics, and AGC steps as often as the sensor's two-frame delay allows.
Applications set `AfMode` (`Manual`, `Auto` with `AfTrigger`, `Continuous`,
the default) and, in manual mode, `LensPosition` as 0.0-1.0 of the range
(not dioptres: the lens isn't calibrated).

Once the exposure and the analogue gain are at their limits, AGC adds up to
4x digital gain, applied with the white balance gains; it is reported as
`DigitalGain`.

`imx386.yaml` uses the IMX519 colour matrices from libcamera's Raspberry Pi
tuning (`src/ipa/rpi/vc4/data/imx519.json`, BSD-2-Clause) as a stand-in until
the IMX386 is calibrated: without a matrix the software ISP shows the sensor's
own, desaturated colours. `s5kgn1.yaml` has the identity. Both set a contrast
default of 1.2 (Snapshot and most apps don't set it); the S5KGN1 adds
saturation 1.1.

`s5k3j1.yaml` (front, fixed focus) and `s5kgm5.yaml` (telephoto, Af on its
SEM1215SA with the main camera's step counts) have the identity, contrast 1.2
and saturation 1.1 (0013). The kernel gives each of the three Samsung parts
its own entity name, which is how libcamera picks the helper and the file.

What the software ISP still lacks: denoising, lens shading correction,
sharpening and a calibrated colour pipeline. White balance is grey-world.
Pictures stay noisier and softer at the corners than with Google's ISP.

## Camera-app controls (0019-0026)

| Feature | Controls | Range | Notes |
| --- | --- | --- | --- |
| AE state | `AeState` (out) | Idle, Searching, Converged | Converged also when every limit is reached; wait for it before keeping a still |
| Exposure compensation | `ExposureValue` | -2.0 to +2.0 | Applies while either exposure time or gain is auto |
| Manual shutter | `ExposureTimeMode`, `ExposureTime` (µs) | From the sensor at camera creation | Clamped to the configured mode's frame time: no exposure longer than a frame |
| Manual ISO | `AnalogueGainMode`, `AnalogueGain` | 1.0 to the sensor's maximum | With one manual, AE drives the other and digital gain |
| AE lock | `AeEnable` false | | Holds exposure, gain and digital gain; the mode controls in the same request win |
| White balance | `AwbEnable`, `ColourGains` [r, b] | 0.25 to 4.0 | `AwbEnable` false without gains holds the current ones |
| White balance presets | `ColourTemperature` | The tuning file's `ctCurve` range | Only the IMX386 has a curve (a stand-in); other cameras don't advertise it |
| Tap to focus and meter | `AfMetering` Windows, `AfWindows` | The sensor's active area stands for the whole picture | At least a tenth of the picture a side; the first rectangle counts |
| Metering | `AeMeteringMode` | Matrix (default), Spot, CentreWeighted | Spot meters the `AfWindows` rectangle, or the centre half |
| Focus lock | `AfPause` | Immediate, Deferred, Resume | Continuous mode; `AfPauseState` reported |
| Manual focus | `AfMode` Manual, `LensPosition` | 0.0 to 1.0 | Normalised lens travel, not dioptres |
| Frame rate | `FrameDurationLimits` [min, max] µs | Per configured mode, in `camera->controls()` after `configure()` | `FrameDuration` reported; without limits the driver's default (30 fps) |
| Sharpening | `Sharpness` | 0.0 to 4.0, default 1.0 | Scales the tuning file's amount; smaller at high gain |
| Lens shading | `LensShadingCorrectionEnable` | bool | Only where the tuning file has `LensShading` |

## Status

0.7.2-4.4 (0001-0003) runs on the phone: the ultrawide captures end to end.
0.7.2-4.18 adds 0049-0052 (2026-10-16): an AGC that predicts the output
(brighter, no hunting), and hue, vibrance and a shadow-lifting tone curve.
0.7.2-4.17 adds 0046-0048 (2026-10-16): the highlight cap counts what the
sensor saturates and near-white output, lamps don't darken a room, and no
hard ring in a clipped sky.
0.7.2-4.16 adds 0042-0045 (2026-10-15): stills no longer start at the
mode's longest exposure, overcast skies keep gradation through a shoulder,
saturated colours keep their hue, and softer hand-tuned colours.
0.7.2-4.15 adds 0037-0041 (2026-10-15; 4.14 was the same without 0041):
overcast skies no longer clip (the cap counted the raw top 3%, not what the
gains and tone curve clip), a gentler first step after a mode change,
hand-tuned colours for the Samsung sensors, and shorter autofocus settling.
0.7.2-4.13 adds 0033-0036 (2026-10-15): daylight stills were about 1.5
stops bright because the AGC aimed the mean of a coarse linear histogram at
its middle (45% of full scale); it now aims the mean luminance at 20%,
caps clipped highlights and clips them to neutral; autofocus scans less.
0.7.2-4.12 adds 0027-0032 (2026-10-14): 60 fps through FrameDurationLimits
(measured: ultrawide 59.5, front 59.9 fps at 1920x1080 with the second pass,
the cam process at 19% of one core), lens shading (not tuned yet), noise
reduction and sharpening, and a white balance that ignores colourful
surfaces. The picture quality of 0028-0032 is still to be judged in daylight.
0.7.2-4.11 adds 0019-0026 (2026-10-14): the camera-app controls below.
0.7.2-4.9 adds 0017 and 0018 (2026-10-14): the AGC no longer oscillates
outdoors, and a still taken from the preview starts at the preview's exposure.
0.7.2-4.8 adds 0016 (2026-10-14): no DMA-BUF leak across stop/start.
0.7.2-4.7 adds 0015 (2026-10-14): the AGC leaves a pinned histogram quickly.
0.7.2-4.6 adds 0013-0014 (2026-10-13, off the phone): all 14 patches
apply in order to `v0.7.2`; a minimal x86_64 build (simple pipeline and
IPA) compiles without warnings; both new tuning files parse.

0.7.2-4.5 (0004-0012) is checked off the phone only (2026-10-13):

- All patches apply in PKGBUILD order to a clean `v0.7.2` checkout with
  `patch -Np1`.
- An x86_64 build of the patched tree with the PKGBUILD's options
  (`simple,uvcvideo`, `softisp-gpu=enabled`, `v4l2`, cam, qcam and the
  GStreamer plugin; no Python bindings on the build host) compiles without
  warnings.
- libcamera's YAML parser reads both tuning files, the S5KGN1 helper gives
  1x and 16x at codes 0x20 and 0x200, and the autofocus algorithm, run on a
  synthetic sharpness curve with a two-frame lens delay, settles within one
  fine step of the peak (about 3 s at 30 fps on the main camera's settings,
  2 s on the ultrawide's).
- `makepkg --printsrcinfo` runs.

To check on the phone, after the AK7375 nodes and the `lens-focus` links are
in the kernel:

```sh
media-ctl -p -d /dev/media0 | grep -B2 -A6 ak7375     # lens entity, ancillary link to the sensor
LIBCAMERA_LOG_LEVELS=IPASoftAf:0,IPASoftExposure:1,SoftwareIsp:1 \
  cam -c1 --capture=150 --file=/tmp/af-#.ppm 2>&1 | grep -E 'Focus range|focus sample|Autofocus completed'
```

Expect "Focus range 0-4095", coarse then fine samples, and "Autofocus
completed at N" within about 100 frames; the frames before and after it should
go from soft to sharp. Without a lens the log says "No focus lens control
available" once and nothing else changes. In a dim room, `IPASoftExposure:0`
shows `dgain` rising above 1 only once `again` is at 16.

## Building on the phone

```sh
tools/phone-install-package packages/libcamera
```

The tool's `pacman -U` glob (`libcamera-*`) installs `libcamera`,
`libcamera-ipa` and `libcamera-tools`. `gst-plugin-libcamera` and
`python-libcamera` are built too; install them by hand if needed.

Then try `cam -l` and `cam -c1 --capture=1 --file=frame.ppm`, after the
camera kernel stages in CAMERA-PLAN. Without Panthor rendering, the GPU
debayer runs on llvmpipe. To compare it with the CPU path, set
`LIBCAMERA_SOFTISP_MODE=cpu`.

Rebase on each new ALARM libcamera release, and drop the patch once
upstream ships the entry. Send it upstream together with the kernel driver;
the human adds `Signed-off-by:`.
