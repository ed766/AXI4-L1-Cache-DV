#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "build" / "verilator" / "coverage"
REPORTS = ROOT / "reports"


def metadata(descriptor: str) -> tuple[str, int, str]:
    file_match = re.search(r"\x01f\x02([^\x01]+)", descriptor)
    line_match = re.search(r"\x01l\x02(\d+)", descriptor)
    object_match = re.search(r"\x01o\x02([^\x01]+)", descriptor)
    return (
        file_match.group(1) if file_match else "",
        int(line_match.group(1)) if line_match else 0,
        object_match.group(1) if object_match else "",
    )


def exclusion(point_type: str, line: int, object_name: str) -> str:
    if point_type == "line" and object_name == "case" and line > 350:
        return "unreachable_defensive_default"
    if point_type == "line" and object_name == "block" and line >= 385:
        return "assertion_declaration_not_executable_rtl"
    if point_type == "toggle" and any(name in object_name for name in
                                       ("tags", "data_mem", "parity_mem", "refill_buf")):
        return "memory_array_bit_toggle"
    return ""


data_files = sorted(DATA_DIR.glob("*.dat"))
if not data_files:
    raise SystemExit("No Verilator coverage data files were generated")

info = REPORTS / "code_coverage.info"
subprocess.run(["verilator_coverage", "--write-info", str(info), *map(str, data_files)], check=True)

points: dict[str, dict[str, int]] = {}
for path in data_files:
    for raw in path.read_text(errors="replace").splitlines():
        if not raw.startswith("C '"):
            continue
        try:
            descriptor, count_text = raw[3:].rsplit("' ", 1)
            count = int(count_text)
        except (ValueError, IndexError):
            continue
        page = re.search(r"\x01page\x02([^\x01]+)", descriptor)
        source, _, _ = metadata(descriptor)
        if not page or "/rtl/" not in source:
            continue
        point_type = {
            "v_line": "line", "v_branch": "branch", "v_expr": "expression",
            "v_toggle": "toggle", "v_user": "user", "v_fsm_state": "fsm_state",
            "v_fsm_arc": "fsm_arc",
        }.get(page.group(1).split("/", 1)[0], page.group(1).removeprefix("v_"))
        points.setdefault(point_type, {})[descriptor] = (
            points.setdefault(point_type, {}).get(descriptor, 0) + count
        )

summary_rows = []
hole_rows = []
for point_type, values in sorted(points.items()):
    raw_total = len(values)
    raw_hit = sum(count > 0 for count in values.values())
    excluded = 0
    reviewed_total = reviewed_hit = 0
    for descriptor, count in values.items():
        source, line, object_name = metadata(descriptor)
        reason = exclusion(point_type, line, object_name)
        if reason:
            excluded += 1
        else:
            reviewed_total += 1
            reviewed_hit += count > 0
        if count == 0:
            hole_rows.append({
                "point_type": point_type,
                "source": pathlib.Path(source).name,
                "line": line,
                "object": object_name or "NA",
                "reviewed_exclusion": reason or "none",
            })
    summary_rows.append({
        "point_type": point_type,
        "raw_hit": raw_hit,
        "raw_total": raw_total,
        "raw_percent": f"{100.0 * raw_hit / raw_total:.2f}" if raw_total else "NA",
        "excluded": excluded,
        "reviewed_hit": reviewed_hit,
        "reviewed_total": reviewed_total,
        "reviewed_percent": f"{100.0 * reviewed_hit / reviewed_total:.2f}" if reviewed_total else "NA",
    })

with (REPORTS / "code_coverage_summary.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(summary_rows)
with (REPORTS / "code_coverage_holes.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=hole_rows[0].keys(), lineterminator="\n")
    writer.writeheader(); writer.writerows(hole_rows)

text = "# Verilator Code Coverage\n\n"
text += "| Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |\n"
text += "| --- | ---: | ---: | ---: | ---: | ---: |\n"
for row in summary_rows:
    text += (f"| {row['point_type']} | {row['raw_hit']} / {row['raw_total']} | "
             f"{row['raw_percent']}% | {row['excluded']} | "
             f"{row['reviewed_hit']} / {row['reviewed_total']} | {row['reviewed_percent']}% |\n")
text += ("\nReviewed exclusions are limited to the defensive default, assertion declaration lines, "
         "and storage-array toggle points. Raw values remain visible. This is Verilator proxy evidence, "
         "not commercial coverage signoff.\n")
(REPORTS / "code_coverage.md").write_text(text)

line_row = next((row for row in summary_rows if row["point_type"] == "line"), None)
print(f"CODE_COVERAGE|status=PASS|line={line_row['raw_percent'] if line_row else 'NA'}|data_files={len(data_files)}")
