# Functional Coverage

This initial executable coverage model is separate from Verilator code coverage.

| Coverage point | Source test | Status |
| --- | --- | --- |
| `cold_miss_refill` | `smoke` | COVERED |
| `load_after_refill_hit` | `smoke` | COVERED |
| `dirty_eviction_writeback` | `dirty_evict` | COVERED |
| `axi_channel_backpressure` | `backpressure` | COVERED |
| `axi_read_error_propagation` | `read_error` | COVERED |
| `axi_writeback_error_propagation` | `write_error` | COVERED |
| `partial_byte_strobe_merge` | `byte_strobes` | COVERED |
| `misaligned_access_containment` | `misaligned` | COVERED |
| `flush_invalidate_maintenance` | `maintenance` | COVERED |
| `flush_only_maintenance` | `flush_only` | COVERED |
| `invalidate_forces_remiss` | `invalidate_only` | COVERED |
| `cpu_response_backpressure` | `response_backpressure` | COVERED |
| `reset_during_refill_recovery` | `reset_mid_refill` | COVERED |
| `independent_axi_channel_waits` | `axi_channel_waits` | COVERED |
| `maintenance_writeback_error` | `maintenance_error` | COVERED |
| `maintenance_terminal_dirty_way` | `maintenance_final_dirty` | COVERED |
| `maintenance_axi_channel_waits` | `maintenance_channel_waits` | COVERED |
| `seeded_random_data_integrity` | `random` | COVERED |

Current baseline: **18 / 18**. The release target expands this model before claiming closure.


## Code Coverage Interpretation

Native Verilator coverage is reported separately in `reports/code_coverage.md`. The current suite reaches all reviewed executable lines and nearly all branch points. Raw toggle coverage remains materially lower because it includes cache-array storage bits, fixed AXI burst constants, and address bits outside the bounded testbench memory window. Those raw values remain visible; only storage-array toggle points and non-executable assertion/default lines are excluded from reviewed summaries.
