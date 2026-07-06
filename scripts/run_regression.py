#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "verilator"
REPORTS = ROOT / "reports"
DEFAULT_TESTS = ["smoke", "read_miss", "read_hit", "write_miss", "write_hit",
                 "clean_evict", "dirty_evict", "backpressure", "read_error", "write_error",
                 "byte_strobes", "misaligned", "maintenance", "random"]
DEFAULT_TESTS += ["flush_only", "invalidate_only", "response_backpressure", "reset_mid_refill"]
DEFAULT_TESTS += ["axi_channel_waits", "maintenance_error", "maintenance_final_dirty"]
DEFAULT_TESTS += ["maintenance_channel_waits"]


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, text=True, **kwargs)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tests", default=",".join(DEFAULT_TESTS))
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--coverage", action="store_true")
    args = parser.parse_args()

    BUILD.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    binary = BUILD / "Vtb_l1_dcache"
    mode_args = ["--binary"]
    extra_sources: list[str] = []
    if args.coverage:
        coverage_main = BUILD / "coverage_main.cpp"
        coverage_main.write_text(
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
        mode_args = ["--cc", "--exe", "--build"]
        extra_sources = [str(coverage_main)]
    compile_cmd = [
        args.verilator, *mode_args, "--sv", "--timing", "--assert", "-Wall",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", "tb_l1_dcache", "--Mdir", str(BUILD),
        str(ROOT / "rtl" / "dcache_pkg.sv"),
        str(ROOT / "rtl" / "l1_dcache_top.sv"),
        str(ROOT / "sim" / "assertions" / "dcache_protocol_assertions.sv"),
        str(ROOT / "sim" / "monitors" / "dcache_trace_observer.sv"),
        str(ROOT / "sim" / "tb_l1_dcache.sv"),
        *extra_sources,
    ]
    if args.coverage:
        compile_cmd[1:1] = ["--coverage"]
    result = run(compile_cmd, cwd=ROOT)
    if result.returncode:
        return result.returncode

    rows: list[dict[str, str]] = []
    pattern = re.compile(r"CACHE_RESULT\|(.*)")
    for test in args.tests.split(","):
        log_path = REPORTS / f"{test}.log"
        coverage_path = ROOT / "coverage.dat"
        if coverage_path.exists():
            coverage_path.unlink()
        trace_dir = BUILD / "traces"
        trace_dir.mkdir(exist_ok=True)
        result = run([str(binary), f"+TEST={test}",
                      "+MODEL_FINAL_FLUSH",
                      f"+TRACE_FILE={trace_dir / (test + '.csv')}"],
                     cwd=ROOT, capture_output=True)
        output = result.stdout + result.stderr
        log_path.write_text(output)
        match = pattern.search(output)
        fields: dict[str, str] = {"test": test, "status": "FAIL", "log": str(log_path.relative_to(ROOT))}
        if match:
            fields.update(item.split("=", 1) for item in match.group(1).split("|") if "=" in item)
        if result.returncode != 0:
            fields["status"] = "FAIL"
        rows.append(fields)
        if args.coverage and coverage_path.exists():
            coverage_dir = BUILD / "coverage"
            coverage_dir.mkdir(exist_ok=True)
            coverage_path.replace(coverage_dir / f"{test}.dat")
        print(f"{test}: {fields['status']}")

    columns = ["test", "status", "requests", "responses", "hits", "misses", "evictions", "errors", "cycles", "log"]
    with (REPORTS / "regress_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"Regression: {passed}/{len(rows)} passed")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
