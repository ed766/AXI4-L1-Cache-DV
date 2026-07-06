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
    ("regress_summary.csv", "status", "PASS", "Directed/random Verilator scenarios"),
    ("functional_coverage.csv", "status", "COVERED", "Functional coverage points"),
    ("stress_summary.csv", "status", "PASS", "Manifest-driven stress executions"),
    ("model_trace_summary.csv", "status", "PASS", "C++ trace-replay checks"),
    ("cache_cross_coverage.csv", "status", "COVERED", "Cache interaction cross coverage"),
    ("bug_validation.csv", "status", "DETECTED", "Compile-time bug mutations"),
    ("debug_waveform_summary.csv", "status", "DETECTED", "Waveform-backed debug cases"),
]
readme = README.read_text()
for report, key, passing, label in expected:
    report_rows = rows(report)
    value = f"`{sum(row[key] == passing for row in report_rows)} / {len(report_rows)}`"
    line = next((line for line in readme.splitlines() if label in line), "")
    if value not in line:
        failures.append(f"README metric {label!r} does not match {report}: expected {value}")

if failures:
    for failure in failures:
        print(f"DOCS_ERROR|{failure}")
    raise SystemExit(1)
print(f"DOCS_CHECK|status=PASS|documents={len(documents)}|metrics={len(expected)}")
