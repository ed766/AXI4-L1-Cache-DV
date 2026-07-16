#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
documents = [README, *sorted((ROOT / "docs").glob("*.md"))]
failures: list[str] = []
link_pattern = re.compile(r"!?(?:\[[^]]*\])\(([^)]+)\)")

for document in documents:
    text = document.read_text()
    if "/home/" in text or "/mnt/c/" in text:
        failures.append(f"{document.relative_to(ROOT)} contains a machine-specific path")
    for target in link_pattern.findall(text):
        target = target.split("#", 1)[0]
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        resolved = (document.parent / target).resolve()
        if not resolved.exists():
            failures.append(f"{document.relative_to(ROOT)} has missing link {target}")

def rows(name: str) -> list[dict[str, str]]:
    with (ROOT / "reports" / name).open() as handle:
        return list(csv.DictReader(handle))

expected = [
    ("regress_summary.csv", "status", "PASS", "Directed scenarios"),
    ("functional_coverage.csv", "status", "COVERED", "Functional coverage"),
    ("stress_summary.csv", "status", "PASS", "Seeded stress"),
    ("model_trace_summary.csv", "status", "PASS", "C++ trace replay"),
    ("cache_cross_coverage.csv", "status", "COVERED", "Interaction coverage"),
    ("bug_validation.csv", "status", "DETECTED", "Mutation detection"),
    ("ras_coverage.csv", "status", "COVERED", "SECDED RAS coverage"),
]
readme = README.read_text()
for report, key, passing, label in expected:
    report_rows = rows(report)
    value = f"`{sum(row[key] == passing for row in report_rows)} / {len(report_rows)}`"
    line = next((line for line in readme.splitlines() if label in line), "")
    if value not in line:
        failures.append(f"README metric {label!r} does not match {report}: expected {value}")

if readme.count("<!-- BEGIN GENERATED METRICS -->") != 1 or readme.count("<!-- END GENERATED METRICS -->") != 1:
    failures.append("README must contain exactly one generated metric block")

coverage_rows = rows("code_coverage_summary.csv")
baseline = {row["point_type"]: row for row in coverage_rows if row["coverage_group"] == "baseline_2way"}
for point in ("line", "branch", "toggle"):
    if point not in baseline:
        failures.append(f"code coverage is missing baseline {point} row")
if "line" in baseline:
    raw = baseline["line"]
    expected_raw = f"`{raw['raw_hit']} / {raw['raw_total']} ({raw['raw_percent']}%)`"
    expected_reviewed = (f"`{raw['reviewed_hit']} / {raw['reviewed_total']} "
                         f"({raw['reviewed_percent']}%); {raw['excluded']} excluded`")
    if expected_raw not in readme:
        failures.append(f"README raw line coverage is stale: expected {expected_raw}")
    if expected_reviewed not in readme:
        failures.append(f"README reviewed line coverage is stale: expected {expected_reviewed}")

if failures:
    for failure in failures:
        print(f"DOCS_ERROR|{failure}")
    raise SystemExit(1)
print(f"DOCS_CHECK|status=PASS|documents={len(documents)}|metrics={len(expected)}")
