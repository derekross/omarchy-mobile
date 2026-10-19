<!-- SPDX-License-Identifier: MIT -->
# flame: direct ABL candidate, not a verified boot path

Status: 2026-10-26, host assessment only. The measured Pixel 4 installation
still uses U-Boot. The Pixel 4 XL report in
[PR #52](https://github.com/derekross/omarchy-mobile/pull/52),
[BRINGUP-M1 at c0375d7](https://github.com/HemangKumawat/omarchy-mobile/blob/c0375d71e70bbba6a94c7901caa6bc01d3c8ed08/device/coral/BRINGUP-M1.md),
is a candidate recipe for the shared `c2f2-0.5-8906123` bootloader family.
Derek's [review](https://github.com/derekross/omarchy-mobile/pull/52#issuecomment-6428244248)
asks for the missing source branches and slot evidence. Its hardware results
have not been reproduced on flame and do not change flame's device matrix.

## Source and image gates

| Reported ABL requirement | Flame evidence / next gate |
| --- | --- |
| ARM64 Image `text_offset=0x80000` | The retained `7.0.0-sm8150` flame Image has `text_offset=0x0` (read-only host header inspection). Build a published, pinned GPL kernel branch with the reviewed `head.S` change; validate the built header. The current input does not pass this gate. |
| Modern LZ4 frame, magic `04 22 4d 18` | Build from that kernel's uncompressed Image with modern frame compression, then decompress and compare. The gzip payload used by U-Boot is not this ABL input. |
| Two base DTBs with `qcom,msm-id` revisions `<339 0x20000>` and `<339 0x20001>`, `qcom,board-id=<0 0>`, and symbols | Use the public flame DTS and its panel/touch configuration. Publish any source change in the kernel repository; validate both generated DTBs and retain their source pins. Coral's panel/board DTB is not a flame input. |
| Matched no-op `dtbo` entries | Derive count, IDs and revisions from the owner's own flame factory image and retain them privately. The coral MP1.0/index-11 values are evidence for coral only. Review a flame-specific guarded boot/dtbo path before any slot-B write. |

The recipe needs Android header v2 with base `0`, page size `4096`,
kernel offset `0x8000`, ramdisk offset `0x01000000`, tags offset `0x100`,
and DTB offset `0x01f00000`. These values are a reported candidate, not a
flame boot test. The native U-Boot payload instead uses its standard
sentinel base `0x10000000`; the two images must never be interchanged.
Keep image roles and hashes separate.

## Hardware gates after source and host validation

Each step requires the owner's approval, current verified private backups,
physical Android Fastboot access, PID 1's watchdog, external logs and a fresh
independent RAM recovery login. This handset has no bootable stock A;
**recovery is the buttons alone** to Fastboot, with stock B backups ready.

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Read-only slot/source check | Own boot/dtbo backups; B active; each slot's success/unbootable/retry flags and available bootloader versions recorded privately; source/header/DT checks pass | Missing or ambiguous evidence | Keep the current installation | Low |
| Separately reviewed candidate boot/dtbo stage | Named `boot_b`/`dtbo_b` writes only through a guarded flame-specific tool path, and only after explicit approval | No reviewed path, slot/size/hash mismatch, exhausted/unsuccessful B | Stay in Fastboot with private stock B images retained | High |
| Approved candidate boot | Guard holds; fresh root and RAM rescue logins; watchdog handoff; readable display | Hang, missing USB/control or unexpected write | Buttons to Android Fastboot | Medium |
| Approved normal/battery restarts | Fresh boot, clear UI, Wi-Fi traffic and protected hashes unchanged | Recovery loop, display fault, missing control | Buttons to Android Fastboot | Medium |

Direct ABL could remove U-Boot and its small-image header-prefix erase.
It does not settle the boot-success policy: writing `boot_b` cleared its
success flag on the measured flame handset. GPT and userdata writes remain
held for the maintainer's named policy decision. No PMIC/PON latch or charger
register mechanism from the coral report is adopted by this assessment.
