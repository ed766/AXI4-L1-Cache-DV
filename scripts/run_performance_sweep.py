#!/usr/bin/env python3
from __future__ import annotations

import csv
import math
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "verilator" / "Vtb_l1_dcache"
TRACE_DIR = ROOT / "build" / "verilator" / "traces"
REPORTS = ROOT / "reports"


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def events(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


TRACE_DIR.mkdir(parents=True, exist_ok=True)
REPORTS.mkdir(exist_ok=True)
latency_rows: list[dict[str, str | int]] = []
summary_rows: list[dict[str, str | int | float]] = []

for bp in (0, 25, 50, 75):
    trace = TRACE_DIR / f"performance_bp_{bp}.csv"
    command = [str(BINARY), "+TEST=performance_workload", "+SEED=20260703",
               "+OPS=100", "+READ_PCT=50", "+CONFLICT_PCT=75",
               f"+BP_PCT={bp}", "+ERROR_PCT=0", "+RESET_OP=-1",
               "+STROBE_PROFILE=mixed", "+ADDR_PROFILE=same-set",
               "+ADDR_BASE=00004000", "+ADDR_SPAN=00010000",
               f"+TRACE_FILE={trace}"]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    random_match = re.search(r"RANDOM_RESULT\|(.*)", result.stdout + result.stderr)
    stats = dict(item.split("=", 1) for item in random_match.group(1).split("|") if "=" in item)
    valid_cycles = int(stats.get("axi_valid", 0))
    stall_fraction = int(stats.get("axi_stalls", 0)) / valid_cycles if valid_cycles else 0.0

    pending: dict[int, dict[str, int | str]] = {}
    maint_pending: tuple[int, int] | None = None
    trace_events = events(trace)
    first_cycle = int(trace_events[0]["cycle"]) if trace_events else 0
    last_cycle = int(trace_events[-1]["cycle"]) if trace_events else first_cycle
    completed = 0
    for event in trace_events:
        cycle = int(event["cycle"])
        name = event["event"]
        event_id = int(event["id"])
        if name == "CPU_ACCEPT":
            pending[event_id] = {"start": cycle, "class": "unclassified"}
        elif name == "LOOKUP" and event_id in pending:
            if int(event["hit"]):
                pending[event_id]["class"] = "hit"
            elif int(event["valid"]) and int(event["dirty"]):
                pending[event_id]["class"] = "dirty-miss"
            else:
                pending[event_id]["class"] = "clean-miss"
        elif name == "CPU_RESPONSE" and event_id in pending:
            item = pending.pop(event_id)
            latency_rows.append({"backpressure_percent": bp, "kind": item["class"],
                                 "id": event_id, "latency_cycles": cycle - int(item["start"]),
                                 "error": int(event["error"]), "trace": str(trace.relative_to(ROOT))})
            completed += 1
        elif name == "MAINT_ACCEPT":
            maint_pending = (cycle, int(event["maint_cmd"]))
        elif name == "MAINT_DONE" and maint_pending:
            start, command_id = maint_pending
            names = ["maintenance-flush", "maintenance-invalidate",
                     "maintenance-flush-invalidate"]
            latency_rows.append({"backpressure_percent": bp, "kind": names[command_id],
                                 "id": -1, "latency_cycles": cycle - start,
                                 "error": int(event["error"]), "trace": str(trace.relative_to(ROOT))})
            maint_pending = None

    scenario_rows = [row for row in latency_rows if row["backpressure_percent"] == bp]
    throughput = completed / max(1, last_cycle - first_cycle + 1)
    for kind in sorted({str(row["kind"]) for row in scenario_rows}):
        values = [int(row["latency_cycles"]) for row in scenario_rows if row["kind"] == kind]
        summary_rows.append({"backpressure_percent": bp, "kind": kind, "count": len(values),
                             "mean": f"{sum(values) / len(values):.2f}",
                             "p50": percentile(values, 0.50), "p95": percentile(values, 0.95),
                             "max": max(values), "throughput_req_per_cycle": f"{throughput:.4f}",
                             "observed_stall_fraction": f"{stall_fraction:.4f}"})

with (REPORTS / "request_latency.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=latency_rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(latency_rows)
with (REPORTS / "performance_summary.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(summary_rows)

text = """# Per-Request Performance Characterization

These are behavioral Verilator cycle measurements, not silicon timing results. Latency runs from accepted request or maintenance command through accepted completion.

| Backpressure | Class | Samples | Mean | p50 | p95 | Max | Throughput | Observed stall fraction |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
"""
for row in summary_rows:
    text += (f"| {row['backpressure_percent']}% | `{row['kind']}` | {row['count']} | "
             f"{row['mean']} | {row['p50']} | {row['p95']} | {row['max']} | "
             f"{row['throughput_req_per_cycle']} | {row['observed_stall_fraction']} |\n")
text += """

## Interpretation

- Hit latency isolates cache-controller service without an AXI refill.
- Clean misses include a four-beat refill; dirty misses add a four-beat writeback and response first.
- Backpressure duty is applied deterministically to all AXI channels and reported from observed stalled-valid cycles.
- Maintenance latency includes the complete set/way scan and any required writebacks.
"""
(ROOT / "docs" / "performance.md").write_text(text)

images = ROOT / "docs" / "images"
images.mkdir(exist_ok=True)
clean = {int(row["backpressure_percent"]): int(row["p95"]) for row in summary_rows
         if row["kind"] == "clean-miss"}
dirty = {int(row["backpressure_percent"]): int(row["p95"]) for row in summary_rows
         if row["kind"] == "dirty-miss"}
throughput = {int(row["backpressure_percent"]): float(row["throughput_req_per_cycle"])
              for row in summary_rows if row["kind"] == "hit"}
levels = (0, 25, 50, 75)
max_latency = max([*clean.values(), *dirty.values()])

def points(values: dict[int, float], maximum: float, x0: int, y0: int,
           width: int, height: int) -> str:
    return " ".join(
        f"{x0 + index * width / 3:.1f},{y0 + height - values[level] * height / maximum:.1f}"
        for index, level in enumerate(levels)
    )

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="960" height="360" viewBox="0 0 960 360">
<rect width="960" height="360" fill="#f7f3ea"/>
<g font-family="DejaVu Sans, sans-serif" fill="#18211d">
  <text x="40" y="28" font-size="18" font-weight="700">Cache latency and throughput under AXI backpressure</text>
  <text x="40" y="52" font-size="12">Behavioral Verilator measurements; p95 request latency and accepted throughput</text>
  <line x1="65" y1="295" x2="445" y2="295" stroke="#56635d"/><line x1="65" y1="80" x2="65" y2="295" stroke="#56635d"/>
  <line x1="535" y1="295" x2="915" y2="295" stroke="#56635d"/><line x1="535" y1="80" x2="535" y2="295" stroke="#56635d"/>
  <text x="65" y="72" font-size="13" font-weight="700">p95 latency (cycles)</text>
  <text x="535" y="72" font-size="13" font-weight="700">Throughput (requests/cycle)</text>
  <polyline fill="none" stroke="#167d6d" stroke-width="3" points="{points(clean, max_latency, 65, 80, 380, 215)}"/>
  <polyline fill="none" stroke="#c84b31" stroke-width="3" points="{points(dirty, max_latency, 65, 80, 380, 215)}"/>
  <polyline fill="none" stroke="#2765a8" stroke-width="3" points="{points(throughput, max(throughput.values()), 535, 80, 380, 215)}"/>
  <text x="78" y="92" font-size="11" fill="#167d6d">clean miss</text><text x="155" y="92" font-size="11" fill="#c84b31">dirty miss</text>
'''
for x0 in (65, 535):
    for index, level in enumerate(levels):
        x = x0 + index * 380 / 3
        svg += f'  <text x="{x:.1f}" y="318" text-anchor="middle" font-size="11">{level}%</text>\n'
svg += '  <text x="480" y="345" text-anchor="middle" font-size="11">Requested AXI backpressure</text>\n</g>\n</svg>\n'
(images / "performance_latency.svg").write_text(svg)

with (ROOT / "docs" / "performance.md").open("a") as handle:
    handle.write("\n## Visual Summary\n\n![Latency and throughput versus AXI backpressure](images/performance_latency.svg)\n")
print(f"PERFORMANCE_SWEEP|status=PASS|samples={len(latency_rows)}|rows={len(summary_rows)}")
