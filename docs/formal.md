# Assertion and Formal Evidence

Simulation enables named response-accounting and ready/valid stability assertions for CPU and AXI channels. The reusable assertion module is bound to the cache in the directed regression.

`formal/cache_safety.sby` provides a solver-ready proof harness for:

- response count never exceeding accepted request count
- read and write address activity not occurring simultaneously in the blocking controller
- fixed four-beat writeback semantics
- refill reachability
- dirty-eviction reachability

The local machine does not currently expose `sby` in `PATH`; therefore no passing solver result is claimed until `make formal` runs with OSS CAD Suite or equivalent tools.

