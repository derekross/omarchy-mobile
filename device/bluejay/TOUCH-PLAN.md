<!-- SPDX-License-Identifier: MIT -->
# Bluejay ALIX touch

Status (2026-11-08): polling ALIX input works in the installed Omarchy session,
automatically after reboot, on `7.3.0-rc6-omamobile-bluejay-input-gated0`.
Single/two-finger motion, complete contact release and all four edge zones were
observed. SPI errors and timeouts remain zero. Volume press/release pairs passed;
Power release is unresolved. No interrupt-driven touch or suspend claim.

## Sources and implementation

Google's Bluejay touch DT selects ALIX chip ID 36:48 on SPI11/USI11. The existing
SALIXP profile accepts 36:40. Keep separate match data rather than accepting both
IDs without board-specific initialization.

The GPL references are Google's `kernel/google-modules/touch/fts_touch` at
`2a0089b3c7b9f1f1dbb52a1460a26621e50f61cf` and touch/common at
`340d76ec988f2960427647e9ac4852f072a86c88`, plus the Bluejay/GS101 DTS at
`android-16.0.0_r0.9`. ALIX shares the register/framebuffer/FIFO read protocol and
scan command. Its flash programming differences are irrelevant to this driver:
no firmware update, calibration, production test or repair command is sent.

The active-low AP request/acknowledgment pair is acquired before reset, power or
SPI. The acknowledgment deadline is 500 ms. The existing CRC, AFE/MP, firmware
ready and scan-echo gates remain enforced. No AoC startup or attention IRQ is
needed for the polling path.

Wiring: USI11 at 0x10d400c0, SPI11 at 0x10d40000, bus/CS gpp23, reset gpp26-0,
attention gpa9-0, AP request gpp26-1 and acknowledgment gpa8-6. Supplies are
S2MPG10 LDO25M/LDO26M. The kernel DT leaves all three path nodes disabled.

## Gates and recovery

`alix_stage` is read-only after load: 0 discovers resources, 1 checks identity,
2 checks CRC/system information and 3 starts input. Higher values fail before
hardware. SALIXP retains its existing full-input behavior. Optional
`exynos_usi.probe_hold_base=0x10d400c0` prevents just this controller from
configuring hardware until the guarded service clears the hold and binds it.
Other already-enabled USIs remain unchanged.

Qualify controller creation, SPI/resources, identity, read-only firmware state
and sensing on separate bounded attempts. Stream logs before loading drivers,
require the owned watchdog and stop on an unexpected ID, missing acknowledgment,
CRC/firmware repair condition or SPI fault. Do not unload/rebind to retry.
Recover through the next guarded boot or retained B RAM images.

The final polling capture contained 1,133 evdev records, 288 frames, three
contacts begun/released and two simultaneous contacts, positive pressure and
all slots released. Later edge/volume feedback passed, followed by actual
Hyprland unlock/app/scroll use. No raw touch or screen capture ran during local
PIN entry. Startup is in the device package; [PERSISTENCE-PLAN](PERSISTENCE-PLAN.md)
describes its failure hold and deadlines.
