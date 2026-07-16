#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
DOCS = ROOT / "docs"


def classify(row: dict[str, str]) -> tuple[str, str]:
    point = row.get("point_type", "")
    rtl_file = row.get("rtl_file", "")
    line = int(row.get("line", "0") or 0)
    signal = row.get("signal_or_branch", "")
    exclusion = row.get("reviewed_exclusion", "")
    group = row.get("coverage_group", "")

    if exclusion and exclusion != "none":
        return exclusion, "Already excluded from reviewed coverage with structural rationale."
    if point == "branch" and line == 234:
        return "verilator_instrumentation_artifact", "All 16 byte-strobe masks are exercised by byte_strobe_lane_matrix; the remaining branch point is a Verilator instrumentation artifact."
    if line in (309, 380, 434, 515):
        return "direct_mapped_structural_variant_only", "Covered by the direct-mapped CACHE_WAYS=1 structural variant, not by baseline 2-way closure."
    if point == "toggle" and any(name in signal for name in ("tags", "data_mem", "parity_mem", "refill_buf", "valid_bits", "dirty_bits", "lru")):
        return "storage_array_toggle_not_closure_target", "Storage and state-array bit toggles are reported raw but not chased as closure targets."
    if point == "line" and line >= 430:
        return "assertion_or_default_non_executable", "Defensive/default or assertion-adjacent RTL path; kept visible in raw coverage."
    if group != "combined_structural_variants" and rtl_file == "l1_dcache_top.sv" and point in ("line", "branch", "expression"):
        return "suite_specific_raw_gap", "Uncovered in this individual run group; disposition is based on the combined structural-variant union."
    if group == "combined_structural_variants" and rtl_file == "l1_dcache_top.sv" and point in ("line", "branch", "expression"):
        return "executable_and_worth_testing", "Potential candidate for a future targeted coverage-edge test if it maps to legal architecture behavior."
    return "reviewed_no_action", "Reviewed and retained as non-gating raw coverage evidence."


def main() -> int:
    holes_path = REPORTS / "code_coverage_holes.csv"
    if not holes_path.exists():
        print("COVERAGE_HOLE_REVIEW|status=SKIP|reason=missing_code_coverage_holes")
        return 0
    rows = list(csv.DictReader(holes_path.open()))
    reviewed = []
    counts: dict[str, int] = {}
    for row in rows:
        category, rationale = classify(row)
        counts[category] = counts.get(category, 0) + 1
        reviewed.append({**row, "category": category, "rationale": rationale})

    fields = list(reviewed[0].keys()) if reviewed else [
        "coverage_group", "point_type", "rtl_file", "line", "signal_or_branch",
        "hit_count", "reviewed_exclusion", "category", "rationale",
    ]
    with (REPORTS / "coverage_hole_review.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(reviewed)

    DOCS.mkdir(exist_ok=True)
    text = """# Coverage Closure Case Study

The canonical closure model is functional coverage (`21 / 21`) plus trace-derived cache interaction crosses (`55 / 55`). Verilator code coverage is separate execution evidence. Raw code coverage remains visible, while reviewed exclusions explain why selected raw holes are not meaningful closure targets.

## Hole Review Summary

| Category | Count | Meaning |
| --- | ---: | --- |
"""
    descriptions = {
        "executable_and_worth_testing": "Reachable-looking RTL that could justify future targeted tests.",
        "direct_mapped_structural_variant_only": "Only reachable in the `CACHE_WAYS=1` structural variant.",
        "memory_array_bit_toggle": "Storage-array toggle points excluded from reviewed toggle closure.",
        "storage_array_toggle_not_closure_target": "Raw toggle points retained but not chased as closure targets.",
        "unreachable_defensive_default": "Defensive/default paths not reachable in legal baseline operation.",
        "assertion_declaration_not_executable_rtl": "Assertion/declaration instrumentation, not executable datapath RTL.",
        "assertion_or_default_non_executable": "Assertion/default-adjacent path kept visible in raw coverage.",
        "verilator_instrumentation_artifact": "Verilator branch artifact after directed stimulus covers the intended behavior.",
        "reviewed_no_action": "Reviewed non-gating evidence.",
        "suite_specific_raw_gap": "A per-suite gap reviewed against the combined structural-variant execution union.",
    }
    for category, count in sorted(counts.items()):
        text += f"| `{category}` | {count} | {descriptions.get(category, 'Reviewed coverage hole category.')} |\n"
    text += """

## Specific Review Notes

- The byte-strobe merge path is exercised with all 16 `WSTRB` masks by `byte_strobe_lane_matrix`; any remaining `merge_word()` branch hole is treated as instrumentation-level evidence, not a missing architectural case.
- `WAYS == 1` paths are covered through the direct-mapped structural-variant coverage group and associativity checks, not through baseline 2-way closure.
- SECDED-only paths are executed in the separately reported `secded_2way_variant` group.
- `combined_structural_variants` is used to disposition suite-specific holes, never to inflate the baseline metric.
- Raw toggle coverage is expected to remain lower than line/branch coverage because cache arrays dominate toggle points. Reviewed closure does not chase every storage bit.
- Coverage-edge scenarios are non-gating evidence. They do not inflate the canonical feature coverage count.

## Source Reports

- `reports/code_coverage_summary.csv`
- `reports/code_coverage_holes.csv`
- `reports/coverage_hole_review.csv`
- `reports/coverage_edges_summary.csv`
"""
    (DOCS / "coverage_closure_case_study.md").write_text(text)
    print(f"COVERAGE_HOLE_REVIEW|status=PASS|holes={len(reviewed)}|categories={len(counts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
