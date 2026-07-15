#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "synthesis"
REPORTS = ROOT / "reports"
DOCS = ROOT / "docs"

VARIANTS = (
    {"geometry": "direct_mapped", "sets": 128, "ways": 1},
    {"geometry": "two_way", "sets": 64, "ways": 2},
)


def parse_yosys_stat(text: str) -> dict[str, str]:
    cells = re.findall(r"Number of cells:\s+([0-9]+)", text)
    wires = re.findall(r"Number of wire bits:\s+([0-9]+)", text)
    memories = re.findall(r"Number of memories:\s+([0-9]+)", text)
    memory_bits = re.findall(r"Number of memory bits:\s+([0-9]+)", text)
    return {
        "cell_count": cells[-1] if cells else "NA",
        "wire_bits": wires[-1] if wires else "NA",
        "memory_count": memories[-1] if memories else "NA",
        "memory_bits": memory_bits[-1] if memory_bits else "NA",
        "area_proxy": cells[-1] if cells else "NA",
        "timing_proxy": "NA",
    }


def run_variant(yosys: str | None, variant: dict[str, int | str]) -> dict[str, str]:
    geometry = str(variant["geometry"])
    sets = int(variant["sets"])
    ways = int(variant["ways"])
    work = BUILD / geometry
    work.mkdir(parents=True, exist_ok=True)
    log = work / "yosys.log"
    if yosys is None:
        log.write_text("SKIP: yosys not found in PATH\n")
        return {
            "geometry": geometry,
            "sets": str(sets),
            "ways": str(ways),
            "status": "SKIP",
            "cell_count": "NA",
            "wire_bits": "NA",
            "memory_count": "NA",
            "memory_bits": "NA",
            "area_proxy": "NA",
            "timing_proxy": "NA",
            "log": str(log.relative_to(ROOT)),
        }

    script = work / "synth.ys"
    script.write_text(f"""
read_verilog -sv -D FORMAL -D SYNTHESIS rtl/l1_dcache_top.sv
chparam -set SETS {sets} -set WAYS {ways} l1_dcache_top
hierarchy -top l1_dcache_top
proc
memory -nomap
opt
stat
""")
    result = subprocess.run([yosys, "-s", str(script)], cwd=ROOT,
                            text=True, capture_output=True)
    output = result.stdout + result.stderr
    log.write_text(output)
    parsed = parse_yosys_stat(output)
    return {
        "geometry": geometry,
        "sets": str(sets),
        "ways": str(ways),
        "status": "PASS" if result.returncode == 0 else "FAIL",
        **parsed,
        "log": str(log.relative_to(ROOT)),
    }


def write_docs(rows: list[dict[str, str]]) -> None:
    DOCS.mkdir(exist_ok=True)
    text = """# Synthesis Characterization

This report compares equal-capacity cache variants using Yosys as an open-source implementation proxy. It is not timing closure, physical design, or commercial signoff.

| Geometry | Sets | Ways | Status | Cell count | Wire bits | Memories | Memory bits | Area proxy | Timing proxy |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
"""
    for row in rows:
        text += (f"| `{row['geometry']}` | {row['sets']} | {row['ways']} | {row['status']} | "
                 f"{row['cell_count']} | {row['wire_bits']} | {row['memory_count']} | "
                 f"{row['memory_bits']} | {row['area_proxy']} | {row['timing_proxy']} |\n")
    text += """

## Interpretation

- The direct-mapped and 2-way variants both model 4 KiB capacity with 32-byte lines.
- `area_proxy` is the Yosys cell-count proxy when no Liberty area data is available.
- `timing_proxy` remains `NA` unless a timing engine/library is available.
- `SKIP` means Yosys was not installed in the local environment; CI installs Yosys for release evidence.
"""
    (DOCS / "synthesis_characterization.md").write_text(text)


def main() -> int:
    REPORTS.mkdir(exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    yosys = shutil.which("yosys")
    rows = [run_variant(yosys, variant) for variant in VARIANTS]
    with (REPORTS / "synthesis_characterization.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    write_docs(rows)
    failed = [row for row in rows if row["status"] == "FAIL"]
    passed = sum(row["status"] == "PASS" for row in rows)
    skipped = sum(row["status"] == "SKIP" for row in rows)
    overall = "FAIL" if failed else ("PASS" if passed == len(rows) else "SKIP")
    print(f"SYNTH_CHARACTERIZE|status={overall}|passed={passed}|skipped={skipped}|total={len(rows)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
