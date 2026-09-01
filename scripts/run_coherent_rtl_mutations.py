#!/usr/bin/env python3
"""Sensitize compile-time coherent crossover mutations with executable RTL."""

from __future__ import annotations

import csv
import subprocess
from pathlib import Path

from build_coherent_firmware import build as build_firmware, build_fault
from run_coherent_closure import compile_bench as compile_closure_bench
from run_coherent_rv32 import BUILD, ROOT, SUMMARY_RE, compile_sim

CASES = (
    ("skipped_invalidation", ("MSI_MUT_SKIP_INVALIDATE",), 6, "coherence_assertion"),
    ("stale_intervention_data", ("COH_MUT_STALE_INTERVENTION",), 5, "firmware_scoreboard"),
    ("illegal_dual_modified", ("MSI_MUT_SKIP_INVALIDATE",), 6, "single_modified_assertion"),
    ("dropped_buffered_store", ("COH_MUT_DROP_BUFFERED_STORE",), 0, "firmware_scoreboard"),
    ("broken_same_address_forwarding", ("COH_MUT_BROKEN_FORWARDING",), 8, "forwarding_scoreboard"),
    ("early_fence_completion", ("COH_MUT_EARLY_FENCE",), 0, "fence_order_assertion"),
    ("response_hart_corruption", ("COH_MUT_RESPONSE_HART",), 0, "response_owner_assertion"),
    ("axi_home_id_corruption", ("COH_MUT_AXI_HOME_ID",), 0, "axi_id_assertion"),
    ("bank_alias_misroute", ("COH_MUT_BANK_ALIAS",), 9, "bank_route_assertion"),
    ("failed_store_pop", ("COH_MUT_POP_FAILED_STORE",), -1, "deferred_store_scoreboard"),
)

INTEGRATION_CASES = (
    ("older_store_forwarded", "COH_MUT_FORWARD_OLDEST", "sb_youngest_forward_h0", "youngest_forwarding_scoreboard"),
    ("younger_store_drains_past_failed_head", "COH_MUT_IGNORE_STORE_FAULT", "store_fault_occupancy_two", "failed_head_ordering_check"),
    ("premature_fence_completion", "COH_MUT_FENCE_IGNORES_BUFFER", "fence_occupancy_two", "fence_quiescence_assertion"),
    ("dirty_victim_writeback_skipped", "COH_MUT_SKIP_DIRTY_VICTIM_WB", "dirty_conflict_h0", "dirty_replacement_check"),
    ("simultaneous_bank_owner_swap", "COH_MUT_SWAP_BANK1_OWNER", "dual_bank_overlap_end_to_end", "response_owner_assertion"),
    ("failed_enqueue_occupancy_lost", "COH_MUT_FAILED_ENQUEUE_COUNT", "simultaneous_enqueue_failed_drain", "failed_head_occupancy_check"),
)


def main() -> int:
    rows = []
    for name, defines, workload, bucket in CASES:
        binary = compile_sim(defines, ("STORE_DRAIN_DELAY=40",))
        images = (build_fault(1, BUILD / "fault_firmware") if workload < 0 else
                  build_firmware(workload, "-O2", BUILD / "firmware"))
        command = [str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
                   f"+TRACE_FILE={BUILD / ('mutation_' + name + '.csv')}",
                   f"+EVENT_TRACE_FILE={BUILD / ('mutation_' + name + '_events.csv')}" ]
        if workload < 0:
            command += ["+FAULT_VALID=1", "+FAULT_WRITE=1", "+FAULT_ADDR=00000000"]
        try:
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=8)
            output = result.stdout + result.stderr
            summary = SUMMARY_RE.search(output)
            nominal_pass = result.returncode == 0 and summary is not None and "result0=00000000" in output and "result1=00000000" in output
            detected = not nominal_pass
            detail = "nonzero_or_scoreboard_failure" if detected else "mutation_survived"
        except subprocess.TimeoutExpired:
            detected, detail = True, "timeout_deadlock"
        rows.append({"mutation": name, "status": "DETECTED" if detected else "MISSED",
                     "detection_bucket": bucket, "detail": detail})
    for name, define, scenario, bucket in INTEGRATION_CASES:
        binary = compile_closure_bench((define,))
        event_trace = ROOT / "build" / "coherent_closure" / f"mutation_{name}_events.csv"
        try:
            result = subprocess.run([
                str(binary), f"+TEST={scenario}", f"+EVENT_TRACE_FILE={event_trace}",
            ], cwd=ROOT, text=True, capture_output=True, timeout=8)
            detected = result.returncode != 0 or "status=FAIL" in (result.stdout + result.stderr)
            detail = "assertion_or_scoreboard_failure" if detected else "mutation_survived"
        except subprocess.TimeoutExpired:
            detected, detail = True, "timeout_deadlock"
        rows.append({"mutation": name, "status": "DETECTED" if detected else "MISSED",
                     "detection_bucket": bucket, "detail": detail})
    # Reset-epoch corruption requires the complete RV32 top so a reset can
    # interrupt real firmware execution and reveal a post-reset ghost response.
    binary = compile_sim(("COH_MUT_RESET_GHOST_RESPONSE",), ("STORE_DRAIN_DELAY=40",))
    images = build_firmware(0, "-O2", BUILD / "firmware")
    try:
        result = subprocess.run([
            str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
            f"+TRACE_FILE={BUILD / 'mutation_reset_epoch.csv'}",
            f"+EVENT_TRACE_FILE={BUILD / 'mutation_reset_epoch_events.csv'}",
            "+RESET_CYCLE=150", "+RESET_HOLD=3",
        ], cwd=ROOT, text=True, capture_output=True, timeout=8)
        detected = result.returncode != 0
        detail = "reset_epoch_assertion" if detected else "mutation_survived"
    except subprocess.TimeoutExpired:
        detected, detail = True, "timeout_deadlock"
    rows.append({"mutation": "stale_reset_epoch_response", "status": "DETECTED" if detected else "MISSED",
                 "detection_bucket": "reset_epoch_containment", "detail": detail})
    report = ROOT / "reports" / "coherent_rtl_mutation_summary.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "DETECTED" for row in rows)
    expected = len(CASES) + len(INTEGRATION_CASES) + 1
    print(f"COHERENT_RTL_MUTATIONS|status={'PASS' if passed == expected else 'FAIL'}|detected={passed}/{expected}")
    return 0 if passed == expected else 1


if __name__ == "__main__": raise SystemExit(main())
