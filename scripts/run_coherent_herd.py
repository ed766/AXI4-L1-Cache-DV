#!/usr/bin/env python3
"""Run the pinned herd7 binary over the checked-in RV32 litmus set."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LITMUS = ROOT / "integration" / "rv32_coherent" / "litmus"
REPORT = ROOT / "reports" / "coherent_herd_summary.csv"
ALLOWED = ROOT / "reports" / "coherent_herd_allowed_outcomes.json"


def locate() -> str | None:
    return (os.environ.get("HERD7") or shutil.which("herd7") or
            (str(ROOT / "build/coherent_external/herd-switch/_opam/bin/herd7")
             if (ROOT / "build/coherent_external/herd-switch/_opam/bin/herd7").exists() else None))


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--require", action="store_true"); args = parser.parse_args()
    subprocess.run(["python3", "scripts/gen_coherent_litmus_files.py"], cwd=ROOT, check=True)
    herd = locate()
    rows = []
    allowed_outcomes: dict[str, list[list[int]]] = {}
    if herd:
        from run_coherent_model import LITMUS as TESTS
        tests = {test.name: test for test in TESTS}
        for path in sorted(LITMUS.glob("*.litmus")):
            result = subprocess.run([herd, str(path)], cwd=ROOT, text=True, capture_output=True, timeout=60)
            output = result.stdout + result.stderr
            observed = next((line.strip() for line in output.splitlines() if line.startswith("Observation ")), "missing_observation")
            state_lines = []
            in_states = False
            for line in output.splitlines():
                if line.startswith("States "): in_states = True; continue
                if in_states and line.strip() == "Ok": break
                if in_states and line.strip(): state_lines.append(line.strip())
            test = tests[path.stem]
            h0_reads = sum(op.kind == "R" for op in test.hart0)
            h1_reads = sum(op.kind == "R" for op in test.hart1)
            reg0 = "x8" if h0_reads else None
            reg1 = f"x{7 + h1_reads}" if h1_reads else None
            pairs = set()
            for line in state_lines:
                values = {(int(h), reg): int(value, 0) for h, reg, value in
                          re.findall(r"([01]):(x\d+)=(-?(?:0x[0-9a-fA-F]+|\d+))", line)}
                pairs.add((values.get((0, reg0), 0) if reg0 else 0,
                           values.get((1, reg1), 0) if reg1 else 0))
            allowed_outcomes[path.stem] = [list(pair) for pair in sorted(pairs)]
            passed = result.returncode == 0 and observed != "missing_observation" and bool(pairs)
            rows.append({"litmus": path.stem, "status": "PASS" if passed else "FAIL",
                         "allowed_outcomes": str(len(pairs)), "observation": observed})
    else:
        rows = [{"litmus": path.stem, "status": "FAIL" if args.require else "SKIP",
                 "allowed_outcomes": "0", "observation": "herd7_unavailable"}
                for path in sorted(LITMUS.glob("*.litmus"))]
    REPORT.parent.mkdir(exist_ok=True)
    with REPORT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n"); writer.writeheader(); writer.writerows(rows)
    ALLOWED.write_text(json.dumps(allowed_outcomes, indent=2, sort_keys=True) + "\n")
    expected = "PASS" if herd else ("FAIL" if args.require else "SKIP")
    good = all(row["status"] == expected for row in rows)
    print(f"COHERENT_HERD|status={'PASS' if herd and good else expected}|tests={sum(r['status']=='PASS' for r in rows)}/{len(rows)}")
    return 0 if good and (herd or not args.require) else 1


if __name__ == "__main__": raise SystemExit(main())
