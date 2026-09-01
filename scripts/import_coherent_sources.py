#!/usr/bin/env python3
"""Import and checksum-lock self-authored RV32/fabric sources for the crossover lane."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "integration" / "rv32_coherent" / "vendor"

SOURCES = {
    "rv32/rv32_core.sv": ("ucie_chiplet_soc", "base_soc/rtl/pd1_rv32/rv32_core.sv"),
    "rv32/rv32_rom_feeder.sv": (
        "ucie_chiplet_soc", "chiplet_extension/rtl/firmware/rv32_rom_feeder.sv"
    ),
    "rv32/rv32_iss.py": ("ucie_chiplet_soc", "chiplet_extension/scripts/rv32_iss.py"),
    "axi/axi4_qos_fabric.sv": ("axi4_qos_fabric_dv", "rtl/axi4_qos_fabric.sv"),
    "axi/qos_arbiter.sv": ("axi4_qos_fabric_dv", "rtl/qos_arbiter.sv"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def revision(repo: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, text=True, capture_output=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=ROOT.parent)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    lock_path = ROOT / "integration" / "rv32_coherent" / "provenance.lock.json"

    if args.verify:
        lock = json.loads(lock_path.read_text())
        failed = []
        for row in lock["files"]:
            path = ROOT / row["destination"]
            if not path.exists() or digest(path) != row["sha256"]:
                failed.append(row["destination"])
        if failed:
            print("PROVENANCE|status=FAIL|files=" + ",".join(failed))
            return 1
        print(f"PROVENANCE|status=PASS|files={len(lock['files'])}")
        return 0

    rows = []
    for destination, (repo_name, source_name) in SOURCES.items():
        repo = args.source_root / repo_name
        source = repo / source_name
        target = DEST / destination
        if not source.exists():
            raise FileNotFoundError(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        rows.append({
            "repository": repo_name,
            "source_revision": revision(repo),
            "source": source_name,
            "destination": str(target.relative_to(ROOT)),
            "sha256": digest(target),
        })
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path.write_text(json.dumps({"schema": 1, "files": rows}, indent=2) + "\n")
    print(f"PROVENANCE|status=IMPORTED|files={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
