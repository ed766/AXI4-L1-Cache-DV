#!/usr/bin/env python3
"""Run depth-stated solver-backed coherent implementation proof/cover groups."""

from __future__ import annotations

import csv
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "coherent_formal"
REPORT = ROOT / "reports" / "coherent_formal_summary.csv"
GROUPS = (
    ("no_dual_modified_owner", "PROP_NO_DUAL_MODIFIED", "msi_implementation", "prove"),
    ("no_shared_plus_modified", "PROP_NO_SHARED_MODIFIED", "msi_implementation", "prove"),
    ("fifo_store_draining", "PROP_FIFO_ORDER", "store_buffer_implementation", "prove"),
    ("same_address_forwarding", "PROP_FORWARDING", "store_buffer_implementation", "prove"),
    ("fence_prior_store_order", "PROP_FENCE", "store_buffer_implementation", "prove"),
    # The preservation property is a reset-reachable bounded proof. Its
    # supporting memory invariant does not close k-induction from arbitrary
    # unreachable initial states with this Yosys frontend.
    ("failed_store_head_preservation", "PROP_FAILED_HEAD", "store_buffer_implementation", "bmc"),
    ("dirty_victim_writeback_before_install", "PROP_DIRTY_VICTIM_WB", "msi_implementation", "prove"),
    ("fenced_publication_freshness", "PROP_PUBLICATION", "reduced_architectural_model", "prove"),
    ("response_hart_ownership", "PROP_RESPONSE_ROUTE", "reduced_architectural_model", "prove"),
    ("reset_epoch_containment", "PROP_RESET_EPOCH", "reduced_architectural_model", "prove"),
)


def find_sby() -> str:
    explicit = os.environ.get("SBY")
    candidates = [explicit, shutil.which("sby"), str(Path.home() / ".cache/oss-cad-suite/bin/sby")]
    for candidate in candidates:
        if candidate and Path(candidate).exists(): return candidate
    raise FileNotFoundError("sby; install OSS CAD Suite or set SBY")


def run_task(sby: str, group: str, define: str, scope: str, mode: str) -> tuple[str, float, str]:
    work = BUILD / f"{group}_{mode}"
    shutil.rmtree(work, ignore_errors=True)
    config = BUILD / f"{group}_{mode}.sby"
    config.parent.mkdir(parents=True, exist_ok=True)
    if scope == "msi_implementation":
        script = f"read -formal -DSYNTHESIS -DFORMAL_OBSERVE -DFORMAL_IMPL_MSI -D{define} coherent_impl_properties.sv msi_two_cache_subsystem.sv\nprep -top coherent_impl_properties"
        files = f"{ROOT / 'formal/coherent_impl_properties.sv'}\n{ROOT / 'rtl/coherence/msi_two_cache_subsystem.sv'}"
    elif scope == "store_buffer_implementation":
        script = f"read -formal -DSYNTHESIS -DFORMAL_OBSERVE -D{define} coherent_impl_properties.sv dual_hart_apb_store_buffer.sv\nprep -top coherent_impl_properties"
        files = f"{ROOT / 'formal/coherent_impl_properties.sv'}\n{ROOT / 'integration/rv32_coherent/rtl/dual_hart_apb_store_buffer.sv'}"
    else:
        script = f"read -formal -D{define} coherent_leaf_properties.sv\nprep -top coherent_leaf_properties"
        files = str(ROOT / 'formal/coherent_leaf_properties.sv')
    config.write_text(f"""[options]
mode {mode}
depth 20

[engines]
smtbmc boolector

[script]
{script}

[files]
{files}
""")
    started = time.monotonic()
    result = subprocess.run([sby, "-f", "-d", str(work), str(config)], cwd=ROOT,
                            text=True, capture_output=True, timeout=120)
    runtime = time.monotonic() - started
    log = result.stdout + result.stderr
    (BUILD / f"{group}_{mode}.log").write_text(log)
    return ("PASS" if result.returncode == 0 else "FAIL", runtime,
            "none" if result.returncode == 0 else log.splitlines()[-1] if log.splitlines() else "tool_failure")


def main() -> int:
    sby = find_sby()
    rows = []
    for group, define, scope, proof_task in GROUPS:
        prove, prove_time, prove_detail = run_task(sby, group, define, scope, proof_task)
        cover, cover_time, cover_detail = run_task(sby, group, define, scope, "cover")
        rows.append({
            "property_group": group,
            "proof_mode": "solver_bounded_safety" if proof_task == "bmc" else "solver_inductive_safety",
            "implementation_scope": scope,
            "depth": 20, "prove_status": prove, "cover_status": cover,
            # Wall-clock time remains in ignored build logs; normalized release
            # evidence must be deterministic across machines and CI runners.
            "runtime_seconds": "build_log_only",
            "detail": prove_detail if prove != "PASS" else cover_detail,
        })
    REPORT.parent.mkdir(exist_ok=True)
    with REPORT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["prove_status"] == "PASS" and row["cover_status"] == "PASS" for row in rows)
    expected = len(GROUPS)
    print(f"COHERENT_FORMAL|status={'PASS' if passed == expected else 'FAIL'}|groups={passed}/{expected}")
    return 0 if passed == expected else 1


if __name__ == "__main__":
    raise SystemExit(main())
