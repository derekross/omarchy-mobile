<!-- SPDX-License-Identifier: MIT -->
# dipper — Wi-Fi plan

Wi-Fi matters more on this phone than on a Pixel: dipper is not A/B, so a boot
without working networking leaves no remote access at all. It is also not a
self-contained driver, which is the main thing to understand before debugging it.

## What actually has to be true

WCN3990 has no firmware of its own. **The WLAN firmware runs on the modem's DSP**, so
`ath10k_snoc` only gets a chip once the whole Qualcomm IPC chain is up:

| Piece | Where it comes from | State |
| --- | --- | --- |
| `ath10k_snoc` + `qcom,wcn3990-wifi` node | mainline; node enabled in our DTS with beryllium's supply set | **in the DTS** |
| `ath10k/WCN3990/hw1.0/firmware-5.bin` | linux-firmware — a 60-byte metadata stub, no code | fetched |
| `ath10k/WCN3990/hw1.0/board-2.bin` | **built from this phone's own calibration** (below) | **built** |
| `wlanmdsp.mbn` (3.6 MiB) | the phone's `/vendor/firmware_mnt/image` | extracted |
| `mba.mbn` + `modem.mbn` (60 MiB) | the phone; `modem` squashed from `.mdt` + 27 `.bNN` | extracted |
| `*.jsn` protection-domain maps | the phone; `pd-mapper` reads them | extracted |
| `qrtr`, `pd-mapper`, `rmtfs`, `tqftpserv` | **AUR PKGBUILDs**, not repository packages: `qrtr` 1.2, `rmtfs` 1.2, `tqftpserv` 1.2, `pd-mapper` 1.1 | exist; **must be built for aarch64** |
| `rmtfs_mem` reserved region | in our DTS at `0xf6301000 + 0x200000` | in the DTS |

So the realistic order is: register the modem remoteproc → start `rmtfs`/`tqftpserv` →
explicitly start the modem firmware → `pd-mapper` answers protection-domain lookups →
`ath10k_snoc` finds a chip. **Wi-Fi cannot be brought up before the modem subsystem runs.** That is why first light
targets USB networking instead, and why the cable is not optional.

## Attended first-radio run

The newest private off-device snapshot of all 15 saved partitions is
`private off-device reference directory (path omitted)/`; all
device/source hashes matched before the RAM boot. Keep
the live kernel log private under `private off-device reference directory (path omitted)/`.

The phone was in rescue initramfs. Its NFS client is built into this kernel, so a
disposable copy at host `the disposable host-side NFS root` was served over USB NCM and mounted
read-write at `the host-side scratch mount`; only that scratch copy was writable. At the latest
host check (2026-10-30), ADB and fastboot listed no device, the Mi 8 Tailscale
peer was offline, and `lsusb` showed no identifiable phone. Host `usb0` remained
up but does not establish phone connectivity. The phone's current screen/mode is
unknown; no further device commands were sent. The host NFS service is disabled
at boot and its export is restricted to the USB client. The original compressed
image and `userdata` are untouched.

The 2026-10-30 RAM boot confirmed the revised image and all five NV links
read-only. The modem exposed QRTR WLAN service 69. On the MCFG retry, both MCFG
files were served successfully and the WLAN DSP firmware was fetched; the modem
still crashed with `modem_xpu_int.c:456:XPU violation End`. Re-timed from
`wifi-20261030-mcfg-ath10k-crash-dmesg.log`: the modem came up at t=160.5 s and
ran healthy for 137 s; `cfg80211` loaded at t=297.53 s (the ath10k insert
pulling in mac80211/cfg80211) and the violation arrived at t=297.89 s, 0.36 s
later. The trigger is therefore ath10k's QMI handshake, not modem boot or MCFG.
That capture holds no ath10k lines at all, so the `CONFIG_ATH10K_DEBUG` output
built for the run was never obtained; stream the log off-device, or read it back
from pstore, before the module is inserted. No WLAN interface, scan or association occurred.
The MCFG files are now in the private firmware tree and scratch rootfs, and
`tools/dipper/extract-firmware` stages them for future builds. Resolved 2026-10-30: the rejected
`/boot/modem_fsg_oem_1` and `/boot/modem_fsg_oem_2` requests are benign. Dipper
has no `fsg_oem*` partition (only a single `fsg`), and stock `/vendor/bin/rmt_storage`
knows exactly four paths -- `/boot/modem_fs1`, `/boot/modem_fs2`, `/boot/modem_fsc`,
`/boot/modem_fsg` -- so stock refuses those two requests too and Android works
regardless. The modem probes them opportunistically. Do not alias them to any
partition; the rejection is not a fault and is not the XPU violation's cause. A whole-phone reboot separated the earlier and
latest RAM attempts. On a prior Android boot, Tailscale reconnected after its
app was opened. The latest radio attempt left remoteproc `crashed` with
recovery disabled; do not retry in place. NV partitions remained read-only.

The saved kmsg logs show automatic remoteproc recovery during the failed
sessions: one boot reached crash counters 1–6 and another reached 1–5,
restarting MBA/MPSS after each fatal error. The kernel defaults recovery to
enabled. Before the next single start, while `remoteproc0` is offline, set
`/sys/class/remoteproc/remoteproc0/recovery` to `disabled` and read it back.
If that attempt crashes, leave it crashed and stop; do not invoke `recover` or
enable recovery.

For the next attempt, first restore physical USB data and identify the phone's
mode. If stock Android has run since the saved snapshot, capture and verify a
fresh off-device backup before radio work. Verify the pending diagnostic build
and image-pack status; `CONFIG_ATH10K_DEBUG=y` was enabled to expose QMI/SNOC
messages. Restore the saved original kernel config after securing outputs, and
ensure matching debug modules are installed in the disposable scratch rootfs.
Then RAM-boot the image (do not flash it), confirm its initramfs created the links above
and recheck their `ro` values. Start a private live log, mount the NFS scratch root
read-write, bind live `/dev`, `/proc`, `/sys` and
`/run`, set
`/sys/module/firmware_class/parameters/path` to `the host-side scratch mount/usr/lib/firmware`, then load
`rmtfs_mem`, `qrtr-smd`, `reset_qcom_pdc` and `qcom_q6v5_mss` from its module tree. The
rebuilt Dipper initramfs creates read-only-checked `by-partlabel` links for `persist`, `fsg`,
`fsc`, `modemst1` and `modemst2`; verify their targets have `ro=1` before continuing. This
image is now RAM-booted. If a link is missing, stop before starting rmtfs. Confirm
`remoteproc0` is `offline`, disable and verify remoteproc recovery, start `pd-mapper` and
`tqftpserv` first, then start `rmtfs -r -P -s` once. Its `-s` option starts the MSS
remoteproc itself; do not also write `start` to the remoteproc state file. `rmtfs` must stay
read-only. Stop if the modem does not stay online,
reports storage/NV errors, or UFS reports an error-handler pass. Do not retry a failed
modem in place. Only after a stable modem and QRTR services are confirmed should a later
session apply the WLAN MAC from read-only `persist`, load `ath10k_snoc`, verify WCN3990
board data, and attempt a scan. Use the owner's Wi-Fi credentials from ignored local provisioning settings
without echoing them or putting them in logs.
The success test is association to the owner's requested network, then DHCP and connectivity.

Stop if any backed-up partition is not read-only, USB rescue SSH or live logging is lost,
or any daemon/firmware/board-data step fails. No partition should be written. After a
successful test, a power-cycle of this RAM boot returns to Android. Do not retry a modem
that crashed in the same boot; diagnose it first.
This test runs the untrusted modem firmware, so keep the phone attended and on USB power,
and leave the live log private.

## Attended run 2026-10-30 (second): where it actually dies

The diagnostic image RAM-booted, rescue SSH came up, all five `by-partlabel`
targets read `ro=1`, and the live kmsg was streamed **off-device over SSH before
any module was inserted** -- the gap that lost the previous run's evidence. The
modem started once from `rmtfs -v -r -P -s`, reached `running`, and registered 46
QRTR services including 69 `ATH10k WLAN firmware service`. `recovery` was
`disabled` before the start and the run ended with exactly **one** crash, no
recovery loop. Nothing was written; all five NV partitions stayed `ro=1`.

`ath10k_core` was loaded with `debug_mask=0x300822` (BOOT|SNOC|QMI|WMI|REGULATORY),
then `ath10k_snoc`. The captured sequence is private at
`private off-device reference directory (path omitted)`:

```
snoc xo-cal-data return -22
qmi msa.paddr: 0x000000008e300000
snoc probe / wifi fw qmi service found / connected
qmi indication register request completed
qmi msa mem region 0 addr 0x8e300000 size 0x4000  flag 0x1
qmi msa mem region 1 addr 0x8e304000 size 0xfc000 flag 0x0
qmi msa mem info request completed          <- last successful step
... 57 ms ...
fatal error received: SFR Init: wdog or kernel error suspected
```

No `msa ready` line and no `failed to assign msa map permissions` error, so the
modem dies inside `ath10k_qmi_setup_msa_permissions()`'s `qcom_scm_assign_mem()`
window or at `msa_ready` immediately after. The two regions sum to 0x100000,
matching our reserved region.

### Ruled out, with evidence -- do not re-test these

| Suspect | Why it is not the cause |
| --- | --- |
| MSA address/size wrong | stock DT reserves `wlan_fw_region@0x8e300000` size `0x100000`, identical to our `wlan_msa_mem` |
| `xo-cal-data return -22` | **no** DTS in the tree sets `qcom,xo-cal-data`, beryllium included; the driver leaves `xo_cal_supported` false and continues |
| rejected `/boot/modem_fsg_oem_1`/`_2` | stock `/vendor/bin/rmt_storage` knows only four paths and refuses them too |
| `qcom,snoc-host-cap-skip-quirk` wrong | beryllium (SDM845 + WCN3990, working) sets the same quirk |
| missing `qrtr-ns` | the name service has been in-kernel (`net/qrtr/ns.c`) since 5.7; upstream dropped the binary. 46 services resolved without it |
| board-2.bin malformed | never reached -- board data is fetched after `msa_ready` |

### Next step, gated

`qcom,msa-fixed-perm` has been added to our `&wifi` node as the one hypothesis
the evidence supports: dipper reserves MSA at a *fixed* address, so ABL/TZ has
likely already granted the modem access, and reassigning it from HLOS strips
permissions the modem already holds. Note that no sdm845 DTS upstream sets this
property, so if it fixes dipper that difference needs explaining before the
change goes anywhere near upstream.

| | |
| --- | --- |
| Do | rebuild DTB + boot image, RAM boot (**never flash**), repeat the sequence above |
| Expect | a `msa ready request completed` line, then board-data fetch, then a `wlan0` interface |
| Pass | modem stays `running` through `ath10k_snoc` load |
| Stop | any fatal error -- leave it crashed, do not `recover`, do not retry in place |
| Rollback | drop the property; power-cycle returns the phone to Android |
| Risk | low: RAM boot only, nothing written, NV read-only |

Two host-side gotchas worth keeping: busybox `mount` needs an explicit
`addr=`, so the NFS mount is `-o nolock,vers=3,addr=172.16.42.2` (v4 and a bare
v3 both fail with "mount program didn't pass remote address"); and the rootfs
daemons are glibc while the rescue initramfs is musl, so `pd-mapper`,
`tqftpserv` and `rmtfs` must be run via `chroot the host-side scratch mount`, not directly.

## 2026-10-30, runs 2-4: the failure is the SDM845 XPU erratum, not our config

Three more attended RAM boots (never flashed; NV read-only throughout; one crash
each, recovery disabled first). Each one moved the failure, and together they
close out most of the suspect list.

### Run 3: `qcom,msa-fixed-perm` -- got much further, then died anyway

Setting it skips `qcom_scm_assign_mem()`. The QMI handshake then sailed past the
point that had killed runs 1-2 and reached, in order: `msa mem ready request
completed`, `chip_id 0x30214 chip_family 0x4001 board_id 0xff`, `fw_build_id
WLAN.HL.2.0.c3-00534-QCAHLSWMTPLZ-1`, board-data match, `bdf download request
completed`, `cal report request completed` -- then `SFR Init: wdog or kernel
error suspected` 24 ms later, with no host log line in between.

So the property is **not** the fix and is deliberately not set: skipping the
assignment leaves the modem without MSA permissions, and it dies at the first
real *use* of that region (the BDF is written into it). The assignment is
required.

### Run 4: upstream board-2.bin -- identical crash, so our board data is cleared

Swapping linux-firmware's generic `board-2.bin` for ours changed nothing: same
`cal report` then same watchdog, 23 ms later. Since that generic data is exactly
what beryllium loads and beryllium works, **board data is not the cause**. Ours
is restored (it carries the phone's factory calibration, so TX power is right).

### What the evidence actually points at

`ath10k_qmi_event_server_arrive()` carries an upstream workaround:

```c
/*
 * HACK: sleep for a while between receiving the msa info response
 * and the XPU update to prevent SDM845 from crashing due to a security
 * violation, when running MPSS.AT.4.0.c2-01184-SDM845_GEN_PACK-1.
 */
msleep(20);
```

Upstream already knows SDM845 trips an XPU security violation here, and the 20 ms
was measured against **one** MPSS build. dipper runs a different one -- taken from
the phone's own modem image, `MPSS.AT.4.0.c2.6-00335-SDM845_GEN_PACK-1.309997.1`
against upstream's `MPSS.AT.4.0.c2-01184`. Same family, different build.

That makes both observed failures one bug seen from two sides: with the
assignment, the XPU update itself faults (runs 1-2); without it, the modem has no
permissions and faults on first use (runs 3-4).

`drivers/net/wireless/ath/ath10k/qmi.c` now takes the settling time from a module
parameter instead of the constant, default 20 so upstream behaviour is unchanged:

```
modprobe ath10k_snoc msa_perm_delay_ms=<ms>     # 0 disables the sleep
```

It lives in `ath10k_snoc.ko`, not `ath10k_core.ko` (`qmi.o` is in `snoc-y`).

### Also cleared, with evidence -- do not re-test

| Suspect | Why not |
| --- | --- |
| WCN3990 supplies | stock `qcom,icnss@18800000` uses pm8998 l5/l7/l17/l25, which is exactly our l5a/l7a/l17a/l25a; voltages are in stock's own configured ranges |
| a missing WLAN enable GPIO | stock's node has none -- only `gpio-force-fatal-error`/`gpio-early-crash-ind` crash lines |
| `iommus` SID | stock `<0x29 0x40 0x01>` matches mainline `<&apps_smmu 0x0040 0x1>` |
| `pd-mapper` not finding its `.jsn` maps | it falls back to `/lib/firmware/` silently, which resolves correctly inside the chroot; an empty log means success |
| our custom `board-2.bin` | run 4, above |
| the `modem.mbn` squash | MBA authenticates every segment and the modem reaches `running` with 46 QMI services, so the image is intact |

### Still unexplained, worth noting

- dipper's `&wifi` is byte-for-byte beryllium's apart from beryllium's
  `qcom,calibration-variant = "xiaomi_beryllium"`. Ours has no variant, so
  ath10k loads the plain `qmi-board-id=ff` entry. Adding a variant with no
  matching board-2.bin entry only falls back to the same data, so it was not
  tried; revisit only if the delay theory fails.
- stock also sets `vdd-3.3-ch1` **nowhere**, while mainline's regulator list has
  five entries and `regulator_bulk_get()` wants them all. Ours points ch1 at
  `vreg_l23a_3p3`, as beryllium does.
- tqftpserv's served-file set differs run to run (`wlanmdsp.mbn` in run 1;
  `miui_customized_region` and `ota_firewall/ruleset`, both rejected, in run 4).
  Those two rejects are unexplained but stock has real files behind them.

### Next step, gated -- NOT yet run

The `delay300` run was prepared and aborted before touching the radio: the phone
did not come back from the previous run's reboot (see STATE.md).

| | |
| --- | --- |
| Do | RAM boot, full sequence, then `modprobe ath10k_snoc msa_perm_delay_ms=300` |
| Expect | `msa ready`, `bdf download`, `cal report`, then a `wlan0` interface |
| Pass | modem stays `running` after the ath10k load |
| If it still crashes | sweep the delay (100/500/1000) before abandoning the theory; one value per boot, the modem cannot be retried in place |
| Stop | any fatal error -- leave it crashed, never `recover` |
| Rollback | `msa_perm_delay_ms=20` restores upstream behaviour; nothing is flashed |

The driver change is local and uncommitted. If a longer delay does fix dipper, it
is evidence the 20 ms is an MPSS-version-dependent guess, which is worth taking
upstream -- but it needs a second device to confirm before it is more than a
local workaround.

## 2026-10-30, run 5: Wi-Fi comes up. The erratum delay was the fix.

`modprobe ath10k_snoc msa_perm_delay_ms=300` and the modem did **not** crash.
The whole chain completed for the first time:

```
qmi msa mem ready request completed
qmi chip_id 0x30214 chip_family 0x4001 board_id 0xff
qmi bdf download request completed / qmi cal report request completed
wifi fw ready event received            <- never reached before
soc power on
qmi wlan mode req completed: 0
boot init ce src/dest ring id 0..11
Hardware name wcn3990 hw1.0 version 0x8
```

Result on the phone: `remoteproc0` stayed `running`, `phy0` exists, `wlan0`
exists, no ath10k error or warning, and `iw dev wlan0 scan` returned **23 BSSes**
across 2.4 GHz and 5 GHz. The radio transmits and receives.

So the 20 ms in `ath10k_qmi_event_server_arrive()` is too short for
`MPSS.AT.4.0.c2.6-00335`; 300 ms works. The value is now
`ath10k_snoc`'s `msa_perm_delay_ms` (default 20, upstream behaviour unchanged).
**The minimum working value has not been bisected** -- 300 was the first tried.
Worth narrowing before this is proposed anywhere, and worth confirming on a
second SDM845 device.

### Why it still does not associate to the owner's AP

Not a driver fault. `iw phy phy0 info` shows:

| Band | State |
| --- | --- |
| 36-48 (UNII-1) | enabled, 23 dBm |
| 52-64 (UNII-2A) | enabled, no-IR, radar detection |
| **100-144 (5470-5725)** | **disabled** |
| 149-165 (UNII-3) | enabled, 13 dBm |

That is exactly the **CN** regulatory domain (CN permits 5150-5350 and
5725-5850, but not 5470-5725) -- this is a Chinese-market handset and the
regdomain comes from its calibration data. The owner's 5 GHz AP sits on
**channel 104 / 5520 MHz**, inside the forbidden gap, so the radio will not even
scan it: none of the three configured SSIDs appears among the 23 networks found,
while 22 neighbours on 2.4 GHz and two on UNII-1 do.

`iw reg set SK` was tried and changes nothing, because `ath10k_regd_update()`
drives the firmware from `ar->ath_common.regulatory.regpair` (ath/regd.c,
`REGULATORY_CUSTOM_REG`): the calibration regdomain wins over the host hint.

Note stock Android **does** connect on 5520 MHz, so the hardware is capable; stock
derives its country from the modem/NV rather than from the ath10k default. Making
mainline do the same means changing where `current_rd` comes from, which is
regulatory-limit territory and is deliberately left as a separate decision rather
than patched quietly.

### To finish: one of these

| Option | Cost |
| --- | --- |
| Put the AP on a permitted channel (36-48, 149-165) or use its 2.4 GHz SSID | router-side, one setting, proves the stack immediately |
| Make ath10k take the country from the modem/NV as stock does | real work, touches regulatory limits, needs a deliberate decision |

Nothing else is in the way: association was not reached only because no network
the phone has credentials for is reachable on a channel this calibration permits.

### Still open from this run

- `wlan0`'s MAC was the random `c2:fa:...`: `omamobile-dipper-identity` does not
  run in the rescue initramfs, so the real address was not applied from `persist`.
  Harmless for association, but apply it for a real boot.
- `DT bdf variant name not set.` remains; beryllium sets
  `qcom,calibration-variant`. Untried, since our board-2.bin has no variant
  entries and ath10k would fall back to the same data.
- wpa_supplicant ran fine (`wpa_state=SCANNING`) and is not implicated.

## 2026-10-30: Wi-Fi WORKS. Associated, DHCP, internet.

On a RAM boot (nothing flashed, NV read-only throughout) the Mi 8 associated to
the owner's AP on 2.4 GHz and carried real traffic:

```
wpa_state=COMPLETED   freq=2447   signal -59 dBm
udhcpc: lease obtained from the local gateway (addresses omitted)
default route via the local gateway on wlan0
ping -I wlan0 1.1.1.1 -> 3/3 packets, 11.0/16.1/20.2 ms
remoteproc0: running
```

### What it took, in the order it mattered

1. **`ath10k_snoc msa_perm_delay_ms=300`.** The upstream `msleep(20)` before the
   XPU update in `ath10k_qmi_event_server_arrive()` is tuned to
   `MPSS.AT.4.0.c2-01184`; dipper runs `MPSS.AT.4.0.c2.6-00335` and needs longer.
   Now a module parameter, default 20, so upstream behaviour is unchanged.
   **The minimum working value has not been bisected.**
2. **Wait for QRTR service 69 before loading ath10k.** This was the whole
   "flakiness": loading `ath10k_snoc` before the modem publishes the ATH10k WLAN
   firmware service makes the driver wait, time out after ~17 s, and take the
   modem down with it (`fatal error without message`). Gating on service 69 --
   it shows up about 4 s after the modem start -- turned a roughly 50% success
   rate into every attempt. **Any boot script must gate on this, not sleep.**
3. **`ath user_regd=1` plus `iw reg set SK`.** The calibration reports **CN**,
   which omits 5470-5725 entirely, and `ath_regd_init_wiphy()` applies it as a
   `REGULATORY_STRICT_REG | REGULATORY_CUSTOM_REG` domain, so the phy ignored the
   global domain -- `iw phy phy0 reg get` kept saying `country CN` while the
   global said SK. The new `user_regd` parameter (ath.ko, default off) leaves the
   phy on cfg80211's domain instead. With it, channels 100-144 went from
   `(disabled)` to `(26.0 dBm) (no IR, radar detection)` and the firmware really
   did scan 5500-5720 with valid noise floors.

### The one thing that does NOT work: DFS channels

The owner's 5 GHz AP is on **channel 104 / 5520 MHz**, a DFS channel. Scanning it
works; associating does not. Every attempt ends the same way, 52 ms after the
driver tunes to it:

```
wmi tlv vdev start
firmware crashed! (guid ...)   kconfig ... dfs 1 ...
wifi fw qmi service disconnected
qcom-q6v5-mss: watchdog received: SFR Init: wdog or kernel error suspected
```

`CONFIG_ATH10K_DFS_CERTIFIED=y` was enabled and makes no difference -- the banner
shows `dfs 1` and it still crashes. The 2.4 GHz run above proves association,
DHCP and traffic are all fine, so this is specific to starting a vdev on a DFS
channel, not to association.

This matches the only close prior art found: a OnePlus 6T (same SDM845, same
WCN3990) report of `mpss` asserting in `wlan_vdev.c:_wlan_vdev_down` and
escalating to a watchdog, where the reporter ruled out ADSP load, module load
timing, rmtfs read-write and firmware packaging, and concluded "I have not found
a configuration that keeps Wi-Fi and is free of this crash." There is no upstream
fix. The firmware is closed (`WLAN.HL.2.0.c3-00534`), so this is a firmware-side
limit, not something the DT or the driver reaches.

**Practical answer: keep the phone off DFS channels.** Non-DFS and permitted
here: 2.4 GHz, UNII-1 (36-48) and UNII-3 (149-165). Moving the AP's 5 GHz radio
to 36-48 is one router setting and should give 5 GHz without the DFS path; that
is untested but uses the same `vdev start` that works on 2.4 GHz.

### Cleared earlier, with evidence -- do not re-test

| Suspect | Why not |
| --- | --- |
| MSA address/size | stock reserves `wlan_fw_region@0x8e300000/0x100000`, identical to ours |
| `qcom,msa-fixed-perm` | gets past the XPU violation but then dies at first MSA *use*; the assignment is required |
| our `board-2.bin` | upstream's generic file crashes identically |
| `xo-cal-data return -22` | no DTS in tree sets `qcom,xo-cal-data`, beryllium included |
| rejected OEM FSG paths | stock `rmt_storage` knows only four paths and refuses them too |
| WCN3990 supplies | stock icnss uses pm8998 l5/l7/l17/l25, exactly our l5a/l7a/l17a/l25a |
| missing `qrtr-ns` | in-kernel since 5.7; 46 services resolve without it |
| stale initramfs modules | rebuilt with the kernel; made no difference |

### For a real boot (not yet done)

- `msa_perm_delay_ms=300` and `user_regd=1` belong in `/etc/modprobe.d`.
- The regulatory domain must be set at boot, or the phy falls back to CN.
- Something must gate ath10k on QRTR service 69; the modem chain
  (`rmtfs`/`pd-mapper`/`tqftpserv`) still starts nothing automatically.
- `wlan0` had a random MAC; `omamobile-dipper-identity` does not run in rescue.

## board-2.bin: why ours and not upstream's

Upstream linux-firmware's WCN3990 `board-2.bin` holds **36 entries, every one keyed
`qmi-board-id=ff`** (plus a few other SoCs). dipper's own WLAN firmware reports
**board id 0** — the stock kernel logs it verbatim:

```
wlan: [443:I:WMA] wma_rx_service_ready_event: Board id: 0, Board version: 0 0 0 0 0
```

With no matching entry ath10k loads no board data, and Wi-Fi stays down. So
`tools/dipper/build-board-2.py` builds one from the phone's own 34 board-data files:

- **23 entries**, `bus=snoc,qmi-board-id=<hex>,qmi-chip-id=30214` (both ids are `%x` in
  `ath10k_core_create_board_name()`; `30214` is hex, as in upstream's own names),
- board ids **0** and **ff** both carry the phone's default `bdwlan.bin`, covering what it
  reports and ath10k's fallback,
- the 21 `bdwlan.bNN` variants go in under their own ids, so a different unit of the same
  phone still finds its own calibration.

This uses **the phone's factory calibration** rather than generic data, which is what keeps
transmit power correct rather than merely legal-looking. The tool cross-checks itself by
parsing upstream's file first (36 entries, all `snoc`) and refuses to write anything if that
parse fails; `tools/dipper/test-board-2.py` covers round-tripping, a bad magic, IE alignment,
the file-name-to-board-id mapping, and the empty-input refusal.

## The MAC address: generic, read at boot

Generic board data carries no per-unit MAC, so without help the interface comes up with
whatever ath10k invents — different on each boot, which breaks anything keyed to the address.

**The image stays device-agnostic.** `tools/dipper/identity/omamobile-dipper-identity` runs
once at boot, mounts `persist` **read-only**, reads `/wlan_bt/wlan.mac` and
`/wlan_bt/bt.mac` — where every Mi 8 keeps its own factory addresses — and applies them:

- writes `/etc/systemd/network/10-dipper-wlan.link`, which `systemd-udevd` applies whoever
  manages the interface afterwards, NetworkManager included, and sets `wlan0` immediately if
  it already exists;
- sets the Bluetooth public address with `btmgmt` when `hci0` and `btmgmt` are both there.

It refuses an all-zero, broadcast, multicast or short-read value rather than configuring
nonsense, is a quiet no-op when `persist` is absent, and does not rewrite an unchanged link
file. `tools/dipper/identity/test-identity.sh` drives **the script itself** (not a copy of its
logic) through all of those cases.

So **the same image works on any Xiaomi Mi 8**: nothing device-specific is compiled in.

### The single-device alternative, off by default
`tools/dipper/apply-identity` can write a Bluetooth address into the built DTB's
`local-bd-address` instead, which has the advantage of being set before userspace runs. It is
opt-in (`DIPPER_BAKE_IDENTITY=1`) because it makes the image specific to one handset. The DTS
itself carries an all-zero placeholder, so no identifier is ever committed, and the tool finds
the `qcom,wcn3990-bt` node by compatible rather than by path and reads the value back to
confirm it took. `tools/dipper/extract-identity` recovers the addresses offline from the
`persist` backup with `debugfs`, for when the phone is not reachable.

## Is any of this specific to one phone?

Worth being precise, because it decides whether this port serves every Mi 8 or just one:

| Piece | Scope |
| --- | --- |
| board data (`bdwlan.*`) | **per model, not per unit** — it comes from the `modem` partition, so every Mi 8 on the same firmware has the identical set. Our `board-2.bin` carries **all 23 board ids**, not just the one this handset reports, so a unit that reports a different id still finds its own calibration. |
| `wlanmdsp.mbn`, `modem.mbn`, `mba.mbn`, DSP and GPU images | per model |
| WLAN and Bluetooth MAC | **per unit** — and therefore never in the image; read from `persist` at boot |
| the device tree, the panel driver, the descriptor | per model |

The one thing that cannot be shared is distribution: the firmware and board data are Xiaomi's
proprietary blobs, so each owner runs `tools/dipper/extract-firmware` against their own phone.
The tooling is general; the blobs are not ours to ship. That is the same line the project draws
for cheetah's camera data.

## Open

- The four IPC daemons are now vendored as source PKGBUILDs under
  `packages/{qrtr,pd-mapper,tqftpserv,rmtfs}` and included in dipper's local package set.
  All four aarch64 packages and `omamobile-device-dipper` built and were signed into
  `out/dipper/repo`; the full rootfs is built at
  `out/dipper/omamobile-rootfs-2026.10.29-dipper-aarch64.img.zst`. Its manifest
  lists the daemons and Qualcomm/Atheros distro firmware packages, and the 11
  rootfs smoke checks pass. The builder copies private firmware from
  `out/dipper/firmware`. This confirms packaging only: Wi-Fi has not been tested
  on mainline and no radio service is enabled automatically.
- All four IPC daemons exist in the AUR (checked against the AUR API: `qrtr` 1.2-1,
  `rmtfs` 1.2-1, `tqftpserv` 1.2-1, `pd-mapper` 1.1-1, plus `-git` variants for qrtr and
  pd-mapper). These source builds use the project package builder for aarch64.
- Two modem starts have been attempted on this phone under mainline, both crashed. No
  modem/Wi-Fi service is enabled automatically. The older backup's `persist` and `modemst2`
  hashes did not match the live partitions. A fresh read-only snapshot was captured after
  stock Android boot at
  `private off-device reference directory (path omitted)/`; all 15 saved
  partitions match the handset and report read-only. The original snapshots remain
  preserved. `userdata`, Android system/vendor and separately extracted firmware are not
  part of this 15-partition snapshot.
- A private live `/dev/kmsg` stream is being captured outside the repository. The rescue
  initramfs has no Qualcomm user-space daemons, firmware or radio modules. To avoid writing
  to `userdata`, a disposable host-side copy of the built rootfs is exported over the USB
  NCM link and mounted read-write at `the host-side scratch mount` on the phone. Writes affect only the
  scratch copy. The NFS server is disabled at host boot and its export is USB-client-only.
- The current crash followed an `rmtfs` failure to open `/dev/disk/by-partlabel/fsc` for
  `/boot/modem_fsc`. A temporary read-only-checked link stopped new errors, but the crashed
  modem was not restarted. `initramfs/init` now includes `fsc`; rebuild the boot image before
  another RAM boot. Recovery is disabled in the current rescue session, and `ath10k_snoc`
  has not been loaded.
- `qcom,calibration-variant` is deliberately **not** set: we key on board id instead, which
  needs no variant string and no guess about which one this unit is.
