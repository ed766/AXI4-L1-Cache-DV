#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "verilator"
REPORTS = ROOT / "reports"

EDGE_TESTS = ("byte_strobe_lane_matrix", "set_way_sweep_toggle", "maintenance_boundary_sets")
DIRECT_MAPPED_TESTS = ("read_miss", "read_hit", "write_miss", "write_hit", "clean_evict", "dirty_evict", "maintenance")


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(command), flush=True)
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=capture)


def write_coverage_main(out: pathlib.Path) -> pathlib.Path:
    path = out / "coverage_main.cpp"
    path.write_text(
        '#include "Vtb_l1_dcache.h"\n'
        '#include "verilated.h"\n'
        '#include "verilated_cov.h"\n'
        'int main(int argc, char** argv) {\n'
        '  VerilatedContext context; context.commandArgs(argc, argv);\n'
        '  Vtb_l1_dcache model{&context};\n'
        '  while (!context.gotFinish()) {\n'
        '    model.eval();\n'
        '    if (model.eventsPending()) context.time(model.nextTimeSlot());\n'
        '    else context.timeInc(1);\n'
        '  }\n'
        '  model.final(); VerilatedCov::write("coverage.dat"); return 0;\n'
        '}\n')
    return path


def compile_binary(name: str, *, sets: int = 64, ways: int = 2) -> pathlib.Path:
    out = BUILD / f"coverage_{name}"
    out.mkdir(parents=True, exist_ok=True)
    coverage_main = write_coverage_main(out)
    command = [
        "verilator", "--coverage", "--cc", "--exe", "--build", "--sv", "--timing",
        "--assert", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", "tb_l1_dcache", "--Mdir", str(out),
        f"-GCACHE_SETS={sets}", f"-GCACHE_WAYS={ways}",
        "rtl/dcache_pkg.sv", "rtl/l1_dcache_top.sv",
        "sim/assertions/dcache_protocol_assertions.sv",
        "sim/monitors/dcache_trace_observer.sv", "sim/tb_l1_dcache.sv",
        str(coverage_main),
    ]
    result = run(command)
    if result.returncode:
        raise SystemExit(result.returncode)
    return out / "Vtb_l1_dcache"


def run_tests(binary: pathlib.Path, tests: tuple[str, ...], *, group: str, coverage_dir: pathlib.Path) -> list[dict[str, str]]:
    coverage_dir.mkdir(parents=True, exist_ok=True)
    trace_dir = BUILD / "traces" / group
    trace_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    pattern = re.compile(r"CACHE_RESULT\|(.*)")
    for test in tests:
        coverage_path = ROOT / "coverage.dat"
        if coverage_path.exists():
            coverage_path.unlink()
        log_path = REPORTS / f"{group}_{test}.log"
        trace_path = trace_dir / f"{test}.csv"
        result = run([str(binary), f"+TEST={test}", "+MODEL_FINAL_FLUSH",
                      f"+TRACE_FILE={trace_path}"], capture=True)
        output = result.stdout + result.stderr
        log_path.write_text(output)
        fields = {"coverage_group": group, "test": test, "status": "FAIL",
                  "log": str(log_path.relative_to(ROOT)), "coverage_dat": "NA"}
        match = pattern.search(output)
        if match:
            fields.update(item.split("=", 1) for item in match.group(1).split("|") if "=" in item)
        if result.returncode != 0:
            fields["status"] = "FAIL"
        if coverage_path.exists():
            dat_path = coverage_dir / f"{group}_{test}.dat"
            coverage_path.replace(dat_path)
            fields["coverage_dat"] = str(dat_path.relative_to(ROOT))
        rows.append(fields)
        print(f"{group}/{test}: {fields['status']}")
    return rows


def main() -> int:
    REPORTS.mkdir(exist_ok=True)
    edge_binary = compile_binary("edges", sets=64, ways=2)
    dm_binary = compile_binary("direct_mapped", sets=128, ways=1)

    rows = []
    rows.extend(run_tests(edge_binary, EDGE_TESTS, group="coverage_edges_2way",
                          coverage_dir=BUILD / "coverage_edges"))
    rows.extend(run_tests(dm_binary, DIRECT_MAPPED_TESTS, group="direct_mapped_variant",
                          coverage_dir=BUILD / "coverage_direct_mapped"))

    columns = ["coverage_group", "test", "status", "requests", "responses", "hits", "misses",
               "evictions", "errors", "cycles", "coverage_dat", "log"]
    with (REPORTS / "coverage_edges_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COVERAGE_EDGES|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}|total={len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
