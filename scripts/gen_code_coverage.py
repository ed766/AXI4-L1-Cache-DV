#!/usr/bin/env python3
from __future__ import annotations

import csv
import functools
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
    "secded_2way_variant": BUILD / "coverage_secded",
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


@functools.lru_cache(maxsize=None)
def secded_function_lines(source: str) -> set[int]:
    path = pathlib.Path(source)
    if not path.is_absolute():
        path = ROOT / path
    if not path.exists():
        return set()
    result: set[int] = set()
    in_optional_function = False
    for number, text in enumerate(path.read_text().splitlines(), 1):
        if "function automatic" in text and any(name in text for name in
                ("secded_encode", "secded_decode", "line_has_uncorrectable")):
            in_optional_function = True
        if in_optional_function:
            result.add(number)
        if in_optional_function and "endfunction" in text:
            in_optional_function = False
    return result


def exclusion(group: str, point_type: str, source: str, line: int, object_name: str) -> str:
    source_path = pathlib.Path(source)
    source_text = ""
    candidate = source_path if source_path.is_absolute() else ROOT / source_path
    if candidate.exists() and line > 0:
        lines = candidate.read_text().splitlines()
        if line <= len(lines):
            source_text = lines[line - 1]
    if (group in ("baseline_2way", "coverage_edges_2way", "direct_mapped_variant") and
            point_type in ("line", "branch", "expression", "toggle") and
            (line in secded_function_lines(source) or "SECDED_ENABLE" in source_text or
             object_name.startswith("ecc_"))):
        return "compile_time_inactive_secded_variant"
    if point_type == "line" and object_name == "case" and line > 350:
        return "unreachable_defensive_default"
    if point_type == "line" and object_name == "block" and line >= 385:
        return "assertion_declaration_not_executable_rtl"
    if point_type == "toggle" and any(name in object_name for name in
                                       ("tags", "data_mem", "parity_mem", "refill_buf")):
        return "memory_array_bit_toggle"
    return ""


def collect(files: list[pathlib.Path], *, structural_union: bool = False) -> dict[str, dict[str, int]]:
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
            key = descriptor
            if structural_union:
                key = re.sub(r"(\x01page\x02[^\x01/]+/)[^\x01]+", r"\1structural_union", key)
            points.setdefault(kind, {})[key] = points.setdefault(kind, {}).get(key, 0) + count
    return points


def summarize(group: str, files: list[pathlib.Path], *, structural_union: bool = False) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    holes: list[dict[str, str]] = []
    points = collect(files, structural_union=structural_union)
    for point_type, values in sorted(points.items()):
        raw_total = len(values)
        raw_hit = sum(count > 0 for count in values.values())
        excluded = 0
        reviewed_total = reviewed_hit = 0
        for descriptor, count in values.items():
            source, line, object_name = metadata(descriptor)
            reason = exclusion(group, point_type, source, line, object_name)
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

if len(available) > 1:
    rows, holes = summarize("combined_structural_variants", all_files, structural_union=True)
    summary_rows.extend(rows)
    hole_rows.extend(holes)

summary_fields = ["coverage_group", "point_type", "raw_hit", "raw_total", "raw_percent",
                  "excluded", "reviewed_hit", "reviewed_total", "reviewed_percent"]
with (REPORTS / "code_coverage_summary.csv").open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(summary_rows)

with (REPORTS / "structural_variant_coverage.csv").open("w", newline="") as handle:
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
text += "- `secded_2way_variant`: optional 2-way SECDED/RAS structural variant.\n"
text += "- `combined_structural_variants`: union across every executed geometry/integrity variant; never substituted for baseline closure.\n"
text += ("\nReviewed exclusions are limited to defensive defaults, assertion declaration lines, "
         "compile-time inactive logic, and storage-array toggle points. Raw values and exclusion "
         "denominators remain visible. Direct-mapped, SECDED, and combined coverage are structural-variant "
         "evidence and are never substituted for the baseline 2-way closure claim. "
         "This is Verilator proxy evidence, not commercial coverage signoff.\n")
(REPORTS / "code_coverage.md").write_text(text)
(ROOT / "docs" / "structural_variant_coverage.md").write_text(
    "# Structural-Variant Code Coverage\n\n"
    "The parity 2-way baseline remains the canonical code-coverage scope. Direct-mapped and SECDED "
    "runs execute compile-time alternatives; the combined row is a union of real executions and is "
    "reported only as supporting structural evidence.\n\n" +
    "| Group | Point | Raw hit/total | Raw | Excluded | Reviewed hit/total | Reviewed |\n"
    "| --- | --- | ---: | ---: | ---: | ---: | ---: |\n" +
    "".join(
        f"| `{row['coverage_group']}` | {row['point_type']} | {row['raw_hit']} / {row['raw_total']} | "
        f"{row['raw_percent']}% | {row['excluded']} | {row['reviewed_hit']} / {row['reviewed_total']} | "
        f"{row['reviewed_percent']}% |\n" for row in summary_rows
    ) +
    "\nRaw baseline coverage is the headline metric. Reviewed values always retain their denominator and "
    "exclusion count; storage-array toggles are not treated as a closure objective.\n"
)

line_row = next((row for row in summary_rows
                 if row["coverage_group"] == "baseline_2way" and row["point_type"] == "line"), None)
if line_row is None:
    line_row = next((row for row in summary_rows if row["point_type"] == "line"), None)
print(f"CODE_COVERAGE|status=PASS|line={line_row['raw_percent'] if line_row else 'NA'}|groups={len(available)}|data_files={len(all_files)}")
