PYTHON ?= python3
VERILATOR ?= verilator

.PHONY: lint smoke regress coverage functional-coverage performance stress-manifest stress bug-validate model-test formal uvm-check-env uvm-compile uvm-smoke project-check clean

lint:
	$(VERILATOR) --lint-only --sv --timing --assert -Wall -Wno-fatal \
		-Wno-UNUSEDSIGNAL -Wno-BLKSEQ -Wno-SYNCASYNCNET \
		rtl/dcache_pkg.sv rtl/l1_dcache_top.sv \
		sim/assertions/dcache_protocol_assertions.sv sim/tb_l1_dcache.sv

smoke:
	$(PYTHON) scripts/run_regression.py --tests smoke

regress:
	$(PYTHON) scripts/run_regression.py

coverage:
	$(PYTHON) scripts/run_regression.py --coverage
	$(PYTHON) scripts/gen_code_coverage.py

functional-coverage: regress
	$(PYTHON) scripts/gen_coverage_report.py

performance: regress
	$(PYTHON) scripts/gen_performance_report.py

stress-manifest:
	$(PYTHON) scripts/gen_stress_manifest.py --count 100

stress: regress stress-manifest
	$(PYTHON) scripts/run_stress.py

bug-validate:
	$(PYTHON) scripts/run_bug_validation.py

model-test:
	mkdir -p build/model
	$(CXX) -std=c++17 -Wall -Wextra -Werror -O2 model/cache_reference.cpp model/cache_reference_test.cpp -o build/model/cache_reference_test
	./build/model/cache_reference_test

formal:
	@if command -v sby >/dev/null 2>&1; then sby -f formal/cache_safety.sby; \
	else echo "SKIP: SymbiYosys (sby) is not installed"; fi

uvm-check-env:
	$(PYTHON) scripts/check_uvm_env.py

uvm-compile: uvm-check-env
	$(PYTHON) scripts/run_uvm.py --compile-only

uvm-smoke: uvm-check-env
	$(PYTHON) scripts/run_uvm.py

project-check: lint model-test regress functional-coverage performance stress-manifest
	$(PYTHON) scripts/gen_metrics.py

clean:
	rm -rf build
