#!/usr/bin/env python3
"""Run the transaction-correlated coherent crossover closure matrix."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

from check_coherent_rtl_events import check as check_events

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "coherent_closure"
REPORT = ROOT / "reports" / "coherent_directed_closure_summary.csv"
SUMMARY = re.compile(r"CLOSURE_SUMMARY\|(?P<body>[^\n]+)")

DIRECT_SCENARIOS = (
    "sb_youngest_forward_h0", "sb_youngest_forward_h1",
    "sb_nonoverlap_bypass_h0", "sb_nonoverlap_bypass_h1",
    "sb_full_stall", "sb_wrap_h0", "sb_wrap_h1", "fence_occupancy_two",
    "mailbox_unfenced_overtake", "mailbox_fenced_order",
    "clean_conflict_h0", "clean_conflict_h1", "dirty_conflict_h0", "dirty_conflict_h1",
    "shared_upgrade_h0", "shared_upgrade_h1",
    "dirty_intervention_h0_h1", "dirty_intervention_h1_h0",
    "same_line_read_write", "same_line_write_write", "dual_bank_overlap_end_to_end",
)


def compile_bench(defines: tuple[str, ...] = ()) -> Path:
    if not defines:
        shutil.rmtree(BUILD, ignore_errors=True)
    suffix = "obj" if not defines else "obj_" + "_".join(item.lower() for item in defines)
    obj = BUILD / suffix
    shutil.rmtree(obj, ignore_errors=True)
    obj.mkdir(parents=True)
    sources = (
        "rtl/coherence/msi_two_cache_subsystem.sv",
        "integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv",
        "integration/rv32_coherent/vendor/axi/qos_arbiter.sv",
        "integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv",
        "integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv",
        "integration/rv32_coherent/rtl/banked_msi_home.sv",
        "integration/rv32_coherent/sim/tb_coherent_closure.sv",
    )
    command = [
        "verilator", "--binary", "--timing", "--assert", "-Wall", "-Wno-fatal",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET", "-Wno-TIMESCALEMOD",
        *(f"-D{define}" for define in defines),
        "--top-module", "tb_coherent_closure", "--Mdir", str(obj), *sources,
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (BUILD / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return obj / "Vtb_coherent_closure"


def parse(output: str) -> dict[str, str]:
    match = SUMMARY.search(output)
    return dict(field.split("=", 1) for field in match.group("body").split("|") if "=" in field) if match else {}


def main() -> int:
    binary = compile_bench()
    trace_dir = BUILD / "traces"
    trace_dir.mkdir()
    rows: list[dict[str, str]] = []
    for scenario in DIRECT_SCENARIOS:
        event_trace = trace_dir / f"{scenario}_events.csv"
        run = subprocess.run(
            [str(binary), f"+TEST={scenario}", f"+EVENT_TRACE_FILE={event_trace}"],
            cwd=ROOT, text=True, capture_output=True, timeout=30,
        )
        output = run.stdout + run.stderr
        (BUILD / f"{scenario}.log").write_text(output)
        fields = parse(output)
        enriched = trace_dir / f"{scenario}_enriched.jsonl"
        model_ok, mismatch, _ = check_events(event_trace, enriched) if event_trace.exists() else (False, "missing_trace", [])
        event_rows = list(csv.DictReader(event_trace.open())) if event_trace.exists() else []
        final_backing_words = sum(row["event"] == "final_backing" for row in event_rows)
        final_line_words = sum(row["event"] == "final_line" for row in event_rows)
        passed = run.returncode == 0 and fields.get("status") == "PASS" and model_ok
        rows.append({
            "scenario": scenario,
            "group": ("store_buffer_ordering" if scenario.startswith(("sb_", "fence_", "mailbox_")) else
                      "coherent_replacement" if scenario.startswith(("clean_", "dirty_", "shared_", "same_line_")) else
                      "concurrency"),
            "evidence_class": "executable_rtl_integration",
            "status": "PASS" if passed else "FAIL",
            "checks": fields.get("checks", "0"),
            "cycles": fields.get("cycles", "0"),
            "first_mismatch": "none" if passed else mismatch if model_ok is False else "scenario_failure",
            "final_backing_words_checked": str(final_backing_words),
            "final_cache_words_checked": str(final_line_words),
            "event_trace": str(event_trace.relative_to(ROOT)),
            "enriched_trace": str(enriched.relative_to(ROOT)),
        })
    REPORT.parent.mkdir(exist_ok=True)
    with REPORT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_DIRECTED_CLOSURE|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
