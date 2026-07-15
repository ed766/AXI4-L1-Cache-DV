# Cache Associativity Characterization

Both variants are 4 KiB write-back, write-allocate caches with 32-byte lines. Results are deterministic behavioral Verilator measurements, not silicon timing or implementation signoff.

| Workload | Geometry | Hit rate | Clean evictions | Dirty evictions | p95 latency | Throughput | Yosys cells |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sequential` | `direct_mapped` | 85.89% | 0 | 1 | 16 | 0.11088 | NA |
| `uniform` | `direct_mapped` | 3.07% | 32 | 37 | 23 | 0.04483 | NA |
| `hot_set` | `direct_mapped` | 78.53% | 0 | 1 | 15 | 0.09583 | NA |
| `same_set` | `direct_mapped` | 0.00% | 82 | 78 | 23 | 0.04405 | NA |
| `read_heavy` | `direct_mapped` | 4.29% | 53 | 19 | 23 | 0.04837 | NA |
| `write_heavy` | `direct_mapped` | 1.84% | 16 | 67 | 23 | 0.04066 | NA |
| `mixed_strobes` | `direct_mapped` | 4.29% | 32 | 44 | 23 | 0.04414 | NA |
| `sequential` | `two_way` | 85.89% | 1 | 0 | 16 | 0.11088 | NA |
| `uniform` | `two_way` | 3.07% | 31 | 29 | 23 | 0.04474 | NA |
| `hot_set` | `two_way` | 78.53% | 1 | 0 | 15 | 0.09583 | NA |
| `same_set` | `two_way` | 96.93% | 1 | 1 | 2 | 0.14658 | NA |
| `read_heavy` | `two_way` | 4.29% | 43 | 18 | 23 | 0.04820 | NA |
| `write_heavy` | `two_way` | 1.84% | 18 | 55 | 23 | 0.04029 | NA |
| `mixed_strobes` | `two_way` | 4.29% | 29 | 37 | 23 | 0.04391 | NA |


## Implementation Proxy

| Geometry | Yosys status | Cell-count proxy | Area proxy | Timing proxy |
| --- | --- | ---: | ---: | ---: |
| `direct_mapped` | FAIL | NA | NA | NA |
| `two_way` | FAIL | NA | NA | NA |


## Interpretation

- The configurations hold capacity and line size constant, isolating associativity and set-count effects.
- Same-set traffic exposes conflict behavior; the 2-way cache can retain two lines per set while direct-mapped placement cannot.
- Refill/writeback traffic and latency are derived from normalized observer traces and checked by the independent C++ model.
- Yosys/OpenSTA numbers are implementation proxies only. `SKIP`/`NA` means the required open-source tool was unavailable in the local environment; no synthesis-cost claim is inferred from simulation.

![Associativity comparison](images/associativity_comparison.svg)
