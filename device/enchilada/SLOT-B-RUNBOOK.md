# OnePlus 6 (enchilada): installing to slot B and marking it

The gated runbook for this phone's first persistent install: `tools/install-phone`
writes `boot_b` and `userdata`, the phone boots slot B, and `tools/mark-slot-b`
marks B successful in `sde`'s GPT. It runs under this phone's entry in
[CONTRIBUTING](../../CONTRIBUTING.md) §3.1; the facts it rests on are in
[NOTES](NOTES.md) ("Slots and what is on them", "2026-11-11: `sde`'s GPT").

The owner runs or approves every step. Read-only steps come first, and each
write step waits for the one before it to pass. Record each result in
[NOTES](NOTES.md) with the date and `uname -r`, and the slot flags before
and after on [#432](https://github.com/derekross/omamobile/issues/432).

## Before anything touches the phone

- The §3.1 entry for enchilada is merged, and the owner's acceptance on #432
  covers buttons-only recovery and the EDL case below in so many words.
- The read-only radio backup is current (NOTES "2026-11-05: complete backup";
  take a fresh one after any boot of another system), and the copy of
  `sde`'s two GPT copies from 2026-11-09 is on the laptop with its SHA-256.
- Images and root image built from this tree: `bin/omamobile images`, then
  `tools/build-rootfs`. `tools/mark-slot-b --device enchilada` with no phone
  attached stops at the SSH connection, not at the descriptor.

## Steps

### 1. Read the phone (read-only)

`fastboot devices`, then `fastboot -s SERIAL getvar all 2>&1 | grep -E 'product|unlocked|current-slot|version-bootloader|slot-'`.

- **Expect:** `product: sdm845`, `unlocked: yes`, `current-slot: a`,
  `version-bootloader:` empty, and the slot flags as the last row of NOTES'
  table (A not successful, 5 tries; B not successful, 7 tries; neither unbootable).
- **Stop if:** another product, a locked bootloader, a slot marked
  unbootable, or a retry count of 1 or less.
- **Risk:** none (read-only).

### 2. Dry run (read-only), posted for the maintainer's go

`tools/install-phone --device enchilada --images IMAGES --rootfs ROOTFS --serial SERIAL --bootloader-slots-match unreported --dry-run`

`--serial` is required: `sdm845` is the SoC's name, so any SDM845 phone in
fastboot answers to it. `--bootloader-slots-match unreported` is the
owner's word that both slots run the same bootloader. This ABL reports no
version, and the 2026-11-05 backup found every firmware partition
byte-identical between `_a` and `_b`.

- **Expect:** the `would run:` lines are exactly `flash boot_b`,
  `flash userdata`, `--set-active=b` and `reboot`, and boot-update.conf
  says `AUTO_WRITE=no`.
- **Pass:** the maintainer says go on #432, after reading the posted output
  with the serial removed.
- **Stop if:** any other partition, any other command, or no go.
- **Risk:** none (fastboot reads only).

### 3. Install (writes `boot_b`, `userdata` and the slot flags)

The same command without `--dry-run`; type the codename when asked.

- **Expect:** the two flashes, `--set-active=b`, and the phone restarts on
  slot B.
- **Stop if:** any flash fails: leave the phone in fastboot, record the
  output and ask on #432 before anything else.
- **Rollback:** `fastboot --set-active=a` restarts the rescue. `userdata`
  is erased by the install; the Arch root on it is rebuilt from this tree,
  and nothing else lives there.
- **Risk:** medium: `userdata` is gone, and `--set-active` writes `sde`'s
  GPT through the bootloader, as every slot switch so far has.

### 4. First boot on slot B (read-only)

Over `tools/phone-ssh`:

- `cat /proc/cmdline | tr ' ' '\n' | grep slot_suffix`: expect `androidboot.slot_suffix=_b`.
- `ls /dev/sde`: expect no such file (the guard removed the whole-disk node).
- `cat /sys/block/sde/ro`: expect `0`; then for each `sde` partition
  (`for p in /sys/block/sde/sde*; do echo "${p##*/} $(cat "$p/ro")"; done`),
  only `sde39` (`boot_b`) at `0`, the other 71 at `1`.
- `findmnt -no OPTIONS /run`: expect no `nodev` (`tools/mark-slot-b`
  makes its private block node under `/run`).
- `boot_b` holds the image: `head -c SIZE /dev/sde39 | sha256sum`, with
  SIZE the byte size of `IMAGES/boot.img`, equals that file's `sha256sum`.
- Which LUN holds `xbl` and `xbl_config` (`grep -l 'PARTNAME=xbl' /sys/class/block/*/uevent`):
  record it in NOTES; it is the last open question of NOTES "2026-11-11".

**The owner key:** a header-v0 `boot.img` carries no owner key in its
initramfs. The key reaches root's `authorized_keys` on the root image only, so
SSH answers once the init has handed off to the root on `userdata`, not
before.

- **Stop if:** another slot suffix, `/dev/sde` present, any partition but
  `sde39` and `userdata` writable, or a checksum mismatch. Then reboot to
  the rescue: `fastboot --set-active=a` from the buttons (Volume Down +
  Power).
- **Risk:** none (read-only).

### 5. A boot with no laptop (unmarked)

With the cable out, power the phone off and on, then reconnect it.

- **Expect:** it comes back on slot B. Compare B's `retry` before and
  after this boot, as the read-only plan of step 6 prints it. If it does
  not drop, as A's doesn't on a rescue boot (NOTES), say so on #432 before
  step 6: the mark may not be needed on this bootloader.
- **Stop if:** it comes up in the slot-A rescue: B is not booting on its own.
  Record the slot flags.
- **Risk:** low (one try).

### 6. Plan the mark (read-only), then write it

`tools/mark-slot-b --device enchilada` prints the plan: `boot_b` as
entry 38 of `sde`, its attributes before and after (bit 54 only), and
the four LBAs it changes: 1, 3, 786428 and 786431. Then, with the owner's
yes, `tools/mark-slot-b --device enchilada --write`.

- **Expect:** the plan's attributes show B active, not successful and not
  unbootable, and the write reads both copies back.
- **Stop if:** the plan names other LBAs or bits, or any check refuses.
- **Rollback:** the tool keeps the four old sectors on the laptop
  (`~/android/reference/enchilada/mark-slot-b-sde/`). A run cut off part
  way offers to finish or to put them back; a whole table can be put back
  from the 2026-11-09 copy.
- **Risk:** high: see "If both copies are lost" below.

### 7. Check the mark

`reboot-to bootloader`, then `fastboot -s SERIAL getvar slot-successful:b`
and the other slot flags, then `fastboot reboot`. With the cable out, power
the phone off and on again, as in step 5.

- **Expect:** `slot-successful:b: yes`. Only this proves that bit 54 means
  successful to OnePlus's ABL (NOTES "The bit layout": Qualcomm's
  `PartitionTableUpdate.h`, `PART_ATT_SUCCESS_BIT` 54, `PART_ATT_UNBOOTABLE_BIT`
  55). B boots again with no laptop and no try spent.
- **Stop if:** `no`, or B marked unbootable: record the flags and ask on #432.
- **Risk:** low.

## If both copies are lost

If both GPT copies on `sde` became invalid, ABL could not be loaded from
either slot: no fastboot, no rescue, and the buttons would not help. The way
in is Qualcomm's emergency download mode (EDL, USB `05c6:9008`) with a
programmer that matches this phone, writing back the 2026-11-09 copy of
`sde`'s LBA 0-5 and 786426-786431. `tools/mark-slot-b` writes one copy and
reads it back before it touches the other, so this needs two failures in a
row, but it is the case the owner's acceptance has to name.
