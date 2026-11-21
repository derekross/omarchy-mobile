<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T Pro (hotdog): GNSS (location)

Status: **works** (G0-G5 passed on 2026-11-15, kernel
`7.3.0-rc6-omamobile-push1-g00e3900120f0`, the keys branch from RAM;
omamobile-gnss 0.2.10, omamobile-device-hotdog 0.1.12): the Location switch
serves GNSS fixes to GeoClue through the modem's QMI LOC.
No kernel change: the engine is the modem's, reached over QRTR, which the
modem bring-up ([MODEM-PLAN](MODEM-PLAN.md)) already provides.

## 1. Facts

- **The GNSS engine runs in the modem** (MPSS) and answers the QMI LOC
  service (0x10) over QRTR, next to the services ModemManager uses. Nothing on
  the application processor powers or clocks it: the stock device tree and the
  board's dtbo (entry 18, "MTP 19801 MP") have no GNSS, LNA or antenna node,
  and the rails Linux votes off at late init (l13a, l15a, l16a, l18a, l4c,
  l5c) have no consumer on stock either.
- **The engine was locked.** `Get Engine Lock` answered with an undocumented
  TLV 0x12 (the lock-client mask in Qualcomm's newer LOC API) of 3: both the
  Android framework and non-framework clients locked, which Android sets while
  its Location setting is off, and the modem keeps it in its EFS. A locked
  engine refuses `LOC_START` with QMI error 46 (`GeneralError`), so
  ModemManager's `--location-enable-gps-nmea` failed with "Couldn't start GPS
  engine". `Set Engine Lock` NONE clears it. rmtfs runs with `-r`
  (omamobile-rmtfs.service), so that write stays in RAM: modemst1/2 are never
  written, and the lock is back at the next modem start.
- **The modem emits no standard NMEA.** With a session running, LOC's NMEA
  indication carries only Qualcomm's proprietary `$PQWM1`, `$PQWS1` and
  `$PQWP1-6` sentences, although `Get NMEA Types` lists GGA, RMC, GSV, GSA and
  VTG. On Android the location HAL builds the standard sentences on the
  application processor from LOC's position and satellite reports. So
  ModemManager's `gps-nmea`/`gps-raw` and GeoClue's `[modem-gps]` source,
  which parse those sentences, never yield a position on this phone.
- **The receiver works.** Indoors, at a window: 26 satellites in the almanac,
  all in "search", signal 0, for 7 minutes, and only cell-ID positions
  (technology mask 2). Outdoors (2026-11-15, cable out, a detached probe):
  first tracked satellites after about a minute, first fix after about two,
  then 37-41 of 47-51 satellites tracked on GPS, GLONASS, Galileo and BeiDou at
  up to 47 dB-Hz, 14-20 used per fix, horizontal uncertainty 3.5-11 m. Coated
  window glass was the whole indoor problem.
- **Time.** The engine asks for time (`Inject Time Request`, naming Qualcomm's
  XTRA time servers); `Inject UTC Time` with the NTP-synchronized system time
  answers it. Predicted orbits (XTRA) are not injected yet.

## 2. Design

`omamobile-gnss` gains a Qualcomm path that any phone with LOC over QRTR can
use (packages/omamobile-gnss 0.2.10):

- `omamobile-gnss-qmi-loc` (Python, standard library): finds LOC through the
  QRTR name service, clears the engine lock when the device allows it,
  injects the system time when timesyncd has synchronized it, starts a
  periodic 1 s session with intermediate reports, and writes GGA, RMC and GSA
  (from position reports; a fix only with status success and the satellite
  technology bit) and GSV (from satellite reports, per constellation) to
  `/run/omamobile-gnss/nmea_out`. It follows a modem restart (DEL_SERVER /
  NEW_SERVER), starts the session again after 30 s without a position report,
  and stops it on SIGTERM. It never logs coordinates.
- The device opts in with `/usr/share/omamobile/gnss/qmi-loc.conf`
  (device-hotdog 0.1.12: `ENGINE_UNLOCK=1`, tested against `rmtfs -r`).
  `omamobile-gnss-start` then execs the daemon as `omamobile-gnss.service`'s
  main process, and the existing NMEA bridge serves the FIFO to GeoClue
  (`nmea.sock`) and gpsd (`nmea-tty`). The Location tile, the on-demand start,
  the sleep inhibitor and the GeoClue agent are unchanged.
- device-hotdog turns GeoClue's `[modem-gps]` source off
  (`/etc/geoclue/conf.d/92-omamobile-hotdog.conf`): it can only start the
  engine through ModemManager and never sees a sentence it can use.

## 3. Runbook

| Step | What | Risk | Pass | Stop / rollback |
| --- | --- | --- | --- | --- |
| G0 | Read-only: `mmcli -m any --location-status`, `qmicli -d qrtr://0 --loc-get-engine-lock`, `--loc-get-operation-mode`, `--loc-get-nmea-types` | none | LOC answers | no LOC: modem not up |
| G1 | `qmicli -d qrtr://0 --loc-set-engine-lock=none` (RAM only, rmtfs -r) | low | `Get Engine Lock` TLV 0x12 reads 0 | `--loc-set-engine-lock=all` puts it back; a modem restart does too |
| G2 | A LOC probe (register events, start, print statuses and satellite counts, no coordinates) for 3-5 min | low | position reports every second, satellite reports | none needed: the probe stops its session |
| G3 | The same probe outdoors, detached (`systemd-run`, log to a file), cable out | low | a fix (status 0, technology 1) | none |
| G4 | `pacman -U` omamobile-gnss 0.2.10 and device-hotdog 0.1.12; `omamobile-gnss on` as the user | low | `omamobile-gnss status` reads installed, location on | `omamobile-gnss off`; downgrade |
| G5 | `/usr/lib/geoclue-2.0/demos/where-am-i -a 8 -t 120` near a window or outdoors; `journalctl -u omamobile-gnss` | low | where-am-i prints a position; the journal shows "session started", "first fix", and "session stopped" a minute after where-am-i exits | `omamobile-gnss off` |

## 4. Results

- **G0-G3, 2026-11-15**: as in section 1. The engine lock came back after a
  re-lock to "MI" (`Get Engine Lock`: type 1, clients 0x1) and the daemon
  cleared it at its start.
- **Daemon on the phone, before packaging**: LOC found, lock cleared, session
  started, GSV for GPS and Galileo and a 1 Hz no-fix GGA/RMC/GSA stream
  indoors, session stopped on SIGTERM. The first version ran the session
  without intermediate reports: the modem then sends no position report
  before the first fix, so no GGA or RMC came indoors and the stall check
  never fired (satellite reports kept the socket busy). Both fixed before
  packaging.
- **G4, 2026-11-15**: both packages installed with `pacman -U`,
  `omamobile-gnss on`. `where-am-i -a 8` indoors: GeoClue connected to the
  NMEA socket, the socket started omamobile-gnss.service, the daemon found LOC
  and started the session, the bridge served it ("first NMEA sentence
  received"); GeoClue answered from its cell and Wi-Fi sources meanwhile.
  60 s after the client left, GeoClue and the bridge exited, the session
  stopped and the sleep inhibitor was gone.
- **G5, 2026-11-15, outdoors, cable out**: a detached `where-am-i -a 8` (as the
  user, 8 minutes). The daemon: first fix 52 s after the request (10
  satellites used), 36 tracked at its next summary. where-am-i received a
  position every second from GeoClue's NMEA source ("GPS GGA", "GPS RMC");
  when it ended the service stopped by itself (5.2 s CPU over 8 min 51 s,
  13.7 MB peak). GeoClue printed accuracies of 0-1 m: it derives accuracy
  from HDOP with a coarse table (HDOP up to 1 is 0 m, up to 2 is 1 m), while
  the engine's own horizontal uncertainty was 3.5-11 m in G3.

## 5. Open

- **GeoClue's accuracy is coarse** (its HDOP table, above), so apps draw a
  smaller circle than the engine's uncertainty. A fix would be in GeoClue (an
  accuracy from GST or from a proprietary field), not in our NMEA.

- **XTRA predicted orbits**: the engine asks for them (`Inject Predicted
  Orbits Request`; servers from `Get Predicted Orbits Data Source`). Injecting
  them would shorten the first fix; it is a download from Qualcomm's servers,
  so it would follow `ASSISTANCE` in `/etc/omamobile/gnss.conf`, as the Pixels'
  LTO does.
- **The modem forgets its ephemeris at every modem start** (its EFS is in RAM),
  so each boot's first fix is a cold-ish start.
- `REF_POSITION` from gnss.conf is not injected on this path yet
  (`Inject Position`, 0x39).
