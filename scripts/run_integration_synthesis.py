#!/usr/bin/env python3
"""Generate Yosys implementation proxies for optional MSI and SRAM-BIST blocks."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {
    "msi_two_cache": ("msi_two_cache_subsystem", "rtl/coherence/msi_two_cache_subsystem.sv"),
    "cache_sram_bist": ("cache_sram_bist", "rtl/bist/cache_sram_bist.sv"),
}


def main() -> int:
    rows: list[dict[str, str]] = []
    yosys = shutil.which("yosys")
    build = ROOT / "build" / "integration_synth"
    build.mkdir(parents=True, exist_ok=True)
    for name, (top, source) in VARIANTS.items():
        if not yosys:
            rows.append({"variant": name, "status": "SKIP", "cells": "NA", "memory_bits": "NA"})
            continue
        if name == "msi_two_cache":
            parameters = f"chparam -set LINES 4 -set MEM_WORDS 64 {top}; "
        else:
            parameters = f"chparam -set WORDS 8 -set DATA_W 8 {top}; "
        script = (f"read_verilog -sv -DSYNTHESIS {source}; {parameters}"
                  f"hierarchy -check -top {top}; proc; memory -nomap; opt; stat")
        try:
            result = subprocess.run([yosys, "-p", script], cwd=ROOT, text=True,
                                    capture_output=True, timeout=120)
        except subprocess.TimeoutExpired as error:
            log = (error.stdout or "") + (error.stderr or "") + "\nTIMEOUT\n"
            (build / f"{name}.log").write_text(log)
            rows.append({"variant": name, "status": "FAIL", "cells": "NA", "memory_bits": "NA"})
            continue
        log = result.stdout + result.stderr
        (build / f"{name}.log").write_text(log)
        cell_matches = re.findall(r"Number of cells:\s+(\d+)", log)
        memory_matches = re.findall(r"Number of memory bits:\s+(\d+)", log)
        rows.append({
            "variant": name,
            "status": "PASS" if result.returncode == 0 else "FAIL",
            "cells": cell_matches[-1] if cell_matches else "NA",
            "memory_bits": memory_matches[-1] if memory_matches else "NA",
        })
    with (ROOT / "reports" / "integration_synthesis.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["variant", "status", "cells", "memory_bits"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    passed = all(row["status"] in {"PASS", "SKIP"} for row in rows)
    print(f"INTEGRATION_SYNTH|status={'PASS' if passed else 'FAIL'}|variants={sum(r['status'] == 'PASS' for r in rows)}/{len(rows)}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
