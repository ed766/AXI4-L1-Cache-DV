# Coverage Closure Case Study

The canonical closure model is functional coverage (`21 / 21`) plus trace-derived cache interaction crosses (`55 / 55`). Verilator code coverage is separate execution evidence. Raw code coverage remains visible, while reviewed exclusions explain why selected raw holes are not meaningful closure targets.

## Hole Review Summary

| Category | Count | Meaning |
| --- | ---: | --- |
| `assertion_declaration_not_executable_rtl` | 20 | Assertion/declaration instrumentation, not executable datapath RTL. |
| `assertion_or_default_non_executable` | 6 | Assertion/default-adjacent path kept visible in raw coverage. |
| `compile_time_inactive_secded_variant` | 66 | Reviewed coverage hole category. |
| `direct_mapped_structural_variant_only` | 8 | Only reachable in the `CACHE_WAYS=1` structural variant. |
| `memory_array_bit_toggle` | 766 | Storage-array toggle points excluded from reviewed toggle closure. |
| `reviewed_no_action` | 1239 | Reviewed non-gating evidence. |
| `storage_array_toggle_not_closure_target` | 1399 | Raw toggle points retained but not chased as closure targets. |
| `suite_specific_raw_gap` | 40 | A per-suite gap reviewed against the combined structural-variant execution union. |
| `unreachable_defensive_default` | 5 | Defensive/default paths not reachable in legal baseline operation. |
| `verilator_instrumentation_artifact` | 3 | Verilator branch artifact after directed stimulus covers the intended behavior. |


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
