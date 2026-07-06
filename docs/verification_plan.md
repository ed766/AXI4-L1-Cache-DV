# Verification Plan

## Objectives

Verify cache data integrity, replacement/writeback behavior, AXI4 channel correctness, error containment, maintenance behavior, and reset recovery with independent prediction and measurable closure.

## Verification Layers

| Layer | Purpose | Current command |
| --- | --- | --- |
| Directed/random SV | Fast executable behavior and protocol checks | `make regress` |
| C++ trace replay | Independent response, replacement, AXI, and memory prediction | `make model-trace-check` |
| Assertions | Temporal and accounting invariants | enabled by regression |
| Formal | Solver-backed safety and reachability | `make formal` |
| Functional coverage | Feature-intent evidence | `make functional-coverage` |
| Interaction coverage | Same-window cache-specific crosses | `make cache-cross-coverage` |
| Performance | Per-request latency and throughput sweeps | `make performance-sweep` |
| Code coverage | RTL execution evidence | `make coverage` |
| Mutation tests | Checker sensitivity | `make bug-validate` |
| Debug waveform | Expected-failure FST and deterministic SVG evidence | `make debug-waveform` |
| Optional UVM compile | Secondary methodology collateral, not closure | `make uvm-compile` |

## Required Scenario Families

- Hits: load/store, byte strobes, both ways, parity-clean access.
- Misses: cold refill, clean replacement, dirty replacement, replay.
- AXI: independent channel backpressure, read/write response errors, burst stability.
- Maintenance: flush, invalidate, flush-invalidate, dirty-line writeback failure.
- Reset: idle, refill, writeback, maintenance.
- Random: manifest-driven operation mix, address distributions, conflicts, strobes, stalls, errors, reset timing, and reproducible seeds.

## Release Targets

- All deterministic and required random tests pass.
- Required functional bins and mandatory crosses close.
- C++ trace model reports no response, lookup, AXI, eviction, or backing-memory mismatch.
- Cache interaction coverage closes at `55 / 55`; feature coverage separately includes explicit read/write hit/miss and clean/dirty replacement scenarios.
- Code coverage reports raw values and reviewed exclusions without manufacturing activity for cache-array bits.
- Formal remains optional until a solver-backed run is available; it is not part of release closure.
- Every implemented bug mutation is detected by a test, assertion, or scoreboard.

Current results must be read from generated reports; targets are not presented as completed results.
