#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
FORMAL = ROOT / "formal"


def write_combined_doc() -> None:
    rows: list[dict[str, str]] = []
    for name in ("formal_proof_summary.csv", "formal_small_proof_summary.csv"):
        path = REPORTS / name
        if path.exists():
            rows.extend(csv.DictReader(path.open()))
    table = "".join(
        f"| `{row['task']}` | `{row['kind']}` | {row['status']} | {row['expected']} | "
        f"{'yes' if row['meets_expectation'].lower() in ('true', 'yes', '1') else 'no'} | "
        f"{row['depth']} | {row['runtime_seconds']} s |\n"
        for row in rows
    )
    (ROOT / "docs" / "formal.md").write_text(f"""# Formal Evidence

The SymbiYosys harness separates DUT guarantees from AXI environment assumptions. Cache-generated `WLAST` is asserted; memory-generated `RLAST` placement is assumed legal and the cache response is checked. The canonical and reduced-geometry tasks target the parity baseline; optional SECDED behavior is checked by the independent model-backed RAS matrix.

| Task | Kind | Observed | Expected | Meets expectation | Depth | Runtime |
| --- | --- | --- | --- | --- | ---: | ---: |
{table}
Properties cover request/response accounting, dirty-writeback ordering, refill/writeback error containment, final-beat write semantics, invalid-way preference, and maintenance exclusion. Reachability tasks exercise hits, misses, dirty evictions, error responses, and maintenance completion; mutation tasks demonstrate checker sensitivity.

The `small_1way` and `small_2way` rows are reduced-geometry bounded proof evidence. All results are depth-stated open-source checks, not exhaustive cache correctness or commercial formal signoff.
""")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", choices=("all", "cover", "mutations", "small"), default="all")
    args = parser.parse_args()
    sby = shutil.which("sby")
    if not sby:
        print("FORMAL_PROVE|status=SKIP|reason=sby_not_installed")
        return 2
    REPORTS.mkdir(exist_ok=True)
    rows = []
    nominal = []
    if args.only == "small":
        nominal = [
            ("small_1way_bounded_safety", "cache_small_1way.sby", "prove", 20, "small_geometry_bounded_safety"),
            ("small_2way_bounded_safety", "cache_small_2way.sby", "prove", 20, "small_geometry_bounded_safety"),
        ]
    elif args.only in ("all", "cover"):
        nominal.append(("cover", "cache_safety.sby", "cover", 50, "cover"))
    if args.only == "all":
        nominal = [("bounded_safety", "cache_safety.sby", "prove", 40, "bounded_safety"),
                   *nominal,
                   ("error_containment_bmc", "cache_error_containment.sby", None, 40, "bounded_error")]
    for task, config, selected_task, depth, kind in nominal:
        start = time.monotonic()
        command = [sby, "-f", config]
        if selected_task: command.append(selected_task)
        result = subprocess.run(command, cwd=FORMAL,
                                text=True, capture_output=True)
        output = result.stdout + result.stderr
        log = REPORTS / f"formal_{task}.log"
        log.write_text(output)
        status = "PASS" if result.returncode == 0 else "FAIL"
        rows.append({"task": task, "kind": kind, "status": status, "depth": depth,
                     "expected": "PASS", "meets_expectation": status == "PASS",
                     "runtime_seconds": f"{time.monotonic() - start:.2f}",
                     "log": str(log.relative_to(ROOT))})
        print(f"FORMAL_TASK|task={task}|status={status}")
    mutation_tasks = []
    if args.only in ("all", "mutations"):
        mutation_tasks = [("mutation_wlast_early", "cache_wlast_mutation.sby"),
                          ("mutation_refill_error_ignore", "cache_refill_error_mutation.sby")]
    for name, config in mutation_tasks:
        start = time.monotonic()
        result = subprocess.run([sby, "-f", config], cwd=FORMAL, text=True, capture_output=True)
        output = result.stdout + result.stderr
        log = REPORTS / f"formal_{name}.log"
        log.write_text(output)
        observed = "FAIL" if result.returncode else "PASS"
        rows.append({"task": name, "kind": "expected_mutation_failure",
                     "status": observed, "depth": 40,
                     "expected": "FAIL", "meets_expectation": observed == "FAIL",
                     "runtime_seconds": f"{time.monotonic() - start:.2f}",
                     "log": str(log.relative_to(ROOT))})
        print(f"FORMAL_TASK|task={name}|status={observed}|expected=FAIL")
    if not rows:
        print("FORMAL_PROVE|status=FAIL|reason=no_tasks_selected")
        return 1
    summary_name = "formal_small_proof_summary.csv" if args.only == "small" else "formal_proof_summary.csv"
    with (REPORTS / summary_name).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["meets_expectation"] for row in rows)
    write_combined_doc()
    print(f"FORMAL_PROVE|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}|total={len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
