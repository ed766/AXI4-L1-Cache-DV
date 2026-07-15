# Small-Geometry Formal Evidence

The SymbiYosys harness separates DUT guarantees from AXI environment assumptions. In particular, cache-generated `WLAST` is asserted; memory-generated `RLAST` placement is assumed legal and the cache response is checked. These tasks target the default parity baseline; optional SECDED behavior is checked by the independent model-backed RAS matrix.

| Task | Kind | Observed | Expected | Meets expectation | Depth | Runtime |
| --- | --- | --- | --- | --- | ---: | ---: |
| `small_1way_bounded_safety` | `small_geometry_bounded_safety` | PASS | PASS | yes | 20 | 11.26 s |
| `small_2way_bounded_safety` | `small_geometry_bounded_safety` | PASS | PASS | yes | 20 | 69.33 s |


Properties cover request/response accounting, dirty-writeback ordering, refill/writeback error containment, final-beat write semantics, invalid-way preference, and maintenance exclusion. The canonical formal lane separately requires hits, misses, dirty evictions, error responses, and maintenance completion to be reachable. Error paths are sensitized by the bounded containment task and expected-failing mutations where included.

These are depth-stated open-source bounded checks and reachability results for selected invariants, not full cache correctness or commercial formal signoff.
