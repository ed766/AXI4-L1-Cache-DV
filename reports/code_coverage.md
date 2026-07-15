# Verilator Code Coverage

Coverage is grouped so optional edge and structural-variant tests do not obscure the baseline 2-way cache result.

| Group | Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `baseline_2way` | branch | 63 / 72 | 87.50% | 16 | 53 / 56 | 94.64% |
| `baseline_2way` | line | 49 / 66 | 74.24% | 39 | 27 / 27 | 100.00% |
| `baseline_2way` | toggle | 760 / 1242 | 61.19% | 260 | 647 / 982 | 65.89% |
| `coverage_edges_2way` | branch | 58 / 72 | 80.56% | 16 | 48 / 56 | 85.71% |
| `coverage_edges_2way` | line | 48 / 66 | 72.73% | 39 | 26 / 27 | 96.30% |
| `coverage_edges_2way` | toggle | 646 / 1242 | 52.01% | 260 | 521 / 982 | 53.05% |
| `direct_mapped_variant` | branch | 48 / 72 | 66.67% | 16 | 38 / 56 | 67.86% |
| `direct_mapped_variant` | line | 45 / 63 | 71.43% | 39 | 23 / 24 | 95.83% |
| `direct_mapped_variant` | toggle | 414 / 1307 | 31.68% | 260 | 337 / 1047 | 32.19% |

## Coverage Groups

- `baseline_2way`: default 4 KiB, 2-way cache closure run.
- `coverage_edges_2way`: optional directed edge tests for byte strobes, set/way toggling, and maintenance boundaries.
- `direct_mapped_variant`: optional 4 KiB direct-mapped structural variant compiled with `CACHE_WAYS=1`, `CACHE_SETS=128`.

Reviewed exclusions are limited to defensive defaults, assertion declaration lines, and storage-array toggle points. Raw values remain visible. Direct-mapped coverage is reported as structural-variant evidence, not as part of the baseline 2-way closure claim. This is Verilator proxy evidence, not commercial coverage signoff.
