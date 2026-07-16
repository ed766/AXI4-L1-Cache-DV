#!/usr/bin/env python3
"""Refresh the cache README snapshot from canonical reports."""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
START = "<!-- BEGIN GENERATED METRICS -->"
END = "<!-- END GENERATED METRICS -->"


def table(path: Path) -> list[dict[str, str]]:
    return list(csv.DictReader(path.open()))


def pair(path: str, field: str, passed: str) -> str:
    rows = table(ROOT / "reports" / path)
    return f"{sum(row.get(field) == passed for row in rows)} / {len(rows)}"


def main() -> int:
    coverage = table(ROOT / "reports" / "code_coverage_summary.csv")
    baseline = {row["point_type"]: row for row in coverage if row["coverage_group"] == "baseline_2way"}
    line = baseline["line"]
    branch = baseline["branch"]
    toggle = baseline["toggle"]
    values = (
        ("Directed scenarios", pair("regress_summary.csv", "status", "PASS")),
        ("Seeded stress", pair("stress_summary.csv", "status", "PASS")),
        ("C++ trace replay", pair("model_trace_summary.csv", "status", "PASS")),
        ("Functional coverage", pair("functional_coverage.csv", "status", "COVERED")),
        ("Interaction coverage", pair("cache_cross_coverage.csv", "status", "COVERED")),
        ("Mutation detection", pair("bug_validation.csv", "status", "DETECTED")),
        ("SECDED RAS coverage", pair("ras_coverage.csv", "status", "COVERED")),
        ("Raw baseline line coverage", f"{line['raw_hit']} / {line['raw_total']} ({line['raw_percent']}%)"),
        ("Reviewed baseline line coverage", f"{line['reviewed_hit']} / {line['reviewed_total']} ({line['reviewed_percent']}%); {line['excluded']} excluded"),
        ("Raw branch / toggle coverage", f"{branch['raw_percent']}% / {toggle['raw_percent']}%"),
    )
    block = [START, "| Evidence | Current result |", "| --- | ---: |"]
    block.extend(f"| {label} | `{value}` |" for label, value in values)
    block.append(END)
    text = README.read_text()
    if START not in text or END not in text:
        raise SystemExit("README generated-metrics markers are missing")
    prefix, rest = text.split(START, 1)
    _, suffix = rest.split(END, 1)
    README.write_text(prefix + "\n".join(block) + suffix)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
