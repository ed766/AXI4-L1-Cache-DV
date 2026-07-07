# AXI4 Cache-Master Subset Compliance

This project verifies a constrained AXI4 master subset used by the blocking L1 cache. It is not an AXI compliance certification and does not claim support for the full AXI4 feature set.

## Supported Subset

| Rule | Supported behavior |
| --- | --- |
| Data width | 64-bit AXI data bus |
| Burst shape | Four-beat `INCR` bursts for 32-byte cache lines |
| Outstanding transactions | One read or one write transaction at a time |
| IDs | Fixed/simple ID semantics |
| Unsupported AXI features | Exclusive, locked, narrow, wrapping, out-of-order, and multi-ID transactions |
| Error handling | Read errors prevent line install; writeback errors preserve dirty victim state |

## Rule-To-Evidence Matrix

| AXI rule | Directed evidence | Assertion/checker | Report artifact |
| --- | --- | --- | --- |
| AW/AR control remains stable under backpressure | `axi_channel_waits`, `backpressure` | AXI stability assertions and C++ trace replay | `regress_summary.csv`, `model_trace_summary.csv` |
| W data/strobe/last remains stable under backpressure | `dirty_evict`, `axi_channel_waits` | `a_wlast_exactly_final_beat` and write-channel stability checks | `debug_waveform_summary.csv` |
| `WLAST` occurs only on beat three | `dirty_evict`, early-WLAST mutation | `a_wlast_exactly_final_beat` | `bug_validation.csv`, `formal_proof_summary.csv` |
| Legal `RLAST` is accepted only on final refill beat | `read_miss`, `read_error` | Formal environment assumption plus trace replay | `formal.md`, `model_trace_summary.csv` |
| Failed refill does not install a valid line | `read_error` | failed-refill containment property and C++ model | `formal_proof_summary.csv`, `model_trace_summary.csv` |
| Failed writeback preserves dirty victim | `write_error`, `maintenance_error` | failed-writeback containment property and trace replay | `formal_proof_summary.csv` |
| Dirty writeback precedes refill | `dirty_evict`, `cross_matrix` | dirty-writeback-before-refill checks | `cache_cross_coverage.csv` |

## Boundary

The AXI model is intentionally scoped to the cache use case. Full AXI compliance would require substantially broader protocol coverage, including multi-ID ordering, interleaving, exclusive accesses, narrow bursts, and illegal-protocol stimulus. Those are out of scope for this student DV project.
