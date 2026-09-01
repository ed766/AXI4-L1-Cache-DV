#!/usr/bin/env python3
"""Run and report Verilator code coverage for coherent integration RTL."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

from build_coherent_firmware import build, build_fault, build_litmus
from run_coherent_closure import DIRECT_SCENARIOS
from run_coherent_rv32 import BUILD, REPORTS, ROOT, SOURCES

COV_ROOT = BUILD / "code_coverage"
RTL_MARKERS = ("integration/rv32_coherent/rtl/", "rtl/coherence/msi_two_cache_subsystem.sv")
COVERAGE_ONLY_SCENARIOS = (
    "simultaneous_enqueue_drain", "simultaneous_enqueue_failed_drain",
    "store_fault_occupancy_two", "store_fault_other_bank_progress",
)


def metadata(descriptor: str) -> tuple[str, str]:
    file_match = re.search(r"\x01f\x02([^\x01]+)", descriptor)
    page_match = re.search(r"\x01page\x02([^\x01]+)", descriptor)
    return (file_match.group(1).replace("\\", "/") if file_match else "",
            page_match.group(1).split("/", 1)[0] if page_match else "unknown")


def compile_top(top: str, sources: tuple[str, ...], label: str) -> Path:
    obj = COV_ROOT / f"obj_{label}"
    obj.mkdir(parents=True)
    class_name = f"V{top}"
    main = COV_ROOT / f"coverage_{label}_main.cpp"
    main.write_text(
        f'#include "{class_name}.h"\n#include "verilated.h"\n#include "verilated_cov.h"\n'
        'int main(int argc, char** argv) { VerilatedContext c; c.commandArgs(argc, argv); '
        f'{class_name} m{{&c}}; while (!c.gotFinish()) {{ m.eval(); '
        'if (m.eventsPending()) c.time(m.nextTimeSlot()); else c.timeInc(1); } '
        'm.final(); VerilatedCov::write("coverage.dat"); return 0; }\n')
    command = [
        "verilator", "--cc", "--exe", "--build", "--timing", "--assert",
        "--coverage", "--coverage-line", "--coverage-toggle", "-Wall", "-Wno-fatal",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "-Wno-PINCONNECTEMPTY", "-Wno-TIMESCALEMOD",
        "--top-module", top, "--Mdir", str(obj), *sources, str(main),
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (COV_ROOT / "compile.log").write_text(result.stdout + result.stderr)
    if result.returncode: raise RuntimeError(result.stderr)
    return obj / class_name


def compile_coverage() -> Path:
    return compile_top("tb_dual_rv32_coherent", SOURCES, "firmware")


def compile_closure_coverage() -> Path:
    sources = (
        "rtl/coherence/msi_two_cache_subsystem.sv",
        "integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv",
        "integration/rv32_coherent/vendor/axi/qos_arbiter.sv",
        "integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv",
        "integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv",
        "integration/rv32_coherent/rtl/banked_msi_home.sv",
        "integration/rv32_coherent/sim/tb_coherent_closure.sv",
    )
    return compile_top("tb_coherent_closure", sources, "closure")


def compile_transport_coverage() -> Path:
    sources = (
        "integration/rv32_coherent/vendor/axi/qos_arbiter.sv",
        "integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv",
        "integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv",
        "integration/rv32_coherent/sim/tb_coherent_transport.sv",
    )
    return compile_top("tb_coherent_transport", sources, "transport")


def execute(binary: Path, label: str, images: list[Path], extra: tuple[str, ...] = ()) -> Path:
    native = ROOT / "coverage.dat"
    native.unlink(missing_ok=True)
    traces = COV_ROOT / "traces"; traces.mkdir(exist_ok=True)
    run = subprocess.run([
        str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
        f"+TRACE_FILE={traces / (label + '_rvfi.csv')}",
        f"+EVENT_TRACE_FILE={traces / (label + '_events.csv')}", *extra,
    ], cwd=ROOT, text=True, capture_output=True, timeout=30)
    (COV_ROOT / f"{label}.log").write_text(run.stdout + run.stderr)
    if run.returncode or not native.exists():
        raise RuntimeError(f"coverage scenario {label} failed or produced no data")
    destination = COV_ROOT / f"{label}.dat"
    native.replace(destination)
    return destination


def execute_closure(binary: Path, scenario: str) -> Path:
    native = ROOT / "coverage.dat"
    native.unlink(missing_ok=True)
    traces = COV_ROOT / "traces"; traces.mkdir(exist_ok=True)
    run = subprocess.run([
        str(binary), f"+TEST={scenario}",
        f"+EVENT_TRACE_FILE={traces / (scenario + '_closure_events.csv')}",
    ], cwd=ROOT, text=True, capture_output=True, timeout=30)
    (COV_ROOT / f"closure_{scenario}.log").write_text(run.stdout + run.stderr)
    if run.returncode or not native.exists():
        raise RuntimeError(f"coverage closure scenario {scenario} failed or produced no data")
    destination = COV_ROOT / f"closure_{scenario}.dat"
    native.replace(destination)
    return destination


def execute_transport(binary: Path, scenario: str) -> Path:
    native = ROOT / "coverage.dat"
    native.unlink(missing_ok=True)
    traces = COV_ROOT / "traces"; traces.mkdir(exist_ok=True)
    run = subprocess.run([
        str(binary), f"+TEST={scenario}",
        f"+EVENT_TRACE_FILE={traces / (scenario + '_transport_events.csv')}",
    ], cwd=ROOT, text=True, capture_output=True, timeout=30)
    (COV_ROOT / f"transport_{scenario}.log").write_text(run.stdout + run.stderr)
    if run.returncode or not native.exists():
        raise RuntimeError(f"coverage transport scenario {scenario} failed or produced no data")
    destination = COV_ROOT / f"transport_{scenario}.dat"
    native.replace(destination)
    return destination


def summarize(files: list[Path]) -> list[dict[str, str]]:
    points: dict[str, dict[str, int]] = {}
    for path in files:
        for raw in path.read_text(errors="replace").splitlines():
            if not raw.startswith("C '"): continue
            try: descriptor, count_text = raw[3:].rsplit("' ", 1); count = int(count_text)
            except (ValueError, IndexError): continue
            source, page = metadata(descriptor)
            if not any(marker in source for marker in RTL_MARKERS): continue
            kind = {"v_line": "line", "v_branch": "branch", "v_expr": "expression",
                    "v_toggle": "toggle"}.get(page, page.removeprefix("v_"))
            points.setdefault(kind, {})[descriptor] = points.setdefault(kind, {}).get(descriptor, 0) + count
    rows = []
    for kind, values in sorted(points.items()):
        hit = sum(value > 0 for value in values.values()); total = len(values)
        rows.append({"scope": "coherent_integration_rtl", "point_type": kind,
                     "hit": str(hit), "total": str(total),
                     "percent": f"{100.0 * hit / total:.2f}" if total else "NA",
                     "reviewed_exclusions": "0"})
    return rows


def holes(files: list[Path]) -> list[dict[str, str]]:
    points: dict[tuple[str, str, str, str], int] = {}
    for path in files:
        for raw in path.read_text(errors="replace").splitlines():
            if not raw.startswith("C '"): continue
            try: descriptor, count_text = raw[3:].rsplit("' ", 1); count = int(count_text)
            except (ValueError, IndexError): continue
            source, page = metadata(descriptor)
            if not any(marker in source for marker in RTL_MARKERS): continue
            kind = {"v_line": "line", "v_branch": "branch", "v_expr": "expression"}.get(page)
            if kind is None: continue
            line_match = re.search(r"\x01l\x02([^\x01]+)", descriptor)
            object_match = re.search(r"\x01o\x02([^\x01]+)", descriptor)
            key = (kind, source, line_match.group(1) if line_match else "0",
                   object_match.group(1) if object_match else "")
            points[key] = points.get(key, 0) + count
    result = []
    for (kind, source, line, object_name), count in points.items():
        if count != 0: continue
        category = "executable_and_worth_testing"
        rationale = "legal uncovered behavior requires directed review"
        if source.endswith("coherent_axi_qos_transport.sv") and line == "224":
            category = "structurally_unreachable_in_adapter"
            rationale = "one-active-request-per-hart adapter cannot sustain fabric-level aging; leaf arbiter aging is executed separately"
        elif source.endswith("coherent_axi_qos_transport.sv") and line == "228":
            category = "mutation_only_failure_path"
            rationale = "reset ghost hold is activated only by the expected-fail reset-epoch mutation"
        elif source.endswith("coherent_axi_qos_transport.sv") and line == "231":
            category = "impractical_diagnostic_saturation"
            rationale = "requires 4095 consecutive active cycles; bounded-progress scenarios reset the watchdog normally"
        elif source.endswith("dual_hart_apb_store_buffer.sv") and line == "129":
            category = "verilator_instrumentation_artifact"
            rationale = "shared-access body is executed by read/write traces; uncovered point is the generated else token"
        elif source.endswith("msi_two_cache_subsystem.sv") and line in ("227", "231"):
            category = "structurally_unreachable_in_adapter"
            rationale = "integrated transport keeps the accepted home response ready, so the response-hold alternative is inactive"
        elif source.endswith("msi_two_cache_subsystem.sv") and line == "235":
            category = "defensive_default_unreachable"
            rationale = "legal enum transitions cannot enter the default control-state arm"
        result.append({
            "point_type": kind, "rtl_file": source, "line": line,
            "signal_or_branch": object_name, "hit_count": "0",
            "category": category, "review_rationale": rationale,
        })
    return sorted(result, key=lambda row: (row["rtl_file"], int(row["line"]), row["point_type"]))


def main() -> int:
    shutil.rmtree(COV_ROOT, ignore_errors=True)
    COV_ROOT.mkdir(parents=True)
    binary = compile_coverage(); files = []
    firmware = COV_ROOT / "firmware"
    for workload in range(10):
        files.append(execute(binary, f"gcc_w{workload}", build(workload, "-O2", firmware),
                             (f"+SCHEDULE_SEED={workload + 1}", f"+AXI_BACKPRESSURE_PERCENT={(workload % 4) * 25}")))
    for litmus_id in range(16):
        files.append(execute(binary, f"litmus_{litmus_id}", build_litmus(litmus_id, firmware),
                             (f"+SCHEDULE_SEED={0x9000 + litmus_id}", "+AXI_BACKPRESSURE_PERCENT=50")))
    files.append(execute(binary, "read_fault", build_fault(0, firmware),
                         ("+FAULT_VALID=1", "+FAULT_WRITE=0", "+FAULT_ADDR=00000000")))
    files.append(execute(binary, "store_fault", build_fault(1, firmware),
                         ("+FAULT_VALID=1", "+FAULT_WRITE=1", "+FAULT_ADDR=00000000")))
    closure_binary = compile_closure_coverage()
    for scenario in DIRECT_SCENARIOS + COVERAGE_ONLY_SCENARIOS:
        files.append(execute_closure(closure_binary, scenario))
    transport_binary = compile_transport_coverage()
    for scenario in ("different_bank", "same_bank_equal", "mixed_qos", "starvation_override",
                     "read_response_backpressure", "write_response_backpressure"):
        files.append(execute_transport(transport_binary, scenario))

    info = REPORTS / "coherent_code_coverage.info"
    subprocess.run(["verilator_coverage", "--write-info", str(info), *map(str, files)], check=True)
    rows = summarize(files)
    report = REPORTS / "coherent_code_coverage.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    hole_rows = holes(files)
    hole_report = REPORTS / "coherent_code_coverage_holes.csv"
    fields = ["point_type", "rtl_file", "line", "signal_or_branch", "hit_count",
              "category", "review_rationale"]
    with hole_report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader(); writer.writerows(hole_rows)
    line = next((float(row["percent"]) for row in rows if row["point_type"] == "line"), 0.0)
    branch_rows = [float(row["percent"]) for row in rows if row["point_type"] in ("branch", "expression")]
    branch = min(branch_rows) if branch_rows else 0.0
    toggle = next((float(row["percent"]) for row in rows if row["point_type"] == "toggle"), 0.0)
    status = "PASS" if line >= 90.0 and branch >= 80.0 else "FAIL"
    (REPORTS / "coherent_code_coverage.md").write_text(
        "# Coherent Integration Code Coverage\n\n"
        "Executable GCC, litmus, error, 21 canonical directed, four focused edge, and six transport scenarios instrument only the coherent integration RTL. "
        "Raw toggle remains visible and cache/data-array bits are not closure targets.\n\n"
        "| Point | Hit / total | Raw | Reviewed exclusions |\n| --- | ---: | ---: | ---: |\n" +
        "".join(f"| {row['point_type']} | {row['hit']} / {row['total']} | {row['percent']}% | 0 |\n" for row in rows) +
        f"\nUncovered executable line/branch points requiring review: {len(hole_rows)}. "
        "See `coherent_code_coverage_holes.csv`.\n\n"
        "Targets: line >= 90%, branch/expression >= 80%. Verilator coverage is open-source proxy evidence.\n")
    print(f"COHERENT_CODE_COVERAGE|status={status}|line={line:.2f}|branch={branch:.2f}|toggle={toggle:.2f}|runs={len(files)}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
