#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
summary = ROOT / "reports" / "regress_summary.csv"
rows = list(csv.DictReader(summary.open())) if summary.exists() else []
passed = sum(row.get("status") == "PASS" for row in rows)
totals = {key: sum(int(row.get(key, 0) or 0) for row in rows)
          for key in ("requests", "responses", "hits", "misses", "evictions", "errors")}
hit_total = totals["hits"] + totals["misses"]
hit_rate = 100.0 * totals["hits"] / hit_total if hit_total else 0.0
coverage_rows = list(csv.DictReader((ROOT / "reports" / "functional_coverage.csv").open()))
coverage_hit = sum(row["status"] == "COVERED" for row in coverage_rows)
bug_path = ROOT / "reports" / "bug_validation.csv"
bug_rows = list(csv.DictReader(bug_path.open())) if bug_path.exists() else []
bugs_hit = sum(row["status"] == "DETECTED" for row in bug_rows)
codecov_path = ROOT / "reports" / "code_coverage_summary.csv"
codecov_rows = list(csv.DictReader(codecov_path.open())) if codecov_path.exists() else []
if codecov_rows and "coverage_group" in codecov_rows[0]:
    primary_codecov_rows = [row for row in codecov_rows if row.get("coverage_group") == "baseline_2way"]
    if not primary_codecov_rows:
        primary_codecov_rows = [row for row in codecov_rows if row.get("coverage_group") == "combined_all_available"]
else:
    primary_codecov_rows = codecov_rows
codecov = {row["point_type"]: row for row in primary_codecov_rows}
edge_codecov_rows = [row for row in codecov_rows
                     if row.get("coverage_group") == "baseline_plus_2way_edges"]
edge_codecov = {row["point_type"]: row for row in edge_codecov_rows}
rtl_line_pct = float(codecov.get("line", {}).get("raw_percent", 0) or 0)
rtl_line_reviewed_pct = float(codecov.get("line", {}).get("reviewed_percent", 0) or 0)
rtl_branch_pct = float(codecov.get("branch", {}).get("raw_percent", 0) or 0)
rtl_toggle_pct = float(codecov.get("toggle", {}).get("raw_percent", 0) or 0)
line_raw_pair = f"{codecov.get('line', {}).get('raw_hit', '0')} / {codecov.get('line', {}).get('raw_total', '0')}"
line_reviewed_pair = f"{codecov.get('line', {}).get('reviewed_hit', '0')} / {codecov.get('line', {}).get('reviewed_total', '0')}"
line_excluded = codecov.get("line", {}).get("excluded", "0")
edge_line_pct = float(edge_codecov.get("line", {}).get("raw_percent", 0) or 0)
edge_path = ROOT / "reports" / "coverage_edges_summary.csv"
edge_rows = list(csv.DictReader(edge_path.open())) if edge_path.exists() else []
edge_pass = sum(row.get("status") == "PASS" for row in edge_rows)
stress_path = ROOT / "reports" / "stress_summary.csv"
stress_rows = list(csv.DictReader(stress_path.open())) if stress_path.exists() else []
stress_pass = sum(row["status"] == "PASS" for row in stress_rows)
model_path = ROOT / "reports" / "model_trace_summary.csv"
model_rows = list(csv.DictReader(model_path.open())) if model_path.exists() else []
model_pass = sum(row["status"] == "PASS" for row in model_rows)
cross_path = ROOT / "reports" / "cache_cross_coverage.csv"
cross_rows = list(csv.DictReader(cross_path.open())) if cross_path.exists() else []
cross_hit = sum(row["status"] == "COVERED" for row in cross_rows)
debug_path = ROOT / "reports" / "debug_waveform_summary.csv"
debug_rows = list(csv.DictReader(debug_path.open())) if debug_path.exists() else []
debug_hit = sum(row["status"] == "DETECTED" for row in debug_rows)
formal_path = ROOT / "reports" / "formal_proof_summary.csv"
formal_rows = list(csv.DictReader(formal_path.open())) if formal_path.exists() else []
formal_hit = sum(row.get("meets_expectation", "").lower() == "true" for row in formal_rows)
formal_small_path = ROOT / "reports" / "formal_small_proof_summary.csv"
formal_small_rows = list(csv.DictReader(formal_small_path.open())) if formal_small_path.exists() else []
formal_small_hit = sum(row.get("meets_expectation", "").lower() == "true" for row in formal_small_rows)
formal_small_result = (f"{formal_small_hit} / {len(formal_small_rows)}"
                       if formal_small_rows else "SKIP (sby unavailable locally)")
assoc_path = ROOT / "reports" / "associativity_check.csv"
assoc_rows = list(csv.DictReader(assoc_path.open())) if assoc_path.exists() else []
assoc_hit = sum(row.get("status") == "PASS" for row in assoc_rows)
assoc_char_path = ROOT / "reports" / "associativity_characterization.csv"
assoc_char_rows = list(csv.DictReader(assoc_char_path.open())) if assoc_char_path.exists() else []
synth_path = ROOT / "reports" / "synthesis_characterization.csv"
synth_rows = list(csv.DictReader(synth_path.open())) if synth_path.exists() else []
synth_pass = sum(row.get("status") == "PASS" for row in synth_rows)
synth_skip = sum(row.get("status") == "SKIP" for row in synth_rows)
synth_result = (f"{synth_pass} / {len(synth_rows)}"
                if synth_rows and synth_skip != len(synth_rows)
                else "SKIP (Yosys unavailable locally)")
uvm_path = ROOT / "reports" / "uvm_runtime_summary.csv"
uvm_rows = list(csv.DictReader(uvm_path.open())) if uvm_path.exists() else []
uvm_hit = sum(row.get("status") == "PASS" for row in uvm_rows)
uvm_skip = sum(row.get("status") == "SKIP" for row in uvm_rows)
uvm_result = (f"{uvm_hit} PASS / {uvm_skip} SKIP / {len(uvm_rows)} total"
              if uvm_rows else "NA")
ras_path = ROOT / "reports" / "ras_summary.csv"
ras_rows = list(csv.DictReader(ras_path.open())) if ras_path.exists() else []
ras_pass = sum(row.get("status") == "PASS" for row in ras_rows)
ras_cov_path = ROOT / "reports" / "ras_coverage.csv"
ras_cov_rows = list(csv.DictReader(ras_cov_path.open())) if ras_cov_path.exists() else []
ras_cov = sum(row.get("status") == "COVERED" for row in ras_cov_rows)
coherence_path = ROOT / "reports" / "coherence_summary.csv"
coherence_rows = list(csv.DictReader(coherence_path.open())) if coherence_path.exists() else []
coherence_pass = sum(row.get("status") == "PASS" for row in coherence_rows)
bist_path = ROOT / "reports" / "bist_summary.csv"
bist_rows = list(csv.DictReader(bist_path.open())) if bist_path.exists() else []
bist_pass = sum(row.get("status") == "PASS" for row in bist_rows)
msi_random_path = ROOT / "reports" / "msi_random_summary.csv"
msi_random_rows = list(csv.DictReader(msi_random_path.open())) if msi_random_path.exists() else []
msi_random_pass = sum(row.get("status") == "PASS" for row in msi_random_rows)
msi_mutation_path = ROOT / "reports" / "msi_mutation_summary.csv"
msi_mutation_rows = list(csv.DictReader(msi_mutation_path.open())) if msi_mutation_path.exists() else []
msi_mutation_pass = sum(row.get("status") == "DETECTED" for row in msi_mutation_rows)
array_bist_path = ROOT / "reports" / "cache_array_bist_summary.csv"
array_bist_rows = list(csv.DictReader(array_bist_path.open())) if array_bist_path.exists() else []
array_bist_pass = sum(row.get("status") == "PASS" for row in array_bist_rows)
nb_path = ROOT / "reports" / "nonblocking_cache_summary.csv"
nb_rows = list(csv.DictReader(nb_path.open())) if nb_path.exists() else []
nb_pass = sum(row.get("status") == "PASS" for row in nb_rows)
nb_cov_path = ROOT / "reports" / "nonblocking_cache_coverage.csv"
nb_cov_rows = list(csv.DictReader(nb_cov_path.open())) if nb_cov_path.exists() else []
nb_cov = sum(row.get("status") == "COVERED" for row in nb_cov_rows)
nb_perf_path = ROOT / "reports" / "nonblocking_cache_performance.csv"
nb_perf_rows = list(csv.DictReader(nb_perf_path.open())) if nb_perf_path.exists() else []
nb_windowed = next((row for row in nb_perf_rows if row.get("mode") == "two_mshr_window"), None)
nb_speedup = f"{nb_windowed['speedup']}x" if nb_windowed else "NA"
coh_gcc_path = ROOT / "reports" / "coherent_gcc_summary.csv"
coh_gcc_rows = list(csv.DictReader(coh_gcc_path.open())) if coh_gcc_path.exists() else []
coh_gcc_pass = sum(row.get("status") == "PASS" for row in coh_gcc_rows)
coh_litmus_path = ROOT / "reports" / "coherent_rtl_litmus_summary.csv"
coh_litmus_rows = list(csv.DictReader(coh_litmus_path.open())) if coh_litmus_path.exists() else []
coh_litmus_pass = sum(row.get("status") == "PASS" for row in coh_litmus_rows)
coh_herd_path = ROOT / "reports" / "coherent_herd_summary.csv"
coh_herd_rows = list(csv.DictReader(coh_herd_path.open())) if coh_herd_path.exists() else []
coh_herd_pass = sum(row.get("status") == "PASS" for row in coh_herd_rows)
coh_random_path = ROOT / "reports" / "coherent_random_summary.csv"
coh_random_rows = list(csv.DictReader(coh_random_path.open())) if coh_random_path.exists() else []
coh_random_pass = sum(row.get("status") == "PASS" for row in coh_random_rows)
coh_func_path = ROOT / "reports" / "coherent_functional_coverage.csv"
coh_func_rows = list(csv.DictReader(coh_func_path.open())) if coh_func_path.exists() else []
coh_func_hit = sum(row.get("status") == "COVERED" for row in coh_func_rows)
coh_cross_path = ROOT / "reports" / "coherent_cross_coverage.csv"
coh_cross_rows = list(csv.DictReader(coh_cross_path.open())) if coh_cross_path.exists() else []
coh_cross_hit = sum(row.get("status") == "COVERED" for row in coh_cross_rows)
coh_advanced_path = ROOT / "reports" / "coherent_advanced_cross_coverage.csv"
coh_advanced_rows = list(csv.DictReader(coh_advanced_path.open())) if coh_advanced_path.exists() else []
coh_advanced_hit = sum(row.get("status") == "COVERED" for row in coh_advanced_rows)
coh_closure_path = ROOT / "reports" / "coherent_crossover_closure_summary.csv"
coh_closure_rows = list(csv.DictReader(coh_closure_path.open())) if coh_closure_path.exists() else []
coh_closure_hit = sum(row.get("status") == "PASS" for row in coh_closure_rows)
coh_activation_path = ROOT / "reports" / "coherent_assertion_activation.csv"
coh_activation_rows = list(csv.DictReader(coh_activation_path.open())) if coh_activation_path.exists() else []
coh_activation_hit = sum(row.get("status") == "ACTIVATED" for row in coh_activation_rows)
coh_mut_path = ROOT / "reports" / "coherent_rtl_mutation_summary.csv"
coh_mut_rows = list(csv.DictReader(coh_mut_path.open())) if coh_mut_path.exists() else []
coh_mut_hit = sum(row.get("status") == "DETECTED" for row in coh_mut_rows)
coh_formal_path = ROOT / "reports" / "coherent_formal_summary.csv"
coh_formal_rows = list(csv.DictReader(coh_formal_path.open())) if coh_formal_path.exists() else []
coh_formal_hit = sum(row.get("prove_status") == "PASS" and row.get("cover_status") == "PASS"
                     for row in coh_formal_rows)
coh_ref_path = ROOT / "reports" / "coherent_reference_summary.csv"
coh_ref_rows = list(csv.DictReader(coh_ref_path.open())) if coh_ref_path.exists() else []
coh_ref_hit = sum(row.get("status") == "PASS" for row in coh_ref_rows)
coh_error_path = ROOT / "reports" / "coherent_error_reset_summary.csv"
coh_error_rows = list(csv.DictReader(coh_error_path.open())) if coh_error_path.exists() else []
coh_error_hit = sum(row.get("status") == "PASS" for row in coh_error_rows)
coh_qos_path = ROOT / "reports" / "coherent_qos_concurrency_summary.csv"
coh_qos_rows = list(csv.DictReader(coh_qos_path.open())) if coh_qos_path.exists() else []
coh_qos_hit = sum(row.get("status") == "PASS" for row in coh_qos_rows)
coh_perf_path = ROOT / "reports" / "coherent_performance.csv"
coh_perf_rows = list(csv.DictReader(coh_perf_path.open())) if coh_perf_path.exists() else []
coh_perf_hit = sum(row.get("status") == "PASS" for row in coh_perf_rows)
coh_codecov_path = ROOT / "reports" / "coherent_code_coverage.csv"
coh_codecov_rows = list(csv.DictReader(coh_codecov_path.open())) if coh_codecov_path.exists() else []
coh_codecov = {row.get("point_type"): row.get("percent", "NA") for row in coh_codecov_rows}
assertion_text = (ROOT / "sim" / "assertions" / "dcache_protocol_assertions.sv").read_text()
assertion_count = len(set(re.findall(r"\b(a_[a-zA-Z0-9_]+)\s*:", assertion_text)))
coherent_assertion_text = "\n".join(
    path.read_text() for path in (ROOT / "integration" / "rv32_coherent" / "rtl").glob("*.sv")
)
coherent_assertion_count = len(set(re.findall(r"\b(a_[a-zA-Z0-9_]+)\s*:", coherent_assertion_text)))
machine_metrics = [
    ("directed_regression", f"{passed} / {len(rows)}"),
    ("functional_coverage", f"{coverage_hit} / {len(coverage_rows)}"),
    ("seeded_stress", f"{stress_pass} / {len(stress_rows)}"),
    ("trace_replay", f"{model_pass} / {len(model_rows)}"),
    ("interaction_coverage", f"{cross_hit} / {len(cross_rows)}"),
    ("mutation_detection", f"{bugs_hit} / {len(bug_rows)}"),
    ("secded_ras_coverage", f"{ras_cov} / {len(ras_cov_rows)}"),
    ("optional_msi_coherence", f"{coherence_pass} / {len(coherence_rows)}"),
    ("msi_model_random", f"{msi_random_pass} / {len(msi_random_rows)}"),
    ("msi_mutations", f"{msi_mutation_pass} / {len(msi_mutation_rows)}"),
    ("sram_bist", f"{bist_pass} / {len(bist_rows)}"),
    ("integrated_cache_array_bist", f"{array_bist_pass} / {len(array_bist_rows)}"),
    ("optional_nonblocking_cache", f"{nb_pass} / {len(nb_rows)}"),
    ("nonblocking_targeted_coverage", f"{nb_cov} / {len(nb_cov_rows)}"),
    ("nonblocking_window_speedup", nb_speedup),
    ("dual_rv32_gcc_matrix", f"{coh_gcc_pass} / {len(coh_gcc_rows)}"),
    ("rvwmo_litmus_schedules", f"{coh_litmus_pass} / {len(coh_litmus_rows)}"),
    ("pinned_herd7_litmus_oracle", f"{coh_herd_pass} / {len(coh_herd_rows)}"),
    ("coherent_seeded_workloads", f"{coh_random_pass} / {len(coh_random_rows)}"),
    ("coherent_functional_coverage", f"{coh_func_hit} / {len(coh_func_rows)}"),
    ("coherent_cross_coverage", f"{coh_cross_hit} / {len(coh_cross_rows)}"),
    ("coherent_crossover_closure", f"{coh_closure_hit} / {len(coh_closure_rows)}"),
    ("coherent_advanced_cross_coverage", f"{coh_advanced_hit} / {len(coh_advanced_rows)}"),
    ("coherent_assertion_activation", f"{coh_activation_hit} / {len(coh_activation_rows)}"),
    ("coherent_mutations", f"{coh_mut_hit} / {len(coh_mut_rows)}"),
    ("coherent_formal_groups", f"{coh_formal_hit} / {len(coh_formal_rows)}"),
    ("coherent_error_reset", f"{coh_error_hit} / {len(coh_error_rows)}"),
    ("coherent_qos_concurrency", f"{coh_qos_hit} / {len(coh_qos_rows)}"),
    ("coherent_rtl_performance_rows", f"{coh_perf_hit} / {len(coh_perf_rows)}"),
    ("coherent_rtl_line_branch_coverage", f"{coh_codecov.get('line', 'NA')}% / {coh_codecov.get('branch', 'NA')}%"),
    ("coherent_named_assertions", str(coherent_assertion_count)),
    ("coherent_reference_checks", f"{coh_ref_hit} / {len(coh_ref_rows)}"),
    ("raw_baseline_line_coverage", f"{rtl_line_pct:.2f}%"),
    ("reviewed_baseline_line_coverage", f"{rtl_line_reviewed_pct:.2f}%"),
    ("raw_2way_execution_union_line_coverage", f"{edge_line_pct:.2f}%"),
    ("raw_baseline_branch_coverage", f"{rtl_branch_pct:.2f}%"),
    ("raw_baseline_toggle_coverage", f"{rtl_toggle_pct:.2f}%"),
]
with (ROOT / "reports" / "project_metrics.csv").open("w", newline="") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow(["metric", "value"])
    writer.writerows(machine_metrics)
text = f"""# Project Metrics

Generated from `reports/regress_summary.csv`. These are behavioral Verilator results, not silicon-signoff metrics.

| Metric | Current result |
| --- | ---: |
| Directed/random scenarios | {passed} / {len(rows)} |
| Accepted CPU requests | {totals['requests']} |
| CPU responses | {totals['responses']} |
| Observed cache hits | {totals['hits']} |
| Observed cache misses | {totals['misses']} |
| Observed dirty evictions | {totals['evictions']} |
| Expected error responses | {totals['errors']} |
| Aggregate observed hit rate | {hit_rate:.1f}% |
| Functional coverage | {coverage_hit} / {len(coverage_rows)} |
| Implemented bug mutations detected | {bugs_hit} / {len(bug_rows)} |
| Optional seeded stress scenarios | {stress_pass} / {len(stress_rows)} |
| C++ trace-replay checks | {model_pass} / {len(model_rows)} |
| Cache interaction cross coverage | {cross_hit} / {len(cross_rows)} |
| Waveform-backed debug cases | {debug_hit} / {len(debug_rows)} |
| Solver-backed formal tasks meeting expectation | {formal_hit} / {len(formal_rows)} |
| Small-geometry formal tasks meeting expectation | {formal_small_result} |
| Equal-capacity associativity directed checks | {assoc_hit} / {len(assoc_rows)} |
| Associativity characterization points | {len(assoc_char_rows)} |
| Synthesis proxy variants | {synth_result} |
| UVM runtime smoke collateral | {uvm_result} |
| Optional SECDED RAS matrix | {ras_pass} / {len(ras_rows)} |
| SECDED RAS coverage | {ras_cov} / {len(ras_cov_rows)} |
| Optional two-cache MSI checks | {coherence_pass} / {len(coherence_rows)} |
| C++-modeled randomized MSI seeds | {msi_random_pass} / {len(msi_random_rows)} |
| MSI mutations detected | {msi_mutation_pass} / {len(msi_mutation_rows)} |
| SRAM March C-minus BIST checks | {bist_pass} / {len(bist_rows)} |
| Integrated parity/SECDED cache-array BIST | {array_bist_pass} / {len(array_bist_rows)} |
| Optional non-blocking cache scenarios | {nb_pass} / {len(nb_rows)} |
| Non-blocking targeted coverage | {nb_cov} / {len(nb_cov_rows)} |
| Two-entry request-window speedup | {nb_speedup} |
| Dual-RV32 GCC workload/optimizer matrix | {coh_gcc_pass} / {len(coh_gcc_rows)} |
| RVWMO litmus schedules without forbidden outcomes | {coh_litmus_pass} / {len(coh_litmus_rows)} |
| Pinned herd7 external litmus queries | {coh_herd_pass} / {len(coh_herd_rows)} |
| Seeded coherent shared-memory workloads | {coh_random_pass} / {len(coh_random_rows)} |
| Coherent functional / same-window cross coverage | {coh_func_hit} / {len(coh_func_rows)}; {coh_cross_hit} / {len(coh_cross_rows)} |
| Focused executable crossover closure | {coh_closure_hit} / {len(coh_closure_rows)} |
| Transaction-correlated advanced crosses | {coh_advanced_hit} / {len(coh_advanced_rows)} |
| Coherent assertion/invariant activation | {coh_activation_hit} / {len(coh_activation_rows)} |
| Coherent expected-fail mutations detected | {coh_mut_hit} / {len(coh_mut_rows)} |
| Coherent solver-backed bounded proof/cover groups | {coh_formal_hit} / {len(coh_formal_rows)} |
| Coherent error/reset scenarios | {coh_error_hit} / {len(coh_error_rows)} |
| Coherent QoS/concurrency scenarios | {coh_qos_hit} / {len(coh_qos_rows)} |
| Coherent measured RTL performance rows | {coh_perf_hit} / {len(coh_perf_rows)} |
| Coherent RTL raw line / branch coverage | {coh_codecov.get('line', 'NA')}% / {coh_codecov.get('branch', 'NA')}% |
| Coherent named integration assertions | {coherent_assertion_count} |
| Coherent reference/oracle execution rows | {coh_ref_hit} / {len(coh_ref_rows)} |
| Named protocol/architecture assertions | {assertion_count} |
| Optional coverage-edge scenarios | {edge_pass} / {len(edge_rows)} |
| Design RTL raw line coverage proxy | {line_raw_pair} ({rtl_line_pct:.2f}%) |
| Design RTL reviewed line coverage proxy | {line_reviewed_pair} ({rtl_line_reviewed_pct:.2f}%); {line_excluded} excluded |
| Design RTL raw 2-way baseline + edge line coverage | {edge_codecov.get('line', {}).get('raw_hit', '0')} / {edge_codecov.get('line', {}).get('raw_total', '0')} ({edge_line_pct:.2f}%) |
| Design RTL reviewed 2-way baseline + edge line coverage | {edge_codecov.get('line', {}).get('reviewed_hit', '0')} / {edge_codecov.get('line', {}).get('reviewed_total', '0')} ({edge_codecov.get('line', {}).get('reviewed_percent', '0')}%); {edge_codecov.get('line', {}).get('excluded', '0')} excluded |
| Design RTL branch coverage proxy | {rtl_branch_pct:.2f}% |
| Design RTL raw toggle coverage proxy | {rtl_toggle_pct:.2f}% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- Results are report-backed local verification closure, not commercial signoff.
- UVM is secondary methodology collateral; runtime reporting is limited and separated from closure.
- SECDED is a separately verified structural variant; the parity baseline remains the canonical cache configuration.
- The non-blocking cache is a separate two-MSHR implementation; its same-clock cycle comparison is not a silicon-frequency claim.
- The dual-RV32 crossover is an optional educational MSI/RVWMO lane; it does not alter baseline cache closure or claim ACE/CHI compliance.
- Formal results are depth-stated bounded safety/error checks plus reachability covers and expected mutation failures, not exhaustive proof of cache correctness.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
"""
(ROOT / "docs").mkdir(exist_ok=True)
(ROOT / "docs" / "project_metrics.md").write_text(text)
print(f"METRICS|status=PASS|regression={passed}/{len(rows)}")
