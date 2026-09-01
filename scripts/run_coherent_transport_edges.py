#!/usr/bin/env python3
"""Run executable bank-concurrency and QoS transport scenarios."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "coherent_transport"
REPORT = ROOT / "reports" / "coherent_qos_concurrency_summary.csv"
SUMMARY = re.compile(r"TRANSPORT_SUMMARY\|(?P<body>[^\n]+)")


def main() -> int:
    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir(parents=True)
    command = ["verilator", "--binary", "--timing", "--assert", "-Wall", "-Wno-fatal",
               "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
               "--top-module", "tb_coherent_transport",
               "--Mdir", str(BUILD / "obj"),
               "integration/rv32_coherent/vendor/axi/qos_arbiter.sv",
               "integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv",
               "integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv",
               "integration/rv32_coherent/sim/tb_coherent_transport.sv"]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (BUILD / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode: raise SystemExit(result.stderr)
    binary = BUILD / "obj" / "Vtb_coherent_transport"
    traces = BUILD / "traces"
    traces.mkdir()
    rows = []
    tests = ("different_bank", "same_bank_equal", "mixed_qos", "starvation_override",
             "read_response_backpressure", "write_response_backpressure")
    for test in tests:
        event_trace = traces / f"{test}_events.csv"
        run = subprocess.run([str(binary), f"+TEST={test}", f"+EVENT_TRACE_FILE={event_trace}"],
                             cwd=ROOT, text=True, capture_output=True, timeout=30)
        match = SUMMARY.search(run.stdout + run.stderr)
        data = dict(item.split("=", 1) for item in match.group("body").split("|") if "=" in item) if match else {}
        passed = run.returncode == 0 and data.get("status") == "PASS"
        rows.append({**data, "status": "PASS" if passed else "FAIL",
                     "first_mismatch": "none" if passed else "scenario_failure",
                     "event_trace": str(event_trace.relative_to(ROOT))})
    REPORT.parent.mkdir(exist_ok=True)
    fields = ["test", "status", "cycles", "service0", "service1", "max_gap0", "max_gap1",
              "simultaneous", "age_overrides", "wait", "leaf_first_grant", "response_stalls", "first_mismatch",
              "event_trace"]
    with REPORT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_QOS_CONCURRENCY|status={'PASS' if passed == len(tests) else 'FAIL'}|passed={passed}/{len(tests)}")
    return 0 if passed == len(tests) else 1


if __name__ == "__main__": raise SystemExit(main())
