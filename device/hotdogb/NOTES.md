<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T (hotdogb) bring-up notes

## 2026-11-24: development kernel and boot slot

One retail OnePlus 7T ran Arch Linux ARM and Omarchy on a development
Linux `7.3.0-rc6-sm8150-omamobile` build (image `local32k73`, kernel source
`ca9170255`). Four RAM boots preceded a clean flash boot. That
development setup used **boot_a**, left the existing `dtbo_a` in
place and used storage on `userdata`. There was no bootable stock
Android fallback on the other slot. This predates the guarded plan in
[BRINGUP-M1](BRINGUP-M1.md). Release installation, automatic boot
updates and slot success marking are outside the current port.

These observations cover the development image and the explicitly named
earlier builds. The descriptor, device package and candidate kernel
topics in this submission still need an attended integration test.

| Subsystem | Evidence and limits |
| --- | --- |
| Display, GPU | Native Samsung OLED modesetting and Adreno A640 rendered the Omarchy desktop on the 7.3 line. On local29, the display stayed at a fixed size through a 15-minute Waydroid run after the window rule change, with no GPU faults at 42 minutes of uptime. The local32 evidence is from boot and hardware checks. |
| Touch and buttons | The 7.3 line used the in-tree RMI4 I²C stack and F12 rather than prebuilt modules. Touch and the alert slider were exercised on the development line. No full button or wake-gesture retest was recorded for local32. |
| USB networking | CDC NCM stalled on transfers from the phone when all requests were busy and the flush timer could no longer drain a partial NTB. Local28 rearmed the timer on a busy result and completed 200 transfers without a stall. |
| Wi-Fi and Bluetooth | Both came up during repeated local26/local27 boots and were present on the local32 flash boot. This records station Wi-Fi and controller bring-up. Bluetooth profiles were outside this retest. |
| Speakers and mic | WCD9340/Tavil capture and TFA9874 speaker playback. On local27 a 1 kHz tone on each channel was audible and registered at the handset mic. The card came up on local32. The amplifiers lack stock speaker protection. See the [device package](../../packages/omamobile-device-hotdogb/README.md) for the opt-in capped UCM profile and its limits. |
| Ambient light and proximity | Auto-brightness ramped, held and learned a manual change on local29. The TCS3701 reads through the stock SLPI firmware via SensorProxy. Its proximity stream initially reported FAR with a zero raw reading. With PM8150L L9 held on at 2.96 V, the LED emitted and the hand test gave 12 near/far cycles. L9 was on at 2.96 V on the local32 flash boot. |
| Cameras | The IMX586 main, IMX481 ultrawide, S5K3M5 telephoto and IMX471 front all streamed. The AK7374 ultrawide actuator moved through 240–900 and repeatable focus sweeps produced sharpness peaks. The local32 build paired the telephoto driver's 1/32-step gain with the libcamera gain helper and the lens table at ISO 50, which resolved hunting between main and telephoto in low light. Lens selection was checked on one phone and module suppliers can vary. |
| CPU | Added the prime core's 2,956,800 kHz OPP on local28. Earlier 7.3 logs show a failed voltage update at that frequency. No sustained top-bin or thermal test was recorded. |
| Suspend | The earlier Linux 6.17 bring-up image entered s2idle and woke on a 15-second PM8150 RTC alarm with USB access restored. Local32 suspend, automatic sleep and standby drain still need a test. |
| Modem, NFC, fingerprint | Modem firmware started. Cellular data, calls and texts were untested without a SIM. An NFC driver probe was recorded earlier and a tag test is pending. Fingerprint is open. |

## Waydroid

On the development setup, a LineageOS 20 image could run with Waydroid's
multi-window mode off and a Hyprland rule maximizing its windows on an
empty workspace. The rule reduced Android display hotplugs to zero
during the 15-minute repeat test. Some app launches could leave stale
windows. One graphics allocator crash was seen during the preceding
20-minute run. The setup also had a build-specific SurfaceFlinger null
display workaround for a vsync callback during display replacement.
The package carries neither the workaround nor the Android image. In a
separate test, Waydroid changing the DMA heap permissions made libcamera
pick an undersized heap. The local29 kernel disabled the CMA DMA-BUF
heap and all four cameras then streamed with Waydroid running.
