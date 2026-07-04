#!/usr/bin/env python3
from __future__ import annotations
import argparse
import csv
import pathlib
import random

parser = argparse.ArgumentParser()
parser.add_argument("--count", type=int, default=100)
parser.add_argument("--seed", type=int, default=20260702)
parser.add_argument("--output", default="reports/stress_manifest.csv")
args = parser.parse_args()
rng = random.Random(args.seed)
families = ["cache_random", "dirty_eviction", "axi_backpressure", "reset_error"]
rows = []
for index in range(args.count):
    family = families[index % len(families)]
    rows.append({
        "scenario": index,
        "family": family,
        "seed": rng.randrange(1, 2**31),
        "operations": rng.choice([50, 100, 200]),
        "read_percent": rng.choice([25, 50, 75]),
        "conflict_percent": rng.choice([0, 25, 50, 75]),
        "backpressure_percent": rng.choice([0, 25, 50, 75]),
        "error_percent": rng.choice([0, 1, 5]) if family == "reset_error" else 0,
    })
output = pathlib.Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
    writer.writeheader(); writer.writerows(rows)
print(f"STRESS_MANIFEST|status=PASS|rows={len(rows)}|seed={args.seed}")

