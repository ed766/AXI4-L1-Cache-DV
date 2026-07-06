#!/usr/bin/env python3
from __future__ import annotations
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "verilator" / "Vtb_l1_dcache"
TRACE = ROOT / "build" / "verilator" / "traces" / "cross_matrix.csv"
TRACE.parent.mkdir(parents=True, exist_ok=True)
result = subprocess.run([str(BINARY), "+TEST=cross_matrix", "+MODEL_FINAL_FLUSH",
                         f"+TRACE_FILE={TRACE}"],
                        cwd=ROOT, text=True, capture_output=True)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
