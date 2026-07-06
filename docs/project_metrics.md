# Project Metrics

Generated from `reports/regress_summary.csv`. These are behavioral Verilator results, not silicon-signoff metrics.

| Metric | Current result |
| --- | ---: |
| Directed/random scenarios | 22 / 22 |
| Accepted CPU requests | 149 |
| CPU responses | 149 |
| Observed cache hits | 146 |
| Observed cache misses | 131 |
| Observed dirty evictions | 8 |
| Expected error responses | 3 |
| Aggregate observed hit rate | 52.7% |
| Functional coverage | 21 / 21 |
| Implemented bug mutations detected | 4 / 4 |
| Optional seeded stress scenarios | 100 / 100 |
| C++ trace-replay checks | 127 / 127 |
| Cache interaction cross coverage | 55 / 55 |
| Waveform-backed debug cases | 1 / 1 |
| Named protocol/architecture assertions | 18 |
| Design RTL line coverage proxy | 86.84% |
| Design RTL reviewed line coverage proxy | 100.00% |
| Design RTL branch coverage proxy | 98.21% |
| Design RTL raw toggle coverage proxy | 59.49% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- Results are report-backed local verification closure, not commercial signoff.
- UVM is secondary compile-only methodology collateral; runtime phase progression and solver-formal results are not claimed.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
