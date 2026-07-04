# Behavioral Performance Characterization

Cycle counts are Verilator behavioral measurements and include test setup. They are useful for relative comparison, not silicon timing claims.

| Scenario | Requests | Hits | Misses | Evictions | Total cycles | Cycles/request |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `smoke` | 4 | 4 | 1 | 0 | 33 | 8.2 |
| `dirty_evict` | 3 | 3 | 3 | 1 | 58 | 19.3 |
| `backpressure` | 3 | 3 | 3 | 1 | 70 | 23.3 |
| `read_error` | 2 | 1 | 2 | 0 | 37 | 18.5 |
| `write_error` | 4 | 3 | 3 | 1 | 50 | 12.5 |
| `byte_strobes` | 3 | 3 | 1 | 0 | 30 | 10.0 |
| `misaligned` | 2 | 1 | 1 | 0 | 27 | 13.5 |
| `maintenance` | 2 | 2 | 2 | 0 | 174 | 87.0 |
| `random` | 100 | 100 | 30 | 0 | 640 | 6.4 |
| `flush_only` | 2 | 2 | 1 | 0 | 163 | 81.5 |
| `invalidate_only` | 2 | 2 | 2 | 0 | 168 | 84.0 |
| `response_backpressure` | 1 | 1 | 1 | 0 | 30 | 30.0 |
| `reset_mid_refill` | 1 | 1 | 2 | 0 | 34 | 34.0 |
| `axi_channel_waits` | 4 | 4 | 4 | 1 | 84 | 21.0 |
| `maintenance_error` | 1 | 1 | 1 | 0 | 160 | 160.0 |
| `maintenance_final_dirty` | 2 | 2 | 2 | 0 | 180 | 90.0 |
| `maintenance_channel_waits` | 2 | 2 | 2 | 0 | 192 | 96.0 |


## Current Observations

- A warm hit avoids the four-beat AXI refill required by a cold miss.
- Dirty conflict replacement adds a complete four-beat writeback before refill.
- Independent AXI ready throttling increases service time without changing architectural results.
- The report is an initial baseline; percentile latency and duty-cycle sweeps remain release work.
