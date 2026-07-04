#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
summary_path = ROOT / "reports" / "regress_summary.csv"
rows = {row["test"]: row for row in csv.DictReader(summary_path.open())}
points = [
    ("cold_miss_refill", "smoke", lambda r: int(r["misses"]) >= 1),
    ("load_after_refill_hit", "smoke", lambda r: int(r["hits"]) >= 1),
    ("dirty_eviction_writeback", "dirty_evict", lambda r: int(r["evictions"]) >= 1),
    ("axi_channel_backpressure", "backpressure", lambda r: r["status"] == "PASS"),
    ("axi_read_error_propagation", "read_error", lambda r: int(r["errors"]) >= 1),
    ("axi_writeback_error_propagation", "write_error", lambda r: int(r["errors"]) >= 1),
    ("partial_byte_strobe_merge", "byte_strobes", lambda r: r["status"] == "PASS"),
    ("misaligned_access_containment", "misaligned", lambda r: int(r["errors"]) >= 1),
    ("flush_invalidate_maintenance", "maintenance", lambda r: r["status"] == "PASS"),
    ("flush_only_maintenance", "flush_only", lambda r: r["status"] == "PASS"),
    ("invalidate_forces_remiss", "invalidate_only", lambda r: int(r["misses"]) >= 2),
    ("cpu_response_backpressure", "response_backpressure", lambda r: r["status"] == "PASS"),
    ("reset_during_refill_recovery", "reset_mid_refill", lambda r: r["status"] == "PASS"),
    ("independent_axi_channel_waits", "axi_channel_waits", lambda r: r["status"] == "PASS"),
    ("maintenance_writeback_error", "maintenance_error", lambda r: r["status"] == "PASS"),
    ("maintenance_terminal_dirty_way", "maintenance_final_dirty", lambda r: r["status"] == "PASS"),
    ("maintenance_axi_channel_waits", "maintenance_channel_waits", lambda r: r["status"] == "PASS"),
    ("seeded_random_data_integrity", "random", lambda r: int(r["requests"]) >= 100),
]
coverage_rows = []
for name, test, predicate in points:
    observed = test in rows and predicate(rows[test])
    coverage_rows.append({"coverage_point": name, "source_test": test,
                          "status": "COVERED" if observed else "MISSING"})
out = ROOT / "reports" / "functional_coverage.csv"
with out.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=coverage_rows[0].keys())
    writer.writeheader(); writer.writerows(coverage_rows)
covered = sum(row["status"] == "COVERED" for row in coverage_rows)
doc = "# Functional Coverage\n\n"
doc += "This initial executable coverage model is separate from Verilator code coverage.\n\n"
doc += "| Coverage point | Source test | Status |\n| --- | --- | --- |\n"
for row in coverage_rows:
    doc += f"| `{row['coverage_point']}` | `{row['source_test']}` | {row['status']} |\n"
doc += f"\nCurrent baseline: **{covered} / {len(coverage_rows)}**. The release target expands this model before claiming closure.\n"
doc += """

## Code Coverage Interpretation

Native Verilator coverage is reported separately in `reports/code_coverage.md`. The current suite reaches all reviewed executable lines and nearly all branch points. Raw toggle coverage remains materially lower because it includes cache-array storage bits, fixed AXI burst constants, and address bits outside the bounded testbench memory window. Those raw values remain visible; only storage-array toggle points and non-executable assertion/default lines are excluded from reviewed summaries.
"""
(ROOT / "docs" / "coverage.md").write_text(doc)
print(f"FUNCTIONAL_COVERAGE|covered={covered}|total={len(coverage_rows)}")
raise SystemExit(0 if covered == len(coverage_rows) else 1)
