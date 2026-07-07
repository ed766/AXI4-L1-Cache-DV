# Functional Coverage

This trace/event-derived feature model is separate from Verilator code coverage and is not presented as simulator covergroup coverage.

| Coverage point | Source test | Status |
| --- | --- | --- |
| `cold_miss_refill` | `read_miss` | COVERED |
| `load_after_refill_hit` | `read_hit` | COVERED |
| `write_miss_allocate` | `write_miss` | COVERED |
| `write_hit_no_axi` | `write_hit` | COVERED |
| `clean_eviction_no_writeback` | `clean_evict` | COVERED |
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

Current release result: **21 / 21** covered.


## Code Coverage Interpretation

Native Verilator coverage is reported separately in `reports/code_coverage.md`. The current suite reaches all reviewed executable lines and nearly all baseline branch points. Raw toggle coverage remains materially lower because it includes cache-array storage bits, fixed AXI burst constants, and address bits outside the bounded testbench memory window. Those raw values remain visible; only storage-array toggle points and non-executable assertion/default lines are excluded from reviewed summaries.

`make coverage-edges` adds optional code-coverage evidence for byte-strobe lane combinations, set/way state toggling, maintenance boundary traversal, and the equal-capacity direct-mapped structural variant. These runs are reported separately from the baseline 2-way cache closure and do not change the feature vector above.

Cache-specific same-window interaction coverage is reported separately in `docs/cross_coverage.md`; it does not inflate the feature vector above.
