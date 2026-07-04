# Verification Plan

## Objectives

Verify cache data integrity, replacement/writeback behavior, AXI4 channel correctness, error containment, maintenance behavior, and reset recovery with independent prediction and measurable closure.

## Verification Layers

| Layer | Purpose | Current command |
| --- | --- | --- |
| Directed/random SV | Fast executable behavior and protocol checks | `make regress` |
| UVM compile collateral | Reusable sequence/driver/monitor/TLM architecture | `make uvm-compile` |
| UVM runtime probe | Environment-dependent phase execution, not a closure gate | `make uvm-smoke` |
| C++ model | Independent cache and backing-memory prediction | `make model-test` |
| Assertions | Temporal and accounting invariants | enabled by regression |
| Formal | Solver-backed safety and reachability | `make formal` |
| Functional coverage | Feature-intent evidence | `make functional-coverage` |
| Code coverage | RTL execution evidence | `make coverage` |
| Mutation tests | Checker sensitivity | `make bug-validate` |

## Required Scenario Families

- Hits: load/store, byte strobes, both ways, parity-clean access.
- Misses: cold refill, clean replacement, dirty replacement, replay.
- AXI: independent channel backpressure, read/write response errors, burst stability.
- Maintenance: flush, invalidate, flush-invalidate, dirty-line writeback failure.
- Reset: idle, refill, writeback, maintenance.
- Random: conflicting addresses, operation mix, delays, errors, and reproducible seeds.

## Release Targets

- All deterministic and required random tests pass.
- Required functional bins and mandatory crosses close.
- C++ model reports no response or backing-memory mismatch.
- Reviewed code coverage reaches 95% line, 85% branch/expression, and 90% toggle.
- Formal safety proofs pass and cover traces demonstrate non-vacuous reachability.
- Every implemented bug mutation is detected by a test, assertion, or scoreboard.

Current results must be read from generated reports; targets are not presented as completed results.
