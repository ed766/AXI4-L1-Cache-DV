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
| Solver-backed formal tasks meeting expectation | 5 / 5 |
| Small-geometry formal tasks meeting expectation | 2 / 2 |
| Equal-capacity associativity directed checks | 20 / 20 |
| Associativity characterization points | 14 |
| Synthesis proxy variants | 2 / 2 |
| UVM runtime smoke collateral | 0 PASS / 3 SKIP / 3 total |
| Optional SECDED RAS matrix | 1 / 1 |
| SECDED RAS coverage | 7 / 7 |
| Named protocol/architecture assertions | 20 |
| Optional coverage-edge scenarios | 19 / 19 |
| Design RTL raw line coverage proxy | 49 / 66 (74.24%) |
| Design RTL reviewed line coverage proxy | 27 / 27 (100.00%); 39 excluded |
| Design RTL branch coverage proxy | 87.50% |
| Design RTL raw toggle coverage proxy | 61.19% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- Results are report-backed local verification closure, not commercial signoff.
- UVM is secondary methodology collateral; runtime reporting is limited and separated from closure.
- SECDED is a separately verified structural variant; the parity baseline remains the canonical cache configuration.
- Formal results are depth-stated bounded safety/error checks plus reachability covers and expected mutation failures, not exhaustive proof of cache correctness.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
