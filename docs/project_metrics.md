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
| Optional two-cache MSI checks | 16 / 16 |
| C++-modeled randomized MSI seeds | 25 / 25 |
| MSI mutations detected | 3 / 3 |
| SRAM March C-minus BIST checks | 7 / 7 |
| Integrated parity/SECDED cache-array BIST | 2 / 2 |
| Optional non-blocking cache scenarios | 11 / 11 |
| Non-blocking targeted coverage | 12 / 12 |
| Two-entry request-window speedup | 2.080x |
| Dual-RV32 GCC workload/optimizer matrix | 24 / 24 |
| RVWMO litmus schedules without forbidden outcomes | 400 / 400 |
| Pinned herd7 external litmus queries | 16 / 16 |
| Seeded coherent shared-memory workloads | 50 / 50 |
| Coherent functional / same-window cross coverage | 64 / 64; 48 / 48 |
| Focused executable crossover closure | 34 / 34 |
| Transaction-correlated advanced crosses | 48 / 48 |
| Coherent assertion/invariant activation | 20 / 20 |
| Coherent expected-fail mutations detected | 17 / 17 |
| Coherent solver-backed bounded proof/cover groups | 10 / 10 |
| Coherent error/reset scenarios | 9 / 9 |
| Coherent QoS/concurrency scenarios | 6 / 6 |
| Coherent measured RTL performance rows | 80 / 80 |
| Coherent RTL raw line / branch coverage | 95.28% / 92.86% |
| Coherent named integration assertions | 18 |
| Coherent reference/oracle execution rows | 895 / 895 |
| Named protocol/architecture assertions | 22 |
| Optional coverage-edge scenarios | 20 / 20 |
| Design RTL raw line coverage proxy | 49 / 71 (69.01%) |
| Design RTL reviewed line coverage proxy | 27 / 28 (96.43%); 43 excluded |
| Design RTL raw 2-way baseline + edge line coverage | 54 / 71 (76.06%) |
| Design RTL reviewed 2-way baseline + edge line coverage | 32 / 32 (100.00%); 39 excluded |
| Design RTL branch coverage proxy | 76.19% |
| Design RTL raw toggle coverage proxy | 57.45% |
| Independent C++ model self-test | PASS |

## Evidence Boundaries

- Results are report-backed local verification closure, not commercial signoff.
- UVM is secondary methodology collateral; runtime reporting is limited and separated from closure.
- SECDED is a separately verified structural variant; the parity baseline remains the canonical cache configuration.
- The non-blocking cache is a separate two-MSHR implementation; its same-clock cycle comparison is not a silicon-frequency claim.
- The dual-RV32 crossover is an optional educational MSI/RVWMO lane; it does not alter baseline cache closure or claim ACE/CHI compliance.
- Formal results are depth-stated bounded safety/error checks plus reachability covers and expected mutation failures, not exhaustive proof of cache correctness.
- AXI4 behavior is a constrained cache-master subset, not an AXI compliance certification.
