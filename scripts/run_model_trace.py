#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "model"
TRACE_DIR = ROOT / "build" / "verilator" / "traces"
REPORTS = ROOT / "reports"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--traces", default="*.csv")
    parser.add_argument("--summary", help="limit traces to tests listed in a summary CSV")
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(exist_ok=True)
    checker = BUILD / "cache_trace_checker"
    compile_result = subprocess.run([
        "g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
        str(ROOT / "model" / "cache_reference.cpp"),
        str(ROOT / "model" / "cache_trace_checker.cpp"),
        "-o", str(checker),
    ], cwd=ROOT)
    if compile_result.returncode:
        return compile_result.returncode

    traces = sorted(TRACE_DIR.glob(args.traces))
    if args.summary:
        summary_path = ROOT / args.summary
        with summary_path.open() as handle:
            selected = {row["test"] for row in csv.DictReader(handle)}
        traces = [trace for trace in traces if trace.stem in selected]
    if not traces:
        raise SystemExit(f"no selected traces matching {args.traces} under {TRACE_DIR}")
    pattern = re.compile(r"TRACE_CHECK\|(.*)")
    rows = []
    for trace in traces:
        result = subprocess.run([str(checker), str(trace)], cwd=ROOT,
                                text=True, capture_output=True)
        output = result.stdout + result.stderr
        match = pattern.search(output)
        fields = {"test": trace.stem, "status": "FAIL", "trace": str(trace.relative_to(ROOT))}
        if match:
            fields.update(item.split("=", 1) for item in match.group(1).split("|") if "=" in item)
        if result.returncode:
            print(output, file=sys.stderr)
            fields["status"] = "FAIL"
        rows.append(fields)
        print(f"{trace.stem}: {fields['status']}")

    columns = ["test", "status", "responses", "axi_beats", "evictions",
               "memory_words", "mismatches", "trace"]
    with (REPORTS / "model_trace_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"MODEL_TRACE|passed={passed}|total={len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
