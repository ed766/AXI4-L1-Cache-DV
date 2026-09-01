#!/usr/bin/env python3
"""Report executable antecedent activation for coherent assertions/invariants."""

from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"


def json_rows(root: Path) -> list[tuple[str, dict[str, object]]]:
    result = []
    for path in sorted(root.glob("*_enriched.jsonl")):
        for line in path.read_text().splitlines():
            if line:
                result.append((str(path.relative_to(ROOT)), json.loads(line)))
    return result


def csv_rows(paths: list[Path]) -> list[tuple[str, dict[str, str]]]:
    result = []
    for path in paths:
        with path.open() as handle:
            result.extend((str(path.relative_to(ROOT)), row) for row in csv.DictReader(handle))
    return result


def main() -> int:
    direct = json_rows(ROOT / "build/coherent_closure/traces")
    errors_report = list(csv.DictReader((REPORTS / "coherent_error_reset_summary.csv").open()))
    error_paths = [ROOT / row["event_trace"] for row in errors_report]
    errors = csv_rows(error_paths)
    qos_report = list(csv.DictReader((REPORTS / "coherent_qos_concurrency_summary.csv").open()))
    qos_paths = [ROOT / row["event_trace"] for row in qos_report]
    qos = csv_rows(qos_paths)
    all_rows = direct + errors + qos
    output = []

    def add(name: str, group: str, predicate) -> None:
        matches = [(source, row) for source, row in all_rows if predicate(row)]
        evidence = ""
        if matches:
            source, row = matches[0]
            evidence = f"{source}:cycle={row.get('cycle', 0)}"
        output.append({
            "assertion": name, "group": group, "antecedent_hits": str(len(matches)),
            "status": "ACTIVATED" if matches else "VACUOUS_OR_UNEXERCISED", "first_evidence": evidence,
        })

    add("a_store_buffer_bound", "store_buffer", lambda e: e.get("event") == "store_enqueue")
    add("a_forwarding_returns_youngest_match", "store_buffer", lambda e: e.get("event") == "load_forward" and e.get("detail0") == "2")
    add("a_failed_store_preserves_head", "store_buffer", lambda e: e.get("event") == "store_drain" and e.get("detail1") == "1")
    add("a_fence_waits_for_prior_stores", "store_buffer", lambda e: e.get("event") in ("fence_blocked", "fence_wait"))
    add("a_apb_stable_while_waiting", "apb", lambda e: e.get("event") == "apb_wait")
    add("a_uncached_write_after_fence", "apb", lambda e: e.get("event") == "apb_accept" and e.get("address") == "40000000")
    add("a_single_modified_owner", "msi", lambda e: e.get("event") == "bank_request" and e.get("transition") in ("I->M", "S->M", "M->M"))
    add("a_dirty_victim_committed_before_install", "msi", lambda e: e.get("event") == "bank_request" and e.get("victim_state") == "M" and e.get("local_hit") is False)
    add("a_dirty_intervention_precedes_grant", "msi", lambda e: e.get("event") == "bank_request" and e.get("source") == "dirty_intervention")
    add("a_shared_upgrade_invalidates_remote", "msi", lambda e: e.get("event") == "bank_request" and e.get("transition") == "S->M")
    add("a_bank_alias_matches", "transport", lambda e: e.get("event") in ("bank_request", "transport_request") and e.get("bank") in ("0", "1"))
    add("a_axi_response_owner_recorded", "transport", lambda e: e.get("event") in ("fabric_response", "transport_response"))
    add("a_response_stable", "transport", lambda e: e.get("event") == "response_stall")
    add("a_simultaneous_home_requests_use_distinct_banks", "transport", lambda e: e.get("event") == "simultaneous_banks")
    add("a_age_override_requires_presented_grant", "qos", lambda e: e.get("event") in ("qos_age_override", "leaf_qos_grant") and e.get("detail1") == "1")
    add("a_equal_qos_progress_h0", "qos", lambda e: e.get("event") == "axi_ar_grant" and e.get("hart") == "0")
    add("a_equal_qos_progress_h1", "qos", lambda e: e.get("event") == "axi_ar_grant" and e.get("hart") == "1")
    add("a_load_error_is_precise", "error", lambda e: e.get("event") == "fabric_response" and e.get("detail1") == "1")
    add("a_reset_epoch_contains_responses", "reset", lambda e: e.get("event") == "reset_assert")
    add("a_final_physical_state_matches_model", "reference", lambda e: e.get("event") in ("final_backing", "final_line"))

    report = REPORTS / "coherent_assertion_activation.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=output[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(output)
    activated = sum(row["status"] == "ACTIVATED" for row in output)
    print(f"COHERENT_ASSERTION_ACTIVATION|status={'PASS' if activated == len(output) else 'FAIL'}|activated={activated}/{len(output)}")
    return 0 if activated == len(output) else 1


if __name__ == "__main__":
    raise SystemExit(main())
