#!/usr/bin/env python3
"""Run optional coherence and SRAM-BIST design/verification demonstrations."""

from __future__ import annotations

import argparse
import csv
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

FEATURES = {
    "coherence": {
        "top": "tb_msi_two_cache",
        "sources": ["rtl/coherence/msi_two_cache_subsystem.sv", "sim/tb_msi_two_cache.sv"],
        "report": "coherence_summary.csv",
        "coverage": "coherence_coverage.csv",
        "required": 16,
    },
    "bist": {
        "top": "tb_cache_sram_bist",
        "sources": ["rtl/bist/cache_sram_bist.sv", "sim/tb_cache_sram_bist.sv"],
        "report": "bist_summary.csv",
        "coverage": "bist_coverage.csv",
        "required": 7,
    },
}


def run_feature(name: str) -> bool:
    cfg = FEATURES[name]
    build = ROOT / "build" / name
    if build.exists():
        shutil.rmtree(build)
    build.mkdir(parents=True)
    command = [
        "verilator", "--binary", "--timing", "--assert", "-Wall", "-Wno-fatal",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", cfg["top"],
        "--Mdir", str(build / "obj"), *[str(ROOT / source) for source in cfg["sources"]],
    ]
    compiled = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (build / "compile.log").write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(compiled.stderr)
        return False
    simulated = subprocess.run(
        [str(build / "obj" / f"V{cfg['top']}")], cwd=build,
        text=True, capture_output=True, timeout=120,
    )
    log = simulated.stdout + simulated.stderr
    (build / "simulation.log").write_text(log)
    checks = [match.groupdict() for match in re.finditer(
        r"CHECK\|name=(?P<name>[^|\n]+)\|status=(?P<status>PASS|FAIL)", log)]
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    with (reports / cfg["report"]).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["feature", "status"], lineterminator="\n")
        writer.writeheader()
        writer.writerows({"feature": row["name"], "status": row["status"]} for row in checks)
    with (reports / cfg["coverage"]).open("w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["coverage_point", "status", "source"])
        writer.writerows((row["name"], "COVERED" if row["status"] == "PASS" else "MISSING", cfg["top"])
                         for row in checks)
    passed = simulated.returncode == 0 and len(checks) == cfg["required"] and all(
        row["status"] == "PASS" for row in checks)
    print(f"{name.upper()}|status={'PASS' if passed else 'FAIL'}|checks={sum(r['status'] == 'PASS' for r in checks)}/{len(checks)}")
    return passed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("feature", choices=["coherence", "bist", "all"], nargs="?", default="all")
    args = parser.parse_args()
    selected = list(FEATURES) if args.feature == "all" else [args.feature]
    return 0 if all(run_feature(name) for name in selected) else 1


if __name__ == "__main__":
    raise SystemExit(main())
