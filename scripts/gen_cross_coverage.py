#!/usr/bin/env python3
from __future__ import annotations
import csv
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
TRACE_DIR = ROOT / "build" / "verilator" / "traces"
REPORTS = ROOT / "reports"

bins: dict[str, tuple[str, bool]] = {}
def add(group: str, name: str) -> None:
    bins[f"{group}:{name}"] = (group, False)
def hit(group: str, name: str) -> None:
    key = f"{group}:{name}"
    if key in bins: bins[key] = (group, True)

for rw in ("read", "write"):
    for outcome in ("hit", "miss"): add("rw_x_hit", f"{rw}_{outcome}")
for state in ("clean", "dirty"):
    for way in (0, 1): add("victim_x_way", f"{state}_way{way}")
for lru in (0, 1):
    for way in (0, 1): add("lru_x_selected", f"lru{lru}_way{way}")
for phase in ("refill", "writeback"):
    for bp in (0, 25, 50, 75): add("phase_x_backpressure", f"{phase}_bp{bp}")
add("error_x_state", "read_error_no_install")
add("error_x_state", "write_error_dirty_preserved")
for command in (0, 1, 2):
    for state in ("invalid", "clean", "dirty"):
        add("maintenance_x_line", f"cmd{command}_{state}")
for offset in range(8):
    for strobe in ("full", "single", "partial"):
        add("offset_x_strobe", f"offset{offset}_{strobe}")

for path in sorted(TRACE_DIR.glob("*.csv")):
    with path.open() as handle:
        rows = list(csv.DictReader(handle))
    saw_read_error = False
    saw_install_after_error = False
    for row in rows:
        event = row["event"]
        bp = int(row["bp_pct"])
        if event == "LOOKUP":
            rw = "write" if int(row["write"]) else "read"
            outcome = "hit" if int(row["hit"]) else "miss"
            hit("rw_x_hit", f"{rw}_{outcome}")
            hit("lru_x_selected", f"lru{int(row['lru'])}_way{int(row['way'])}")
            if not int(row["hit"]) and int(row["valid"]):
                state = "dirty" if int(row["dirty"]) else "clean"
                hit("victim_x_way", f"{state}_way{int(row['way'])}")
        elif event == "AXI_AR":
            hit("phase_x_backpressure", f"refill_bp{bp}")
        elif event == "AXI_AW":
            hit("phase_x_backpressure", f"writeback_bp{bp}")
        elif event == "AXI_R" and int(row["error"]):
            saw_read_error = True
        elif event == "LINE_INSTALL" and saw_read_error:
            saw_install_after_error = True
        elif event == "CPU_RESPONSE" and int(row["error"]) and saw_read_error:
            if not saw_install_after_error: hit("error_x_state", "read_error_no_install")
            saw_read_error = saw_install_after_error = False
        elif event == "AXI_B" and int(row["error"]) and int(row["dirty"]):
            hit("error_x_state", "write_error_dirty_preserved")
        elif event == "MAINT_SCAN":
            state = "invalid" if not int(row["valid"]) else ("dirty" if int(row["dirty"]) else "clean")
            hit("maintenance_x_line", f"cmd{int(row['maint_cmd'])}_{state}")
        elif event == "CPU_ACCEPT" and int(row["write"]):
            strobe_value = int(row["wstrb"])
            strobe = "full" if strobe_value == 15 else (
                "single" if strobe_value in (1, 2, 4, 8) else "partial")
            hit("offset_x_strobe", f"offset{(int(row['addr'], 16) >> 2) & 7}_{strobe}")

rows = [{"group": group, "bin": key.split(":", 1)[1],
         "status": "COVERED" if covered else "MISSING"}
        for key, (group, covered) in sorted(bins.items())]
with (REPORTS / "cache_cross_coverage.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
covered = sum(row["status"] == "COVERED" for row in rows)
text = "# Cache Interaction Cross Coverage\n\n"
text += "| Group | Covered | Total |\n| --- | ---: | ---: |\n"
for group in sorted({row["group"] for row in rows}):
    subset = [row for row in rows if row["group"] == group]
    text += f"| `{group}` | {sum(row['status'] == 'COVERED' for row in subset)} | {len(subset)} |\n"
missing = [row for row in rows if row["status"] == "MISSING"]
text += f"\nOverall: **{covered} / {len(rows)}**.\n"
if missing:
    text += "\nMissing bins: " + ", ".join(f"`{row['group']}:{row['bin']}`" for row in missing) + ".\n"
(ROOT / "docs" / "cross_coverage.md").write_text(text)
print(f"CACHE_CROSS_COVERAGE|covered={covered}|total={len(rows)}")
raise SystemExit(0 if covered == len(rows) else 1)
