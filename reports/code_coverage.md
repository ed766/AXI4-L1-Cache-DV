# Verilator Code Coverage

Coverage is grouped so optional edge and structural-variant tests do not obscure the baseline 2-way cache result.

| Group | Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `baseline_2way` | branch | 64 / 84 | 76.19% | 26 | 54 / 58 | 93.10% |
| `baseline_2way` | line | 49 / 71 | 69.01% | 43 | 27 / 28 | 96.43% |
| `baseline_2way` | toggle | 760 / 1323 | 57.45% | 341 | 647 / 982 | 65.89% |
| `coverage_edges_2way` | branch | 69 / 84 | 82.14% | 16 | 59 / 68 | 86.76% |
| `coverage_edges_2way` | line | 53 / 71 | 74.65% | 39 | 31 / 32 | 96.88% |
| `coverage_edges_2way` | toggle | 668 / 1323 | 50.49% | 260 | 543 / 1063 | 51.08% |
| `direct_mapped_variant` | branch | 49 / 84 | 58.33% | 16 | 39 / 68 | 57.35% |
| `direct_mapped_variant` | line | 45 / 68 | 66.18% | 39 | 23 / 29 | 79.31% |
| `direct_mapped_variant` | toggle | 414 / 1389 | 29.81% | 260 | 337 / 1129 | 29.85% |
| `secded_2way_variant` | branch | 54 / 84 | 64.29% | 0 | 54 / 84 | 64.29% |
| `secded_2way_variant` | line | 57 / 71 | 80.28% | 19 | 43 / 52 | 82.69% |
| `secded_2way_variant` | toggle | 386 / 1323 | 29.18% | 256 | 321 / 1067 | 30.08% |
| `baseline_plus_2way_edges` | branch | 74 / 84 | 88.10% | 16 | 64 / 68 | 94.12% |
| `baseline_plus_2way_edges` | line | 54 / 71 | 76.06% | 39 | 32 / 32 | 100.00% |
| `baseline_plus_2way_edges` | toggle | 836 / 1323 | 63.19% | 260 | 708 / 1063 | 66.60% |
| `combined_structural_variants` | branch | 83 / 84 | 98.81% | 0 | 83 / 84 | 98.81% |
| `combined_structural_variants` | line | 64 / 72 | 88.89% | 19 | 50 / 53 | 94.34% |
| `combined_structural_variants` | toggle | 860 / 1519 | 56.62% | 256 | 726 / 1263 | 57.48% |

## Coverage Groups

- `baseline_2way`: default 4 KiB, 2-way cache closure run.
- `coverage_edges_2way`: optional directed edge tests for byte strobes, set/way toggling, and maintenance boundaries.
- `baseline_plus_2way_edges`: union of baseline and optional 2-way edge executions, without structural variants.
- `direct_mapped_variant`: optional 4 KiB direct-mapped structural variant compiled with `CACHE_WAYS=1`, `CACHE_SETS=128`.
- `secded_2way_variant`: optional 2-way SECDED/RAS structural variant.
- `combined_structural_variants`: union across every executed geometry/integrity variant; never substituted for baseline closure.

Reviewed exclusions are limited to defensive defaults, assertion declaration lines, compile-time inactive logic, and storage-array toggle points. Raw values and exclusion denominators remain visible. Direct-mapped, SECDED, and combined coverage are structural-variant evidence and are never substituted for the baseline 2-way closure claim. This is Verilator proxy evidence, not commercial coverage signoff.
