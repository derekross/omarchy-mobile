#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Summarize the first passive Grizzly D1 DSI0 handoff read."""

import argparse
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
import re


HOST = "f7d8000.dsi2host"
DOMAINS = {"sswrp_dpu_pd", "dpu_be_pd", "dpu_dsi0_pd", "dpu.v", "DpuBe.v", "DpuDsi0.v"}
ROW = re.compile(
    r"-(?P<pid>\d+)\s+(?:\([^)]*\)\s+)?\[\d+\]\s+\S+\s+"
    r"(?P<time>\d+\.\d+):\s+(?P<event>\w+):\s+(?P<body>.*)"
)
REGISTER = re.compile(rf"{re.escape(HOST)}\S* reg=([0-9a-f]+) val=([0-9a-fA-F]+)$")
PHY_INIT = re.compile(r"f7c0000\.dw_mipi_cdphy reg=0*7124 val=([0-9a-fA-F]+)$")
RESUME_RETURN = re.compile(rf"rpm_resume(?:\+\S+)?\s*:{re.escape(HOST)} ret=(-?\d+)$")
MBFS = re.compile(r"(0x[0-9a-f]+):\S+\s+en:([01])(?:\s+\(res:(-?\d+)\))?$")
MBFS_DOMAINS = {0x08: "wrapper", 0x200: "BE", 0x203: "DSI0"}
CPM_EVENT = re.compile(r"dsi0_(clk|rst)_(call|result)$")
CPM_CALL = re.compile(r" lpcm=(\d+) id=(\d+) op=(\d+)$")
CPM_RESULT = re.compile(r" result=(-?\d+)$")
DISPLAY_LPCM = 0x23
DPU_CHANNEL_CLOCK = (0x2a, 0)
PLL_ARM = "DSI0 PLL lock probes armed"
PLL_PHASES = {
    "dsi0_pll_first": "first",
    "dsi0_pll_last": "last",
    "dsi0_pll_relock_first": "relock first",
    "dsi0_pll_relock_last": "relock last",
    "dsi0_pll_cfg_first": "configure first",
    "dsi0_pll_cfg_last": "configure last",
    "dsi0_pll_cfg_timeout": "configure final deadline read",
}
PLL_SAMPLE = re.compile(r" bank=(0x[0-9a-fA-F]+) value=(0x[0-9a-fA-F]+)$")
DSI0_PLL_BANK = 0x0f7d8800
GENPD_ARM = "DSI0 genpd probes armed"
PHY_LOAD = "DSI0 loading mipi-cdphy.ko"
HOST_LOAD = "DSI0 loading mipi-dsi2h.ko"
GENPD_EVENTS = ("dsi0_genpd_sync", "dsi0_genpd_off_begin", "dsi0_genpd_off_end")
GENPD_QUEUE_RESULT = "dsi0_genpd_queue_result"
GENPD_SAMPLE = re.compile(r' domain="dpu_dsi0_pd" work=(0x[0-9a-fA-F]+)$')
GENPD_QUEUED = re.compile(r" queued=([01])$")


def display_resource(kind, lpcm, resource):
    return lpcm == DISPLAY_LPCM or (kind == "clk" and (lpcm, resource) == DPU_CHANNEL_CLOCK)


def summarize_pll(timeline, arm, host_id_time):
    last_on = None
    samples = 0
    for timestamp, index, pid, event, body in timeline:
        if event == "recv_result_mbfs" and (vote := MBFS.fullmatch(body)):
            if int(vote[1], 16) == 0x203 and vote[3] == "0":
                last_on = timestamp if vote[2] == "1" else None
        elif event in PLL_PHASES:
            if (timestamp, index) <= arm:
                raise ValueError("DSI0 PLL sample precedes arm marker")
            match = PLL_SAMPLE.search(body)
            if not match:
                raise ValueError("unexpected stock PLL sample format")
            bank, value = (int(field, 16) for field in match.groups())
            if bank != DSI0_PLL_BANK:
                raise ValueError("unexpected stock PLL register bank")
            samples += 1
            on_delta = "unknown" if last_on is None else f"{(timestamp - last_on) * 1000:.3f}"
            host_delta = "unknown" if host_id_time is None else f"{(timestamp - host_id_time) * 1000:.3f}"
            print(f"{timestamp} DSI0 PHY PLL {PLL_PHASES[event]} pid={pid} "
                  f"reg=0x24 value={value:#010x} lock={(value >> 1) & 1} "
                  f"since_dsi0_on_ms={on_delta} from_host_id_ms={host_delta}")
    print(f"dsi0_pll_samples={samples}")


def summarize_genpd(timeline, status, required):
    markers = defaultdict(list)
    for timestamp, index, _, event, body in timeline:
        if event == "tracing_mark_write" and body in (GENPD_ARM, PHY_LOAD, HOST_LOAD):
            markers[body].append((timestamp, index))
    probe_events = (*GENPD_EVENTS, GENPD_QUEUE_RESULT)
    if not (required or markers or any(row[3] in probe_events for row in timeline)):
        return
    if any(len(markers[name]) != 1 for name in (GENPD_ARM, PHY_LOAD, HOST_LOAD)):
        raise ValueError("expected one genpd arm, PHY load and host load marker")
    arm, phy, host = (markers[name][0] for name in (GENPD_ARM, PHY_LOAD, HOST_LOAD))
    if not arm < phy < host < status:
        raise ValueError("DSI0 genpd markers out of order")

    samples = defaultdict(list)
    votes = defaultdict(list)
    queue_results = defaultdict(list)
    for timestamp, index, pid, event, body in timeline:
        order = (timestamp, index)
        if event in probe_events and order < arm:
            raise ValueError("DSI0 genpd event precedes arm marker")
        if not phy < order < host:
            continue
        if event in GENPD_EVENTS:
            sample = GENPD_SAMPLE.search(body)
            if not sample or not (work := int(sample[1], 16)):
                raise ValueError("invalid DSI0 genpd work sample")
            samples[event].append((order, pid, work))
        elif event == GENPD_QUEUE_RESULT:
            result = GENPD_QUEUED.search(body)
            if not result:
                raise ValueError("invalid genpd queue result")
            queue_results[pid].append((order, result[1]))
        elif event in ("send_mail_mbfs", "recv_result_mbfs") and (vote := MBFS.fullmatch(body)):
            if int(vote[1], 16) == 0x203:
                votes[event, vote[2]].append((order, pid, vote[3]))
    on = votes["recv_result_mbfs", "1"]
    off_request = votes["send_mail_mbfs", "0"]
    off = votes["recv_result_mbfs", "0"]
    if any(len(samples[event]) != 1 for event in GENPD_EVENTS) or any(
        len(messages) != 1 for messages in (on, off_request, off)
    ):
        raise ValueError("missing or ambiguous early DSI0 sync, worker or MBFS events")
    sync, begin, end = (samples[event][0] for event in GENPD_EVENTS)
    [(on_order, on_pid, on_result)] = on
    [(request_order, request_pid, _)] = off_request
    [(off_order, off_pid, off_result)] = off
    queued = next((result for order, result in queue_results[sync[1]] if order > sync[0]), None)
    if not (on_order < sync[0] < begin[0] < request_order < off_order < end[0]
            and on_pid == sync[1]
            and begin[1] == request_pid == off_pid == end[1]
            and sync[2] == begin[2] == end[2]
            and queued == "1"
            and on_result == off_result == "0"):
        raise ValueError("early DSI0 OFF could not be matched to the sync and worker")
    print(f"{sync[0][0]} DSI0 genpd sync pid={sync[1]}")
    print(f"{begin[0][0]} DSI0 genpd power-off worker pid={begin[1]} "
          f"off_reply={off_order[0]} worker_return={end[0][0]} result=0")
    print("dsi0_early_off_correlated=yes")


def summarize(trace, require_genpd=False):
    counts = re.search(r"entries-in-buffer/entries-written:\s*(\d+)/(\d+)", trace)
    if not counts or counts[1] != counts[2] or "LOST EVENTS" in trace:
        raise ValueError("trace buffer loss or missing tracefs header")

    timeline = []
    reads = []
    for index, line in enumerate(trace.splitlines()):
        match = ROW.search(line)
        if not match:
            continue
        pid, timestamp, event, body = match.group("pid", "time", "event", "body")
        clock = Decimal(timestamp)
        register = REGISTER.fullmatch(body) if event == "regmap_reg_read" else None
        if register and int(register[1], 16) == 0x0c:
            reads.append((clock, index, pid, int(register[2], 16)))
        else:
            timeline.append((clock, index, pid, event, body))

    timeline.sort()
    pll_markers = [(timestamp, index) for timestamp, index, _, event, body in timeline
                   if event == "tracing_mark_write" and body == PLL_ARM]
    if len(pll_markers) > 1:
        raise ValueError("duplicate DSI0 PLL arm marker")
    if not pll_markers and any(event in PLL_PHASES for _, _, _, event, _ in timeline):
        raise ValueError("missing DSI0 PLL arm marker")
    if not reads or (not pll_markers and len(reads) != 1):
        raise ValueError(f"expected DSI0 status read, found {len(reads)}")

    read_time, read_index, read_pid, value = min(reads)
    if pll_markers and pll_markers[0] >= (read_time, read_index):
        raise ValueError("DSI0 PLL probe armed after the first host status read")
    resumes = []
    returns = []
    identity = {}
    host_id_time = None
    cpm_armed = False
    phy_armed = False
    phy_reads = 0
    cpm_pending = defaultdict(list)
    cpm_calls = {"clk": 0, "rst": 0}
    cpm_results = {"clk": 0, "rst": 0}
    domain_events = clock_events = 0
    mbfs_events = 0
    for timestamp, index, pid, event, body in timeline:
        if (timestamp, index) >= (read_time, read_index):
            break
        name = body.split(maxsplit=1)[0] if body else ""
        if event == "tracing_mark_write" and body == "DSI0 CPM provider probes armed":
            cpm_armed = True
        elif event == "tracing_mark_write" and body == "DSI0 PHY init read trace armed":
            phy_armed = True
        elif probe := CPM_EVENT.fullmatch(event):
            kind, phase = probe.groups()
            pending = cpm_pending[pid, kind]
            if phase == "call":
                call = CPM_CALL.search(body)
                if not call:
                    raise ValueError("unexpected stock CPM provider call format")
                lpcm, resource, op = map(int, call.groups())
                pending.append((lpcm, resource, op))
                if display_resource(kind, lpcm, resource):
                    cpm_calls[kind] += 1
                    print(f"{timestamp} display CPM {kind} call pid={pid} "
                          f"lpcm={lpcm:#x} id={resource:#x} op={op}")
            else:
                result = CPM_RESULT.search(body)
                if not result:
                    raise ValueError("unexpected stock CPM provider result format")
                if pending:
                    lpcm, resource, op = pending.pop()
                    if display_resource(kind, lpcm, resource):
                        cpm_results[kind] += 1
                        print(f"{timestamp} display CPM {kind} result pid={pid} "
                              f"lpcm={lpcm:#x} id={resource:#x} op={op} result={result[1]}")
        elif event == "regmap_reg_read" and pid == read_pid and (sample := PHY_INIT.fullmatch(body)):
            phy_value = int(sample[1], 16)
            phy_reads += 1
            print(f"{timestamp} DSI0 PHY reg=0x7124 value={phy_value:#010x} "
                  f"lp_dco_clk_dyn_gating={(phy_value >> 8) & 1}")
        elif event == "regmap_reg_read" and pid == read_pid and (register := REGISTER.fullmatch(body)):
            offset, reg_value = (int(field, 16) for field in register.groups())
            if offset in (0, 4):
                identity[offset] = reg_value
                if offset == 0 and reg_value == 0x30313130 and host_id_time is None:
                    host_id_time = timestamp
                print(f"{timestamp} DSI0 reg={offset:#04x} value={reg_value:#010x}")
        elif event == "power_domain_target" and name in DOMAINS:
            print(f"{timestamp} genpd {body}")
            domain_events += 1
        elif event in ("send_mail_mbfs", "recv_result_mbfs"):
            vote = MBFS.fullmatch(body)
            if not vote or (event == "recv_result_mbfs") != (vote[3] is not None):
                raise ValueError("unexpected stock MBFS event format")
            resource = int(vote[1], 16)
            if resource not in MBFS_DOMAINS:
                continue
            result = "" if vote[3] is None else f" result={vote[3]}"
            print(f"{timestamp} MBFS {event} {MBFS_DOMAINS[resource]} "
                  f"resource={resource:#x} on={vote[2]}{result}")
            mbfs_events += 1
        elif event in ("clk_enable", "clk_disable", "clk_set_rate") and ("dsi" in name or "dpu" in name):
            print(f"{timestamp} CCF {event} {body}")
            clock_events += 1
        elif pid == read_pid:
            if event == "rpm_resume" and name == HOST:
                resumes.append((timestamp, index))
                print(f"{timestamp} DSI0 runtime resume")
            elif event == "rpm_status" and body.startswith(f"{HOST} status="):
                print(f"{timestamp} DSI0 runtime {body.split(maxsplit=1)[1]}")
            elif event == "rpm_return_int" and (result := RESUME_RETURN.fullmatch(body)):
                returns.append(((timestamp, index), int(result[1])))
                print(f"{timestamp} DSI0 runtime resume return={result[1]}")

    print(f"{read_time} DSI0 reg=0x0c value=0x{value:08x} pwr_up={value & 1}")
    correlated = bool(resumes and returns and resumes[-1] <= returns[-1][0]
                      and returns[-1][1] >= 0)
    print(f"runtime_resume_correlated={'yes' if correlated else 'no'} "
          f"genpd_events={domain_events} ccf_events={clock_events}")
    print(f"mbfs_events={mbfs_events}")
    if phy_armed:
        print(f"dsi0_phy_reads_on_host_task={phy_reads}")
    if cpm_armed:
        print(f"display_cpm_clock_calls={cpm_calls['clk']} results={cpm_results['clk']} "
              f"display_cpm_reset_calls={cpm_calls['rst']} results={cpm_results['rst']}")
        expected = {0: 0x30313130, 4: 0x1a000110}
        print(f"dsi0_stock_identity={'matched' if identity == expected else 'unconfirmed'}")
    elif any(cpm_calls.values()):
        raise ValueError("missing CPM provider arm marker")
    if pll_markers:
        summarize_pll(timeline, pll_markers[0], host_id_time)
    summarize_genpd(timeline, (read_time, read_index), require_genpd)
    print("APB clock and external reset state require separate evidence.")
    return correlated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="saved tracefs instance trace")
    parser.add_argument("--require-genpd", action="store_true", help="require the early DSI0 OFF correlation")
    args = parser.parse_args()
    try:
        return 0 if summarize(args.trace.read_text(), args.require_genpd) else 1
    except (OSError, ValueError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
