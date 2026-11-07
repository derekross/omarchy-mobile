<!-- SPDX-License-Identifier: MIT -->
# Prospective Omarchy qualification and migration policy

This isolated candidate is not installed. qualifications.json is deliberately
unapproved: no whole 4.5 release is blessed by its version number. A production
approval belongs to the coordinator after review of the concrete package,
private lock/PAM integration, plugin configuration and runtime gates.

## Before a package transaction

The updater now binds an approved record to the exact package name/version,
aarch64 architecture and archive SHA256 from pacman's prospective metadata.
It also checks the complete target-family patch-series digest, patch-tool
bytes, updater bytes and migration/transaction-shim bytes. Unknown families,
missing records, an unreviewed record, missing signature/reverse evidence,
changed source/policy, mismatched package metadata or missing cached archive
all refuse. Default policy files must be regular root-owned files without
writable group/other bits. Environment path overrides are for the existing
isolated test/maintainer workflow; there is no skip-qualification flag.

4.0.6 targets use legacy-4.0.6; 4.5.0 targets use patches. This does not qualify
all versions in either family: every approved package still needs its exact
version/hash record. The version-aware patcher independently preserves the
currently installed 4.0.6 patch family during adapter deployment.

Every accepted check rehearses the actual cached package. It streams the
archive, materializes only touched regular files and validated absolute-bin
leaf symlinks in a temporary root, checks .PKGINFO, and uses the real patch
tool's path mapping/fuzz=0 behavior. Applied patches are reversed in reverse
order and all touched pristine bytes must match, including created/deleted
files. No archive executable, install script, migration or hook is run. Touched
file limits bound extraction; the whole package is not expanded on disk.

`qualify-prospective` verifies the detached signature against an explicit
keyring, performs this same rehearsal and emits an **approved:false** review
record. It does not edit qualification policy. Do not set approved=true until
the coordinator's concrete review gates pass. Re-run it whenever any bound
source/hash changes. No package is downloaded by automatic check/notify.

The system-package stage is overridden by name for both the old and new
Omarchy update flow. It refreshes metadata alone, resolves the resulting plan,
repeats repository/boot/kernel/prospective checks, then delegates the real
transaction with -Su (no second refresh) and an exact Omarchy version target.
Omarchy 4.5's existing PID1-scope pacman helper and conflict retry remain in
use. On older Omarchy without that helper, the guarded fallback also uses a
PID1 scope where systemd is running. Unsupported refresh results never reach
the install transaction. Direct administrator package-manager commands remain
outside this updater flow; the post-transaction patch hook remains necessary.

## Migration and PAM preservation

Always held pending individual review:

- 1789764927: starts owedvideo; not qualified for the phone video pipeline.
- 1791367434: Fcitx defaults can replace the working phone input method.
- 1792648436: deletes notification history/images; requires backup and review.
- 1791125650: changes fprintd resume/stop lifecycle; mobile claim/PAM policy wins.

PAM rewrites, fingerprint resume hooks, Fcitx and owedvideo are also recognized
by content, including renamed scripts. These mobile-critical matches remain
held with the generic desktop hold override disabled; reviewed migrations are
run individually through the existing run-migration command. Existing generic
boot/repository protections remain in place. No PAM template is rewritten by
this work. Radio's separate public patch 0022 preserves existing protected
mobile password/fingerprint PAM and hooks when apply-lock is invoked.

The private lock's latest one-line PIN-success fix must also remain in the
private integration. It is not part of these public runtime patches.

## Verification

- test/prospective.py uses actual patch application and reverse, rejects
  unapproved/writable/no-signature/changed-series/changed-cache/unknown-family
  inputs, and checks refresh -> gate -> no-refresh pinned transaction ordering.
- test/update.sh exercises the broad existing update/auth/result/notification
  fixture suite with prospective inputs. Host free space is mocked inside the
  test interpreter; the runtime's 10 GiB rule is unchanged.
- test/migration-mobile-holds.py reads the four actual 4.5 migration scripts as
  inert inputs and verifies they and renamed PAM rewrites are held with generic
  holds on/off. Real migration commands are never run. Custom PIN/FP fixture
  files remain unchanged, including max-tries=1.
- The real signed 4.5.0-3 aarch64 archive passes the streamed apply/reverse
  rehearsal with its absolute package-bin links. A source-only rehearsal had
  missed patch hunks targeting tests absent from the package; those were
  removed by the patch-series owner. No live transaction was attempted.
