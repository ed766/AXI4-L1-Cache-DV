#!/usr/bin/env python3
"""Combine direct, error/reset, and QoS evidence into one executable gate."""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"


def rows(name: str) -> list[dict[str, str]]:
    with (REPORTS / name).open() as handle:
        return list(csv.DictReader(handle))


def main() -> int:
    combined: list[dict[str, str]] = []
    for row in rows("coherent_directed_closure_summary.csv"):
        combined.append({
            "scenario": row["scenario"], "group": row["group"],
            "evidence_class": row["evidence_class"], "status": row["status"],
            "first_mismatch": row["first_mismatch"], "artifact": row["event_trace"],
        })
    for row in rows("coherent_error_reset_summary.csv"):
        combined.append({
            "scenario": row["scenario"], "group": "error_reset",
            "evidence_class": row["evidence_class"], "status": row["status"],
            "first_mismatch": row["first_mismatch"], "artifact": row["event_trace"],
        })
    core_qos = {"different_bank", "same_bank_equal", "mixed_qos", "starvation_override"}
    for row in rows("coherent_qos_concurrency_summary.csv"):
        if row["test"] not in core_qos:
            continue
        combined.append({
            "scenario": row["test"], "group": "qos_concurrency",
            "evidence_class": "executable_rtl_transport", "status": row["status"],
            "first_mismatch": row["first_mismatch"],
            "artifact": row["event_trace"],
        })
    expected = 34
    if len(combined) != expected:
        raise RuntimeError(f"closure matrix contains {len(combined)} rows, expected {expected}")
    report = REPORTS / "coherent_crossover_closure_summary.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=combined[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(combined)
    passed = sum(row["status"] == "PASS" for row in combined)
    print(f"COHERENT_CROSSOVER_CLOSURE|status={'PASS' if passed == expected else 'FAIL'}|passed={passed}/{expected}")
    return 0 if passed == expected else 1


if __name__ == "__main__":
    raise SystemExit(main())
