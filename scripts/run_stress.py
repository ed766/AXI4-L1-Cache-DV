#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
binary = ROOT / "build" / "verilator" / "Vtb_l1_dcache"
manifest = list(csv.DictReader((ROOT / "reports" / "stress_manifest.csv").open()))
if not binary.is_file():
    raise SystemExit("Regression binary missing; run make regress first")

rows = []
for row in manifest:
    operations = int(row["operations"])
    reset_operation = int(row["reset_operation"])
    if operations not in (50, 100, 200):
        raise SystemExit(f"scenario {row['scenario']}: invalid operation count")
    for key, legal in (("read_percent", (25, 50, 75)),
                       ("conflict_percent", (0, 25, 50, 75)),
                       ("backpressure_percent", (0, 25, 50, 75)),
                       ("error_percent", (0, 1, 5))):
        if int(row[key]) not in legal:
            raise SystemExit(f"scenario {row['scenario']}: invalid {key}")
    if reset_operation >= operations or (reset_operation >= 0 and reset_operation < 10):
        raise SystemExit(f"scenario {row['scenario']}: invalid reset operation")
    if row["reset_phase"] == "writeback" and int(row["conflict_percent"]) < 50:
        raise SystemExit(f"scenario {row['scenario']}: writeback reset lacks conflict traffic")

    trace_dir = ROOT / "build" / "verilator" / "traces"
    trace_dir.mkdir(parents=True, exist_ok=True)
    trace = trace_dir / f"stress_{int(row['scenario']):03d}.csv"
    args = [str(binary), "+TEST=random", "+MODEL_FINAL_FLUSH",
            f"+verilator+seed+{row['seed']}",
            f"+SEED={row['seed']}", f"+OPS={row['operations']}",
            f"+READ_PCT={row['read_percent']}",
            f"+CONFLICT_PCT={row['conflict_percent']}",
            f"+BP_PCT={row['backpressure_percent']}",
            f"+ERROR_PCT={row['error_percent']}",
            f"+RESET_OP={row['reset_operation']}",
            f"+RESET_PHASE={row['reset_phase']}",
            f"+STROBE_PROFILE={row['strobe_profile']}",
            f"+ADDR_PROFILE={row['address_profile']}",
            f"+ADDR_BASE={row['address_base']}",
            f"+ADDR_SPAN={row['address_span']}", f"+TRACE_FILE={trace}"]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    match = re.search(r"RANDOM_RESULT\|(.*)", output)
    realized = {}
    if match:
        realized = {f"realized_{key}": value for key, value in
                    (item.split("=", 1) for item in match.group(1).split("|") if "=" in item)}
    rows.append({**row, **realized, "mapped_test": "random", "trace": str(trace.relative_to(ROOT)),
                 "status": "PASS" if result.returncode == 0 and match else "FAIL"})

output = ROOT / "reports" / "stress_summary.csv"
with output.open("w", newline="") as handle:
    fieldnames = list(dict.fromkeys(key for item in rows for key in item.keys()))
    writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
passed = sum(row["status"] == "PASS" for row in rows)
print(f"STRESS_RESULT|passed={passed}|total={len(rows)}")
raise SystemExit(0 if passed == len(rows) else 1)
