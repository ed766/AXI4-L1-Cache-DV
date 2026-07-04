# Verification Traceability Matrix

| Requirement | Stimulus | Checker | Assertion | Coverage evidence |
| --- | --- | --- | --- | --- |
| Cold miss installs complete line | `smoke` | read-data comparison | response accounting | `cold_miss_refill` |
| Warm access hits | `smoke` | expected response | response ID/stability | `load_after_refill_hit` |
| Dirty victim writes back before refill | `dirty_evict` | backing-memory comparison | AXI W stability | `dirty_eviction_writeback` |
| AXI stalls preserve protocol state | `backpressure`, `axi_channel_waits` | final memory/result | AW/W/AR/R stability | `axi_channel_backpressure`, `independent_axi_channel_waits` |
| Read error is CPU-visible | `read_error` | expected error response | no orphan response | `axi_read_error_propagation` |
| Flush/invalidate processes all lines | `maintenance` | backing memory and re-miss | maintenance busy blocks CPU | `flush_invalidate_maintenance` |
| Maintenance writeback tolerates independent AXI waits | `maintenance_channel_waits` | backing-memory comparison | AXI AW/W stability | `maintenance_axi_channel_waits` |
| Maintenance writeback errors are visible | `maintenance_error` | `maint_error` check | response accounting remains bounded | `maintenance_writeback_error` |
| Random conflicts preserve data | `random` | shadow data model | response count bound | `seeded_random_data_integrity` |
| Checker detects dirty-state mutation | `CACHE_BUG_DIRTY_SKIP` | dirty-eviction test | planned dirty-implies-valid proof | bug report |
| Checker detects LRU mutation | `CACHE_BUG_LRU_INVERT` | victim/writeback check | planned replacement property | bug report |
| Checker detects ignored AXI error | `CACHE_BUG_REFILL_ERROR_IGNORE` | error propagation test | failed refill not installed | bug report |
