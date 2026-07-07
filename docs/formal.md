# Solver-Backed Formal Evidence

The SymbiYosys harness separates DUT guarantees from AXI environment assumptions. In particular, cache-generated `WLAST` is asserted; memory-generated `RLAST` placement is assumed legal and the cache response is checked.

| Task | Kind | Observed | Expected | Meets expectation | Depth | Runtime |
| --- | --- | --- | --- | --- | ---: | ---: |
| `bounded_safety` | `bounded_safety` | PASS | PASS | yes | 40 | 3.02 s |
| `cover` | `cover` | PASS | PASS | yes | 50 | 78.80 s |
| `error_containment_bmc` | `bounded_error` | PASS | PASS | yes | 40 | 9.12 s |
| `mutation_wlast_early` | `expected_mutation_failure` | FAIL | FAIL | yes | 40 | 2.45 s |
| `mutation_refill_error_ignore` | `expected_mutation_failure` | FAIL | FAIL | yes | 40 | 5.34 s |


Properties cover request/response accounting, dirty-writeback ordering, refill/writeback error containment, final-beat write semantics, invalid-way preference, and maintenance exclusion. Cover tasks require hits, misses, dirty evictions, and maintenance completion to be reachable. Error paths are separately sensitized by the bounded containment task and expected-failing mutations.

These are depth-stated open-source bounded checks and reachability results for selected invariants, not full cache correctness or commercial formal signoff.
