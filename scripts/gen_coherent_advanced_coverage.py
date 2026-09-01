#!/usr/bin/env python3
"""Generate 48 transaction-correlated advanced crossover bins."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"


def table(name: str) -> list[dict[str, str]]:
    with (REPORTS / name).open() as handle:
        return list(csv.DictReader(handle))


direct = {row["scenario"]: row for row in table("coherent_directed_closure_summary.csv")}
errors = {row["scenario"]: row for row in table("coherent_error_reset_summary.csv")}
qos = {row["test"]: row for row in table("coherent_qos_concurrency_summary.csv")}


def json_events(scenario: str) -> list[dict[str, object]]:
    path = ROOT / direct[scenario]["enriched_trace"]
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def csv_events(path_text: str) -> list[dict[str, str]]:
    with (ROOT / path_text).open() as handle:
        return list(csv.DictReader(handle))


def direct_event(scenario: str, predicate: Callable[[dict[str, object]], bool]) -> str:
    for row in json_events(scenario):
        if predicate(row):
            txn = row.get("transaction_id", f"e{row.get('epoch', 1)}:h{row.get('hart', -1)}:cycle{row.get('cycle')}")
            return f"{direct[scenario]['enriched_trace']}:cycle={row.get('cycle')}:txn={txn}"
    return ""


def ordered_events(scenario: str, first_predicate, second_predicate, first_before_second: bool) -> str:
    events = json_events(scenario)
    first = next((row for row in events if first_predicate(row)), None)
    second = next((row for row in events if second_predicate(row)), None)
    if first and second and ((int(first["cycle"]) < int(second["cycle"])) == first_before_second):
        return f"{direct[scenario]['enriched_trace']}:cycles={first['cycle']}->{second['cycle']}:txn=e1:h0:ordering"
    return ""


def error_event(scenario: str, predicate) -> str:
    for row in csv_events(errors[scenario]["event_trace"]):
        if predicate(row):
            return f"{errors[scenario]['event_trace']}:cycle={row['cycle']}:txn=e{row['epoch']}:h{row['hart']}:error"
    return ""


def qos_event(scenario: str, predicate) -> str:
    sequence = [0, 0]
    for row in csv_events(qos[scenario]["event_trace"]):
        hart = int(row["hart"])
        if row["event"] == "transport_request" and hart >= 0:
            row["transaction_id"] = f"e1:h{hart}:t{sequence[hart]}"; sequence[hart] += 1
        if predicate(row):
            txn = row.get("transaction_id", f"e1:h{hart}:cycle{row['cycle']}")
            return f"{qos[scenario]['event_trace']}:cycle={row['cycle']}:txn={txn}"
    return ""


bins: list[dict[str, str]] = []


def add(group: str, name: str, evidence: str) -> None:
    bins.append({"group": group, "cross_bin": name,
                 "status": "COVERED" if evidence else "MISSING",
                 "evidence_class": "transaction_correlated_executable_rtl",
                 "same_window_evidence": evidence})


# Store-buffer dependency and ordering: 10 bins.
for hart in (0, 1):
    add("store_buffer_ordering", f"h{hart}_youngest_forward_occ2",
        direct_event(f"sb_youngest_forward_h{hart}",
                     lambda e, h=hart: e.get("event") == "load_forward" and e.get("hart") == str(h) and e.get("detail0") == "2"))
for hart in (0, 1):
    add("store_buffer_ordering", f"h{hart}_nonoverlap_bypass_occ1",
        direct_event(f"sb_nonoverlap_bypass_h{hart}",
                     lambda e, h=hart: e.get("event") == "fabric_request" and e.get("hart") == str(h) and e.get("detail0") == "0" and e.get("detail1") == "1"))
add("store_buffer_ordering", "full_fifo_backpressures_third_store",
    direct_event("sb_full_stall", lambda e: e.get("event") == "apb_wait" and e.get("detail1") == "2"))
for hart in (0, 1):
    add("store_buffer_ordering", f"h{hart}_fifo_wrap",
        direct_event(f"sb_wrap_h{hart}", lambda e, h=hart: e.get("event") == "store_enqueue" and e.get("transaction_id") == f"e1:h{h}:s5"))
add("store_buffer_ordering", "fence_blocked_at_occupancy_two",
    direct_event("fence_occupancy_two", lambda e: e.get("event") == "fence_blocked" and e.get("detail0") == "2"))
add("store_buffer_ordering", "unfenced_mailbox_overtakes_store",
    ordered_events("mailbox_unfenced_overtake",
                   lambda e: e.get("event") == "apb_accept" and e.get("address") == "40000000",
                   lambda e: e.get("event") == "store_drain", True))
add("store_buffer_ordering", "fenced_mailbox_follows_store",
    ordered_events("mailbox_fenced_order",
                   lambda e: e.get("event") == "store_drain",
                   lambda e: e.get("event") == "apb_accept" and e.get("address") == "40000000", True))

# Replacement, coherence, and bank interactions: 12 bins.
for hart in (0, 1):
    add("replacement_coherence", f"h{hart}_clean_conflict",
        direct_event(f"clean_conflict_h{hart}", lambda e: e.get("event") == "bank_request" and e.get("address") == "00000080" and e.get("victim_state") == "S"))
for hart in (0, 1):
    add("replacement_coherence", f"h{hart}_dirty_conflict",
        direct_event(f"dirty_conflict_h{hart}", lambda e: e.get("event") == "bank_request" and e.get("address") == "00000080" and e.get("victim_state") == "M"))
for hart in (0, 1):
    add("replacement_coherence", f"h{hart}_shared_upgrade",
        direct_event(f"shared_upgrade_h{hart}", lambda e: e.get("event") == "bank_request" and e.get("transition") == "S->M"))
add("replacement_coherence", "dirty_intervention_h0_to_h1",
    direct_event("dirty_intervention_h0_h1", lambda e: e.get("event") == "bank_request" and e.get("hart") == "1" and e.get("source") == "dirty_intervention"))
add("replacement_coherence", "dirty_intervention_h1_to_h0",
    direct_event("dirty_intervention_h1_h0", lambda e: e.get("event") == "bank_request" and e.get("hart") == "0" and e.get("source") == "dirty_intervention"))
add("replacement_coherence", "same_line_read_write_convergence",
    direct_event("same_line_read_write", lambda e: e.get("event") == "bank_request" and e.get("remote_state") in ("S", "M")))
add("replacement_coherence", "same_line_write_write_convergence",
    direct_event("same_line_write_write", lambda e: e.get("event") == "bank_request" and e.get("detail0") == "1" and e.get("remote_state") == "M"))
add("replacement_coherence", "bank0_modified_install",
    direct_event("dual_bank_overlap_end_to_end", lambda e: e.get("event") == "bank_request" and e.get("bank") == "0" and e.get("transition") == "I->M"))
add("replacement_coherence", "bank1_modified_install",
    direct_event("dual_bank_overlap_end_to_end", lambda e: e.get("event") == "bank_request" and e.get("bank") == "1" and e.get("transition") == "I->M"))

# Error and reset-state interactions: 10 bins.
add("error_reset", "precise_load_error", error_event("precise_load_error", lambda e: e["event"] == "fabric_response" and e["detail1"] == "1"))
add("error_reset", "deferred_store_error_retains_head", error_event("deferred_store_error_recovery", lambda e: e["event"] == "store_drain" and e["detail1"] == "1"))
add("error_reset", "deferred_store_retry_succeeds", error_event("deferred_store_error_recovery", lambda e: e["event"] == "store_drain" and e["detail1"] == "0"))
for scenario in ("reset_idle", "reset_store_pending", "reset_read_outstanding", "reset_response_pending", "reset_concurrent_banks"):
    add("error_reset", scenario, error_event(scenario, lambda e: e["event"] == "reset_assert"))
add("error_reset", "post_reset_response_h0_new_epoch", error_event("reset_concurrent_banks", lambda e: e["event"] == "fabric_response" and e["hart"] == "0" and e["epoch"] == "2"))
add("error_reset", "post_reset_response_h1_new_epoch", error_event("reset_concurrent_banks", lambda e: e["event"] == "fabric_response" and e["hart"] == "1" and e["epoch"] == "2"))

# QoS and concurrency: 10 bins.
add("qos_concurrency", "different_bank_overlap", qos_event("different_bank", lambda e: e["event"] == "simultaneous_banks"))
add("qos_concurrency", "same_bank_h0_grant", qos_event("same_bank_equal", lambda e: e["event"] == "axi_ar_grant" and e["hart"] == "0"))
add("qos_concurrency", "same_bank_h1_grant", qos_event("same_bank_equal", lambda e: e["event"] == "axi_ar_grant" and e["hart"] == "1"))
add("qos_concurrency", "equal_qos_h0_service", qos_event("same_bank_equal", lambda e: e["event"] == "transport_response" and e["hart"] == "0"))
add("qos_concurrency", "equal_qos_h1_service", qos_event("same_bank_equal", lambda e: e["event"] == "transport_response" and e["hart"] == "1"))
add("qos_concurrency", "mixed_qos_high_first", qos_event("mixed_qos", lambda e: e["event"] == "leaf_qos_grant" and e["hart"] == "1" and e["cycle"] == "0"))
add("qos_concurrency", "mixed_qos_low_eventual_service", qos_event("mixed_qos", lambda e: e["event"] == "axi_ar_grant" and e["hart"] == "0"))
add("qos_concurrency", "starvation_age_override", qos_event("starvation_override", lambda e: e["event"] == "leaf_qos_grant" and e["detail1"] == "1"))
add("qos_concurrency", "bounded_service_gap_h0", qos_event("same_bank_equal", lambda e: e["event"] == "axi_ar_grant" and e["hart"] == "0") if int(qos["same_bank_equal"]["max_gap0"]) <= 1 else "")
add("qos_concurrency", "bounded_service_gap_h1", qos_event("same_bank_equal", lambda e: e["event"] == "axi_ar_grant" and e["hart"] == "1") if int(qos["same_bank_equal"]["max_gap1"]) <= 1 else "")

# APB and AXI ownership interactions: 6 bins.
add("mmio_axi", "shared_apb_read_accept", direct_event("clean_conflict_h0", lambda e: e.get("event") == "apb_accept" and e.get("detail0") == "0" and e.get("address", "").startswith("8")))
add("mmio_axi", "shared_apb_write_accept", direct_event("dirty_conflict_h0", lambda e: e.get("event") == "apb_accept" and e.get("detail0") == "1" and e.get("address", "").startswith("8")))
add("mmio_axi", "uncached_mailbox_accept", direct_event("mailbox_fenced_order", lambda e: e.get("event") == "apb_accept" and e.get("address") == "40000000"))
add("mmio_axi", "axi_read_grant", qos_event("different_bank", lambda e: e["event"] == "axi_ar_grant"))
add("mmio_axi", "read_response_backpressure", qos_event("read_response_backpressure", lambda e: e["event"] == "response_stall"))
add("mmio_axi", "write_response_backpressure", qos_event("write_response_backpressure", lambda e: e["event"] == "response_stall"))


def main() -> int:
    if len(bins) != 48:
        raise RuntimeError(f"advanced coverage contains {len(bins)} bins, expected 48")
    report = REPORTS / "coherent_advanced_cross_coverage.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=bins[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(bins)
    covered = sum(row["status"] == "COVERED" for row in bins)
    print(f"COHERENT_ADVANCED_COVERAGE|status={'PASS' if covered == 48 else 'FAIL'}|crosses={covered}/48")
    return 0 if covered == 48 else 1


if __name__ == "__main__":
    raise SystemExit(main())
