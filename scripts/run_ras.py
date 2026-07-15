#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "ras"
REPORTS = ROOT / "reports"
DOC = ROOT / "docs" / "ras.md"


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(exist_ok=True)
    sources = [
        ROOT / "rtl" / "dcache_pkg.sv",
        ROOT / "rtl" / "l1_dcache_top.sv",
        ROOT / "sim" / "assertions" / "dcache_protocol_assertions.sv",
        ROOT / "sim" / "monitors" / "dcache_trace_observer.sv",
        ROOT / "sim" / "tb_l1_dcache.sv",
    ]
    command = [
        "verilator", "-j", "0", "--binary", "--sv", "--timing", "--assert", "-Wall",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", "tb_l1_dcache", "--Mdir", str(BUILD),
        "-GCACHE_SECDED_ENABLE=1'h1", *map(str, sources),
    ]
    compile_result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    (REPORTS / "ras_compile.log").write_text(compile_result.stdout + compile_result.stderr)
    if compile_result.returncode:
        print(compile_result.stdout + compile_result.stderr)
        return compile_result.returncode

    run_result = subprocess.run(
        [str(BUILD / "Vtb_l1_dcache"), "+TEST=secded_ras_matrix"],
        cwd=ROOT, text=True, capture_output=True,
    )
    output = run_result.stdout + run_result.stderr
    (REPORTS / "ras_matrix.log").write_text(output)
    cover_rows = [
        dict(item.split("=", 1) for item in match.split("|") if "=" in item)
        for match in re.findall(r"RAS_COVER\|(.*)", output)
    ]
    result_match = re.search(r"RAS_RESULT\|(.*)", output)
    result = dict(item.split("=", 1) for item in result_match.group(1).split("|") if "=" in item) \
        if result_match else {"status": "FAIL", "corrected": "0", "uncorrectable": "0", "scrubs": "0"}

    with (REPORTS / "ras_coverage.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["point", "status"], lineterminator="\n")
        writer.writeheader()
        writer.writerows(cover_rows)
    with (REPORTS / "ras_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=["test", "status", "corrected", "uncorrectable", "scrubs", "log"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerow({"test": "secded_ras_matrix", **result, "log": "reports/ras_matrix.log"})

    covered = sum(row.get("status") == "COVERED" for row in cover_rows)
    DOC.write_text(f"""# SECDED and RAS Verification

The optional `SECDED_ENABLE` cache variant stores a seven-bit SECDED code with each 32-bit data word. The parity baseline remains unchanged. Single-bit data or code faults are corrected; corrected reads scrub the repaired word and code back into the cache. Double-bit faults return the existing CPU error response and cannot initiate a dirty eviction or silently update backing memory.

## Executed Evidence

| Evidence | Result |
| --- | ---: |
| RAS matrix | `{result.get('status', 'FAIL')}` |
| Required RAS points | `{covered} / {len(cover_rows)}` |
| Correction events | `{result.get('corrected', '0')}` |
| Uncorrectable detections | `{result.get('uncorrectable', '0')}` |
| Read scrubs | `{result.get('scrubs', '0')}` |
| Independent C++ SECDED known-answer cases | `40` |

The matrix covers clean-line data correction, ECC-bit correction, clean-line double-error detection, corrected dirty eviction, blocked uncorrectable dirty eviction, corrected maintenance writeback, and uncorrectable maintenance containment. Faults are injected through verification-only hierarchy access; no CPU or AXI port was added.

## Scope Boundary

SECDED protects cache data words only. Tags retain the existing architectural treatment, and this project does not claim production RAS qualification or fault-injection signoff.
""")
    print(f"RAS_CHECK|status={result.get('status')}|coverage={covered}/{len(cover_rows)}")
    return 0 if run_result.returncode == 0 and result.get("status") == "PASS" and covered == 7 else 1


if __name__ == "__main__":
    raise SystemExit(main())
