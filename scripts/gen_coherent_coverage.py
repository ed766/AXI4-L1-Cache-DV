#!/usr/bin/env python3
"""Generate executable-RTL functional and same-window crossover coverage."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from run_coherent_model import LITMUS

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
BUILD = ROOT / "build" / "coherent"


def report(name: str) -> list[dict[str, str]]:
    with (REPORTS / name).open() as handle: return list(csv.DictReader(handle))


def event_index() -> list[tuple[str, dict[str, object]]]:
    indexed = []
    roots = (BUILD / "rtl_litmus_traces", BUILD / "event_traces",
             BUILD / "edge_traces", BUILD / "coverage_edge_traces",
             BUILD / "performance_traces")
    for root in roots:
        for path in sorted(root.glob("*_enriched.jsonl")) if root.exists() else ():
            for line in path.read_text().splitlines():
                if line: indexed.append((str(path.relative_to(ROOT)), json.loads(line)))
        if root == BUILD / "edge_traces" and root.exists():
            for path in sorted(root.glob("*.jsonl")):
                for line in path.read_text().splitlines():
                    if line: indexed.append((str(path.relative_to(ROOT)), json.loads(line)))
    return indexed


def first(indexed, predicate) -> str:
    for source, row in indexed:
        if predicate(row): return f"{source}:cycle={row.get('cycle', 0)}"
    return ""


def main() -> int:
    litmus_rows = report("coherent_rtl_litmus_summary.csv")
    error_rows = report("coherent_error_reset_summary.csv")
    perf_rows = report("coherent_performance.csv")
    indexed = event_index()
    points = []

    def add(group: str, name: str, evidence: str, evidence_class: str = "executable_rtl") -> None:
        points.append({"group": group, "coverage_point": name,
                       "status": "COVERED" if evidence else "MISSING",
                       "evidence_class": evidence_class, "evidence": evidence})

    for test in LITMUS:
        row = next((r for r in litmus_rows if r["litmus"] == test.name and r["status"] == "PASS"), None)
        add("instruction_ordering", f"litmus_{test.name.lower()}", row["event_trace"] if row else "")

    buffer_specs = (
        ("enqueue_h0", lambda e: e.get("event") == "store_enqueue" and e.get("hart") == "0"),
        ("enqueue_h1", lambda e: e.get("event") == "store_enqueue" and e.get("hart") == "1"),
        ("drain_h0", lambda e: e.get("event") == "store_drain" and e.get("hart") == "0" and e.get("detail1") == "0"),
        ("drain_h1", lambda e: e.get("event") == "store_drain" and e.get("hart") == "1" and e.get("detail1") == "0"),
        ("forward_h0", lambda e: e.get("event") == "load_forward" and e.get("hart") == "0"),
        ("forward_h1", lambda e: e.get("event") == "load_forward" and e.get("hart") == "1"),
        ("bypass_h0", lambda e: e.get("event") == "fabric_request" and e.get("hart") == "0" and e.get("detail0") == "0"),
        ("bypass_h1", lambda e: e.get("event") == "fabric_request" and e.get("hart") == "1" and e.get("detail0") == "0"),
        ("fence_wait_h0", lambda e: e.get("event") == "fence_wait" and e.get("hart") == "0"),
        ("fence_wait_h1", lambda e: e.get("event") == "fence_wait" and e.get("hart") == "1"),
        ("occupancy_two_h0", lambda e: e.get("event") == "store_enqueue" and e.get("hart") == "0" and e.get("detail0") == "2"),
        ("occupancy_two_h1", lambda e: e.get("event") == "store_enqueue" and e.get("hart") == "1" and e.get("detail0") == "2"),
    )
    for name, predicate in buffer_specs: add("buffering", name, first(indexed, predicate))

    for hart in range(2):
        hs = str(hart)
        specs = (
            ("read_miss", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("detail0") == "0" and e.get("transition") == "I->S"),
            ("local_hit", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("local_hit") is True),
            ("write_miss", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("detail0") == "1" and e.get("transition") == "I->M"),
            ("shared_upgrade", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("transition") == "S->M"),
            ("intervention_to", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("source") == "dirty_intervention"),
            ("invalidation_by", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("detail0") == "1" and e.get("remote_state") in ("S", "M")),
            ("home_data_to", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("source") == "home_memory"),
            ("dirty_data_to", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("source") == "dirty_intervention"),
            ("modified_rewrite", lambda e, h=hs: e.get("event") == "bank_request" and e.get("hart") == h and e.get("transition") == "M->M"),
            ("response_owner", lambda e, h=hs: e.get("event") == "fabric_response" and e.get("hart") == h),
        )
        for prefix, predicate in specs: add("coherence", f"{prefix}_h{hart}", first(indexed, predicate))

    for duty in (0, 25, 50, 75):
        row = next((r for r in litmus_rows if r["backpressure_percent"] == str(duty)), None)
        add("fabric", f"axi_backpressure_{duty}", row["event_trace"] if row else "")
    add("fabric", "home_read_request", first(indexed, lambda e: e.get("event") == "bank_request" and e.get("detail0") == "0"))
    add("fabric", "home_write_request", first(indexed, lambda e: e.get("event") == "bank_request" and e.get("detail0") == "1"))
    add("fabric", "response_route_h0", first(indexed, lambda e: e.get("event") == "fabric_response" and e.get("hart") == "0"))
    add("fabric", "response_route_h1", first(indexed, lambda e: e.get("event") == "fabric_response" and e.get("hart") == "1"))

    for name in ("precise_load_error", "deferred_store_error_recovery", "reset_idle",
                 "reset_store_pending", "reset_read_outstanding", "reset_response_pending"):
        row = next((r for r in error_rows if r["scenario"] == name and r["status"] == "PASS"), None)
        add("error_reset", name, row["event_trace"] if row else "")
    reset_row = next((r for r in error_rows if r["scenario"] == "reset_concurrent_banks" and r["status"] == "PASS"), None)
    add("error_reset", "no_ghost_h0", reset_row["event_trace"] if reset_row else "")
    add("error_reset", "no_ghost_h1", reset_row["event_trace"] if reset_row else "")

    crosses = []
    def cross(group: str, name: str, evidence: str) -> None:
        crosses.append({"group": group, "cross_bin": name,
                        "status": "COVERED" if evidence else "MISSING",
                        "evidence_class": "same_window_executable_rtl", "same_window_evidence": evidence})

    for family in sorted({test.family for test in LITMUS}):
        for fenced in (False, True):
            row = next((r for r in litmus_rows if r["family"] == family and r["fenced"] == str(fenced).lower() and r["status"] == "PASS"), None)
            cross("litmus_fence_outcome", f"{family}__{'fenced' if fenced else 'unfenced'}", row["event_trace"] if row else "")
    actions = (
        ("enqueue_occ1", lambda e, h: e.get("event") == "store_enqueue" and e.get("hart") == h and e.get("detail0") == "1"),
        ("enqueue_occ2", lambda e, h: e.get("event") == "store_enqueue" and e.get("hart") == h and e.get("detail0") == "2"),
        ("drain_occ1", lambda e, h: e.get("event") == "store_drain" and e.get("hart") == h and e.get("detail0") == "1"),
        ("forward_occ1", lambda e, h: e.get("event") == "load_forward" and e.get("hart") == h and e.get("detail0") == "1"),
        ("bypass_occ1", lambda e, h: e.get("event") == "fabric_request" and e.get("hart") == h and e.get("detail0") == "0" and e.get("detail1") == "1"),
        ("fence_wait_occ1", lambda e, h: e.get("event") == "fence_wait" and e.get("hart") == h and e.get("detail0") == "1"),
    )
    for hart in range(2):
        for name, predicate in actions: cross("buffer_action_occupancy", f"h{hart}_{name}", first(indexed, lambda e, p=predicate, h=str(hart): p(e, h)))
    for hart in range(2):
        for transition in ("I->S", "I->M", "S->M", "M->M"):
            cross("coherence_transition_hart", f"h{hart}_{transition}", first(indexed, lambda e, h=str(hart), t=transition: e.get("event") == "bank_request" and e.get("hart") == h and e.get("transition") == t))
    for duty in (0, 25, 50, 75):
        low = next((r for r in perf_rows if r["backpressure_percent"] == str(duty) and int(r["simultaneous_bank_cycles"]) == 0), None)
        high = next((r for r in perf_rows if r["backpressure_percent"] == str(duty) and int(r["simultaneous_bank_cycles"]) > 0), None)
        cross("home_occupancy_backpressure", f"low_bp{duty}", low["event_trace"] if low else "")
        cross("home_occupancy_backpressure", f"high_bp{duty}", high["event_trace"] if high else "")
    for phase in ("reset_idle", "reset_store_pending", "reset_read_outstanding", "reset_response_pending"):
        row = next((r for r in error_rows if r["scenario"] == phase and r["status"] == "PASS"), None)
        cross("reset_error_outstanding", phase.removeprefix("reset_"), row["event_trace"] if row else "")

    assert len(points) == 64 and len(crosses) == 48
    with (REPORTS / "coherent_functional_coverage.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=points[0].keys(), lineterminator="\n"); writer.writeheader(); writer.writerows(points)
    with (REPORTS / "coherent_cross_coverage.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=crosses[0].keys(), lineterminator="\n"); writer.writeheader(); writer.writerows(crosses)
    covered = sum(row["status"] == "COVERED" for row in points); crossed = sum(row["status"] == "COVERED" for row in crosses)
    print(f"COHERENT_COVERAGE|status={'PASS' if (covered, crossed) == (64, 48) else 'FAIL'}|functional={covered}/64|crosses={crossed}/48")
    return 0 if (covered, crossed) == (64, 48) else 1


if __name__ == "__main__": raise SystemExit(main())
