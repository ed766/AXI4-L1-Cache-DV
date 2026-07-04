# UVM Status

The repository contains a real UVM architecture with:

- constrained cache sequence items and sequencer
- CPU driver and monitor over a virtual interface
- reactive AXI backing-memory component
- analysis-port traffic into a scoreboard and coverage subscriber
- a response-accounting scoreboard; the independently tested C++ model exposes a DPI-compatible API for a later online-prediction step
- phase objections and UVM report accounting

The environment compiles with the local development Verilator `5.043` and the checked-out `uvm-verilator` source. The current runtime probe stalls before run-phase progression and is terminated by a 60-second timeout. Therefore UVM execution or closure is not claimed; the default report-backed gate remains the non-UVM Verilator regression.

Use `make uvm-check-env` to validate dependencies, `make uvm-compile` for the passing compile/elaboration check, and `make uvm-smoke` only as the bounded runtime probe. This split prevents compilation evidence from being confused with a passing UVM test.
