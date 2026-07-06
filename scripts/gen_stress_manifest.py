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
address_profiles = ["uniform", "sequential", "hot-set", "same-set"]
strobe_profiles = ["full", "single-byte", "mixed"]
rows = []
for index in range(args.count):
    family = families[index % len(families)]
    operations = rng.choice([50, 100, 200])
    read_percent = rng.choice([25, 50, 75])
    conflict_percent = rng.choice([0, 25, 50, 75])
    backpressure_percent = rng.choice([0, 25, 50, 75])
    error_percent = rng.choice([0, 1, 5]) if family == "reset_error" else 0
    reset_operation = -1
    reset_phase = "idle"
    address_profile = rng.choice(address_profiles)
    if family == "dirty_eviction":
        read_percent = 25
        conflict_percent = 75
        address_profile = "same-set"
    if family == "axi_backpressure":
        backpressure_percent = rng.choice([25, 50, 75])
    if family == "reset_error":
        reset_operation = rng.randrange(10, operations - 9)
        reset_phase = rng.choice(["idle", "refill", "writeback"])
        if reset_phase == "writeback":
            read_percent = 25
            conflict_percent = 75
            address_profile = "same-set"
    rows.append({
        "scenario": index,
        "family": family,
        "seed": rng.randrange(1, 2**31),
        "operations": operations,
        "read_percent": read_percent,
        "conflict_percent": conflict_percent,
        "backpressure_percent": backpressure_percent,
        "error_percent": error_percent,
        "reset_operation": reset_operation,
        "reset_phase": reset_phase,
        "strobe_profile": rng.choice(strobe_profiles),
        "address_profile": address_profile,
        "address_base": "00004000",
        "address_span": "00010000",
    })
output = pathlib.Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
print(f"STRESS_MANIFEST|status=PASS|rows={len(rows)}|seed={args.seed}")
