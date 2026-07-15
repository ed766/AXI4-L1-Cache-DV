# Verification Traceability Matrix

| Requirement | Stimulus | Checker | Assertion | Coverage evidence |
| --- | --- | --- | --- | --- |
| Cold miss installs complete line | `smoke` | C++ trace replay and read-data comparison | failed-refill containment, response accounting | `cold_miss_refill` |
| Warm access hits | `smoke` | expected response | response ID/stability | `load_after_refill_hit` |
| Explicit read miss/hit paths issue expected AXI traffic | `read_miss`, `read_hit` | AXI handshake counters and C++ trace replay | request/response and AXI stability | cold-miss and load-hit feature points |
| Explicit write miss/hit paths allocate or stay local | `write_miss`, `write_hit` | AXI handshake counters, data readback, C++ replay | response uniqueness and request stability | write-miss and write-hit feature points |
| Clean victim is replaced without writeback | `clean_evict` | zero-AW check and refill observation | invalid-way/LRU selection | `clean_eviction_no_writeback` |
| Dirty victim writes back before refill | `dirty_evict`, `cross_matrix` | C++ AXI/writeback replay and backing-memory comparison | dirty-writeback-before-refill, exact WLAST | `dirty_eviction_writeback`, victim/way crosses |
| AXI stalls preserve protocol state | `backpressure`, `axi_channel_waits` | final memory/result | AW/W/AR/R stability | `axi_channel_backpressure`, `independent_axi_channel_waits` |
| Read error is CPU-visible | `read_error` | expected error response | no orphan response | `axi_read_error_propagation` |
| Flush/invalidate processes all lines | `maintenance` | backing memory and re-miss | maintenance busy blocks CPU | `flush_invalidate_maintenance` |
| Maintenance writeback tolerates independent AXI waits | `maintenance_channel_waits` | backing-memory comparison | AXI AW/W stability | `maintenance_axi_channel_waits` |
| Maintenance writeback errors are visible | `maintenance_error` | `maint_error` check | response accounting remains bounded | `maintenance_writeback_error` |
| Random conflicts preserve data | 100 manifest-driven scenarios | shadow model plus independent C++ trace replay | response uniqueness and replacement assertions | `55 / 55` cache crosses and stress summary |
| Per-request latency tradeoffs are measurable | `performance_workload` at 0/25/50/75% backpressure | trace-derived latency classifier | protocol assertions remain active | mean/p50/p95/max by hit, clean miss, dirty miss, and maintenance |
| Associativity changes conflict behavior at equal capacity | identical deterministic traces on 128x1 and 64x2 geometries | geometry-aware C++ trace replay | invalid-way preference and response accounting | 20/20 checks and 14-point characterization CSV |
| Implementation-cost proxy is tied to the associativity study | Yosys cache-geometry proxy for 128x1 and 64x2 variants | cell/memory-count extraction | full RTL variants remain behaviorally checked | `synthesis_characterization.csv` |
| Optional SECDED corrects and contains data faults | hierarchy-only single/double-bit injection over clean, dirty, eviction, and maintenance paths | CPU error, backing-memory, event-count, and C++ SECDED known-answer checks | SECDED scrub/correction and uncorrectable-error properties | `ras_summary.csv`, `ras_coverage.csv`, and `ras.md` |
| Selected safety and error paths hold under symbolic stimulus | SymbiYosys environment with legal AXI response assumptions | bounded safety/error tasks and reachability covers | WLAST, writeback/refill ordering, invalid-way preference, maintenance exclusion | `formal_proof_summary.csv` |
| Reduced-geometry formal avoids full-cache state explosion | 2-set 1-way and 2-way SymbiYosys harnesses | bounded proof and cover tasks | response count, maintenance exclusion, final-beat assumptions | `formal_small_proof_summary.csv` when `sby` is installed |
| Coverage holes are reviewed rather than hidden | coverage-edge and direct-mapped structural runs | hole-review categorizer | N/A | `coverage_hole_review.csv` and `coverage_closure_case_study.md` |
| AXI4 cache-master subset rules are explicit and checked | read/write miss, dirty eviction, channel waits, error paths | C++ trace replay and AXI response model | AW/AR/W stability, final-beat WLAST, failed-refill containment | `axi_subset_compliance.md` |
| Limited UVM methodology lane exercises representative scenarios | UVM compile plus read-miss, dirty-evict, and read-error equivalent probes | UVM runtime summary and equivalent scenario logs | response accounting remains in default SV/C++ lane | `uvm_runtime_summary.csv` |
| Checker detects dirty-state mutation | `CACHE_BUG_DIRTY_SKIP` | dirty-eviction test | planned dirty-implies-valid proof | bug report |
| Checker detects LRU mutation | `CACHE_BUG_LRU_INVERT` | victim/writeback check | planned replacement property | bug report |
| Checker detects ignored AXI error | `CACHE_BUG_REFILL_ERROR_IGNORE` | error propagation test | failed refill not installed | bug report |
| Early WLAST is rejected before acceptance | `CACHE_BUG_WLAST_EARLY` | FST, normalized trace, deterministic debug SVG | `a_wlast_exactly_final_beat` | debug waveform summary |
| Debug story is reviewable in one pass | early-WLAST mutation case study | assertion failure, waveform SVG, mutation report | `a_wlast_exactly_final_beat` | `hiring_manager_case_study.md` |
