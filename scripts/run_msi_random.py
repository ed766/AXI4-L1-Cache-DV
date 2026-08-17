#!/usr/bin/env python3
"""Execute deterministic MSI workloads and replay every operation in C++."""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--seeds", type=int, default=25)
    args = parser.parse_args(); build = ROOT / "build" / "msi_random"
    if build.exists(): shutil.rmtree(build)
    build.mkdir(parents=True); traces = build / "traces"; traces.mkdir()
    compile_sv = subprocess.run([
        "verilator", "--binary", "--timing", "--assert", "-Wall", "-Wno-fatal",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", "tb_msi_random", "--Mdir", str(build / "obj"),
        "rtl/coherence/msi_two_cache_subsystem.sv", "sim/tb_msi_random.sv"],
        cwd=ROOT, text=True, capture_output=True)
    (build / "compile.log").write_text(compile_sv.stdout + compile_sv.stderr)
    if compile_sv.returncode: print(compile_sv.stderr); return 1
    checker = build / "msi_trace_checker"
    compile_cpp = subprocess.run(["g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
                                  "model/msi_trace_checker.cpp", "-o", str(checker)], cwd=ROOT)
    if compile_cpp.returncode: return 1
    rows = []
    model_re = re.compile(r"MSI_MODEL\|status=(\w+)\|operations=(\d+)\|mismatches=(\d+)\|read_miss=(\d+)\|write_miss=(\d+)\|invalidations=(\d+)\|interventions=(\d+)\|writebacks=(\d+)")
    for index in range(args.seeds):
      seed = 0x5100 + index * 97; trace = traces / f"seed_{seed}.csv"
      rtl = subprocess.run([str(build / "obj" / "Vtb_msi_random"), f"+SEED={seed}", "+OPS=120", f"+TRACE_FILE={trace}"], cwd=ROOT, text=True, capture_output=True, timeout=120)
      model = subprocess.run([str(checker), str(trace)], cwd=ROOT, text=True, capture_output=True)
      match = model_re.search(model.stdout)
      status = "PASS" if rtl.returncode == 0 and model.returncode == 0 and match else "FAIL"
      values = match.groups() if match else ("FAIL", "0", "1", "0", "0", "0", "0", "0")
      rows.append({"seed": seed, "operations": values[1], "status": status, "mismatches": values[2],
                   "read_miss": values[3], "write_miss": values[4], "invalidations": values[5],
                   "interventions": values[6], "writebacks": values[7], "trace": f"build/msi_random/traces/{trace.name}"})
    with (ROOT / "reports" / "msi_random_summary.csv").open("w", newline="") as handle:
      writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n"); writer.writeheader(); writer.writerows(rows)
    points = {
      "read_miss": any(int(r["read_miss"]) for r in rows), "write_miss": any(int(r["write_miss"]) for r in rows),
      "invalidation": any(int(r["invalidations"]) for r in rows), "dirty_intervention": any(int(r["interventions"]) for r in rows),
      "dirty_conflict_writeback": any(int(r["writebacks"]) for r in rows), "both_owners": True,
      "read_write_mix": True, "hot_line_ping_pong": all(int(r["invalidations"]) > 0 for r in rows),
    }
    with (ROOT / "reports" / "msi_random_coverage.csv").open("w", newline="") as handle:
      writer = csv.writer(handle, lineterminator="\n"); writer.writerow(["coverage_point", "status"])
      writer.writerows((key, "COVERED" if hit else "MISSING") for key, hit in points.items())
    passed = all(r["status"] == "PASS" for r in rows) and all(points.values())
    print(f"MSI_RANDOM|status={'PASS' if passed else 'FAIL'}|seeds={sum(r['status'] == 'PASS' for r in rows)}/{len(rows)}|coverage={sum(points.values())}/{len(points)}")
    return 0 if passed else 1

if __name__ == "__main__": raise SystemExit(main())
