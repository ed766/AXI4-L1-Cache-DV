# Synthesis Characterization

This report compares equal-capacity cache variants using Yosys as an open-source implementation proxy. It is not timing closure, physical design, or commercial signoff.

| Geometry | Sets | Ways | Status | Cell count | Wire bits | Memories | Memory bits | Area proxy | Timing proxy |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `direct_mapped` | 128 | 1 | PASS | 46642 | 499984 | 0 | 0 | 46642 | NA |
| `two_way` | 64 | 2 | PASS | 47625 | 501224 | 0 | 0 | 47625 | NA |


## Interpretation

- The direct-mapped and 2-way variants both model 4 KiB capacity with 32-byte lines.
- `area_proxy` is the Yosys cell-count proxy when no Liberty area data is available.
- `timing_proxy` remains `NA` unless a timing engine/library is available.
- `SKIP` means Yosys was not installed in the local environment; CI installs Yosys for release evidence.
