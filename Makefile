PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: lint smoke regress coverage coverage-edges functional-coverage performance performance-sweep cache-cross-coverage stress-manifest stress random-stress bug-validate debug-waveform docs-check model-test model-trace-check formal formal-prove formal-small-prove formal-cover formal-mutations synth-characterize associativity-check associativity-characterize uvm-check-env uvm-compile uvm-smoke uvm-runtime-smoke project-check release-check clean

lint:
	$(VERILATOR) --lint-only --sv --timing --assert -Wall \
		-Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET \
		rtl/dcache_pkg.sv rtl/l1_dcache_top.sv \
		sim/assertions/dcache_protocol_assertions.sv \
		sim/monitors/dcache_trace_observer.sv sim/tb_l1_dcache.sv

smoke:
	$(PYTHON) scripts/run_regression.py --tests smoke

regress:
	$(PYTHON) scripts/run_regression.py

coverage:
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

model-test:
	mkdir -p build/model
	$(CXX) -std=c++17 -Wall -Wextra -Werror -O2 model/cache_reference.cpp model/cache_reference_test.cpp -o build/model/cache_reference_test
	./build/model/cache_reference_test

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

project-check: lint model-test regress model-trace-check functional-coverage performance stress-manifest
	$(PYTHON) scripts/gen_metrics.py

release-check: project-check random-stress cache-cross-coverage performance-sweep bug-validate debug-waveform coverage associativity-check associativity-characterize
	$(PYTHON) scripts/run_model_trace.py --traces '*.csv'
	$(PYTHON) scripts/gen_metrics.py
	$(PYTHON) scripts/check_docs.py

clean:
	rm -rf build
