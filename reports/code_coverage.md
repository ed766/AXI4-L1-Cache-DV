# Verilator Code Coverage

Coverage is grouped so optional edge and structural-variant tests do not obscure the baseline 2-way cache result.

| Group | Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `baseline_2way` | branch | 63 / 72 | 87.50% | 16 | 53 / 56 | 94.64% |
| `baseline_2way` | line | 49 / 66 | 74.24% | 39 | 27 / 27 | 100.00% |
| `baseline_2way` | toggle | 760 / 1242 | 61.19% | 260 | 647 / 982 | 65.89% |
| `coverage_edges_2way` | branch | 52 / 60 | 86.67% | 4 | 49 / 56 | 87.50% |
| `coverage_edges_2way` | line | 36 / 42 | 85.71% | 18 | 23 / 24 | 95.83% |
| `coverage_edges_2way` | toggle | 587 / 1170 | 50.17% | 287 | 446 / 883 | 50.51% |
| `direct_mapped_variant` | branch | 42 / 60 | 70.00% | 4 | 39 / 56 | 69.64% |
| `direct_mapped_variant` | line | 33 / 39 | 84.62% | 16 | 22 / 23 | 95.65% |
| `direct_mapped_variant` | toggle | 374 / 1235 | 30.28% | 286 | 286 / 949 | 30.14% |

## Coverage Groups

- `baseline_2way`: default 4 KiB, 2-way cache closure run.
- `coverage_edges_2way`: optional directed edge tests for byte strobes, set/way toggling, and maintenance boundaries.
- `direct_mapped_variant`: optional 4 KiB direct-mapped structural variant compiled with `CACHE_WAYS=1`, `CACHE_SETS=128`.

Reviewed exclusions are limited to defensive defaults, assertion declaration lines, and storage-array toggle points. Raw values remain visible. Direct-mapped coverage is reported as structural-variant evidence, not as part of the baseline 2-way closure claim. This is Verilator proxy evidence, not commercial coverage signoff.
