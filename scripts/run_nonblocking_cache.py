#!/usr/bin/env python3
"""Build, run, and summarize the optional non-blocking cache variant."""

from __future__ import annotations

import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "nonblocking"
REPORTS = ROOT / "reports"
TESTS = [
    "dual_miss_reorder",
    "hit_under_miss",
    "same_line_merge",
    "dirty_eviction",
    "refill_error",
    "writeback_error_preserve",
    "response_backpressure",
    "reset_outstanding",
    "random",
    "performance_serial",
    "performance_windowed",
]
RESULT_RE = re.compile(r"NB_CACHE_RESULT\|(.*)")


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(command), flush=True)
    return subprocess.run(command, text=True, **kwargs)


def write_csv(path: Path, rows: list[dict[str, str]], columns: list[str]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    obj = BUILD / "obj"
    obj.mkdir(exist_ok=True)
    compile_result = run([
        "verilator", "--binary", "--sv", "--timing", "--assert", "-Wall",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
        "--top-module", "tb_l1_dcache_nonblocking", "--Mdir", str(obj),
        str(ROOT / "rtl" / "l1_dcache_nonblocking.sv"),
        str(ROOT / "sim" / "tb_l1_dcache_nonblocking.sv"),
    ], cwd=ROOT)
    if compile_result.returncode:
        return compile_result.returncode

    binary = obj / "Vtb_l1_dcache_nonblocking"
    rows: list[dict[str, str]] = []
    for test in TESTS:
        result = run([str(binary), f"+TEST={test}"], cwd=ROOT, capture_output=True)
        output = result.stdout + result.stderr
        (BUILD / f"{test}.log").write_text(output)
        match = RESULT_RE.search(output)
        row = {"test": test, "status": "FAIL"}
        if match:
            row.update(item.split("=", 1) for item in match.group(1).split("|") if "=" in item)
        if result.returncode:
            row["status"] = "FAIL"
        rows.append(row)
        print(f"{test}: {row['status']}")

    columns = ["test", "status", "checks", "requests", "responses", "max_mshrs",
               "merged", "hit_under_miss", "writebacks", "cycles"]
    write_csv(REPORTS / "nonblocking_cache_summary.csv", rows, columns)
    by_test = {row["test"]: row for row in rows}

    coverage_specs = [
        ("two_mshrs_occupied", "dual_miss_reorder", lambda row: int(row["max_mshrs"]) == 2),
        ("out_of_order_refill_completion", "dual_miss_reorder", lambda row: row["status"] == "PASS"),
        ("hit_under_miss", "hit_under_miss", lambda row: int(row["hit_under_miss"]) > 0),
        ("same_line_miss_merge", "same_line_merge", lambda row: int(row["merged"]) > 0),
        ("dirty_eviction_buffer", "dirty_eviction", lambda row: int(row["writebacks"]) > 0),
        ("refill_error_no_install", "refill_error", lambda row: row["status"] == "PASS"),
        ("writeback_error_preserves_dirty", "writeback_error_preserve", lambda row: row["status"] == "PASS"),
        ("response_backpressure", "response_backpressure", lambda row: row["status"] == "PASS"),
        ("reset_cancels_outstanding", "reset_outstanding", lambda row: row["status"] == "PASS"),
        ("randomized_hazards", "random", lambda row: int(row["requests"]) == 100),
        ("serialized_reference_window", "performance_serial", lambda row: row["status"] == "PASS"),
        ("two_entry_request_window", "performance_windowed", lambda row: int(row["max_mshrs"]) == 2),
    ]
    coverage_rows = []
    for point, test, predicate in coverage_specs:
        observed = by_test[test]["status"] == "PASS" and predicate(by_test[test])
        coverage_rows.append({"point": point, "status": "COVERED" if observed else "MISSING", "evidence": test})
    write_csv(REPORTS / "nonblocking_cache_coverage.csv", coverage_rows, ["point", "status", "evidence"])

    serial = by_test["performance_serial"]
    windowed = by_test["performance_windowed"]
    serial_cycles = int(serial["cycles"])
    windowed_cycles = int(windowed["cycles"])
    speedup = serial_cycles / windowed_cycles
    perf_rows = [
        {"mode": "serialized", "requests": serial["requests"], "cycles": serial["cycles"],
         "requests_per_cycle": f"{int(serial['requests']) / serial_cycles:.6f}", "speedup": "1.000"},
        {"mode": "two_mshr_window", "requests": windowed["requests"], "cycles": windowed["cycles"],
         "requests_per_cycle": f"{int(windowed['requests']) / windowed_cycles:.6f}",
         "speedup": f"{speedup:.3f}"},
    ]
    write_csv(REPORTS / "nonblocking_cache_performance.csv", perf_rows,
              ["mode", "requests", "cycles", "requests_per_cycle", "speedup"])

    assertion_count = len(re.findall(
        r"^\s*a_[A-Za-z0-9_]+:",
        (ROOT / "rtl" / "l1_dcache_nonblocking.sv").read_text(),
        re.MULTILINE,
    ))
    passed = sum(row["status"] == "PASS" for row in rows)
    covered = sum(row["status"] == "COVERED" for row in coverage_rows)
    report = f"""# Non-Blocking L1 Cache Evidence

This optional structural variant is separate from the canonical blocking-cache closure.

| Evidence | Result |
| --- | ---: |
| Directed/random/performance scenarios | `{passed} / {len(rows)}` |
| Architecture coverage points | `{covered} / {len(coverage_rows)}` |
| Named safety assertions | `{assertion_count}` |
| Serialized 32-miss workload | `{serial_cycles}` cycles |
| Two-MSHR windowed workload | `{windowed_cycles}` cycles |
| Measured same-clock speedup | `{speedup:.2f}x` |

The performance comparison uses the same RTL, memory model, addresses, and ten-cycle
refill delay. The serialized mode waits for each response; the windowed mode keeps up
to two different-set misses active. Values are behavioral Verilator cycles, not silicon
frequency or implementation signoff.
"""
    (REPORTS / "nonblocking_cache_report.md").write_text(report)
    print(f"Non-blocking cache: {passed}/{len(rows)} scenarios, {covered}/{len(coverage_rows)} coverage")
    return 0 if passed == len(rows) and covered == len(coverage_rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
