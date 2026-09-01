PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: lint smoke regress coverage coverage-edges functional-coverage performance performance-sweep cache-cross-coverage stress-manifest stress random-stress bug-validate debug-waveform readme-metrics docs-check model-test model-trace-check ras-check coherence-check bist-check integration-check integration-synth-check nonblocking-cache-check formal formal-prove formal-small-prove formal-cover formal-mutations synth-characterize associativity-check associativity-characterize uvm-check-env uvm-compile uvm-smoke uvm-runtime-smoke coherent-lint coherent-rv32-smoke coherent-litmus-check coherent-rtl-litmus-check coherent-herd-check coherent-gcc-check coherent-random-check coherent-store-buffer-check coherent-replacement-check coherent-mmio-order-check coherent-reference-check coherent-crossover-check coherent-error-reset-check coherent-qos-concurrency-check coherent-advanced-coverage coherent-assertion-coverage coherent-coverage-review coherent-coverage-edges coherent-formal-prove coherent-mutation-check coherent-code-coverage coherent-performance coherent-dashboard coherent-release-check project-check release-check clean

lint:
	$(VERILATOR) --lint-only --sv --timing --assert -Wall \
		-Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET \
		rtl/dcache_pkg.sv rtl/l1_dcache_top.sv \
		sim/assertions/dcache_protocol_assertions.sv \
		sim/monitors/dcache_trace_observer.sv sim/tb_l1_dcache.sv
	$(VERILATOR) --lint-only --sv --timing --assert -Wall \
		-Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET \
		rtl/l1_dcache_nonblocking.sv

smoke:
	$(PYTHON) scripts/run_regression.py --tests smoke

regress:
	$(PYTHON) scripts/run_regression.py

coverage: ras-check
	$(PYTHON) scripts/run_regression.py --coverage
	$(PYTHON) scripts/gen_code_coverage.py
	$(PYTHON) scripts/gen_coverage_hole_review.py

coverage-edges:
	$(PYTHON) scripts/run_coverage_edges.py
	$(PYTHON) scripts/gen_code_coverage.py
	$(PYTHON) scripts/gen_coverage_hole_review.py

functional-coverage: regress
	$(PYTHON) scripts/gen_coverage_report.py

performance: performance-sweep

performance-sweep: regress
	$(PYTHON) scripts/run_performance_sweep.py

cache-cross-coverage: regress performance-sweep
	$(PYTHON) scripts/run_cross_scenarios.py
	$(PYTHON) scripts/gen_cross_coverage.py

stress-manifest:
	$(PYTHON) scripts/gen_stress_manifest.py --count 100

stress: regress stress-manifest
	$(PYTHON) scripts/run_stress.py

random-stress: stress
	$(PYTHON) scripts/run_model_trace.py --traces 'stress_*.csv'

model-trace-check: regress
	$(PYTHON) scripts/run_model_trace.py --summary reports/regress_summary.csv

bug-validate:
	$(PYTHON) scripts/run_bug_validation.py

debug-waveform:
	$(PYTHON) scripts/gen_debug_waveform.py

docs-check:
	$(PYTHON) scripts/check_docs.py

readme-metrics:
	$(PYTHON) scripts/gen_metrics.py
	$(PYTHON) scripts/update_readme_metrics.py

model-test:
	mkdir -p build/model
	$(CXX) -std=c++17 -Wall -Wextra -Werror -O2 model/cache_reference.cpp model/cache_reference_test.cpp -o build/model/cache_reference_test
	./build/model/cache_reference_test

ras-check: model-test
	$(PYTHON) scripts/run_ras.py

coherence-check:
	$(PYTHON) scripts/run_integration_features.py coherence
	$(PYTHON) scripts/run_msi_random.py --seeds 25
	$(PYTHON) scripts/run_msi_mutations.py

bist-check:
	$(PYTHON) scripts/run_integration_features.py bist
	$(PYTHON) scripts/run_cache_array_bist.py

integration-check: coherence-check bist-check

integration-synth-check:
	$(PYTHON) scripts/run_integration_synthesis.py

nonblocking-cache-check:
	$(PYTHON) scripts/run_nonblocking_cache.py

coherent-lint:
	verilator --lint-only --sv --timing --assert -Wall \
		-Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET -Wno-PINCONNECTEMPTY \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT --top-module tb_coherent_closure \
		rtl/coherence/msi_two_cache_subsystem.sv \
		integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv \
		integration/rv32_coherent/vendor/axi/qos_arbiter.sv \
		integration/rv32_coherent/vendor/axi/axi4_qos_fabric.sv \
		integration/rv32_coherent/rtl/coherent_axi_qos_transport.sv \
		integration/rv32_coherent/rtl/banked_msi_home.sv \
		integration/rv32_coherent/sim/tb_coherent_closure.sv

coherent-rv32-smoke:
	$(PYTHON) scripts/run_coherent_rv32.py smoke

coherent-litmus-check:
	$(PYTHON) scripts/run_coherent_model.py litmus

coherent-rtl-litmus-check:
	$(PYTHON) scripts/run_coherent_rtl_litmus.py

coherent-herd-check:
	$(PYTHON) scripts/run_coherent_herd.py --require

coherent-gcc-check:
	$(PYTHON) scripts/run_coherent_rv32.py gcc

coherent-random-check:
	$(PYTHON) scripts/run_coherent_model.py random

coherent-store-buffer-check coherent-replacement-check coherent-mmio-order-check coherent-reference-check:
	$(PYTHON) scripts/run_coherent_closure.py

coherent-crossover-check: coherent-store-buffer-check coherent-error-reset-check coherent-qos-concurrency-check
	$(PYTHON) scripts/gen_coherent_closure_summary.py

coherent-advanced-coverage: coherent-crossover-check
	$(PYTHON) scripts/gen_coherent_advanced_coverage.py

coherent-assertion-coverage: coherent-advanced-coverage
	$(PYTHON) scripts/gen_coherent_assertion_activation.py

coherent-coverage-review:
	$(PYTHON) scripts/check_coherent_coverage_review.py

coherent-error-reset-check:
	$(PYTHON) scripts/run_coherent_error_reset.py

coherent-qos-concurrency-check:
	$(PYTHON) scripts/run_coherent_transport_edges.py

coherent-coverage-edges:
	$(PYTHON) scripts/run_coherent_coverage_edges.py

coherent-formal-prove:
	$(PYTHON) scripts/run_coherent_formal.py

coherent-mutation-check:
	$(PYTHON) scripts/run_coherent_model.py mutations
	$(PYTHON) scripts/run_coherent_rtl_mutations.py

coherent-performance:
	$(PYTHON) scripts/run_coherent_model.py performance
	$(PYTHON) scripts/run_coherent_performance_rtl.py

coherent-code-coverage:
	$(PYTHON) scripts/run_coherent_code_coverage.py

coherent-dashboard:
	$(PYTHON) scripts/gen_coherent_coverage.py
	$(PYTHON) scripts/gen_coherent_dashboard.py

coherent-release-check: coherent-lint coherent-rv32-smoke coherent-gcc-check coherent-herd-check coherent-rtl-litmus-check coherent-litmus-check coherent-random-check coherent-crossover-check coherent-advanced-coverage coherent-assertion-coverage coherent-coverage-edges coherent-formal-prove coherent-mutation-check coherent-code-coverage coherent-coverage-review coherent-performance
	$(PYTHON) scripts/gen_coherent_coverage.py
	$(PYTHON) scripts/gen_coherent_dashboard.py
	$(PYTHON) scripts/gen_metrics.py
	$(PYTHON) scripts/update_readme_metrics.py
	$(PYTHON) scripts/check_docs.py

formal:
	@if command -v sby >/dev/null 2>&1; then sby -f formal/cache_safety.sby; \
	else echo "SKIP: SymbiYosys (sby) is not installed"; fi

formal-prove:
	$(PYTHON) scripts/run_formal.py

formal-small-prove:
	$(PYTHON) scripts/run_formal.py --only small

formal-cover:
	$(PYTHON) scripts/run_formal.py --only cover

formal-mutations:
	$(PYTHON) scripts/run_formal.py --only mutations

associativity-check:
	$(PYTHON) scripts/run_associativity.py check

associativity-characterize:
	$(PYTHON) scripts/run_associativity.py characterize

synth-characterize:
	$(PYTHON) scripts/run_synthesis_characterization.py

uvm-check-env:
	$(PYTHON) scripts/check_uvm_env.py

uvm-compile: uvm-check-env
	$(PYTHON) scripts/run_uvm.py --compile-only

uvm-smoke: uvm-check-env
	$(PYTHON) scripts/run_uvm.py

uvm-runtime-smoke: uvm-check-env
	$(PYTHON) scripts/run_uvm.py --runtime-smoke

project-check: lint model-test regress model-trace-check functional-coverage performance stress-manifest integration-check
	$(PYTHON) scripts/gen_metrics.py
	$(PYTHON) scripts/update_readme_metrics.py

release-check: project-check random-stress cache-cross-coverage performance-sweep bug-validate debug-waveform coverage coverage-edges associativity-check synth-characterize associativity-characterize ras-check integration-synth-check nonblocking-cache-check
	$(PYTHON) scripts/run_model_trace.py --traces '*.csv'
	$(PYTHON) scripts/gen_metrics.py
	$(PYTHON) scripts/update_readme_metrics.py
	$(PYTHON) scripts/check_docs.py

clean:
	rm -rf build
