<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): USB host (OTG), plan

Last updated: 2026-11-02. Written 2026-11-01 from source reading; stage 1 has run (section 4), stage 2 is the gated [HOST-MODE-RUNBOOK.md](HOST-MODE-RUNBOOK.md) and runs only on the maintainer's go. Paths: `L/` = our kernel tree (linux-omarchy-mobile); `G/` = Google's GPL sources, branch `android-gs-shusky-6.1-android16`: `kernel/devices/google/shusky` (`dts/zuma-shusky-usecases.dtsi`), `kernel/google-modules/bms` (`max77759_usecase.c`, `max77759_charger.c`, `max77759_A1_regs.h`) and `kernel/google-modules/usbc` (`tcpci_max77759.c`, `tcpci_max77759_vendor_reg.h`). Claims: **[V]** read in the file:line given; **[I]** inferred, with what settles it; **[U]** unknown.

## 0. Where we stand

- `tcpci_maxim` binds on husky, `typec/port0` is `power_role [sink]`, `data_role host [device]`, `port_type [sink]`, 3.0 A from the desktop port, a replug handled by the driver ([BATTERY-NOTES.md](BATTERY-NOTES.md) 7.2). **[V]**
- Kernel messages `dummy supplies not allowed for exclusive requests (id=vbus)` / `Failed to get vbus regulator handle`: `max_tcpci_set_vbus()` asks for an exclusive regulator named `vbus`, the TCPC node has no `vbus-supply`, and for a sink-only port it then returns success. **[V: L/drivers/usb/typec/tcpm/tcpci_maxim_core.c:210-251]**

## 1. What is missing

### 1.1 The data role never becomes host without a power role change

- Without PD, TCPM sets the data role from the power role at attach: a source becomes `TYPEC_HOST`, a sink `TYPEC_DEVICE` (`tcpm_data_role_for_source/sink`; only `data-role = "host"`/`"device"` overrides). **[V: L/drivers/usb/typec/tcpm/tcpm.c:786-792, 5059, 5227]**
- Our connector is `power-role = "sink"`, so the phone is always Rd/UFP and can only be a device; `data-role = "dual"` alone changes nothing; PD is disabled (`pd-disable`), so no DR_Swap. **[V: L/arch/arm64/boot/dts/exynos/google/zuma-husky.dts:446-477; tcpm.c:8324]**
- So host mode = a DRP port (`power-role = "dual"`, `try-power-role = "sink"` so chargers still win) and Type-C toggling attaching as source (Rp) to a device that presents Rd. PD is not needed for 5 V host mode. **[V: tcpm.c:778-784 (try-sink needs DRP); 5030-5062 (`tcpm_src_attach` sets VBUS, then the roles)]**
- `tcpm_src_attach()` calls `tcpm_set_vbus(port, true)` and bails on error, so a DRP port without `vbus-supply` would fail every source attach (`max_tcpci_set_vbus` returns -ENODEV for `source`). **[V: tcpci_maxim_core.c:235-240; tcpm.c:5055-5057]**

### 1.2 The VBUS source is an EXTERNAL boost, not the MAX77759's reverse boost

- Google's husky use-case node: `max77759,ext-otg-only`, `max77759,bst-on = <&max777x9_gpio 4>` (GPIO5), `max77759,extbst-ctl = <&max77759_tcpc_gpio 0>` (the TCPC's `VENDOR_EXTBST_CTRL`), `max77759,extbst-mode = <&s2mpg14_gpio 4>`, `max77759,bst-lsw-sequence`; no `max77759,usb-otg-mv`. **[V: G/shusky dts/zuma-shusky-usecases.dtsi:10-34]**
- Google's OTG path with `ext_otg_only`: `gs101_otg_enable()` default branch: the bypass registers (`gs101_otg_bypass_enable`), `gs101_ext_mode(EXT_MODE_OTG_5_0V)` = `bst_on` high, 5 ms, `gs101_ls_mode(1)` = TCPC vendor register `EXTBST_CTRL` 0x92 bit 0 `EXT_BST_EN` (the load switch LSW1), then 30 ms. `MODE` (0xb9) stays off: `gs101_otg_mode()` returns early. **[V: G/bms max77759_usecase.c:144-160, 220-250, 370-389, 729-737, 789-875; G/usbc tcpci_max77759_vendor_reg.h:91-92; tcpci_max77759.c:611-618]** The functions are listed line by line in HOST-MODE-RUNBOOK section 1.
- `ext_bst_mode` (s2mpg14 GPIO4) is set after enable when `ext_otg_only && !wlc_otg_extbst_en`; Google's code calls it "extbst mode" (FCCM). Whether 5 V appears without it: **[I: the runbook's stage (a) meter]**. **[V: usecase.c:920-940, 985-996]**
- Google's TCPC driver clears `EXTBST_CTRL` on every toggle restart. **[V: tcpci_max77759.c:2021-2022]**
- The internal reverse boost (`MODE = 0xA`, `CHG_CNFG_05` OTG_ILIM, `CHG_CNFG_11` OTG_VBYP) is what Google uses on boards WITHOUT `ext-otg-only`; the comment in Google's zuma TCPC include says the external boost does about 1 A, the internal 1.5 A, and the source PDO is 5 V / 900 mA. **[V: G/ zuma `max777x9-tcpc.dtsi`:38-49]** Whether husky's internal boost is even wired to the connector: **[U]**; never test `MODE = 0xA` first.

### 1.3 What our tree already has

- `max77759_charger.c` registers a `chgin-otg` regulator (fixed 5 V, enable = `MODE 0xA`), DT child `chgin-otg-regulator`; this is the INTERNAL boost, not husky's path, and has no ILIM/VBYP handling. **[V: L/drivers/power/supply/max77759_charger.c:513-548, 1026-1033; L/include/linux/mfd/max77759.h:207-210]**
- `maxim,max33359.yaml` has `vbus-supply` on the TCPC node. **[V: L/Documentation/devicetree/bindings/usb/maxim,max33359.yaml:36-37, 60]**
- `gpio-max77759` exposes two lines, "GPIO5" (offset 0) and "GPIO6" (offset 1); the gpio cell is in husky's `pmic@66`. GPIO6 is the VBUS input switch (active low), left alone. **[V: L/drivers/gpio/gpio-max77759.c:23-24; zuma-husky.dts:457-459, 501-507]**
- No driver exposes TCPC 0x92: mainline `tcpci_maxim_core.c` only knows 0x93 `USBSW_CTRL`. **[V: tcpci_maxim_core.c:25-27]**
- dwc3: `dr_mode = "peripheral"`, no `usb-role-switch`, no graph port. dwc3 registers a role switch when `usb-role-switch` is present, with `role-switch-default-mode`; TCPM finds it through the connector's graph. **[V: L/arch/arm64/boot/dts/exynos/google/zuma.dtsi:953-963; L/drivers/usb/dwc3/drd.c:498-540; tcpm.c:8924-8926; L/drivers/usb/roles/class.c:126-136, 190-197]**
- Config: `USB_DWC3_DUAL_ROLE=y`, `USB_ROLE_SWITCH=y`, `USB_XHCI_HCD/PLATFORM=y`, `USB_HID=y`, `HID_GENERIC=y`, `USB_STORAGE=y`, `USB_USBNET/CDCETHER/AX8817X/AX88179/RTL8152=m`, `TYPEC_DP_ALTMODE=m`. **[V: the e1 build's .config]**
- The PHY (`phy-exynos5-usbdrd.c`, `zuma_usb32drd_phy`) has no `set_mode`; it forces VBUS valid unless it has an orientation switch. **[V: phy-exynos5-usbdrd.c:2114-2124, 547-566]** Stage 1 showed it survives a role switch with nothing attached (section 4).
- The eUSB2 repeater at 0x3e has no driver; high speed as a device works without it. Host HS with it untuned: **[U; stage 3 devices]**.

## 2. Patch outlines (kernel, later)

### 2.1 External-boost VBUS regulator

Option A (preferred, no new driver): a `regulator-fixed` with `gpio = <&max77759_gpio 0 GPIO_ACTIVE_HIGH>` (bst_on), `enable-active-high`, `regulator-name = "usb-otg-vbus"`, 5 V, `startup-delay-us = <5000>`, never `regulator-boot-on` or `regulator-always-on`; plus `tcpci_maxim_core.c` setting and clearing `TCPC_VENDOR_EXTBST_CTRL` (0x92) bit 0 around `regulator_enable/disable` in `max_tcpci_set_vbus()`, gated by a new TCPC DT property, with a `dt-bindings:` patch for `maxim,max33359.yaml`. Register and bit from Google's header and driver. **[V: vendor_reg.h:91-92; order from usecase.c:789-875]** The bypass registers (HOST-MODE-RUNBOOK section 5) then belong in the charger driver, through its regmap. Open question for the maintainers: a boolean or a GPIO-chip-like description as Google's `max77759_tcpc_gpio`.
Option B: a small regulator driver in the TCPC owning both the GPIO and 0x92. More code, same binding question.
Not in scope: `chgin-otg` (internal boost), OTG while charging, FRS, `ext_bst_mode` unless stage (a) shows no 5 V.

### 2.2 DT (husky, upstream style, one commit each)

1. `arm64: dts: exynos: google: zuma-husky: add the Type-C VBUS boost`: a label on the gpio node, `usb_otg_vbus: regulator-usb-otg-vbus` (regulator-fixed on GPIO5), `vbus-supply = <&usb_otg_vbus>` on `usb-typec@25`, the new TCPC property.
2. `arm64: dts: exynos: google: zuma-husky: make the Type-C port dual role`: `power-role = "dual"`, `try-power-role = "sink"`, `source-pdos = <PDO_FIXED(5000, 900, ...)>` (Google's), `pd-disable` and the sink PDOs kept.
3. `arm64: dts: exynos: google: zuma-husky: wire the USB controller to the Type-C port`: `&usb_dwc3 { dr_mode = "otg"; usb-role-switch; role-switch-default-mode = "peripheral"; port { ... } }` and the connector's port@0 endpoint; `maximum-speed = "high-speed"` kept. (This is what `overlays/usb-role-test.dtso` does for the test boot.)

Sent to linux-omarchy-mobile as one branch with the prefixes `dt-bindings: usb: maxim,max33359:`, `usb: typec: tcpci_maxim:`, `arm64: dts: exynos: google: zuma-husky:`. Questions for the maintainers first: the binding shape, and whether zuma's dwc3 may switch to host without a glue driver (stock wraps it in `exynos9-dwusb`; stage 1 says yes for the switch itself). Cheetah has the same stock wiring and may want the same.

## 3. Staged plan (overlays first, DT later; dead-man pattern from `tools/husky-deadman`)

- **Stage 0** (no reboot): with `tcpci_maxim` loaded, read `/sys/class/usb_role/*` (expect none), `/sys/class/typec/port0/{data_role,power_role,port_type}`; dump TCPC 0x92, charger 0xb9/0xbe/0xc4. Rollback: none.
- **Stage 1** (role switch only, NO VBUS, one reboot): `overlays/usb-role-test.dtso` on top of `overlays/typec-test.dtso`: dwc3 `dr_mode = "otg"`, `usb-role-switch`, default peripheral, connector port@0 to dwc3; the connector stays sink-only. Load `tcpci_maxim` under `b4-tcpm`. Pass: `/sys/class/usb_role/11210000.usb-role-switch/role` = `device`, the `usb0` gadget still configured, Wi-Fi up. Hand test: `echo host > .../role` for a few seconds with nothing plugged in (no VBUS involved, the desktop cable out, control over Wi-Fi), then back to `device`. Pass: xHCI root hubs appear, dmesg clean, no PHY hang, the gadget returns. Stop: no `role` file, dwc3 "Configuration mismatch", an oops, the gadget never returns. Rollback: `echo device`, `undo b4-tcpm`, re-flash the known-good images.
- **Stage 2** (VBUS sourcing from userspace, nothing attached): [HOST-MODE-RUNBOOK.md](HOST-MODE-RUNBOOK.md) stage (a), under `b5-host`, with an independent USB-C meter, on the maintainer's go. Pass: about 5 V on the meter while sourcing, 0 V after the undo. No-go: any trip. If no 5 V: `ext_bst_mode` (s2mpg14 GPIO4) next, the internal boost last, each as its own reviewed step.
- **Stage 3** (attached devices): through the kernel path of section 2 (TCPM sources only after a sink attaches), with its own runbook alongside the kernel pull request: a keyboard (HID, about 100 mA), then a flash drive (200-400 mA), then an Ethernet dongle (300-500 mA), watching VBUS sag and pack current. Not from userspace.
- HDMI/DisplayPort dongles need DP alt mode (PD required), the SBU mux (`sbu-mux-sel-gpio` in Google's DT), the USB3/DP combo PHY at 0x11130000 and a DRM DP sink; mainline has none of this for zuma. Out of scope, far larger. **[V: zuma.dtsi:892-895; grep typec_mux in L/drivers/phy/samsung empty]**

Retry cost: each stage with a reboot spends one slot B boot (three per flash); re-flash the known-good images before a stage to refill. Everything inside a stage (module loads, `echo host`) is live and costs nothing.

## 4. Results

**Stage 1, 2026-11-01 20:56-21:03, kernel `7.3.0-rc6-omamobile-push1-g5899fec2bd28`** (the e1 images with `typec-test` and `usb-role-test` applied; slot B read 2 tries before the flash, the flash refilled to 3, one boot used). **[V: BATTERY-NOTES.md 7.2 and the kernel logs kept locally]**
- After boot: `dr_mode otg` in the live DT, `/sys/class/usb_role/11210000.usb-role-switch/role` = `device`, UDC `configured`, USB SSH up on the first boot with the overlay (dwc3 does not wait for the Type-C driver), `typec/port0` absent until the Type-C driver loads. Then `b4-tcpm` (charger-less, soak 120 s) over Wi-Fi: clean, port0 sink, 3.0 A, no hard resets, USBSW 0x09.
- `echo host > .../role` (no VBUS, connector still sink-only), by hand over Wi-Fi with a restore-to-device trap: the gadget went away and two xHCI root hubs appeared, `usb1` at 480 Mbit/s and `usb2` at 10000 Mbit/s; `typec/port0/data_role` still read `host [device]` (the userspace write bypasses TCPM, as expected). `echo device`: UDC `configured`, `usb0` carrier 1, the USB address answered in 4 ms. No hang, no oops, no kernel message during the 5 s in host mode.
- Conclusion: zuma's dwc3 runs as a host with the in-tree `dwc3` + `xhci-plat` and no stock glue driver, and the PHY survives the role switch with nothing attached. Not shown: whether the eUSB2 PHY/repeater enumerates real devices (no VBUS, so nothing could attach); that TCPM sets the role switch by itself on an attach.
- A planned check for a sysfs link from `typec/port0` to the dwc3 role switch was wrong (TCPM keeps the switch as an internal pointer; there is no such link) and was dropped.

**Stage 2:** not run. One earlier sourcing attempt (2026-11-01 21:33, before the maintainer's review, over Wi-Fi with nothing attached) used a first version of `b5-host` without the baseline-relative guard; it tripped at once on the charger's details (`CHG_DETAILS_01` 0xb1 with the bootloader's MODE 0x05) and the undo brought the TCPC's VBUS reading back under 0.8 V within a second. That is why the runbook writes MODE 0x00 first and defines the charger guard against a baseline. **[V: the tool's log, kept locally]**
