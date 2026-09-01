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
    ("coherence_summary.csv", "status", "PASS", "Optional MSI coherence"),
    ("msi_random_summary.csv", "status", "PASS", "C++-modeled MSI random seeds"),
    ("msi_mutation_summary.csv", "status", "DETECTED", "MSI mutation detection"),
    ("bist_summary.csv", "status", "PASS", "SRAM BIST"),
    ("cache_array_bist_summary.csv", "status", "PASS", "Integrated cache-array BIST"),
    ("nonblocking_cache_summary.csv", "status", "PASS", "Optional non-blocking cache"),
    ("nonblocking_cache_coverage.csv", "status", "COVERED", "Non-blocking targeted coverage"),
    ("coherent_gcc_summary.csv", "status", "PASS", "Dual-RV32 GCC matrix"),
    ("coherent_rtl_litmus_summary.csv", "status", "PASS", "Executable RTL RVWMO litmus schedules"),
    ("coherent_herd_summary.csv", "status", "PASS", "Pinned herd7 litmus oracle"),
    ("coherent_random_summary.csv", "status", "PASS", "Coherent seeded workloads"),
    ("coherent_crossover_closure_summary.csv", "status", "PASS", "Focused crossover"),
    ("coherent_advanced_cross_coverage.csv", "status", "COVERED", "Transaction-correlated advanced crosses"),
    ("coherent_assertion_activation.csv", "status", "ACTIVATED", "Coherent assertion activation"),
    ("coherent_rtl_mutation_summary.csv", "status", "DETECTED", "Coherent RTL mutations"),
    ("coherent_error_reset_summary.csv", "status", "PASS", "Coherent error/reset scenarios"),
    ("coherent_qos_concurrency_summary.csv", "status", "PASS", "Coherent QoS/concurrency scenarios"),
    ("coherent_performance.csv", "status", "PASS", "Coherent measured RTL performance"),
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

coherent_functional = rows("coherent_functional_coverage.csv")
if any(row.get("evidence_class") != "executable_rtl" for row in coherent_functional):
    failures.append("coherent canonical functional coverage contains non-RTL evidence")
coherent_crosses = rows("coherent_cross_coverage.csv")
if any(row.get("evidence_class") != "same_window_executable_rtl" for row in coherent_crosses):
    failures.append("coherent canonical crosses contain non-RTL or inferred evidence")
coherent_code = {row["point_type"]: row for row in rows("coherent_code_coverage.csv")}
if float(coherent_code.get("line", {}).get("percent", 0)) < 90:
    failures.append("coherent integration line coverage is below 90%")
if float(coherent_code.get("branch", {}).get("percent", 0)) < 80:
    failures.append("coherent integration branch coverage is below 80%")
formal_scopes = {row.get("implementation_scope") for row in rows("coherent_formal_summary.csv")}
if not {"msi_implementation", "store_buffer_implementation", "reduced_architectural_model"} <= formal_scopes:
    failures.append("coherent formal evidence does not preserve implementation/model scope distinctions")
if any(row.get("prove_status") != "PASS" or row.get("cover_status") != "PASS"
       for row in rows("coherent_formal_summary.csv")):
    failures.append("coherent formal proof or reachability cover is not passing")
if any(row.get("evidence_class") != "transaction_correlated_executable_rtl"
       for row in rows("coherent_advanced_cross_coverage.csv")):
    failures.append("coherent advanced crosses contain inferred or non-transaction evidence")
if any(row.get("category") == "executable_and_worth_testing"
       for row in rows("coherent_code_coverage_holes.csv")):
    failures.append("coherent coverage review contains an unresolved executable hole")

if failures:
    for failure in failures:
        print(f"DOCS_ERROR|{failure}")
    raise SystemExit(1)
print(f"DOCS_CHECK|status=PASS|documents={len(documents)}|metrics={len(expected)}")
