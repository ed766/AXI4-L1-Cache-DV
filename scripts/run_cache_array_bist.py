#!/usr/bin/env python3
"""Run integrated destructive BIST against real cache arrays in parity and SECDED variants."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "rtl/dcache_pkg.sv", "rtl/l1_dcache_top.sv",
    "sim/assertions/dcache_protocol_assertions.sv",
    "sim/monitors/dcache_trace_observer.sv", "sim/tb_l1_dcache.sv",
]


def main() -> int:
    rows: list[dict[str, str]] = []
    coverage: dict[str, set[str]] = {}
    for variant, secded in (("parity", 0), ("secded", 1)):
        build = ROOT / "build" / f"cache_array_bist_{variant}"
        if build.exists():
            shutil.rmtree(build)
        command = ["verilator", "--binary", "--sv", "--timing", "--assert", "-Wall",
                   "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
                   "--top-module", "tb_l1_dcache", "--Mdir", str(build),
                   f"-GCACHE_SECDED_ENABLE=1'h{secded}", *SOURCES]
        compiled = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        (ROOT / "reports" / f"cache_array_bist_{variant}_compile.log").write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            rows.append({"variant": variant, "status": "FAIL", "integrity_mode": variant})
            continue
        run = subprocess.run([str(build / "Vtb_l1_dcache"), "+TEST=cache_array_bist"],
                             cwd=ROOT, text=True, capture_output=True, timeout=120)
        log = run.stdout + run.stderr
        (ROOT / "reports" / f"cache_array_bist_{variant}.log").write_text(log)
        status = "PASS" if run.returncode == 0 and "status=PASS" in log else "FAIL"
        rows.append({"variant": variant, "status": status, "integrity_mode": variant})
        for point in re.findall(r"CACHE_BIST_COVER\|point=([^|]+)\|status=COVERED", log):
            coverage.setdefault(point, set()).add(variant)
    with (ROOT / "reports" / "cache_array_bist_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    required = ["parity_integrity_precheck", "secded_integrity_precheck", "first_failure_metadata",
                "destructive_array_scan", "clean_retest", "post_bist_cache_reuse"]
    with (ROOT / "reports" / "cache_array_bist_coverage.csv").open("w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["coverage_point", "status", "variants"])
        for point in required:
            writer.writerow([point, "COVERED" if point in coverage else "MISSING", ";".join(sorted(coverage.get(point, set())))])
    passed = all(row["status"] == "PASS" for row in rows) and all(point in coverage for point in required)
    print(f"CACHE_ARRAY_BIST|status={'PASS' if passed else 'FAIL'}|variants={sum(r['status'] == 'PASS' for r in rows)}/{len(rows)}|coverage={sum(p in coverage for p in required)}/{len(required)}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
