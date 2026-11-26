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


def display_resource(kind, lpcm, resource):
    return lpcm == DISPLAY_LPCM or (kind == "clk" and (lpcm, resource) == DPU_CHANNEL_CLOCK)


def summarize(trace):
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

    if len(reads) != 1:
        raise ValueError(f"expected one DSI0 status read, found {len(reads)}")

    read_time, read_index, read_pid, value = reads[0]
    resumes = []
    returns = []
    identity = {}
    cpm_armed = False
    phy_armed = False
    phy_reads = 0
    cpm_pending = defaultdict(list)
    cpm_calls = {"clk": 0, "rst": 0}
    cpm_results = {"clk": 0, "rst": 0}
    domain_events = clock_events = 0
    mbfs_events = 0
    for timestamp, index, pid, event, body in sorted(timeline):
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
            print(f"{timestamp} DSI0 PHY reg=0x7124 value={phy_value:#010x} bit8={(phy_value >> 8) & 1}")
        elif event == "regmap_reg_read" and pid == read_pid and (register := REGISTER.fullmatch(body)):
            offset, reg_value = (int(field, 16) for field in register.groups())
            if offset in (0, 4):
                identity[offset] = reg_value
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
    print("APB clock and external reset state require separate evidence.")
    return correlated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="saved tracefs instance trace")
    args = parser.parse_args()
    try:
        return 0 if summarize(args.trace.read_text()) else 1
    except (OSError, ValueError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
