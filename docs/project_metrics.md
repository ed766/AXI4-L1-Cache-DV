# Project Metrics

Generated from `reports/regress_summary.csv`. These are behavioral Verilator results, not silicon-signoff metrics.

| Metric | Current result |
| --- | ---: |
| Directed/random scenarios | 17 / 17 |
| Accepted CPU requests | 138 |
| CPU responses | 138 |
| Observed cache hits | 135 |
| Observed cache misses | 61 |
| Observed dirty evictions | 4 |
| Expected error responses | 3 |
| Aggregate observed hit rate | 68.9% |
| Initial functional coverage | 18 / 18 |
| Implemented bug mutations detected | 4 / 4 |
| Optional seeded stress scenarios | 100 / 100 |
| Design RTL line coverage proxy | 86.84% |
| Design RTL reviewed line coverage proxy | 100.00% |
| Design RTL branch coverage proxy | 98.21% |
| Design RTL raw toggle coverage proxy | 50.57% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- The local regression is an initial executable baseline, not final coverage closure.
- Full UVM collateral compiles; runtime phase progression and solver-formal results remain separate until their corresponding commands pass.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
