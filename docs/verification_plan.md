# Verification Plan

## Objectives

Verify cache data integrity, replacement/writeback behavior, AXI4 channel correctness, error containment, maintenance behavior, and reset recovery with independent prediction and measurable closure.

## Verification Layers

| Layer | Purpose | Current command |
| --- | --- | --- |
| Directed/random SV | Fast executable behavior and protocol checks | `make regress` |
| C++ trace replay | Independent response, replacement, AXI, and memory prediction | `make model-trace-check` |
| SECDED/RAS | Optional correction, scrub, dirty-writeback, and double-error containment matrix | `make ras-check` |
| Assertions | Temporal and accounting invariants | enabled by regression |
| Formal | Bounded solver-backed safety/error checks, covers, and mutations | `make formal-prove` |
| Small-geometry formal | Reduced 2-set 1-way/2-way bounded proof and cover lane | `make formal-small-prove` |
| Associativity | Equal-capacity direct-mapped versus 2-way checks and characterization | `make associativity-characterize` |
| Synthesis proxy | Yosys storage/control geometry proxy for equal-capacity variants; full RTL remains behaviorally checked | `make synth-characterize` |
| Functional coverage | Feature-intent evidence | `make functional-coverage` |
| Interaction coverage | Same-window cache-specific crosses | `make cache-cross-coverage` |
| Performance | Per-request latency and throughput sweeps | `make performance-sweep` |
| Code coverage | RTL execution evidence | `make coverage` |
| Coverage-edge lane | Optional byte-strobe, reset/error matrix, LRU/replacement, maintenance-boundary, and direct-mapped structural coverage evidence | `make coverage-edges` |
| Mutation tests | Checker sensitivity | `make bug-validate` |
| Debug waveform | Expected-failure FST and deterministic SVG evidence | `make debug-waveform` |
| Optional UVM compile/runtime smoke | Secondary methodology collateral, not closure | `make uvm-runtime-smoke` |

## Required Scenario Families

- Hits: load/store, byte strobes, both ways, parity-clean access.
- Misses: cold refill, clean replacement, dirty replacement, replay.
- AXI: independent channel backpressure, read/write response errors, burst stability.
- Maintenance: flush, invalidate, flush-invalidate, dirty-line writeback failure.
- Reset: idle, refill, writeback, maintenance.
- Coverage edges: reset on every refill/writeback beat, read-error beat matrix, writeback-error containment, invalid-way preference, LRU walk, and maintenance boundary stress.
- Random: manifest-driven operation mix, address distributions, conflicts, strobes, stalls, errors, reset timing, and reproducible seeds.
- RAS: single-bit data/code correction, read scrub, double-bit detection, corrected dirty eviction and maintenance, and uncorrectable dirty-line containment.

## Release Targets

- All deterministic and required random tests pass.
- Required functional bins and mandatory crosses close.
- C++ trace model reports no response, lookup, AXI, eviction, or backing-memory mismatch.
- Cache interaction coverage closes at `55 / 55`; feature coverage separately includes explicit read/write hit/miss and clean/dirty replacement scenarios.
- Code coverage reports raw values and reviewed exclusions without manufacturing activity for cache-array bits; optional coverage-edge runs are reported separately from the baseline 2-way closure.
- Formal tasks must meet their stated bounded depths; results are not presented as exhaustive proof.
- Small-geometry formal tasks are reported separately from the full-geometry bounded harness and may skip locally when SymbiYosys is unavailable. Formal tasks target the default parity baseline; optional SECDED behavior has a separate model-backed RAS matrix.
- Both equal-capacity cache geometries must pass directed and C++ trace checks before characterization is accepted.
- Yosys synthesis proxy data must be reported as `PASS` when Yosys is available and `SKIP` otherwise; no implementation-cost claim is made from a skipped local run.
- The AXI4 subset appendix must map each supported protocol rule to an assertion/checker and a directed scenario.
- UVM runtime evidence remains explicitly separate from default closure unless real phase runtime is stable across the supported environment.
- Every implemented bug mutation is detected by a test, assertion, or scoreboard.
- The optional SECDED variant must close all seven RAS points without changing parity-baseline closure metrics.

Current results must be read from generated reports; targets are not presented as completed results.
