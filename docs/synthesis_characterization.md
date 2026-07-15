# Synthesis Characterization

This report compares equal-capacity cache geometries using a Yosys storage/control proxy with tag/data arrays, parallel way lookup, dirty metadata, victim selection, and LRU state. Behavioral results use the full cache RTL. This is not timing closure, physical design, or commercial signoff.

| Geometry | Sets | Ways | Status | Cell count | Wire bits | Memories | Memory bits | Area proxy | Timing proxy |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `direct_mapped` | 128 | 1 | PASS | 8 | 1232 | 2 | 35584 | 564 | NA |
| `two_way` | 64 | 2 | PASS | 26 | 1302 | 3 | 35776 | 585 | NA |


## Interpretation

- The direct-mapped and 2-way variants both model 4 KiB capacity with 32-byte lines.
- `memory_bits` is the architectural data/tag/valid/dirty/LRU storage represented by Yosys `$mem_v2` cells.
- `area_proxy` is `logic cells + ceil(memory_bits / 64)` so inferred memories contribute to the comparison without pretending to use a foundry area library.
- `timing_proxy` remains `NA` unless a timing engine/library is available.
- The proxy isolates associativity cost from the full cache FSM and optional SECDED implementation; it is not whole-cache synthesis.
- `SKIP` means Yosys was not installed in the local environment; CI installs Yosys for release evidence.
