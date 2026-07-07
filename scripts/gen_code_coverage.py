#!/usr/bin/env python3
from __future__ import annotations

import csv
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "verilator"
REPORTS = ROOT / "reports"

GROUP_DIRS = {
    "baseline_2way": BUILD / "coverage",
    "coverage_edges_2way": BUILD / "coverage_edges",
    "direct_mapped_variant": BUILD / "coverage_direct_mapped",
}


def metadata(descriptor: str) -> tuple[str, int, str]:
    file_match = re.search(r"\x01f\x02([^\x01]+)", descriptor)
    line_match = re.search(r"\x01l\x02(\d+)", descriptor)
    object_match = re.search(r"\x01o\x02([^\x01]+)", descriptor)
    return (
        file_match.group(1) if file_match else "",
        int(line_match.group(1)) if line_match else 0,
        object_match.group(1) if object_match else "",
    )


def point_kind(descriptor: str) -> str:
    page = re.search(r"\x01page\x02([^\x01]+)", descriptor)
    if not page:
        return "unknown"
    return {
        "v_line": "line", "v_branch": "branch", "v_expr": "expression",
        "v_toggle": "toggle", "v_user": "user", "v_fsm_state": "fsm_state",
        "v_fsm_arc": "fsm_arc",
    }.get(page.group(1).split("/", 1)[0], page.group(1).removeprefix("v_"))


def exclusion(point_type: str, line: int, object_name: str) -> str:
    if point_type == "line" and object_name == "case" and line > 350:
        return "unreachable_defensive_default"
    if point_type == "line" and object_name == "block" and line >= 385:
        return "assertion_declaration_not_executable_rtl"
    if point_type == "toggle" and any(name in object_name for name in
                                       ("tags", "data_mem", "parity_mem", "refill_buf")):
        return "memory_array_bit_toggle"
    return ""


def collect(files: list[pathlib.Path]) -> dict[str, dict[str, int]]:
    points: dict[str, dict[str, int]] = {}
    for path in files:
        for raw in path.read_text(errors="replace").splitlines():
            if not raw.startswith("C '"):
                continue
            try:
                descriptor, count_text = raw[3:].rsplit("' ", 1)
                count = int(count_text)
            except (ValueError, IndexError):
                continue
            source, _, _ = metadata(descriptor)
            normalized_source = source.replace("\\", "/")
            if "/rtl/" not in normalized_source and not normalized_source.startswith("rtl/"):
                continue
            kind = point_kind(descriptor)
            points.setdefault(kind, {})[descriptor] = points.setdefault(kind, {}).get(descriptor, 0) + count
    return points


def summarize(group: str, files: list[pathlib.Path]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    holes: list[dict[str, str]] = []
    points = collect(files)
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
                holes.append({
                    "coverage_group": group,
                    "point_type": point_type,
                    "rtl_file": pathlib.Path(source).name,
                    "line": str(line),
                    "signal_or_branch": object_name or "NA",
                    "hit_count": str(count),
                    "reviewed_exclusion": reason or "none",
                })
        rows.append({
            "coverage_group": group,
            "point_type": point_type,
            "raw_hit": str(raw_hit),
            "raw_total": str(raw_total),
            "raw_percent": f"{100.0 * raw_hit / raw_total:.2f}" if raw_total else "NA",
            "excluded": str(excluded),
            "reviewed_hit": str(reviewed_hit),
            "reviewed_total": str(reviewed_total),
            "reviewed_percent": f"{100.0 * reviewed_hit / reviewed_total:.2f}" if reviewed_total else "NA",
        })
    return rows, holes


REPORTS.mkdir(exist_ok=True)
available: dict[str, list[pathlib.Path]] = {
    group: sorted(path.glob("*.dat"))
    for group, path in GROUP_DIRS.items()
    if path.exists() and list(path.glob("*.dat"))
}
if not available:
    raise SystemExit("No Verilator coverage data files were generated")

all_files = [path for files in available.values() for path in files]
info = REPORTS / "code_coverage.info"
subprocess.run(["verilator_coverage", "--write-info", str(info), *map(str, all_files)], check=True)

summary_rows: list[dict[str, str]] = []
hole_rows: list[dict[str, str]] = []
for group, files in available.items():
    rows, holes = summarize(group, files)
    summary_rows.extend(rows)
    hole_rows.extend(holes)

summary_fields = ["coverage_group", "point_type", "raw_hit", "raw_total", "raw_percent",
                  "excluded", "reviewed_hit", "reviewed_total", "reviewed_percent"]
with (REPORTS / "code_coverage_summary.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(summary_rows)

hole_fields = ["coverage_group", "point_type", "rtl_file", "line", "signal_or_branch",
               "hit_count", "reviewed_exclusion"]
with (REPORTS / "code_coverage_holes.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=hole_fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(hole_rows)

text = "# Verilator Code Coverage\n\n"
text += "Coverage is grouped so optional edge and structural-variant tests do not obscure the baseline 2-way cache result.\n\n"
text += "| Group | Point type | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |\n"
text += "| --- | --- | ---: | ---: | ---: | ---: | ---: |\n"
for row in summary_rows:
    text += (f"| `{row['coverage_group']}` | {row['point_type']} | "
             f"{row['raw_hit']} / {row['raw_total']} | {row['raw_percent']}% | "
             f"{row['excluded']} | {row['reviewed_hit']} / {row['reviewed_total']} | "
             f"{row['reviewed_percent']}% |\n")

text += "\n## Coverage Groups\n\n"
text += "- `baseline_2way`: default 4 KiB, 2-way cache closure run.\n"
text += "- `coverage_edges_2way`: optional directed edge tests for byte strobes, set/way toggling, and maintenance boundaries.\n"
text += "- `direct_mapped_variant`: optional 4 KiB direct-mapped structural variant compiled with `CACHE_WAYS=1`, `CACHE_SETS=128`.\n"
text += ("\nReviewed exclusions are limited to defensive defaults, assertion declaration lines, "
         "and storage-array toggle points. Raw values remain visible. Direct-mapped coverage is "
         "reported as structural-variant evidence, not as part of the baseline 2-way closure claim. "
         "This is Verilator proxy evidence, not commercial coverage signoff.\n")
(REPORTS / "code_coverage.md").write_text(text)

line_row = next((row for row in summary_rows
                 if row["coverage_group"] == "baseline_2way" and row["point_type"] == "line"), None)
if line_row is None:
    line_row = next((row for row in summary_rows if row["point_type"] == "line"), None)
print(f"CODE_COVERAGE|status=PASS|line={line_row['raw_percent'] if line_row else 'NA'}|groups={len(available)}|data_files={len(all_files)}")
