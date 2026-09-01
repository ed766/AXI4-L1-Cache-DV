#!/usr/bin/env python3
"""Require every uncovered coherent source point to have a reviewed disposition."""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"


def main() -> int:
    with (REPORTS / "coherent_code_coverage_holes.csv").open() as handle:
        rows = list(csv.DictReader(handle))
    unresolved = [row for row in rows if row["category"] == "executable_and_worth_testing"]
    categories = Counter(row["category"] for row in rows)
    markdown = [
        "# Coherent Coverage Hole Review", "",
        "Raw line, branch, and toggle values remain unchanged. This review classifies uncovered "
        "source points without removing them from the denominator.", "",
        "| Category | Points |", "| --- | ---: |",
    ]
    markdown.extend(f"| {category} | {count} |" for category, count in sorted(categories.items()))
    markdown.extend(["", "| Type | RTL file | Line | Category | Rationale |",
                     "| --- | --- | ---: | --- | --- |"])
    markdown.extend(
        f"| {row['point_type']} | `{row['rtl_file']}` | {row['line']} | {row['category']} | {row['review_rationale']} |"
        for row in rows
    )
    (REPORTS / "coherent_coverage_hole_review.md").write_text("\n".join(markdown) + "\n")
    print(f"COHERENT_COVERAGE_REVIEW|status={'PASS' if not unresolved else 'FAIL'}|reviewed={len(rows)-len(unresolved)}/{len(rows)}|unresolved={len(unresolved)}")
    return 0 if not unresolved else 1


if __name__ == "__main__":
    raise SystemExit(main())
