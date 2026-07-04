#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
rows = list(csv.DictReader((ROOT / "reports" / "regress_summary.csv").open()))
text = """# Behavioral Performance Characterization

Cycle counts are Verilator behavioral measurements and include test setup. They are useful for relative comparison, not silicon timing claims.

| Scenario | Requests | Hits | Misses | Evictions | Total cycles | Cycles/request |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
"""
for row in rows:
    requests = int(row.get("requests", 0))
    cycles = int(row.get("cycles", 0))
    ratio = cycles / requests if requests else 0
    text += f"| `{row['test']}` | {requests} | {row.get('hits','0')} | {row.get('misses','0')} | {row.get('evictions','0')} | {cycles} | {ratio:.1f} |\n"
text += """

## Current Observations

- A warm hit avoids the four-beat AXI refill required by a cold miss.
- Dirty conflict replacement adds a complete four-beat writeback before refill.
- Independent AXI ready throttling increases service time without changing architectural results.
- The report is an initial baseline; percentile latency and duty-cycle sweeps remain release work.
"""
(ROOT / "docs" / "performance.md").write_text(text)
print(f"PERFORMANCE_REPORT|status=PASS|rows={len(rows)}")

