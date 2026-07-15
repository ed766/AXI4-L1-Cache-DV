# Optional UVM Collateral

UVM is not closure evidence for this cache project. The repository retains a UVM architecture with:

- constrained cache sequence items and sequencer
- CPU driver and monitor over a virtual interface
- reactive AXI backing-memory component
- analysis-port traffic into a scoreboard and coverage subscriber
- a response-accounting scoreboard; authoritative independent prediction is provided by the non-UVM C++ trace-replay lane
- phase objections and UVM report accounting

The environment compiles with the local development Verilator `5.043` and the checked-out `uvm-verilator` source. Full UVM phase runtime still stalls in this open-source setup, so the default report-backed gate remains the non-UVM Verilator regression.

Use `make uvm-check-env` to validate dependencies, `make uvm-compile` for the passing compile/elaboration check, and `make uvm-runtime-smoke` for a limited three-scenario compatibility lane. The runtime summary separates UVM compile status, UVM phase-runtime status, and equivalent cache scenario status so it cannot be confused with UVM closure. A row is only `PASS` when the actual UVM phase runtime completes with zero `UVM_ERROR` and zero `UVM_FATAL`; timeout rows are reported as `SKIP`, even if the equivalent non-UVM cache scenario passes.

Current smoke scenarios:

| UVM-lane scenario | Equivalent cache scenario | Purpose |
| --- | --- | --- |
| `uvm_read_miss_refill_test` | `read_miss` | cold refill path |
| `uvm_dirty_evict_test` | `dirty_evict` | dirty victim writeback path |
| `uvm_axi_error_path_test` | `read_error` | refill error containment |

Current local result: UVM compilation passes, all three UVM runtime attempts time out, and the three equivalent non-UVM scenarios pass. This is compile/methodology collateral, not UVM closure.
