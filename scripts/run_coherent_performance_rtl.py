#!/usr/bin/env python3
"""Measure executable dual-RV32 shared-memory performance in RTL cycles."""

from __future__ import annotations

import csv
import re
import statistics
import subprocess
from pathlib import Path

from build_coherent_firmware import build
from check_coherent_rtl_events import check as check_events
from run_coherent_rv32 import BUILD, REPORTS, ROOT, SUMMARY_RE, compile_sim, parse_fields


def percentile(values: list[int], percent: int) -> int:
    if not values: return 0
    ordered = sorted(values); return ordered[max(0, (len(ordered) * percent + 99) // 100 - 1)]


def latencies(path: Path) -> tuple[list[int], list[int]]:
    pending_load: list[list[int]] = [[], []]
    pending_store: list[list[int]] = [[], []]
    loads, stores = [], []
    for row in csv.DictReader(path.open()):
        hart, cycle = int(row["hart"]), int(row["cycle"])
        if hart < 0: continue
        if row["event"] == "fabric_request" and row["detail0"] == "0": pending_load[hart].append(cycle)
        elif row["event"] == "store_enqueue": pending_store[hart].append(cycle)
        elif row["event"] == "fabric_response" and row["detail1"] == "0":
            if pending_load[hart]: loads.append(cycle - pending_load[hart].pop(0))
        elif row["event"] == "store_drain" and row["detail1"] == "0" and pending_store[hart]:
            stores.append(cycle - pending_store[hart].pop(0))
    return loads, stores


def main() -> int:
    binaries = {
        "buffered": compile_sim(parameters=("SERIALIZE_STORES=0",)),
        "drain_before_next_op": compile_sim(parameters=("SERIALIZE_STORES=1",)),
    }
    rows = []
    for mode, binary in binaries.items():
        for duty in (0, 25, 50, 75):
            for workload in range(10):
                images = build(workload, "-O2", BUILD / "firmware")
                stem = f"perf_{mode}_bp{duty}_w{workload}"
                rvfi = BUILD / "performance_traces" / f"{stem}_rvfi.csv"
                events = BUILD / "performance_traces" / f"{stem}_events.csv"
                events.parent.mkdir(parents=True, exist_ok=True)
                seed = 1 if workload == 9 else 0x5000 + duty * 17 + workload
                run = subprocess.run([
                    str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
                    f"+TRACE_FILE={rvfi}", f"+EVENT_TRACE_FILE={events}",
                    f"+AXI_BACKPRESSURE_PERCENT={duty}", f"+SCHEDULE_SEED={seed}",
                ], cwd=ROOT, text=True, capture_output=True, timeout=30)
                match = SUMMARY_RE.search(run.stdout + run.stderr)
                data = parse_fields(match.group("body")) if match else {}
                model_ok, mismatch, _ = check_events(events, events.with_suffix(".jsonl")) if events.exists() else (False, "missing_trace", [])
                load_lat, store_lat = latencies(events) if events.exists() else ([], [])
                cycles = int(data.get("cycles", "0")); retirements = sum(1 for row in csv.DictReader(rvfi.open()) if row["event"] == "retire") if rvfi.exists() else 0
                grants = int(data.get("grants0", "0")) + int(data.get("grants1", "0"))
                passed = run.returncode == 0 and match is not None and model_ok
                rows.append({
                    "mode": mode, "backpressure_percent": str(duty), "workload": str(workload),
                    "status": "PASS" if passed else "FAIL", "cycles": str(cycles),
                    "retirements": str(retirements), "cpi": f"{cycles/retirements:.3f}" if retirements else "NA",
                    "load_latency_p50": str(percentile(load_lat, 50)), "load_latency_p95": str(percentile(load_lat, 95)),
                    "load_latency_max": str(max(load_lat, default=0)),
                    "store_drain_mean": f"{statistics.mean(store_lat):.2f}" if store_lat else "0.00",
                    "store_drain_p95": str(percentile(store_lat, 95)),
                    "axi_wait_cycles": data.get("axi_wait", "0"),
                    "simultaneous_bank_cycles": data.get("simultaneous_banks", "0"),
                    "simultaneous_bank_utilization": f"{int(data.get('simultaneous_banks','0'))/cycles:.4f}" if cycles else "0.0000",
                    "invalidations": data.get("invalidations", "0"), "interventions": data.get("interventions", "0"),
                    "grants_h0": data.get("grants0", "0"), "grants_h1": data.get("grants1", "0"),
                    "accepted_throughput": f"{grants/cycles:.5f}" if cycles else "0.00000",
                    "first_mismatch": "none" if passed else mismatch,
                    "event_trace": str(events.relative_to(ROOT)),
                })
    report = REPORTS / "coherent_performance.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_RTL_PERFORMANCE|status={'PASS' if passed == len(rows) else 'FAIL'}|rows={passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__": raise SystemExit(main())
