#!/usr/bin/env python3
from __future__ import annotations
import argparse
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--compile-only", action="store_true")
args = parser.parse_args()
BUILD = ROOT / "build" / "uvm"
VERILATOR = os.environ.get("VERILATOR_UVM", str(ROOT.parent / "verilator/bin/verilator"))
UVM_HOME = pathlib.Path(os.environ.get("UVM_HOME", ROOT.parent / "uvm-verilator/src"))
BUILD.mkdir(parents=True, exist_ok=True)
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
try:
    result = subprocess.run([str(BUILD / "Vtb_cache_uvm"), "+UVM_TESTNAME=cache_smoke_test"],
                            cwd=ROOT, text=True, capture_output=True, timeout=60)
except subprocess.TimeoutExpired as error:
    output = (error.stdout or "") + (error.stderr or "")
    (ROOT / "reports").mkdir(exist_ok=True)
    (ROOT / "reports" / "uvm_smoke.log").write_text(output)
    print("UVM smoke timed out after 60 seconds", file=sys.stderr)
    sys.exit(1)
output = result.stdout + result.stderr
(ROOT / "reports").mkdir(exist_ok=True)
(ROOT / "reports" / "uvm_smoke.log").write_text(output)
print(output)
if result.returncode or "UVM_ERROR :    0" not in output or "UVM_FATAL :    0" not in output:
    sys.exit(1)
