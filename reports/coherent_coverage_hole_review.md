# Coherent Coverage Hole Review

Raw line, branch, and toggle values remain unchanged. This review classifies uncovered source points without removing them from the denominator.

| Category | Points |
| --- | ---: |
| defensive_default_unreachable | 1 |
| impractical_diagnostic_saturation | 1 |
| mutation_only_failure_path | 1 |
| structurally_unreachable_in_adapter | 3 |
| verilator_instrumentation_artifact | 1 |

| Type | RTL file | Line | Category | Rationale |
| --- | --- | ---: | --- | --- |
| branch | `integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv` | 224 | structurally_unreachable_in_adapter | one-active-request-per-hart adapter cannot sustain fabric-level aging; leaf arbiter aging is executed separately |
| branch | `integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv` | 228 | mutation_only_failure_path | reset ghost hold is activated only by the expected-fail reset-epoch mutation |
| branch | `integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv` | 231 | impractical_diagnostic_saturation | requires 4095 consecutive active cycles; bounded-progress scenarios reset the watchdog normally |
| line | `integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv` | 129 | verilator_instrumentation_artifact | shared-access body is executed by read/write traces; uncovered point is the generated else token |
| branch | `rtl/coherence/msi_two_cache_subsystem.sv` | 227 | structurally_unreachable_in_adapter | integrated transport keeps the accepted home response ready, so the response-hold alternative is inactive |
| branch | `rtl/coherence/msi_two_cache_subsystem.sv` | 231 | structurally_unreachable_in_adapter | integrated transport keeps the accepted home response ready, so the response-hold alternative is inactive |
| line | `rtl/coherence/msi_two_cache_subsystem.sv` | 235 | defensive_default_unreachable | legal enum transitions cannot enter the default control-state arm |
