#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
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
    memory_cells = re.findall(r"\$mem_v2\s+([0-9]+)", text)
    return {
        "cell_count": cells[-1] if cells else "NA",
        "wire_bits": wires[-1] if wires else "NA",
        "memory_count": memory_cells[-1] if memory_cells else "0",
        "memory_bits": "NA",
        "area_proxy": "NA",
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

    proxy = work / "cache_geometry_proxy.sv"
    proxy.write_text(f"""module cache_geometry_proxy (
  input logic clk,
  input logic access_valid,
  input logic fill_valid,
  input logic [31:0] address,
  input logic [255:0] fill_line,
  input logic fill_dirty,
  output logic hit,
  output logic victim_way,
  output logic [255:0] read_line
);
  localparam integer SETS = {sets};
  localparam integer WAYS = {ways};
  localparam integer INDEX_BITS = $clog2(SETS);
  localparam integer TAG_BITS = 32 - INDEX_BITS - 5;
  localparam integer LINES = SETS * WAYS;
  logic [TAG_BITS+1:0] metadata [0:LINES-1];
  logic [255:0] data_array [0:LINES-1];
  logic lru [0:SETS-1];
  logic [INDEX_BITS-1:0] set_index;
  logic [TAG_BITS-1:0] request_tag;
  logic hit0, hit1;
  integer index0, index1, selected_index;

  always_comb begin
    set_index = address[5 + INDEX_BITS - 1:5];
    request_tag = address[31:5 + INDEX_BITS];
    index0 = set_index;
    index1 = SETS + set_index;
    hit0 = metadata[index0][TAG_BITS] && metadata[index0][TAG_BITS-1:0] == request_tag;
    hit1 = WAYS == 2 && metadata[index1][TAG_BITS] && metadata[index1][TAG_BITS-1:0] == request_tag;
    hit = hit0 || hit1;
    if (WAYS == 1 || !metadata[index0][TAG_BITS]) victim_way = 1'b0;
    else if (!metadata[index1][TAG_BITS]) victim_way = 1'b1;
    else victim_way = lru[set_index];
    selected_index = (hit1 || (!hit && victim_way)) ? index1 : index0;
    read_line = data_array[selected_index];
  end

  always_ff @(posedge clk) begin
    if (access_valid && hit && WAYS == 2) lru[set_index] <= hit0;
    if (fill_valid) begin
      metadata[selected_index] <= {{fill_dirty, 1'b1, request_tag}};
      data_array[selected_index] <= fill_line;
      if (WAYS == 2) lru[set_index] <= ~victim_way;
    end
  end
endmodule
""")
    script = work / "synth.ys"
    script.write_text(f"""
read_verilog -sv {proxy}
hierarchy -top cache_geometry_proxy
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
    tag_bits = 32 - int(math.log2(sets)) - 5
    storage_bits = sets * ways * (256 + tag_bits + 2) + (sets if ways == 2 else 0)
    parsed["memory_bits"] = str(storage_bits)
    if parsed["cell_count"] != "NA":
        parsed["area_proxy"] = str(int(parsed["cell_count"]) + math.ceil(storage_bits / 64))
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

This report compares equal-capacity cache geometries using a Yosys storage/control proxy with tag/data arrays, parallel way lookup, dirty metadata, victim selection, and LRU state. Behavioral results use the full cache RTL. This is not timing closure, physical design, or commercial signoff.

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
- `memory_bits` is the architectural data/tag/valid/dirty/LRU storage represented by Yosys `$mem_v2` cells.
- `area_proxy` is `logic cells + ceil(memory_bits / 64)` so inferred memories contribute to the comparison without pretending to use a foundry area library.
- `timing_proxy` remains `NA` unless a timing engine/library is available.
- The proxy isolates associativity cost from the full cache FSM and optional SECDED implementation; it is not whole-cache synthesis.
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
