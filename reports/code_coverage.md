# Verilator Code Coverage

Coverage is grouped so optional edge and structural-variant tests do not obscure the baseline 2-way cache result.

| Group | Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `baseline_2way` | branch | 57 / 60 | 95.00% | 0 | 57 / 60 | 95.00% |
| `baseline_2way` | line | 37 / 42 | 88.10% | 13 | 29 / 29 | 100.00% |
| `baseline_2way` | toggle | 696 / 1170 | 59.49% | 256 | 583 / 914 | 63.79% |
| `coverage_edges_2way` | branch | 52 / 60 | 86.67% | 0 | 52 / 60 | 86.67% |
| `coverage_edges_2way` | line | 36 / 42 | 85.71% | 13 | 28 / 29 | 96.55% |
| `coverage_edges_2way` | toggle | 587 / 1170 | 50.17% | 256 | 462 / 914 | 50.55% |
| `direct_mapped_variant` | branch | 42 / 60 | 70.00% | 0 | 42 / 60 | 70.00% |
| `direct_mapped_variant` | line | 33 / 39 | 84.62% | 13 | 25 / 26 | 96.15% |
| `direct_mapped_variant` | toggle | 374 / 1235 | 30.28% | 256 | 297 / 979 | 30.34% |

## Coverage Groups

- `baseline_2way`: default 4 KiB, 2-way cache closure run.
- `coverage_edges_2way`: optional directed edge tests for byte strobes, set/way toggling, and maintenance boundaries.
- `direct_mapped_variant`: optional 4 KiB direct-mapped structural variant compiled with `CACHE_WAYS=1`, `CACHE_SETS=128`.

Reviewed exclusions are limited to defensive defaults, assertion declaration lines, and storage-array toggle points. Raw values remain visible. Direct-mapped coverage is reported as structural-variant evidence, not as part of the baseline 2-way closure claim. This is Verilator proxy evidence, not commercial coverage signoff.
