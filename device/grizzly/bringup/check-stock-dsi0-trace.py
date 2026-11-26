#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Summarize the first passive Grizzly D1 DSI0 handoff read."""

import argparse
from decimal import Decimal
from pathlib import Path
import re


HOST = "f7d8000.dsi2host"
DOMAINS = {"sswrp_dpu_pd", "dpu_be_pd", "dpu_dsi0_pd", "dpu.v", "DpuBe.v", "DpuDsi0.v"}
ROW = re.compile(
    r"-(?P<pid>\d+)\s+(?:\([^)]*\)\s+)?\[\d+\]\s+\S+\s+"
    r"(?P<time>\d+\.\d+):\s+(?P<event>\w+):\s+(?P<body>.*)"
)
STATUS = re.compile(rf"{re.escape(HOST)}\S* reg=0?c val=([0-9a-fA-F]+)$")
RESUME_RETURN = re.compile(rf"rpm_resume(?:\+\S+)?\s*:{re.escape(HOST)} ret=(-?\d+)$")
MBFS = re.compile(r"(0x[0-9a-f]+):\S+\s+en:([01])(?:\s+\(res:(-?\d+)\))?$")
MBFS_DOMAINS = {0x08: "wrapper", 0x200: "BE", 0x203: "DSI0"}


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
        if event == "regmap_reg_read" and (status := STATUS.fullmatch(body)):
            reads.append((clock, index, pid, int(status[1], 16)))
        else:
            timeline.append((clock, index, pid, event, body))

    if len(reads) != 1:
        raise ValueError(f"expected one DSI0 status read, found {len(reads)}")

    read_time, read_index, read_pid, value = reads[0]
    resumes = []
    returns = []
    domain_events = clock_events = 0
    mbfs_events = 0
    for timestamp, index, pid, event, body in sorted(timeline):
        if (timestamp, index) >= (read_time, read_index):
            break
        name = body.split(maxsplit=1)[0] if body else ""
        if event == "power_domain_target" and name in DOMAINS:
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
