# Formal Evidence

The SymbiYosys harness separates DUT guarantees from AXI environment assumptions. Cache-generated `WLAST` is asserted; memory-generated `RLAST` placement is assumed legal and the cache response is checked. The canonical and reduced-geometry tasks target the parity baseline; optional SECDED behavior is checked by the independent model-backed RAS matrix.

| Task | Kind | Observed | Expected | Meets expectation | Depth | Runtime |
| --- | --- | --- | --- | --- | ---: | ---: |
| `bounded_safety` | `bounded_safety` | PASS | PASS | yes | 40 | 60.23 s |
| `cover` | `cover` | PASS | PASS | yes | 50 | 193.14 s |
| `error_containment_bmc` | `bounded_error` | PASS | PASS | yes | 40 | 57.89 s |
| `mutation_wlast_early` | `expected_mutation_failure` | FAIL | FAIL | yes | 40 | 55.05 s |
| `mutation_refill_error_ignore` | `expected_mutation_failure` | FAIL | FAIL | yes | 40 | 50.78 s |
| `small_1way_bounded_safety` | `small_geometry_bounded_safety` | PASS | PASS | yes | 20 | 9.39 s |
| `small_2way_bounded_safety` | `small_geometry_bounded_safety` | PASS | PASS | yes | 20 | 57.33 s |

Properties cover request/response accounting, dirty-writeback ordering, refill/writeback error containment, final-beat write semantics, invalid-way preference, and maintenance exclusion. Reachability tasks exercise hits, misses, dirty evictions, error responses, and maintenance completion; mutation tasks demonstrate checker sensitivity.

The `small_1way` and `small_2way` rows are reduced-geometry bounded proof evidence. All results are depth-stated open-source checks, not exhaustive cache correctness or commercial formal signoff.

## Dual-RV32 Coherent Leaf Proofs

The optional coherent crossover adds ten depth-20 solver-backed safety/cover groups. Seven bind reduced instances of the implemented MSI and store-buffer RTL; three use reduced architectural models for publication freshness, response ownership, and reset epochs because the installed Yosys frontend cannot flatten the full multidimensional AXI fabric hierarchy. Nine groups close with inductive `prove` tasks. Failed-store-head preservation is honestly reported as reset-reachable bounded safety because its memory invariant does not close induction from arbitrary unreachable states. All `10 / 10` groups and their non-vacuous covers pass, and `proof_mode` plus `implementation_scope` in `reports/coherent_formal_summary.csv` preserve these distinctions.

The failed-store group exposed a real simultaneous enqueue/error occupancy defect. The design was corrected, an executable regression was added, and an expected-fail mutation restores the original logic to demonstrate detection.

These are deliberately reduced leaf/control models. They complement simulation and RVWMO outcome checking; they are not an exhaustive proof of the complete dual-core, MSI, AXI, or firmware state space.
