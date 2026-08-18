# Non-Blocking L1 Cache Evidence

This optional structural variant is separate from the canonical blocking-cache closure.

| Evidence | Result |
| --- | ---: |
| Directed/random/performance scenarios | `11 / 11` |
| Architecture coverage points | `12 / 12` |
| Named safety assertions | `7` |
| Serialized 32-miss workload | `778` cycles |
| Two-MSHR windowed workload | `374` cycles |
| Measured same-clock speedup | `2.08x` |

The performance comparison uses the same RTL, memory model, addresses, and ten-cycle
refill delay. The serialized mode waits for each response; the windowed mode keeps up
to two different-set misses active. Values are behavioral Verilator cycles, not silicon
frequency or implementation signoff.
