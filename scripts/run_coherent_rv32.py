#!/usr/bin/env python3
"""Build and run the executable dual-RV32 coherent integration lane."""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path

from build_coherent_firmware import build as build_firmware
from check_coherent_rtl_events import check as check_events

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "coherent"
REPORTS = ROOT / "reports"
SUMMARY_RE = re.compile(r"COHERENT_SUMMARY\|(?P<body>[^\n]+)")

SOURCES = (
    "integration/rv32_coherent/vendor/rv32/rv32_core.sv",
    "rtl/coherence/msi_two_cache_subsystem.sv",
    "integration/rv32_coherent/rtl/coherent_rv32_rom_feeder.sv",
    "integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv",
    "integration/rv32_coherent/vendor/axi/qos_arbiter.sv",
    "integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv",
    "integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv",
    "integration/rv32_coherent/rtl/banked_msi_home.sv",
    "integration/rv32_coherent/rtl/dual_rv32_coherent_top.sv",
    "integration/rv32_coherent/sim/tb_dual_rv32_coherent.sv",
)


def parse_fields(body: str) -> dict[str, str]:
    return dict(field.split("=", 1) for field in body.split("|") if "=" in field)


def compile_sim(defines: tuple[str, ...] = (), parameters: tuple[str, ...] = ()) -> Path:
    suffix = "nominal" if not defines else "_".join(item.lower() for item in defines)
    if parameters: suffix += "_" + "_".join(item.lower().replace("=", "") for item in parameters)
    obj = BUILD / f"obj_{suffix}"
    shutil.rmtree(obj, ignore_errors=True)
    command = [
        "verilator", "--binary", "--timing", "--assert", "-Wall", "-Wno-fatal",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "-Wno-PINCONNECTEMPTY", "-Wno-TIMESCALEMOD",
        *(f"-D{define}" for define in defines),
        *(f"-G{parameter}" for parameter in parameters),
        "--top-module", "tb_dual_rv32_coherent", "--Mdir", str(obj), *SOURCES,
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / f"compile_{suffix}.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return obj / "Vtb_dual_rv32_coherent"


def check_trace(path: Path) -> tuple[bool, str, int]:
    rows = list(csv.DictReader(path.open()))
    last_order = [-1, -1]
    retirements = 0
    for row in rows:
        if row["event"] != "retire":
            continue
        hart = int(row["hart"])
        order = int(row["order"])
        if order != last_order[hart] + 1:
            return False, f"hart{hart}_order_{last_order[hart]}_to_{order}", retirements
        last_order[hart] = order
        retirements += 1
        instruction = int(row["insn"], 16)
        if instruction & 0x707f == 0x000f and (int(row["sb0"]) if hart == 0 else int(row["sb1"])):
            return False, f"hart{hart}_fence_retired_nonempty", retirements
    if not retirements:
        return False, "empty_trace", 0

    vendor = ROOT / "integration" / "rv32_coherent" / "vendor" / "rv32"
    if str(vendor) not in sys.path: sys.path.insert(0, str(vendor))
    from rv32_iss import check_trace as iss_check
    for hart in range(2):
        normalized = BUILD / "traces" / f"{path.stem}_hart{hart}_iss.csv"
        selected = []
        for row in rows:
            if row["event"] != "retire" or int(row["hart"]) != hart: continue
            cooked = {key: value for key, value in row.items()
                      if key not in ("cycle", "event", "hart", "sb0", "sb1")}
            address = int(cooked["mem_addr"], 16)
            if address >= 0x4000_0000:
                cooked["mem_addr"] = f"{0x100 | (address & 0xfc):08x}"
            selected.append(cooked)
        with normalized.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=selected[0].keys(), lineterminator="\n")
            writer.writeheader(); writer.writerows(selected)
        result = iss_check(normalized)
        if result.mismatches:
            return False, f"hart{hart}_iss_{result.mismatches[0]}", retirements
    return True, "none", retirements


def run_case(binary: Path, workload: int, optimization: str, label: str) -> dict[str, str]:
    images = build_firmware(workload, optimization, BUILD / "firmware")
    trace = BUILD / "traces" / f"{label}.csv"
    event_trace = BUILD / "event_traces" / f"{label}.csv"
    trace.parent.mkdir(parents=True, exist_ok=True)
    event_trace.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
        f"+TRACE_FILE={trace}", f"+EVENT_TRACE_FILE={event_trace}",
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30)
    (BUILD / f"{label}.log").write_text(result.stdout + result.stderr)
    match = SUMMARY_RE.search(result.stdout + result.stderr)
    fields = parse_fields(match.group("body")) if match else {}
    trace_ok, mismatch, retirements = check_trace(trace) if trace.exists() else (False, "missing_trace", 0)
    enriched_trace = BUILD / "event_traces" / f"{label}_enriched.jsonl"
    model_ok, model_mismatch, _ = check_events(event_trace, enriched_trace) if event_trace.exists() else (False, "missing_event_trace", [])
    if trace_ok and not model_ok: mismatch = model_mismatch
    passed = result.returncode == 0 and match is not None and trace_ok and model_ok
    cycles = int(fields.get("cycles", "0"))
    return {
        "scenario": label,
        "workload": str(workload),
        "optimization": optimization,
        "status": "PASS" if passed else "FAIL",
        "cycles": str(cycles),
        "retirements": str(retirements),
        "cpi": f"{cycles / retirements:.3f}" if retirements else "NA",
        "forwarded_loads": fields.get("forwarded", "0"),
        "bypassed_loads": fields.get("bypassed", "0"),
        "drained_stores": fields.get("drained", "0"),
        "invalidations": fields.get("invalidations", "0"),
        "interventions": fields.get("interventions", "0"),
        "dirty_writebacks": fields.get("writebacks", "0"),
        "axi_wait_cycles": fields.get("axi_wait", "0"),
        "simultaneous_bank_cycles": fields.get("simultaneous_banks", "0"),
        "grants_h0": fields.get("grants0", "0"),
        "grants_h1": fields.get("grants1", "0"),
        "age_overrides": fields.get("age_overrides", "0"),
        "reset_epoch": fields.get("epoch", "0"),
        "first_mismatch": mismatch,
        "trace": str(trace.relative_to(ROOT)),
        "event_trace": str(event_trace.relative_to(ROOT)),
        "enriched_trace": str(enriched_trace.relative_to(ROOT)),
    }


def write_report(name: str, rows: list[dict[str, str]]) -> None:
    REPORTS.mkdir(exist_ok=True)
    with (REPORTS / name).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("smoke", "gcc"), default="smoke", nargs="?")
    args = parser.parse_args()
    subprocess.run(["python3", "scripts/import_coherent_sources.py", "--verify"], cwd=ROOT, check=True)
    binary = compile_sim()
    if args.mode == "smoke":
        rows = [run_case(binary, 0, "-O2", "producer_consumer_smoke")]
        report = "coherent_rv32_smoke.csv"
    else:
        rows = [
            run_case(binary, workload, optimization, f"workload{workload}_{optimization[1:]}")
            for workload in range(8) for optimization in ("-O0", "-O2", "-Os")
        ]
        report = "coherent_gcc_summary.csv"
    write_report(report, rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_{args.mode.upper()}|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
