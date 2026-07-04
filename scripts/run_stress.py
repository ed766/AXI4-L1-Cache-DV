#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
binary = ROOT / "build" / "verilator" / "Vtb_l1_dcache"
manifest = list(csv.DictReader((ROOT / "reports" / "stress_manifest.csv").open()))
if not binary.is_file():
    raise SystemExit("Regression binary missing; run make regress first")

rows = []
for row in manifest:
    family = row["family"]
    if family == "cache_random":
        test = "random"
    elif family == "dirty_eviction":
        test = "dirty_evict"
    elif family == "axi_backpressure":
        test = "backpressure"
    else:
        test = "read_error" if int(row["scenario"]) % 2 else "write_error"
    args = [str(binary), f"+TEST={test}", f"+verilator+seed+{row['seed']}"]
    if family == "axi_backpressure":
        duty = int(row["backpressure_percent"])
        args.append(f"+STALL_MOD={max(2, 100 // max(duty, 25))}")
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    rows.append({**row, "mapped_test": test,
                 "status": "PASS" if result.returncode == 0 else "FAIL"})

output = ROOT / "reports" / "stress_summary.csv"
with output.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader(); writer.writerows(rows)
passed = sum(row["status"] == "PASS" for row in rows)
print(f"STRESS_RESULT|passed={passed}|total={len(rows)}")
raise SystemExit(0 if passed == len(rows) else 1)

