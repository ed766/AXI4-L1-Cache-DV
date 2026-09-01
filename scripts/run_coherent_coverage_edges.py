#!/usr/bin/env python3
"""Run executable store-buffer/fence edge cases used by coherent coverage."""

from __future__ import annotations

import csv
import re
import subprocess

from build_coherent_firmware import build_litmus
from check_coherent_rtl_events import check as check_events
from run_coherent_rv32 import BUILD, REPORTS, ROOT, compile_sim

SUMMARY_RE = re.compile(r"COHERENT_SUMMARY\|(?P<body>[^\n]+)")


def main() -> int:
    binary = compile_sim(parameters=("STORE_DRAIN_DELAY=40",))
    trace_root = BUILD / "coverage_edge_traces"
    firmware_root = BUILD / "litmus_firmware"
    trace_root.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, litmus_id in (("buffer_bypass", 0), ("fence_stall", 1)):
        images = build_litmus(litmus_id, firmware_root)
        event_trace = trace_root / f"{name}_events.csv"
        rvfi_trace = trace_root / f"{name}_rvfi.csv"
        run = subprocess.run([
            str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
            f"+EVENT_TRACE_FILE={event_trace}", f"+TRACE_FILE={rvfi_trace}",
            "+SCHEDULE_SEED=1", "+AXI_BACKPRESSURE_PERCENT=25", "+QOS0=4", "+QOS1=4",
        ], cwd=ROOT, text=True, capture_output=True, timeout=30)
        summary = SUMMARY_RE.search(run.stdout + run.stderr)
        enriched = event_trace.with_name(event_trace.stem.replace("_events", "_enriched") + ".jsonl")
        model_ok, mismatch, events = check_events(event_trace, enriched) if event_trace.exists() else (False, "missing_trace", [])
        fence_harts = {int(row["hart"]) for row in events if row.get("event") == "fence_wait"}
        bypass_harts = {
            int(row["hart"]) for row in events
            if row.get("event") == "fabric_request" and row.get("detail0") == "0" and row.get("detail1") == "1"
        }
        required = fence_harts == {0, 1} if name == "fence_stall" else bypass_harts == {0, 1}
        passed = run.returncode == 0 and summary is not None and model_ok and required
        rows.append({
            "scenario": name, "status": "PASS" if passed else "FAIL",
            "fence_harts": ";".join(map(str, sorted(fence_harts))) or "none",
            "bypass_harts": ";".join(map(str, sorted(bypass_harts))) or "none",
            "event_trace": str(event_trace.relative_to(ROOT)),
            "enriched_trace": str(enriched.relative_to(ROOT)),
            "first_mismatch": "none" if passed else (mismatch if not model_ok else "required_event_missing"),
        })
    report = REPORTS / "coherent_coverage_edge_summary.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_COVERAGE_EDGES|status={'PASS' if passed == 2 else 'FAIL'}|passed={passed}/2")
    return 0 if passed == 2 else 1


if __name__ == "__main__":
    raise SystemExit(main())
