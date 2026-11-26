<!-- SPDX-License-Identifier: MIT -->
# Pixel Tablet Wi-Fi: BCM43752 on PCIe

**Status (2026-11-26):** built, not run on the tablet. Kernel branch `omamobile-tangorpro-wifi` (worktree `wt-tangorpro-wifi`, output `out-tangorpro-wifi`), two commits on `omamobile-tangorpro` `2f4a9e65f`: `1e29745eb` (brcmfmac re-polls after INTx on any chip with DMA'd ring indices) and `2dc38771d` (the board's Wi-Fi nodes, all disabled). `overlays/wifi.dtso` turns them on for a gated boot. Firmware mapping in `tools/extract-vendor-firmware -d tangorpro`. Device package 0.1.1 carries the Pixel 7's start script, unit (not enabled at boot), blacklist and MAC rule.

## Goal

1. W1: the PCIe link trains at Gen1 x1 and the chip enumerates, with nothing else loaded.
2. W2: brcmfmac loads the tablet's own firmware and makes an interface, with no oops, no hang and storage untouched.
3. W3: WPA2 on 2.4 and 5 GHz, a download alongside heavy `userdata` writes with every checksum matching (the Pixel 7's proof).
4. W4: Wi-Fi at boot through `omamobile-wifi.service` (a package bump that adds the wants link).
5. Later, not here: suspend with Wi-Fi loaded (D3 on this chip), Bluetooth, 6 GHz (the chip has none).

## Path abbreviations

- `GT/` = Google's tablet DT, `/mnt/data/omamobile/reference/google-tangorpro-dt/dts/`.
- `G2/` = Google's shared gs201 DT, `/mnt/data/omamobile/reference/google-gs201-dt/dts/`.
- `GW/` = Google's GPL Wi-Fi driver for this chip, `kernel/google-modules/wlan/syna/dhd43752p`, branch `android-gs-tangorpro-6.1-android16` (`bc03aa1a`), cloned to `/mnt/data/omamobile/reference/google-syna-dhd43752p`.
- `F/` = factory image CP1A.260505.005 (`/mnt/data/omamobile/factory/x/tangorpro-cp1a.260505.005/`); `F/dtbo` = its dtbo entries, unpacked under `img/dt/` (`e.6` is the MP board, id 0x30706).
- `L/` = linux-omamobile, branch `omamobile-tangorpro-wifi`.

## Facts

- [V] **The chip is a BCM43752, not the Pixel 7's BCM4389.** `F/vendor/firmware/fw_bcmdhd.bin` carries `<FW-TAG>4362b0-roml/config_pcie_release_android Version=18.36.3501.39 (gba3812c8)`; 4362b0 is the 43752's silicon family. Stock's driver is `F/vendor_dlkm/lib/modules/synadhd.ko` (Synaptics DHD), with PCI aliases `pci:v000014E4d0000449Dsv*sd*bc02sc80i*` and `...d00004362...`, and `GW/Kbuild` builds it with `CONFIG_BCM43752=y`.
- [V] **Mainline brcmfmac already supports it:** `BRCM_PCIE_43752_DEVICE_ID 0x449d`, firmware `brcmfmac43752-pcie`, RAM base 0x170000, the random-seed flag (`WCC_SEED`) (`L/drivers/net/wireless/broadcom/brcm80211/`, `include/brcm_hw_ids.h:56,101`, `brcmfmac/pcie.c:75,121,3718`, `chip.c:924`), and the binding lists `pci14e4,449d` (`Documentation/devicetree/bindings/net/wireless/brcm,bcm4329-fmac.yaml:69`). It came with the AP6275P work for RK3588 boards; it has not run on gs201.
- [V] `GW/Kbuild:870`: `-DBCMPCI_NOOTP_DEV_ID=0x4362`. A chip whose OTP is blank enumerates as `14e4:4362`, which brcmfmac does not bind; runbook W2 has a `new_id` fallback.
- [V] **Same wiring as the Pixel 7.** `GT/gs201-tangorpro-common.dtsi:14` includes `gs201/gs201-cloudripper-wlan.dtsi`: WL_REG_ON gph2-4 (output, no pull), WL_DEV_WAKE gph2-5 (input, pull-down), WL_HOST_WAKE gpa6-1 (EINT, pull-down), on `pcie_1` (GEN4A_1, `ch-num = 1`). No tablet file overrides them, and `F/dtbo` `e.6` carries them unchanged (`cfg_wlanen`, `wlan_dev_wake`, `wlan_host_wake`, `wl_reg_on = <&gph2 4 1>`, `wl_host_wake = <&gpa6 1 1>`, `wl_dev_wake = <&gph2 5 1>`).
- [V] No pin conflict: in `F/dtbo` `e.6`, gph2-2/gph2-3 belong to the GNSS (`mcu-resp`, `nstandby`) and Bluetooth's host wake is gpa6-6; nothing else uses gph2-4, gph2-5 or gpa6-1.
- [V] **Gen1, the one tablet change:** `GT/gs201-tangorpro-wlan.dtsi` sets `max-link-speed = <LINK_SPEED_GEN1>` on `pcie_1` over `G2/gs201-common.dtsi:373`'s Gen2; `F/dtbo` `e.6` has both, the Gen1 fragment last. Our host takes `max-link-speed` through the DesignWare core (`L/drivers/pci/controller/dwc/pcie-designware.c:196`).
- [V] Rails: `vreg1` = S2MPG13 LDO3 (`L3S_PCIE1`, 0.85 V), `vreg2` = S2MPG13 LDO18 (`L18S_PCIE1`, 1.8 V), both `regulator-always-on` (`G2/gs201-common.dtsi:376-377`, `G2/gs201-pmic.dtsi:970-979,1129-1138`); `GT/gs201-tangorpro-pmic.dtsi` touches only main-PMIC LDOs (`m_ldo18_reg`), and `F/dtbo` `e.6` keeps both always on. As on the Pixel 7, our DT leaves them as the bootloader does.
- [V] WL_REG_ON timing: `GW/dhd_custom_google.c:536-537` waits `WIFI_TURNON_DELAY` (200 ms, `GW/dhd_custom_exynos.c:85`) after raising it; the regulator's `startup-delay-us = <200000>` matches.
- [V] Reserved memory: no tablet file adds a carve-out below 4 GiB besides the 20 MiB display handover at 0xfac00000 (`GT/gs201-tangorpro-display.dtsi:14-16`), already reserved in our board file; the rest are `G2`'s, reserved in `gs201.dtsi`. The 16 MiB restricted DMA pool is placed by the kernel inside 0x80000000-0xffffffff, as on the Pixel 7.
- [V] Firmware names: the vendor partition has the 7 Pro's file names, `firmware/fw_bcmdhd.bin` (936402 bytes), `firmware/bcmdhd.cal` (9659 bytes, `boardtype=0x08ed`, `boardrev=0x1213`, no `macaddr`), `firmware/bcmdhd_clm.blob` (31685 bytes, CLM 1.53.0); `GW/Kbuild:55,885` names the same files. No `firmware/brcm/` directory: Bluetooth's patch lives elsewhere (not mapped).
- [V] INTx: Broadcom's driver re-runs its interrupt work after every INTx when the firmware DMAs its ring indices, for any chip (`GW/dhd_pcie.c:13289-13300,13369`, `dhd_bus_handle_intx_ahead_dma_indices()`). brcmfmac did that only for the BCM4389 family; commit `1e29745eb` keys it to INTx with DMA'd indices as well. gs201's `pcie_1` has no MSI.
- [I] The MAC: the 7 Pro's bootloader writes `/chosen/config/wlan_mac1`; the tablet's is the same ABL family, unverified. Without it the chip keeps its random address (the NVRAM has none).
- [I] The tablet has no sleep hook yet (no `omamobile-sleep` in its package), and D3 on this chip is untested: don't suspend with brcmfmac loaded.

## What was built

| Where | What |
|---|---|
| `L/` `1e29745eb` | `wifi: brcmfmac: pcie: re-poll after INTx with DMA'd indices on any chip`: one condition in `brcmf_pcie_setup()`. Chips on MSI or without DMA'd indices are unchanged. |
| `L/` `2dc38771d` | `gs201-tangorpro: describe Wi-Fi`: `regulator-wlan` (WL_REG_ON, the root port's `vpcie3v3-supply`), `wifi-dma-pool` (16 MiB restricted DMA pool), `&pcie_1` at `max-link-speed = <1>` with root port `pcie@0,0` and `wifi@0,0` (`compatible = "pci14e4,449d"`, `brcm,board-type = "google,gs201-tangorpro"`, `memory-region`), the System MMU's DMA window, and the pins. The regulator and the pool are `disabled`; `pinctrl_hsi2`, `pcie_1`, `pcie_1_phy` and `pcie_1_sysmmu` stay disabled from `gs201.dtsi`. |
| `overlays/wifi.dtso` | Enables the regulator, the pool, `pinctrl_hsi2`, `pcie_1_phy` and `pcie_1`. Not the System MMU. |
| `tools/extract-vendor-firmware -d tangorpro` | Stages the three files as `brcm/brcmfmac43752-pcie.google,gs201-tangorpro.{bin,txt,clm_blob}` under `/usr/lib/firmware/updates`, checking for `4362b0-roml`. Test in `tests/extract-vendor-firmware`. |
| `packages/omamobile-device-tangorpro` 0.1.1 | `omamobile-wifi-start`, `omamobile-wifi.service` (no wants link), `modprobe.d/omamobile-wifi.conf` (blacklists `pcie_gs201`, `brcmfmac`), `omamobile-wlan-mac` + its udev rule: the Pixel 7's files byte for byte (the test checks for drift). |
| `tools/wifi-w1-capture` | `--brcmfmac` now waits for `Firmware: BCM<any>` rather than only `BCM4389`. |

Checks run (2026-11-26): checkpatch `--strict` clean on both commits (bar the human sign-off); `W=1` clean on `brcmfmac/pcie.o` (in the build container); `W=1 CHECK_DTBS=y` on `gs201-tangorpro.dtb`: no warning from the new nodes (the one W=1 warning is `gs201.dtsi`'s `dsi@1c2c0000`, already there), and `dt-validate` (dtschema 2026.9) reports 0 warnings on the DTB alone and with `touch.dtso` + `wifi.dtso` applied by `fdtoverlay` (a bad `max-link-speed` in a test overlay was caught, so the check bites). In the merged DTB, `pcie_1`, its PHY, `pinctrl_hsi2`, `regulator-wlan` and `wifi-dma-pool` read `okay` and the System MMU `disabled`; in the base DTB all six are `disabled`. `tests/device-overlays` (with dtc) compiles all 80 overlays; `tests/extract-vendor-firmware` passes, and the tool on the real factory image gives the sha256 below; the package's `test/all` passes its Wi-Fi checks, and a wants link or a dropped blacklist line fails it.

Build: `out-tangorpro-wifi`, kernel release `7.3.0-rc6-omamobile-push1`, `arch/arm64/boot/Image` (+ `Image.gz`), `arch/arm64/boot/dts/exynos/google/gs201-tangorpro.dtb`; `pcie-gs201.ko`, `phy-gs201-pcie.ko`, `brcmfmac.ko` and `brcmfmac-wcc.ko` as modules.

Firmware staged on the laptop (from the owner's factory image; never committed), `/mnt/data/omamobile/firmware/tangorpro/usr/lib/firmware/updates/brcm/`:

```
71e68498260af4c207ac159e902934d7b9e6342b247b49bf95c99470a710ee39  brcmfmac43752-pcie.google,gs201-tangorpro.bin
811950cca3cbca9be0692d8ce0f6a0d4c0cdee77ae93131aa3e39591eb179aef  brcmfmac43752-pcie.google,gs201-tangorpro.txt
7150f1b4da0d258cc50e9c44f07be3f708a47e0fe594140b4c6abc017cbcb624  brcmfmac43752-pcie.google,gs201-tangorpro.clm_blob
```

## Risks

- **Firmware/driver mismatch.** Synaptics' 18.36 Android firmware has only met mainline brcmfmac on other boards with other builds. Possible failures: an unsupported shared-RAM version, a trap at init, the random seed rejected, the CLM refused. They fail the probe, not the SoC.
- **Blank OTP:** the chip shows up as `14e4:4362` (W2 fallback).
- **The link at Gen1.** Our host only ever trained Gen2 with a BCM4389. Gen1 is the slower, simpler setting and the PHY tables are the same, but it is new on this driver.
- **DMA reach.** The restricted pool keeps the driver's buffers in one place; nothing stops the chip's firmware writing elsewhere (no S2MPU or SysMMU confinement, as on the Pixel 7). The same trade the Pixel 7 runs with.
- **Bus hang.** A PCIe step that touches an unpowered block hangs the SoC. The Pixel 7's runs say the gs201 sequence is safe, and the same host driver runs here, so this is low, but W1 runs under the watchdog with the log streamed off the tablet.
- **Suspend** with brcmfmac loaded is untested on this chip: hold sleep off during the runbook.
- **INTx re-poll** (`1e29745eb`): if it misbehaves, revert that commit alone; the DT works without it.

## Runbook

Each step needs the human. One change per boot. Stop at the first stop condition, copy the log lines into Results, and don't go on. Rollback for any boot: slot B images built without `wifi` in `DTB_OVERLAYS` (the previous pack). The tablet has no modem and `NV_PARTS` is empty, so there is no radio backup to check.

### W0. Read-only, on the running tablet (no change)

```sh
tools/phone-ssh 'uname -r; lsmod | grep -E "pcie_gs201|brcmfmac" || echo none-loaded;
  ls /sys/bus/platform/devices/ | grep -c 14520000.pcie;
  [ -e /proc/device-tree/chosen/config/wlan_mac1 ] && echo wlan_mac1:present || echo wlan_mac1:absent;
  ls /var/lib/omamobile/wifi-bringup-started 2>/dev/null; free -m | sed -n 2p'
```

**Expect / pass:** none loaded, `0` (pcie_1 disabled in today's DTB), no marker. Note whether `wlan_mac1` is present (don't print its value: it's an identifier). **Stop:** `pcie_gs201` or `brcmfmac` loaded already. **Risk:** none.

### W1a. Firmware and the package's Wi-Fi files (no boot)

```sh
tar -C /mnt/data/omamobile/firmware/tangorpro -cf - usr/lib/firmware/updates/brcm | tools/phone-ssh 'tar -C / -xf -'
tools/phone-ssh 'cd /usr/lib/firmware/updates/brcm && sha256sum -c SHA256SUMS'
```

Then the package (fix its `device.conf` first: it lacks the descriptor's `DTB_OVERLAYS` line, and `test/all`, which `makepkg` runs, fails on that drift):
`tools/phone-install-package packages/omamobile-device-tangorpro`.

**Expect / pass:** three `OK`; `pacman -Q omamobile-device-tangorpro` = 0.1.1; `/usr/lib/modprobe.d/omamobile-wifi.conf` blacklists both modules; `systemctl is-enabled omamobile-wifi` says `disabled`. **Stop:** a checksum mismatch. **Rollback:** delete the three files; reinstall 0.1.0. **Risk:** none.

### W1b. The image with the overlay (laptop, then a push)

Kernel `out-tangorpro-wifi` (this branch). For this pack only, set `DTB_OVERLAYS="touch wifi"` in `device/tangorpro/device.conf`, run `DEVICE=tangorpro bin/omamobile images`, then put the line back (don't commit it). `bin/omamobile push` (the human), which also pushes this kernel's modules.

**Expect / pass:** the pack prints `DTB overlays: touch wifi`. **Stop:** the overlay fails to apply. **Risk:** low (nothing loads the modules).

### W1c. Boot, read-only

```sh
tools/phone-ssh 'uname -r; dmesg | grep -iE "restricted DMA|wifi-dma|14520000|wlan-reg-on"; lsmod | grep -E "pcie_gs201|brcmfmac" || echo none-loaded;
  ls /sys/bus/platform/devices/ | grep 14520000.pcie; cat /sys/class/regulator/*/name | grep -n wlan-reg-on'
```

**Expect / pass:** `Reserved memory: created restricted DMA pool at 0x..., size 16 MiB`; `14520000.pcie` exists; neither module loaded; `omamobile-wifi.service` did not run (`systemctl status omamobile-wifi` inactive, it isn't enabled). **Stop:** either module loaded (the blacklist is missing), any new oops, UFS errors. **Rollback:** the previous pack. **Risk:** low.

Hold sleep off for the rest of the runbook: `tools/phone-ssh 'systemd-run --unit=x-nosleep systemd-inhibit --what=sleep:idle --why=wifi-bringup sleep 3600'`.

### W1d. The link alone (pcie_gs201, under the watchdog)

```sh
tools/wifi-w1-capture --watchdog 5
tools/phone-ssh 'lspci -nn; cat /sys/bus/pci/devices/0001:01:00.0/current_link_speed /sys/bus/pci/devices/0001:01:00.0/current_link_width 2>/dev/null'
```

(The domain may differ: use the endpoint `lspci` shows.)

**Expect / pass:** the capture shows `link up on try 1`; `lspci` shows the root port and `[14e4:449d]`; link `2.5 GT/s`, width `1`. **Stop:** `Link failed`, `Device not found` after all tries, a watchdog reset (then `tools/wifi-w1-capture --pstore` and stop), or any UFS error. **Rollback:** reboot (don't `rmmod` the host with a device on it). **Risk:** medium (first PCIe on this board).

If `lspci` shows `[14e4:4362]` instead: the OTP is blank; note it, and use the fallback in W2.

### W2. brcmfmac (next boot, or the same boot if W1d passed cleanly)

```sh
tools/wifi-w1-capture --watchdog --brcmfmac 5
```

Blank-OTP fallback only (`14e4:4362` in W1d): after the link is up, `tools/phone-ssh 'modprobe brcmfmac; echo "14e4 4362 ffffffff ffffffff 028000 ffff00 3" > /sys/bus/pci/drivers/brcmfmac/new_id'` (driver data 3 is the 43752's `WCC_SEED`), with `tools/phone-ssh 'dmesg -w'` streaming in another terminal.

**Expect / pass:** `brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac43752-pcie for chip BCM43752/<rev>`, the `.google,gs201-tangorpro.bin` and `.txt` found, CLM loaded, `Firmware: BCM43752/<rev> wl0: ... 18.36.3501.39 ...`, an interface `wlp1s0` (`ip link`). **Stop:** `Dongle setup failed`, `FW failed to initialize`, `Invalid shared RAM`, `Unsupported PCIE version`, a firmware trap dump, ioctl timeouts (`brcmf_msgbuf_query_dcmd: Timeout on response`), or any oops. Copy the lines and stop: each is a driver-side fix on the laptop. **Rollback:** reboot. **Risk:** medium.

### W3. Scan and connect

```sh
tools/phone-ssh 'ip link show wlp1s0; nmcli dev wifi rescan; nmcli -f SSID,CHAN,FREQ,SIGNAL dev wifi list | head'
```

Then the owner connects (`nmcli dev wifi connect <SSID> --ask` on the tablet). Then: a 1 GB download with a known sha256 on 5 GHz while `dd if=/dev/zero of=/home/<user>/fill bs=1M count=2000 oflag=direct` runs, three times, and `rm` the file.

**Expect / pass:** both bands listed; connected; every checksum matches; no `ufshcd` errors in `dmesg`; `ip link` shows the bootloader's MAC if W0 found `wlan_mac1` (compare without pasting it). **Stop:** a checksum mismatch (DMA reaching the wrong memory: stop at once and unload), UFS errors, disconnect storms. **Rollback:** `nmcli con down`, reboot. **Risk:** medium (the DMA-path proof).

Don't put SSIDs, MACs or the network's addresses in Results.

### W4. Wi-Fi at boot (a later package change)

Only after W3 passes twice on separate boots: add the `multi-user.target.wants` link to `install`, update `test/all` (which now refuses it), bump the package, and add `wifi` to `DTB_OVERLAYS` in the descriptor (or move the status lines from the overlay into the board file). One boot with it: `systemctl status omamobile-wifi` says `up: wlp1s0` and no marker is left.

## Results

None yet.

## Open questions

- The BCM43752's revision and whether its OTP is programmed (W1d).
- Whether the tablet's ABL writes `/chosen/config/wlan_mac1` (W0).
- Bluetooth: which UART and pins, and where the tablet keeps its patch (no `vendor/firmware/brcm/BCM.hcd`).
- Suspend: does this firmware honour brcmfmac's D3 messages (the BCM4389 needed the control-ring D3 inform)?
