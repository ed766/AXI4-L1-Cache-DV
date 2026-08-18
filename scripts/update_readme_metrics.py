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
    two_way_edges = {row["point_type"]: row for row in coverage
                     if row["coverage_group"] == "baseline_plus_2way_edges"}
    edge_line = two_way_edges["line"]
    nb_perf = table(ROOT / "reports" / "nonblocking_cache_performance.csv")
    nb_windowed = next((row for row in nb_perf if row.get("mode") == "two_mshr_window"), None)
    nb_speedup = f"{nb_windowed['speedup']}x" if nb_windowed else "NA"
    values = (
        ("Directed scenarios", pair("regress_summary.csv", "status", "PASS")),
        ("Seeded stress", pair("stress_summary.csv", "status", "PASS")),
        ("C++ trace replay", pair("model_trace_summary.csv", "status", "PASS")),
        ("Functional coverage", pair("functional_coverage.csv", "status", "COVERED")),
        ("Interaction coverage", pair("cache_cross_coverage.csv", "status", "COVERED")),
        ("Mutation detection", pair("bug_validation.csv", "status", "DETECTED")),
        ("SECDED RAS coverage", pair("ras_coverage.csv", "status", "COVERED")),
        ("Optional MSI coherence", pair("coherence_summary.csv", "status", "PASS")),
        ("C++-modeled MSI random seeds", pair("msi_random_summary.csv", "status", "PASS")),
        ("MSI mutation detection", pair("msi_mutation_summary.csv", "status", "DETECTED")),
        ("SRAM BIST", pair("bist_summary.csv", "status", "PASS")),
        ("Integrated cache-array BIST", pair("cache_array_bist_summary.csv", "status", "PASS")),
        ("Optional non-blocking cache", pair("nonblocking_cache_summary.csv", "status", "PASS")),
        ("Non-blocking targeted coverage", pair("nonblocking_cache_coverage.csv", "status", "COVERED")),
        ("Two-MSHR request-window speedup", nb_speedup),
        ("Raw baseline line coverage", f"{line['raw_hit']} / {line['raw_total']} ({line['raw_percent']}%)"),
        ("Reviewed baseline line coverage", f"{line['reviewed_hit']} / {line['reviewed_total']} ({line['reviewed_percent']}%); {line['excluded']} excluded"),
        ("2-way baseline + edge line coverage", f"raw {edge_line['raw_hit']} / {edge_line['raw_total']} ({edge_line['raw_percent']}%); reviewed {edge_line['reviewed_hit']} / {edge_line['reviewed_total']} ({edge_line['reviewed_percent']}%); {edge_line['excluded']} excluded"),
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
