<!-- SPDX-License-Identifier: MIT -->
# dipper (Xiaomi Mi 8) — first-light runbook

**Read §0 first. dipper is not a Pixel and the shared safety model does not apply to it.**

## 0. Why this device needs its own runbook

The project's safety model is "stock Android stays on slot A, we only ever write slot B".
**dipper has no second OS slot.** Measured on the phone: one `boot` (64 MiB), one
`recovery` (64 MiB), one `system`, one `vendor`, one `userdata` (113 GiB). Only the
bootloader chain is slotted (`xbl`, `abl`, `tz`, `hyp`, `aop`, `cmnlib`, `devcfg`,
`keymaster`, `qupfw`, `storsec`), and this port never writes any of it.

Consequences, stated plainly:

- **A bad `boot` image means a bootloop with nothing to fall back to.** The way out is
  physical: power off, hold **Volume Down + Power** until "FASTBOOT" appears, then
  `fastboot flash boot boot.img` with the stock image from the backup.
- **`fastboot` is USB-only.** There is no fastboot over a network. Tailscale and SSH
  reach the *running* phone; they are not a recovery path. **Do not attempt any of
  this without the phone in hand and a cable.**
- So: **step 2 below boots from RAM and writes nothing.** Do not flash until that has
  worked.

## 1. Before anything: a verified stock backup

```sh
tools/dipper/backup-stock                 # boot, recovery, dtbo, vbmeta, persist,
                                          # modemst1/2, fsg, fsc, devinfo, misc, frp,
                                          # logo, splash  (~460 MiB)
tools/dipper/backup-stock --with-firmware # adds modem (192 MiB) and dsp (32 MiB)
```

It reads each partition over SSH and compares a `sha256sum` taken **on the phone**
against one taken locally; a mismatch deletes the file and fails the run. Keep the
output and checksums in an operator-controlled backup location outside the repository.

`persist` and `modemst1`/`modemst2` hold per-device calibration and the modem's NV.
They cannot be downloaded from anywhere. Keep this backup even if you never flash.

## 2. Build, then boot from RAM — nothing is written

```sh
# kernel (once): mainline 7.3-rc6 tree + our fragment
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image.gz dtbs modules
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/sdm845-xiaomi-dipper.dtb

# initramfs (aarch64 container) + the Android v1 boot image
tools/dipper/build

# full Arch/Omarchy root image (keep the signed source packages and local key private)
tools/fetch-published out/dipper/published
tools/build-packages --local dipper --import out/dipper/published \
  packages/qrtr packages/pd-mapper packages/tqftpserv packages/rmtfs \
  packages/omamobile-device-dipper
KERNEL_OUT=../out/dipper DEVICE=dipper tools/build-rootfs --local dipper
```

The host needs `zopfli` for the smaller kernel gzip stream that fits dipper's ABL
limit; `tools/dipper/build` uses it when available and `build-boot.py` refuses an
oversized kernel. The build also stages the private modem/WLAN firmware and the
module archive under `out/dipper/` for the root image.

Then, phone powered off, **Volume Down + Power** until "FASTBOOT" shows:

```sh
fastboot getvar unlocked        # must say yes. Android's props on this phone are
                                # spoofed and cannot be trusted for this.
fastboot boot out/dipper/images/boot.img
```

`fastboot boot` runs the image from RAM. **It does not touch `boot`.** A power cycle
returns the phone to stock, whatever happens. This is the only step that is safe to
repeat freely, so iterate here.

What success looks like: a USB network device appears on the laptop
(`Xiaomi Mi 8 Omarchy`, CDC NCM plus an ACM console), and

```sh
tools/phone-ssh --fresh -- 'id'
```

gets a shell from the initramfs. The rescue sshd is bound to `172.16.42.1` only —
never to Wi-Fi. There is no display yet at this stage: the console is the USB link.

If nothing appears: the ACM console (`/dev/ttyACM0`, 115200) carries the kernel log.
If not even that, the kernel did not reach the initramfs; power-cycle and read §4.

## 3. Only then: flash

Do not do this until §2 has booted and you have §1's backup verified.

```sh
fastboot flash boot out/dipper/images/boot.img
fastboot reboot
```

To go back to stock at any time:

```sh
fastboot flash boot "$VERIFIED_STOCK_BOOT_IMAGE"
```

Set `VERIFIED_STOCK_BOOT_IMAGE` to the checksum-verified stock image in the
private backup before running the recovery command.

**Never flash** `xbl*`, `abl*`, `tz*`, `hyp*`, `aop*`, `cmnlib*`, `devcfg*`,
`keymaster*`, `qupfw*`, `storsec*`, `modem`, `modemst1`, `modemst2`, `fsg`, `persist`,
`vbmeta` or `devinfo`. Nothing in this port needs them, and several of them are
unrecoverable per-device data.

`userdata` is not touched by any step above. Installing a full Omarchy root later
**erases it**, which also removes stock Android's data — that is a separate decision,
not part of first light.

## 4. Known unknowns at first light

- **Touch** is an ST FTS5 controller (`st,fts` downstream, `fts@49` on `i2c14`). The
  DTS uses `st,stmfts5` and the kernel carries upstream's FTS5 driver and controller-ready
  wait fix, whose series was tested on Mi 8. On the updated RAM boot, the driver bound and
  a physical tap produced `ABS_MT_POSITION_X`, confirming basic touch input. Full
  coordinate/gesture coverage is open; firmware loading, low-power touch and wake-on-touch
  are not implemented.
- **Display.** The panel is Samsung EA8074 in **command mode** (the stock kernel's
  `dsi_ss_ea8074_notch_fhd_cmd_display`, and `qcom,mdss-dsi-panel-type = "dsi_cmd_mode"`
  in the stock tree), but the recovered panel driver sets `MIPI_DSI_MODE_VIDEO_BURST`.
  That mismatch is left exactly as its author wrote it, because changing untested
  timing blind is worse than reporting it. Expect the display to need work.
- **Sound** will not probe: the DTS asks for `ti,tas2559`, whose driver exists only in
  the `sdm845-mainline` fork, not upstream.
- **Modem/Wi-Fi, cameras, fingerprint (Goodix), suspend**: not yet tested on mainline.
- The shared initramfs crashes deliberately after 20 s with no USB host, expecting ABL
  to fall back to slot A. **On dipper there is no slot A**, so that path just reboots
  into the same image. With `fastboot boot` this is harmless; after flashing it is a
  bootloop, exited with Volume Down + Power.
