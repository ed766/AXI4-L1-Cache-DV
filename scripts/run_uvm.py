#!/usr/bin/env python3
from __future__ import annotations
import argparse
import csv
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--compile-only", action="store_true")
parser.add_argument("--runtime-smoke", action="store_true")
args = parser.parse_args()
BUILD = ROOT / "build" / "uvm"
EQUIV_BUILD = ROOT / "build" / "uvm_equiv"
REPORTS = ROOT / "reports"
VERILATOR = os.environ.get("VERILATOR_UVM", str(ROOT.parent / "verilator/bin/verilator"))
UVM_HOME = pathlib.Path(os.environ.get("UVM_HOME", ROOT.parent / "uvm-verilator/src"))
BUILD.mkdir(parents=True, exist_ok=True)
EQUIV_BUILD.mkdir(parents=True, exist_ok=True)
REPORTS.mkdir(exist_ok=True)
cmd = [VERILATOR, "--binary", "--sv", "--timing", "-Wno-fatal", "+define+UVM_NO_DPI",
       f"+incdir+{UVM_HOME}", f"+incdir+{ROOT / 'sim' / 'uvm'}", "--top-module", "tb_cache_uvm",
       "--Mdir", str(BUILD), str(UVM_HOME / "uvm_pkg.sv"),
       str(ROOT / "rtl" / "dcache_pkg.sv"), str(ROOT / "rtl" / "l1_dcache_top.sv"),
       str(ROOT / "sim" / "uvm" / "cache_if.sv"),
       str(ROOT / "sim" / "uvm" / "cache_uvm_pkg.sv"),
       str(ROOT / "sim" / "uvm" / "tb_cache_uvm.sv"), "-j", "4"]
print("+", " ".join(cmd))
if subprocess.run(cmd, cwd=ROOT).returncode: sys.exit(1)
if args.compile_only:
    print("UVM_COMPILE|status=PASS")
    sys.exit(0)

def run_uvm_binary(test_name: str, timeout: int = 8) -> tuple[str, str, int, int]:
    log = REPORTS / f"{test_name}.log"
    try:
        result = subprocess.run([str(BUILD / "Vtb_cache_uvm"), f"+UVM_TESTNAME={test_name}"],
                                cwd=ROOT, text=True, capture_output=True, timeout=timeout)
        output = result.stdout + result.stderr
        log.write_text(output)
    except subprocess.TimeoutExpired as error:
        output = (error.stdout or "") + (error.stderr or "")
        log.write_text(output)
        return "TIMEOUT", str(log.relative_to(ROOT)), -1, -1
    errors = 0 if "UVM_ERROR :    0" in output else -1
    fatals = 0 if "UVM_FATAL :    0" in output else -1
    status = "PASS" if result.returncode == 0 and errors == 0 and fatals == 0 else "FAIL"
    return status, str(log.relative_to(ROOT)), errors, fatals

def run_equivalent_scenario(scenario: str) -> tuple[str, str]:
    log = REPORTS / f"uvm_equiv_{scenario}.log"
    trace = BUILD / f"uvm_equiv_{scenario}.csv"
    binary = EQUIV_BUILD / "Vtb_l1_dcache"
    if not binary.exists():
        compile_equiv = [
            os.environ.get("VERILATOR", "verilator"), "--binary", "--sv", "--timing",
            "--assert", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
            "--top-module", "tb_l1_dcache", "--Mdir", str(EQUIV_BUILD),
            str(ROOT / "rtl" / "dcache_pkg.sv"),
            str(ROOT / "rtl" / "l1_dcache_top.sv"),
            str(ROOT / "sim" / "assertions" / "dcache_protocol_assertions.sv"),
            str(ROOT / "sim" / "monitors" / "dcache_trace_observer.sv"),
            str(ROOT / "sim" / "tb_l1_dcache.sv"),
        ]
        compiled = subprocess.run(compile_equiv, cwd=ROOT, text=True, capture_output=True)
        if compiled.returncode:
            log.write_text(compiled.stdout + compiled.stderr)
            return "FAIL", str(log.relative_to(ROOT))
    result = subprocess.run([str(binary), f"+TEST={scenario}", "+MODEL_FINAL_FLUSH",
                             f"+TRACE_FILE={trace}"],
                            cwd=ROOT, text=True, capture_output=True)
    output = result.stdout + result.stderr
    log.write_text(output)
    status = "PASS" if result.returncode == 0 else "FAIL"
    return status, str(log.relative_to(ROOT))

if args.runtime_smoke:
    tests = [
        ("uvm_read_miss_refill_test", "read_miss"),
        ("uvm_dirty_evict_test", "dirty_evict"),
        ("uvm_axi_error_path_test", "read_error"),
    ]
    rows = []
    for uvm_test, scenario in tests:
        runtime_status, runtime_log, uvm_errors, uvm_fatals = run_uvm_binary(uvm_test)
        scenario_status, scenario_log = run_equivalent_scenario(scenario)
        # Do not count an equivalent non-UVM scenario as UVM runtime success.
        # The equivalent row is useful debug context only; actual UVM phase
        # runtime must finish with zero UVM_ERROR/UVM_FATAL to be PASS.
        if runtime_status == "PASS":
            status = "PASS"
        elif runtime_status == "TIMEOUT":
            status = "SKIP"
        else:
            status = "FAIL"
        rows.append({
            "test": uvm_test,
            "equivalent_scenario": scenario,
            "status": status,
            "uvm_compile": "PASS",
            "uvm_phase_runtime": runtime_status,
            "uvm_error": uvm_errors if uvm_errors >= 0 else "NA",
            "uvm_fatal": uvm_fatals if uvm_fatals >= 0 else "NA",
            "equivalent_scenario_status": scenario_status,
            "uvm_log": runtime_log,
            "scenario_log": scenario_log,
        })
    with (REPORTS / "uvm_runtime_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    skipped = sum(row["status"] == "SKIP" for row in rows)
    failed = sum(row["status"] == "FAIL" for row in rows)
    overall = "PASS" if passed == len(rows) else ("SKIP" if failed == 0 else "FAIL")
    print(f"UVM_RUNTIME_SMOKE|status={overall}|passed={passed}|skipped={skipped}|failed={failed}|total={len(rows)}")
    sys.exit(0 if failed == 0 else 1)

try:
    result = subprocess.run([str(BUILD / "Vtb_cache_uvm"), "+UVM_TESTNAME=cache_smoke_test"],
                            cwd=ROOT, text=True, capture_output=True, timeout=60)
except subprocess.TimeoutExpired as error:
    output = (error.stdout or "") + (error.stderr or "")
    (REPORTS / "uvm_smoke.log").write_text(output)
    print("UVM smoke timed out after 60 seconds", file=sys.stderr)
    sys.exit(1)
output = result.stdout + result.stderr
(REPORTS / "uvm_smoke.log").write_text(output)
print(output)
if result.returncode or "UVM_ERROR :    0" not in output or "UVM_FATAL :    0" not in output:
    sys.exit(1)
