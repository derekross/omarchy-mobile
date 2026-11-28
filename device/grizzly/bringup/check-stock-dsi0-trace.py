#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Summarize the first passive Grizzly D1 DSI0 handoff read."""

import argparse
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
import re


HOST = "f7d8000.dsi2host"
WRAPPER_RPM_DEVICES = {"f190000.disp_smmu", "f600000.dc9x00"}
DOMAINS = {"sswrp_dpu_pd", "dpu_be_pd", "dpu_dsi0_pd", "dpu.v", "DpuBe.v", "DpuDsi0.v"}
ROW = re.compile(
    r"-(?P<pid>\d+)\s+(?:\([^)]*\)\s+)?\[(?P<cpu>\d+)\]\s+\S+\s+"
    r"(?P<time>\d+\.\d+):\s+(?P<event>\w+):\s+(?P<body>.*)"
)
REGISTER = re.compile(rf"{re.escape(HOST)}\S* reg=([0-9a-f]+) val=([0-9a-fA-F]+)$")
PHY_INIT = re.compile(r"f7c0000\.dw_mipi_cdphy reg=0*7124 val=([0-9a-fA-F]+)$")
RESUME_RETURN = re.compile(rf"rpm_resume(?:\+\S+)?\s*:{re.escape(HOST)} ret=(-?\d+)$")
MBFS = re.compile(r"(0x[0-9a-f]+):\S+\s+en:([01])(?:\s+\(res:(-?\d+)\))?$")
MBFS_DOMAINS = {0x08: "wrapper", 0x200: "BE", 0x201: "FE0", 0x202: "FE1",
                0x203: "DSI0", 0x204: "DSI1", 0x205: "DP0"}
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
GENPD_DEVICES_ARM = "DSI0 genpd device probes armed"
WRAPPER_STACK_ARM = "DSI0 wrapper stack trace armed"
WRAPPER_FRAME = re.compile(r"[a-zA-Z_]\w*(?:[.$]\w+)*(?:\+0x[0-9a-f]+/0x[0-9a-f]+)?(?: \[[\w-]+\])?$")
PHY_LOAD = "DSI0 loading mipi-cdphy.ko"
HOST_LOAD = "DSI0 loading mipi-dsi2h.ko"
GENPD_EVENTS = ("dsi0_genpd_sync", "dsi0_genpd_off_begin", "dsi0_genpd_off_end")
GENPD_QUEUE_RESULT = "dsi0_genpd_queue_result"
GENPD_SAMPLE = re.compile(r' domain="([a-z0-9_]+)" work=(0x[0-9a-fA-F]+)$')
GENPD_DEVICE = re.compile(r' device="([a-zA-Z0-9_.:@+-]+)" domain="([a-z0-9_]+)"')
GENPD_ATTACH_END = re.compile(r" result=(-?\d+)$")
GENPD_ATTACH_EVENTS = ("dsi0_genpd_attach", "dsi0_genpd_attach_end")
GENPD_QUEUED = re.compile(r" queued=([01])$")
PHY_RESET_ARM = "DSI0 PHY reset probe armed"
PHY_RESET_PM = "dsi0_phy_reset_pm"
PHY_RESET_RESULT = "dsi0_phy_reset_result"
PHY_RESET_PREFIX = "DSI0 PHY reset "
PHY_RESET_BEGIN = re.compile(r"DSI0 PHY reset begin (after-phy|after-display) (phy_rst_n|shutdown_n)")
PHY_RESET_END = re.compile(
    r"DSI0 PHY reset end (after-phy|after-display) (phy_rst_n|shutdown_n) "
    r"(unavailable|missing|unreadable|read_failed|invalid|(?:0x)?0*[01])"
)
PHY_RESET_VALUES = re.compile(r"(?:0x)?0*[01]")
RMW_ARM = "DSI0 PHY register 0x28 trace armed"
RMW_PROFILE = "PHY RMW probe profile count=20 missed=0"
RMW_SITE = re.compile(r"((?:cfg|off)_[a-z0-9_]+)_(begin|end)$")
RMW_FIELDS = re.compile(r" bank=0x0*f7d8800 (value|result)=(-?\d+)$")
RMW_WORD = re.compile(r"f7c0000\.dw_mipi_cdphy\S* reg=0*28 val=(?:0x)?([0-9a-fA-F]+)$")


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
            if not sample or not (work := int(sample[2], 16)):
                raise ValueError("invalid DSI0 genpd work sample")
            if sample[1] == "dpu_dsi0_pd":
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


def summarize_genpd_devices(timeline, arm, status):
    attached = set()
    pending = defaultdict(list)
    work_ids = {}
    for timestamp, index, pid, event, body in timeline:
        if (timestamp, index) >= status:
            break
        if event not in (*GENPD_EVENTS, *GENPD_ATTACH_EVENTS):
            continue
        if (timestamp, index) <= arm:
            raise ValueError("display genpd event precedes device-arm marker")
        detail = ""
        if event in (*GENPD_ATTACH_EVENTS, "dsi0_genpd_sync"):
            device = GENPD_DEVICE.search(body)
            if not device:
                raise ValueError("missing display genpd device name")
            detail = f" device={device[1]}"
            if event in GENPD_ATTACH_EVENTS:
                phase = event.removeprefix("dsi0_genpd_")
                result = ""
                if phase == "attach":
                    pending[pid].append(device.groups())
                else:
                    reply = GENPD_ATTACH_END.search(body)
                    if not reply or not pending[pid] or pending[pid].pop() != device.groups():
                        raise ValueError("unmatched display genpd attachment result")
                    result = f" result={reply[1]}"
                    if reply[1] == "0":
                        attached.add(device.groups())
                print(f"{timestamp} display genpd {phase} pid={pid}{detail} domain={device[2]}{result}")
                continue
        sample = GENPD_SAMPLE.search(body)
        if not sample or not (work := int(sample[2], 16)):
            raise ValueError("invalid display genpd work sample")
        work_id = work_ids.setdefault(work, len(work_ids) + 1)
        phase = event.removeprefix("dsi0_genpd_")
        print(f"{timestamp} display genpd {phase} pid={pid}{detail} domain={sample[1]} work={work_id}")
    expected = {("f7c0000.dw_mipi_cdphy", "dpu_dsi0_pd"), (HOST, "dpu_dsi0_pd")}
    if not expected <= attached:
        raise ValueError("missing DSI0 PHY or host attachment")


def summarize_wrapper(trace, required):
    rows = [match for line in trace.splitlines() if (match := ROW.search(line))]
    armed = [index for index, row in enumerate(rows)
             if row["event"] == "tracing_mark_write" and row["body"] == WRAPPER_STACK_ARM]
    if not armed and not required:
        return
    if len(armed) != 1:
        raise ValueError("expected one wrapper stack arm marker")

    pending = {}
    paths = []
    rpm_events = 0
    for row in rows[armed[0] + 1:]:
        pid, cpu, timestamp, event, body = row.group("pid", "cpu", "time", "event", "body")
        task = (pid, cpu)
        if event == "dsi0_wrapper_frame":
            if not paths or task != paths[-1][0] or timestamp != paths[-1][1]:
                raise ValueError("unexpected wrapper stack frame")
            if WRAPPER_FRAME.fullmatch(body):
                paths[-1][4].append(body)
            continue
        if event == "dsi0_wrapper_stack":
            if body != "<stack trace>" or task not in pending:
                raise ValueError("wrapper stack has no matching vote")
            request_time, on = pending.pop(task)
            paths.append((task, timestamp, request_time, on, []))
        elif event == "send_mail_mbfs" and (vote := MBFS.fullmatch(body)) and int(vote[1], 16) == 8:
            if task in pending:
                raise ValueError("wrapper vote is missing its stack")
            pending[task] = (timestamp, vote[2])
        elif event.startswith("rpm_"):
            device = body.split(maxsplit=1)[0].rsplit(":", 1)[-1]
            if device in WRAPPER_RPM_DEVICES:
                rpm_events += 1
                print(f"{timestamp} display {event} pid={pid} {body}")
    if pending or not paths or any(not frames for _, _, _, _, frames in paths):
        raise ValueError("wrapper vote stack capture incomplete")
    for (pid, cpu), _, request_time, on, frames in paths:
        print(f"{request_time} wrapper vote on={on} pid={pid} cpu={cpu} path={' -> '.join(frames)}")
    print(f"wrapper_vote_stacks={len(paths)} display_rpm_events={rpm_events}")


def summarize_phy_reset(timeline, host_status, required):
    rows = [row for row in timeline if row[3] in (PHY_RESET_PM, PHY_RESET_RESULT) or
            (row[3] == "tracing_mark_write" and row[4].startswith(PHY_RESET_PREFIX))]
    if not (required or rows):
        return
    if not rows or rows[0][3:] != ("tracing_mark_write", PHY_RESET_ARM) or rows[0][:2] >= host_status:
        raise ValueError("expected the PHY reset probe to arm before host status")

    position = 1
    confirmed = 0
    for phase, before_host in (("after-phy", True), ("after-display", False)):
        for field in ("phy_rst_n", "shutdown_n"):
            if position >= len(rows):
                raise ValueError("missing PHY reset attempt")
            begin = rows[position]
            marker = PHY_RESET_BEGIN.fullmatch(begin[4]) if begin[3] == "tracing_mark_write" else None
            if not marker or marker.groups() != (phase, field):
                raise ValueError("unexpected PHY reset begin marker")
            position += 1
            pm_result = None
            result = None
            sample = begin
            if position < len(rows) and rows[position][3] == PHY_RESET_PM:
                sample = rows[position]
                pm_match = CPM_RESULT.search(sample[4])
                if not pm_match or sample[2] != begin[2]:
                    raise ValueError("invalid PHY reset runtime PM result")
                pm_result = int(pm_match[1])
                position += 1
            if position < len(rows) and rows[position][3] == PHY_RESET_RESULT:
                sample = rows[position]
                result = CPM_RESULT.search(sample[4])
                if not result or sample[2] != begin[2]:
                    raise ValueError("invalid PHY reset regmap result")
                result = int(result[1])
                position += 1
            if position >= len(rows):
                raise ValueError("missing PHY reset end marker")
            end = rows[position]
            marker = PHY_RESET_END.fullmatch(end[4]) if end[3] == "tracing_mark_write" else None
            if (not marker or marker.groups()[:2] != (phase, field) or begin[2] != end[2]
                    or any((row[:2] < host_status) != before_host for row in (begin, end))):
                raise ValueError("invalid PHY reset end marker or host ordering")
            position += 1

            value = marker[3]
            has_value = PHY_RESET_VALUES.fullmatch(value) is not None
            if pm_result is not None and ((pm_result > 0) != (result is not None)):
                raise ValueError("PHY reset regmap result disagrees with runtime PM gate")
            if result == 0 and has_value:
                state = f"value={int(value, 16)}"
                confirmed += 1
            elif result is None and has_value:
                raise ValueError("PHY reset value lacks a regmap result")
            elif result is None:
                cause = "no_regmap_read" if value == "unavailable" else value
                if pm_result is not None:
                    cause = "phy_not_in_use" if pm_result == 0 else "pm_check_error"
                state = f"unobserved={cause}"
            elif result != 0:
                state = f"unobserved=regmap_error regmap_result={result}"
            else:
                state = "unobserved=debugfs_unavailable regmap_result=0"
            if pm_result is not None:
                state += f" pm_result={pm_result}"

            last_on = None
            for timestamp, index, _, event, body in timeline:
                if (timestamp, index) >= sample[:2]:
                    break
                if event == "recv_result_mbfs" and (vote := MBFS.fullmatch(body)):
                    if int(vote[1], 16) == 0x203 and vote[3] == "0":
                        last_on = timestamp if vote[2] == "1" else None
            on_delta = "unknown" if last_on is None else f"{(sample[0] - last_on) * 1000:.3f}"
            host_delta = f"{(sample[0] - host_status[0]) * 1000:.3f}"
            print(f"{sample[0]} DSI0 PHY reset {phase} {field} {state} "
                  f"since_dsi0_on_ms={on_delta} from_pwr_up_ms={host_delta}")
    if position != len(rows):
        raise ValueError("unexpected extra PHY reset trace events")
    print(f"dsi0_phy_reset_confirmed={confirmed}/4")


def check_buffer(trace):
    counts = re.search(r"entries-in-buffer/entries-written:\s*(\d+)/(\d+)", trace)
    if not counts or counts[1] != counts[2] or "LOST EVENTS" in trace:
        raise ValueError("trace buffer loss or missing tracefs header")
    return int(counts[1])


def summarize_rmw(trace):
    count = check_buffer(trace)
    if trace.count(RMW_PROFILE) != 1:
        raise ValueError("missing or invalid PHY register probe profile")
    rows = [match.group("pid", "time", "event", "body")
            for line in trace.splitlines() if (match := ROW.search(line))]
    if len(rows) != count:
        raise ValueError("incomplete PHY register trace export")
    rows.sort(key=lambda row: Decimal(row[1]))
    active = {}
    armed = False
    calls = reads = writes = unmatched = 0
    for pid, timestamp, event, body in rows:
        if event == "tracing_mark_write" and body == RMW_ARM:
            if armed:
                raise ValueError("duplicate PHY register trace arm marker")
            armed = True
        elif site := RMW_SITE.fullmatch(event):
            field = RMW_FIELDS.search(body)
            if not armed or not field:
                raise ValueError("invalid PHY register call marker or aperture")
            if site[2] == "begin":
                if pid in active or field[1] != "value":
                    raise ValueError("nested or malformed PHY register call")
                active[pid] = (site[1], int(field[2]), {})
            else:
                if pid not in active or active[pid][0] != site[1] or field[1] != "result":
                    raise ValueError("unpaired PHY register return")
                name, requested, words = active.pop(pid)
                decoded = []
                for kind in ("read", "write"):
                    if kind in words:
                        word = words[kind]
                        decoded.append(f"{kind}={word:#010x} {kind}_phy_rst_n={word & 1} "
                                       f"{kind}_shutdown_n={(word >> 1) & 1}")
                print(f"{timestamp} {name} requested={requested} result={field[2]} "
                      + (" ".join(decoded) if decoded else "word=unobserved"))
                calls += 1
                reads += "read" in words
                writes += "write" in words
        elif event in ("regmap_reg_read", "regmap_reg_write"):
            word = RMW_WORD.fullmatch(body)
            if not word:
                raise ValueError("unexpected PHY register access")
            if pid not in active:
                unmatched += 1
                continue
            kind = event.removeprefix("regmap_reg_")
            words = active[pid][2]
            if kind in words or (kind == "read" and "write" in words):
                raise ValueError("ambiguous PHY register accesses within one call")
            words[kind] = int(word[1], 16)
    if not armed or active:
        raise ValueError("missing arm or incomplete PHY register call")
    print(f"phy_rmw_calls={calls} reads={reads} writes={writes} unmatched={unmatched}")


def summarize(trace, require_genpd=False, require_phy_reset=False, require_genpd_devices=False,
              require_wrapper=False):
    check_buffer(trace)
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
    genpd_device_markers = [(ts, index) for ts, index, _, event, body in timeline
                            if event == "tracing_mark_write" and body == GENPD_DEVICES_ARM]
    if len(genpd_device_markers) > 1 or (require_genpd_devices and not genpd_device_markers):
        raise ValueError("expected one display genpd device-arm marker")
    if genpd_device_markers and genpd_device_markers[0] >= (read_time, read_index):
        raise ValueError("display genpd device probes armed after the first host status read")
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
            caller = f" pid={pid}" if genpd_device_markers else ""
            print(f"{timestamp} MBFS {event} {MBFS_DOMAINS[resource]} "
                  f"resource={resource:#x} on={vote[2]}{result}{caller}")
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
    if genpd_device_markers:
        summarize_genpd_devices(timeline, genpd_device_markers[0], (read_time, read_index))
    summarize_wrapper(trace, require_wrapper)
    summarize_phy_reset(timeline, (read_time, read_index), require_phy_reset)
    print("APB clock and external reset state require separate evidence.")
    return correlated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="saved tracefs instance trace")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--require-genpd", action="store_true", help="require the early DSI0 OFF correlation")
    mode.add_argument("--require-genpd-devices", action="store_true",
                      help="require display genpd device samples and the early DSI0 OFF correlation")
    mode.add_argument("--require-wrapper", action="store_true",
                      help="require display genpd device samples and wrapper vote call stacks")
    mode.add_argument("--require-phy-reset", action="store_true", help="require the four PHY reset attempts")
    mode.add_argument("--phy-rmw", action="store_true", help="decode the stock PHY register 0x28 trace")
    args = parser.parse_args()
    try:
        trace = args.trace.read_text()
        if args.phy_rmw:
            summarize_rmw(trace)
            return 0
        devices = args.require_genpd_devices or args.require_wrapper
        return 0 if summarize(trace, args.require_genpd or devices, args.require_phy_reset,
                              devices, args.require_wrapper) else 1
    except (OSError, ValueError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
