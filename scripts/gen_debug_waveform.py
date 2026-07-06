#!/usr/bin/env python3
from __future__ import annotations

import csv
import html
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "debug_wlast"
TRACE = BUILD / "wlast_early_trace.csv"
FST = BUILD / "wlast_early.fst"
LOG = BUILD / "wlast_early.log"
IMAGE = ROOT / "docs" / "images" / "wlast_early_debug.svg"
REPORT = ROOT / "reports" / "debug_waveform_summary.csv"

BUILD.mkdir(parents=True, exist_ok=True)
IMAGE.parent.mkdir(parents=True, exist_ok=True)
sources = [
    ROOT / "rtl" / "dcache_pkg.sv",
    ROOT / "rtl" / "l1_dcache_top.sv",
    ROOT / "sim" / "assertions" / "dcache_protocol_assertions.sv",
    ROOT / "sim" / "monitors" / "dcache_trace_observer.sv",
    ROOT / "sim" / "tb_l1_dcache.sv",
]
compile_cmd = [
    "verilator", "--binary", "--sv", "--timing", "--assert", "--trace-fst",
    "--trace-structs", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ",
    "-Wno-SYNCASYNCNET", "+define+CACHE_BUG_WLAST_EARLY",
    "--top-module", "tb_l1_dcache", "--Mdir", str(BUILD),
    *map(str, sources),
]
subprocess.run(compile_cmd, cwd=ROOT, check=True)
run = subprocess.run([
    str(BUILD / "Vtb_l1_dcache"), "+TEST=dirty_evict",
    "+TRACE_FLUSH", f"+TRACE_FILE={TRACE}", f"+WAVE_FILE={FST}",
], cwd=ROOT, text=True, capture_output=True)
LOG.write_text(run.stdout + run.stderr)
if run.returncode == 0:
    raise SystemExit("early-WLAST mutation unexpectedly passed")
if "a_wlast_exactly_final_beat" not in LOG.read_text():
    raise SystemExit("expected a_wlast_exactly_final_beat failure was not observed")
if not FST.is_file() or FST.stat().st_size == 0:
    raise SystemExit("Verilator did not generate the expected FST waveform")

with TRACE.open() as handle:
    events = list(csv.DictReader(handle))
early = next((row for row in events if row["event"] == "AXI_W" and
              int(row["resp"]) == 1 and int(row["beat"]) < 3), None)
if early is None:
    previous = next((row for row in reversed(events) if row["event"] == "AXI_W"), None)
    if previous is None or int(previous["beat"]) != 1:
        raise SystemExit("trace did not reach the writeback beat before the assertion")
    failure_cycle = int(previous["cycle"]) + 1
    early_beat = 2
else:
    failure_cycle = int(early["cycle"])
    early_beat = int(early["beat"])
start = max(0, failure_cycle - 5)
cycles = list(range(start, failure_cycle + 3))
by_cycle: dict[int, list[dict[str, str]]] = {cycle: [] for cycle in cycles}
for row in events:
    cycle = int(row["cycle"])
    if cycle in by_cycle:
        by_cycle[cycle].append(row)

state_names = {
    0: "IDLE", 1: "LOOKUP", 2: "WB_AW", 3: "WB_W", 4: "WB_B",
    5: "REFILL_AR", 6: "REFILL_R", 7: "REFILL_FIN", 8: "REPLAY",
    9: "RESPONSE", 10: "MAINT_SCAN", 11: "MAINT_AW", 12: "MAINT_W",
    13: "MAINT_B",
}

def event_at(cycle: int, name: str) -> dict[str, str] | None:
    return next((row for row in by_cycle[cycle] if row["event"] == name), None)

rows = ["state", "AW handshake", "W handshake", "writeback beat", "WLAST",
        "B handshake", "CPU response", "assertion failure"]
cell_w, row_h, left, top = 82, 34, 150, 64
width = left + len(cycles) * cell_w + 20
height = top + len(rows) * row_h + 35
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       f'<rect width="{width}" height="{height}" fill="#f7f3ea"/>',
       '<g font-family="DejaVu Sans, sans-serif" fill="#18211d">',
       '<text x="18" y="26" font-size="17" font-weight="700">Early-WLAST mutation: assertion-driven debug</text>',
       '<text x="18" y="47" font-size="11">Highlighted cycle terminates a four-beat writeback at beat 2 instead of beat 3.</text>']
for index, cycle in enumerate(cycles):
    x = left + index * cell_w
    fill = "#f3c8bd" if cycle == failure_cycle else "#e8e2d5"
    svg.append(f'<rect x="{x}" y="{top - 22}" width="{cell_w}" height="{row_h * len(rows) + 22}" fill="{fill}" opacity="0.62"/>')
    svg.append(f'<text x="{x + cell_w / 2}" y="{top - 7}" text-anchor="middle" font-size="10">cycle {cycle}</text>')
for row_index, label in enumerate(rows):
    y = top + row_index * row_h
    svg.append(f'<text x="12" y="{y + 21}" font-size="11">{html.escape(label)}</text>')
    svg.append(f'<line x1="{left}" y1="{y + row_h}" x2="{width - 20}" y2="{y + row_h}" stroke="#c6bfb1"/>')
    for index, cycle in enumerate(cycles):
        x = left + index * cell_w
        cycle_events = by_cycle[cycle]
        if label == "state":
            prior = next((row for row in reversed(events) if int(row["cycle"]) <= cycle), None)
            value = state_names.get(int(prior["state"]), "-") if prior else "-"
        elif label == "AW handshake": value = "1" if event_at(cycle, "AXI_AW") else "0"
        elif label == "W handshake": value = "1" if event_at(cycle, "AXI_W") else "0"
        elif label == "writeback beat":
            event = event_at(cycle, "AXI_W")
            value = event["beat"] if event else (str(early_beat) if cycle == failure_cycle else "-")
        elif label == "WLAST":
            event = event_at(cycle, "AXI_W")
            value = event["resp"] if event else ("1" if cycle == failure_cycle else "0")
        elif label == "B handshake": value = "1" if event_at(cycle, "AXI_B") else "0"
        elif label == "CPU response": value = "1" if event_at(cycle, "CPU_RESPONSE") else "0"
        else: value = "FAIL" if cycle == failure_cycle else ""
        color = "#a62920" if value == "FAIL" else "#18211d"
        weight = "700" if value in ("1", "FAIL") else "400"
        svg.append(f'<text x="{x + cell_w / 2}" y="{y + 21}" text-anchor="middle" font-size="11" font-weight="{weight}" fill="{color}">{value}</text>')
svg.extend(['</g>', '</svg>'])
IMAGE.write_text("\n".join(svg) + "\n")

with REPORT.open("w", newline="") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow(["mutation", "test", "expected_assertion", "failure_cycle",
                     "early_beat", "fst", "trace", "image", "status"])
    writer.writerow(["CACHE_BUG_WLAST_EARLY", "dirty_evict",
                     "a_wlast_exactly_final_beat", failure_cycle, early_beat,
                     str(FST.relative_to(ROOT)), str(TRACE.relative_to(ROOT)),
                     str(IMAGE.relative_to(ROOT)), "DETECTED"])
print(f"DEBUG_WAVEFORM|status=PASS|cycle={failure_cycle}|beat={early_beat}")
