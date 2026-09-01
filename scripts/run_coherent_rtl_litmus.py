#!/usr/bin/env python3
"""Execute 16 two-hart litmus pairs under 25 RTL schedules each."""

from __future__ import annotations

import csv
import json
import re
import subprocess
from pathlib import Path

from build_coherent_firmware import build_litmus
from check_coherent_rtl_events import check as check_events
from run_coherent_model import LITMUS
from run_coherent_rv32 import BUILD, REPORTS, ROOT, compile_sim

SUMMARY_RE = re.compile(r"COHERENT_SUMMARY\|(?P<body>[^\n]+)")


def fields(body: str) -> dict[str, str]:
    return dict(item.split("=", 1) for item in body.split("|") if "=" in item)


def main() -> int:
    subprocess.run(["python3", "scripts/run_coherent_herd.py", "--require"], cwd=ROOT, check=True)
    allowed = json.loads((REPORTS / "coherent_herd_allowed_outcomes.json").read_text())
    binary = compile_sim()
    rows = []
    trace_root = BUILD / "rtl_litmus_traces"
    trace_root.mkdir(parents=True, exist_ok=True)
    firmware_root = BUILD / "litmus_firmware"

    for litmus_id, test in enumerate(LITMUS):
        images = build_litmus(litmus_id, firmware_root)
        legal = {tuple(pair) for pair in allowed[test.name]}
        for schedule in range(25):
            seed = 0x811c + litmus_id * 4099 + schedule * 131
            issue_stall = (0, 10, 25, 40, 55)[schedule % 5]
            backpressure = (0, 25, 50, 75)[(schedule // 5) % 4]
            stem = f"{test.name.lower()}_{schedule:02d}"
            rvfi_trace = trace_root / f"{stem}_rvfi.csv"
            event_trace = trace_root / f"{stem}_events.csv"
            command = [
                str(binary), f"+HART0_HEX={images[0]}", f"+HART1_HEX={images[1]}",
                f"+TRACE_FILE={rvfi_trace}", f"+EVENT_TRACE_FILE={event_trace}",
                f"+SCHEDULE_SEED={seed}", f"+ISSUE_STALL_PERCENT={issue_stall}",
                f"+AXI_BACKPRESSURE_PERCENT={backpressure}", "+QOS0=4", "+QOS1=4",
            ]
            result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=20)
            match = SUMMARY_RE.search(result.stdout + result.stderr)
            data = fields(match.group("body")) if match else {}
            enriched_trace = trace_root / f"{stem}_enriched.jsonl"
            model_ok, model_mismatch, _ = check_events(event_trace, enriched_trace) if event_trace.exists() else (False, "missing_event_trace", [])
            observed = (int(data.get("observed0", "ffffffff"), 16),
                        int(data.get("observed1", "ffffffff"), 16))
            permitted = observed in legal
            passed = (result.returncode == 0 and match is not None and permitted and model_ok and
                      data.get("done0") == "1" and data.get("done1") == "1")
            rows.append({
                "litmus": test.name, "family": test.family,
                "fenced": str(test.fenced).lower(), "schedule": str(schedule),
                "seed": str(seed), "issue_stall_percent": str(issue_stall),
                "backpressure_percent": str(backpressure),
                "r0": str(observed[0]), "r1": str(observed[1]),
                "outcome": f"{observed[0]},{observed[1]}",
                "herd_allowed_outcomes": str(len(legal)),
                "status": "PASS" if passed else "FAIL",
                "first_mismatch": "none" if passed else
                    ("herd_forbidden_outcome" if not permitted else
                     (model_mismatch if not model_ok else "rtl_failure")),
                "cycles": data.get("cycles", "0"),
                "simultaneous_bank_cycles": data.get("simultaneous_banks", "0"),
                "axi_wait_cycles": data.get("axi_wait", "0"),
                "rvfi_trace": str(rvfi_trace.relative_to(ROOT)),
                "event_trace": str(event_trace.relative_to(ROOT)),
                "enriched_trace": str(enriched_trace.relative_to(ROOT)),
            })

    report = REPORTS / "coherent_rtl_litmus_summary.csv"
    with report.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_RTL_LITMUS|status={'PASS' if passed == len(rows) else 'FAIL'}|passed={passed}/{len(rows)}")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
