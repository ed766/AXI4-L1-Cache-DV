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
    coherent = (
        ("Dual-RV32 GCC matrix", pair("coherent_gcc_summary.csv", "status", "PASS")),
        ("Executable RTL RVWMO litmus schedules", pair("coherent_rtl_litmus_summary.csv", "status", "PASS")),
        ("Pinned herd7 litmus oracle", pair("coherent_herd_summary.csv", "status", "PASS")),
        ("Coherent seeded workloads", pair("coherent_random_summary.csv", "status", "PASS")),
        ("Coherent functional / cross coverage",
         f"{pair('coherent_functional_coverage.csv', 'status', 'COVERED')} / {pair('coherent_cross_coverage.csv', 'status', 'COVERED')}"),
        ("Focused crossover closure", pair("coherent_crossover_closure_summary.csv", "status", "PASS")),
        ("Transaction-correlated advanced crosses", pair("coherent_advanced_cross_coverage.csv", "status", "COVERED")),
        ("Coherent assertion activation", pair("coherent_assertion_activation.csv", "status", "ACTIVATED")),
        ("Coherent RTL mutations", pair("coherent_rtl_mutation_summary.csv", "status", "DETECTED")),
        ("Coherent formal proof/cover groups",
         f"{sum(row.get('prove_status') == 'PASS' and row.get('cover_status') == 'PASS' for row in table(ROOT / 'reports' / 'coherent_formal_summary.csv'))} / {len(table(ROOT / 'reports' / 'coherent_formal_summary.csv'))}"),
        ("Coherent error/reset scenarios", pair("coherent_error_reset_summary.csv", "status", "PASS")),
        ("Coherent QoS/concurrency scenarios", pair("coherent_qos_concurrency_summary.csv", "status", "PASS")),
        ("Coherent measured RTL performance", pair("coherent_performance.csv", "status", "PASS")),
        ("Coherent raw line / branch coverage",
         f"{next(row['percent'] for row in table(ROOT / 'reports' / 'coherent_code_coverage.csv') if row['point_type'] == 'line')}% / {next(row['percent'] for row in table(ROOT / 'reports' / 'coherent_code_coverage.csv') if row['point_type'] == 'branch')}%"),
        ("Coherent named integration assertions",
         next(row["value"] for row in table(ROOT / "reports" / "project_metrics.csv")
              if row["metric"] == "coherent_named_assertions")),
    ) if (ROOT / "reports" / "coherent_gcc_summary.csv").exists() else ()
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
        *coherent,
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
