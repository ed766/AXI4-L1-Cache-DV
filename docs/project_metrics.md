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
| C++ trace-replay checks | 22 / 22 |
| Cache interaction cross coverage | 55 / 55 |
| Waveform-backed debug cases | 1 / 1 |
| Solver-backed formal tasks meeting expectation | 5 / 5 |
| Small-geometry formal tasks meeting expectation | SKIP (sby unavailable locally) |
| Equal-capacity associativity directed checks | 20 / 20 |
| Associativity characterization points | 14 |
| Synthesis proxy variants | 2 / 2 |
| UVM runtime smoke collateral | 0 PASS / 3 SKIP / 3 total |
| Named protocol/architecture assertions | 18 |
| Optional coverage-edge scenarios | 19 / 19 |
| Design RTL line coverage proxy | 88.10% |
| Design RTL reviewed line coverage proxy | 100.00% |
| Design RTL branch coverage proxy | 95.00% |
| Design RTL raw toggle coverage proxy | 59.49% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- Results are report-backed local verification closure, not commercial signoff.
- UVM is secondary methodology collateral; runtime reporting is limited and separated from closure.
- Formal results are depth-stated bounded safety/error checks plus reachability covers and expected mutation failures, not exhaustive proof of cache correctness.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
