#!/usr/bin/env python3
from __future__ import annotations
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
verilator = pathlib.Path(os.environ.get("VERILATOR_UVM", root.parent / "verilator/bin/verilator"))
uvm_home = pathlib.Path(os.environ.get("UVM_HOME", root.parent / "uvm-verilator/src"))
errors = []
if not verilator.is_file(): errors.append(f"VERILATOR_UVM executable missing: {verilator}")
if not (uvm_home / "uvm_pkg.sv").is_file(): errors.append(f"UVM package missing: {uvm_home / 'uvm_pkg.sv'}")
if errors:
    print("\n".join(f"ERROR: {error}" for error in errors))
    sys.exit(1)
version = subprocess.check_output([str(verilator), "--version"], text=True).strip()
print(f"UVM_ENV|status=PASS|verilator={version}|uvm_home={uvm_home}")
