#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
bugs = [
    ("CACHE_BUG_DIRTY_SKIP", "dirty_evict"),
    ("CACHE_BUG_LRU_INVERT", "dirty_evict"),
    ("CACHE_BUG_REFILL_ERROR_IGNORE", "read_error"),
    ("CACHE_BUG_WLAST_EARLY", "dirty_evict"),
]
rows = []
for define, test in bugs:
    build = ROOT / "build" / "bugs" / define.lower()
    build.mkdir(parents=True, exist_ok=True)
    cmd = ["verilator", "--binary", "--sv", "--timing", "--assert", "-Wno-fatal",
           f"+define+{define}", "--top-module", "tb_l1_dcache", "--Mdir", str(build),
           str(ROOT / "rtl/dcache_pkg.sv"), str(ROOT / "rtl/l1_dcache_top.sv"),
           str(ROOT / "sim/assertions/dcache_protocol_assertions.sv"),
           str(ROOT / "sim/tb_l1_dcache.sv")]
    compiled = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    detected = False
    log = compiled.stdout + compiled.stderr
    if compiled.returncode == 0:
      executed = subprocess.run([str(build / "Vtb_l1_dcache"), f"+TEST={test}"],
                                cwd=ROOT, capture_output=True, text=True)
      log += executed.stdout + executed.stderr
      detected = executed.returncode != 0
    log_path = REPORTS / f"bug_{define.lower()}.log"
    log_path.write_text(log)
    rows.append({"bug": define, "test": test, "status": "DETECTED" if detected else "MISSED",
                 "log": str(log_path.relative_to(ROOT))})
with (REPORTS / "bug_validation.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys()); writer.writeheader(); writer.writerows(rows)
detected = sum(row["status"] == "DETECTED" for row in rows)
print(f"BUG_VALIDATION|detected={detected}|total={len(rows)}")
raise SystemExit(0 if detected == len(rows) else 1)
