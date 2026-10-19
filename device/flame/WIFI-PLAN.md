<!-- SPDX-License-Identifier: MIT -->
# flame: WCN3990 Wi-Fi bring-up

Status (2026-10-19): RAM-only probe registered `wlan0` and scanned 27 BSS
entries; association and traffic are not validated by this probe.
Kernel source: [postmarketOS SM8150 Linux][kernel], tag `v7.0.0-sm8150`,
release `7.0.0-sm8150`. Packaged inputs and
explicit output directories are described in [BRINGUP-M1](BRINGUP-M1.md).
All UFS nodes stayed read-only; persistent radio startup is deferred with
the native installation work.

## Goal and evidence

Get a WLAN interface, scan, and connect before claiming Wi-Fi support.

- [V, source] `sm8150-google-flame.dts` uses `qcom,wcn3990-wifi` at
  0x18800000 with its regulator supplies. The [SM8150 kernel][kernel] has
  ath10k SNOC, QRTR and the Qualcomm remoteproc drivers.
- [V, hardware] Explicitly loading QRTR SMD and ath10k SNOC succeeded and
  left USB/SSH working. Only `lo` and `usb0` existed afterward. No WLAN
  interface was exposed by that initial step alone.
- [V, source] ath10k's `snoc.c` initializes a QMI client and an MPSS subsystem
  notifier; `qmi.c` waits for the WLFW service. The first-light DTB deliberately
  disables all remote processors. A driver probe alone cannot establish that
  the firmware service is running.
- [V, local extraction] The matching factory vendor image supplies
  `wlanmdsp.mbn`, `bdwlan-flame.bin`, and the GPU firmware. The user's modem
  partition backup supplies `modem.mdt` and its split ELF segments. These
  files remain private and must never enter the repository or a PR.
- [V, source] ath10k's firmware API container and board-file fallback are
  described by `core.c`. The generic WCN3990 `firmware-5.bin` in
  [linux-firmware][linuxfw] is a 60-byte metadata container; the device-specific
  board payload must come from this phone's matching firmware.
- [V, hardware] MPSS runs through `qcom_q6v5_pas`, with QRTR SMD,
  `tqftpserv` and `rmtfs -r -o /run/rmtfs`. Starting it alone did not expose
  WLFW. Loading `qcom_pd_mapper` then registered service 69 (WLFW),
  started WCN3990 and created `wlan0`. ADSP, CDSP and SLPI stayed disabled.
- [V, source] The [kernel PD mapper][pdmapper] includes the SM8150
  `msm/modem/wlan_pd` service map. No new driver or userspace register
  access was needed.

[kernel]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/tree/v7.0.0-sm8150/drivers/net/wireless/ath/ath10k
[pdmapper]: https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux/-/blob/v7.0.0-sm8150/drivers/soc/qcom/qcom_pd_mapper.c
[linuxfw]: https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/ath10k/WCN3990/hw1.0

## Next gated experiment

The next probe may enable MPSS's DT node while leaving its module unloaded
until firmware is staged in RAM. Keep ADSP, CDSP and SLPI disabled initially;
do not start unrelated services or infer cellular support from Wi-Fi.

Before a radio experiment, recheck the five calibration backups against
`persist`, `modemst1`, `modemst2`, `fsg` and `fsc`. Start an external kernel
log stream, confirm the hardware watchdog, and arm a return-to-fastboot timer.
Check a fresh SSH connection before canceling that timer.

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Check backups and storage flags | All checksums match; every UFS node is read-only | Any mismatch or writable node | Stop | Low |
| Stage matching firmware in RAM | Exact requested filenames and matching module release | Missing file or wrong build | Remove RAM files or reboot | Low |
| Load the radio dependency under watchdog/logging | Firmware starts; USB survives; fresh SSH succeeds | DMA fault, kernel warning, firmware crash, or USB loss | Recovery timer / hardware watchdog; Android fastboot and stock B remain intact | Medium |
| Inspect interface and scan | WLAN interface and scan results, kept private | Firmware missing or unstable | Stop before further hardware changes | Low |
| Recheck calibration | All five partition hashes still match | Any change | Stop and investigate; never restore calibration blindly | Low |

Never mount calibration partitions read-write. If a remote filesystem service
is needed, first inspect its source and configure it to serve RAM copies or
avoid writes; do not enable its normal writable-storage service on this
probe. A successful scan still does not prove association or stable traffic.

## Measured firmware-start result

2026-10-18, `7.0.0-sm8150`:

- A fresh RAM boot of the probe verified its built-in watchdog keeper and all
  74 UFS nodes read-only. All five calibration hashes matched before MPSS.
- Matching firmware and checksum-verified NV copies were uploaded in 2 MiB
  chunks and extracted into RAM. `rmtfs` used its read-only shadow-buffer
  mode with no `-P` option; the real NV partitions stayed protected.
- `/dev/qcom_rmtfs_mem1` existed. `/dev/mem` was removed before starting
  `rmtfs` so its legacy fallback could not access physical memory.
- The platform's `qcom,sm8150-mpss-pas` compatible selects
  `qcom_q6v5_pas`, not `qcom_q6v5_mss`. MPSS registered offline because its
  descriptor has `auto_boot=false`; an explicit `start` brought it up.
- Loading `qcom_pd_mapper` supplied the missing registry locator. WLFW
  appeared and ath10k registered `wlan0` using the phone's matching
  `wlanmdsp.mbn`, factory `bdwlan-flame.bin` as `board.bin`, and the generic
  firmware API metadata. The driver selected a random MAC; persistent
  address provisioning has not been implemented.
- Every gated step kept USB and a fresh SSH login working; recovery timers
  were canceled only after those checks. No association, traffic or
  cellular functionality is claimed by this result.

A scan with `iw` returned 27 BSS entries. The requested network was absent,
so association and traffic could not be tested. The ath10k scan path logged
`chan info: invalid frequency 0`; scans still returned results, but that
warning remains open. `persist`, `modemst1/2`, `fsg` and `fsc` were hashed
again after the firmware and scan tests; all matched their backups.
