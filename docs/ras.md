# SECDED and RAS Verification

The optional `SECDED_ENABLE` cache variant stores a seven-bit SECDED code with each 32-bit data word. The parity baseline remains unchanged. Single-bit data or code faults are corrected; corrected reads scrub the repaired word and code back into the cache. Double-bit faults return the existing CPU error response and cannot initiate a dirty eviction or silently update backing memory.

## Executed Evidence

| Evidence | Result |
| --- | ---: |
| RAS matrix | `PASS` |
| Required RAS points | `7 / 7` |
| Correction events | `2` |
| Uncorrectable detections | `3` |
| Read scrubs | `2` |
| Independent C++ SECDED known-answer cases | `40` |

The matrix covers clean-line data correction, ECC-bit correction, clean-line double-error detection, corrected dirty eviction, blocked uncorrectable dirty eviction, corrected maintenance writeback, and uncorrectable maintenance containment. Faults are injected through verification-only hierarchy access; no CPU or AXI port was added.

## Scope Boundary

SECDED protects cache data words only. Tags retain the existing architectural treatment, and this project does not claim production RAS qualification or fault-injection signoff.
