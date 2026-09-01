#!/usr/bin/env python3
"""Exercise precise reads, deferred-store recovery, and reset epochs in RTL."""

from __future__ import annotations

import csv
import re
import subprocess
from pathlib import Path

from build_coherent_firmware import build, build_fault
from check_coherent_rtl_events import check as check_events
from run_coherent_rv32 import BUILD, REPORTS, ROOT, compile_sim

SUMMARY = re.compile(r"COHERENT_SUMMARY\|(?P<body>[^\n]+)")


def parse(output: str) -> dict[str, str]:
    match = SUMMARY.search(output)
    return dict(item.split("=", 1) for item in match.group("body").split("|") if "=" in item) if match else {}


def execute(binary: Path, images: list[Path], name: str, extra: list[str]) -> tuple[bool, dict[str, str], Path]:
    trace = BUILD / "edge_traces" / f"{name}_rvfi.csv"
    events = BUILD / "edge_traces" / f"{name}_events.csv"
    trace.parent.mkdir(parents=True, exist_ok=True)
    command = [str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
               f"+TRACE_FILE={trace}", f"+EVENT_TRACE_FILE={events}", *extra]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30)
    data = parse(result.stdout + result.stderr)
    model_ok, mismatch, _ = check_events(events, events.with_suffix(".jsonl")) if events.exists() else (False, "missing_trace", [])
    ok = result.returncode == 0 and data.get("done0") == "1" and data.get("done1") == "1" and model_ok
    data["model_mismatch"] = mismatch
    return ok, data, events


def first_cycle(path: Path, predicate) -> int:
    for row in csv.DictReader(path.open()):
        if predicate(row): return int(row["cycle"])
    raise RuntimeError(f"required phase not observed in {path}")


def main() -> int:
    binary = compile_sim()
    rows = []
    for mode, name in ((0, "precise_load_error"), (1, "deferred_store_error_recovery")):
        images = build_fault(mode, BUILD / "fault_firmware")
        ok, data, events = execute(binary, images, name,
            ["+FAULT_VALID=1", f"+FAULT_WRITE={mode}", "+FAULT_ADDR=00000000"])
        if mode == 0: ok &= data.get("result0") == "00000000" and data.get("fault0") == "0"
        else: ok &= data.get("result0") == "00000000" and data.get("fault0") == "0"
        rows.append({"scenario": name, "evidence_class": "executable_rtl", "status": "PASS" if ok else "FAIL",
                     "epoch": data.get("epoch", "0"), "first_mismatch": data.get("model_mismatch", "rtl_failure"),
                     "event_trace": str(events.relative_to(ROOT))})

    probes = [(0, build(0, "-O2", BUILD / "firmware")), (9, build(9, "-O2", BUILD / "firmware"))]
    _, _, base_events = execute(binary, probes[0][1], "reset_phase_probe", [])
    _, _, concurrent_events = execute(binary, probes[1][1], "reset_concurrent_probe", [])
    fault_images = build_fault(1, BUILD / "fault_firmware")
    _, _, fault_events = execute(binary, fault_images, "reset_fault_probe",
                                 ["+FAULT_VALID=1", "+FAULT_WRITE=1", "+FAULT_ADDR=00000000"])
    phases = {
        "reset_idle": (probes[0][1], 1),
        "reset_store_pending": (probes[0][1], first_cycle(base_events, lambda r: r["event"] == "store_enqueue") + 1),
        "reset_read_outstanding": (probes[0][1], first_cycle(base_events, lambda r: r["event"] == "fabric_request" and r["detail0"] == "0") + 1),
        "reset_response_pending": (probes[0][1], first_cycle(base_events, lambda r: r["event"] == "bank_request") + 2),
        "reset_concurrent_banks": (probes[1][1], first_cycle(concurrent_events, lambda r: r["event"] == "simultaneous_banks")),
        "reset_dirty_owner": (
            probes[0][1],
            first_cycle(base_events, lambda r: r["event"] == "store_drain" and r["detail1"] == "0") + 1,
        ),
    }
    for name, (images, cycle) in phases.items():
        ok, data, events = execute(binary, images, name, [f"+RESET_CYCLE={cycle}", "+RESET_HOLD=3"])
        ok &= data.get("epoch") == "2"
        rows.append({"scenario": name, "evidence_class": "executable_rtl", "status": "PASS" if ok else "FAIL",
                     "epoch": data.get("epoch", "0"), "first_mismatch": data.get("model_mismatch", "rtl_failure"),
                     "event_trace": str(events.relative_to(ROOT))})

    fault_cycle = first_cycle(
        fault_events, lambda r: r["event"] == "store_drain" and r["detail1"] == "1"
    ) + 1
    ok, data, events = execute(
        binary, fault_images, "reset_failed_store_pending",
        ["+FAULT_VALID=1", "+FAULT_WRITE=1", "+FAULT_ADDR=00000000",
         f"+RESET_CYCLE={fault_cycle}", "+RESET_HOLD=3"],
    )
    ok &= data.get("epoch") == "2" and data.get("fault0") == "0"
    rows.append({
        "scenario": "reset_failed_store_pending", "evidence_class": "executable_rtl",
        "status": "PASS" if ok else "FAIL", "epoch": data.get("epoch", "0"),
        "first_mismatch": data.get("model_mismatch", "rtl_failure"),
        "event_trace": str(events.relative_to(ROOT)),
    })

    report = REPORTS / "coherent_error_reset_summary.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_ERROR_RESET|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__": raise SystemExit(main())
