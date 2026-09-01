#!/usr/bin/env python3
"""Build separate freestanding RV32I ROMs for both coherent harts."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FW = ROOT / "integration" / "rv32_coherent" / "firmware"


def locate(name: str) -> str:
    prefix = os.environ.get("RISCV_TOOLCHAIN_PREFIX", "")
    candidates = []
    if prefix:
      candidates.append(Path(prefix + name))
    candidates += [
        ROOT.parent / "ucie_chiplet_soc" / "chiplet_extension" / "build" /
        "rv32_toolchain" / "root" / "usr" / "bin" / f"riscv64-unknown-elf-{name}",
        Path(f"/usr/bin/riscv64-unknown-elf-{name}"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    found = shutil.which(f"riscv64-unknown-elf-{name}")
    if found:
        return found
    raise FileNotFoundError(f"riscv64-unknown-elf-{name}; install it or set RISCV_TOOLCHAIN_PREFIX")


def binary_to_hex(binary: Path, output: Path) -> None:
    data = binary.read_bytes()
    data += bytes((-len(data)) % 4)
    output.write_text("".join(
        f"{int.from_bytes(data[idx:idx + 4], 'little'):08x}\n"
        for idx in range(0, len(data), 4)
    ))


def build(workload: int, optimization: str, out: Path) -> list[Path]:
    gcc, objcopy = locate("gcc"), locate("objcopy")
    outputs = []
    out.mkdir(parents=True, exist_ok=True)
    for hart in range(2):
        stem = out / f"workload{workload}_{optimization[1:]}_hart{hart}"
        elf, binary, hex_file = stem.with_suffix(".elf"), stem.with_suffix(".bin"), stem.with_suffix(".hex")
        command = [
            gcc, "-march=rv32i_zicsr", "-mabi=ilp32", optimization,
            "-ffreestanding", "-nostdlib", "-fno-builtin", "-fno-pic",
            "-fno-stack-protector", "-msmall-data-limit=0", "-mno-relax",
            f"-DHART_ID={hart}", f"-DWORKLOAD_ID={workload}",
            str(FW / "crt0.S"), str(FW / "coherent_workload.c"),
            f"-T{FW / 'link.ld'}", "-Wl,--build-id=none", "-o", str(elf),
        ]
        subprocess.run(command, check=True)
        subprocess.run([objcopy, "-O", "binary", "--only-section=.text", str(elf), str(binary)], check=True)
        binary_to_hex(binary, hex_file)
        outputs.append(hex_file)
    manifest = out / f"workload{workload}_{optimization[1:]}.sha256"
    manifest.write_text("".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in outputs
    ))
    return outputs


def build_litmus(litmus_id: int, out: Path) -> list[Path]:
    gcc, objcopy = locate("gcc"), locate("objcopy")
    outputs = []
    out.mkdir(parents=True, exist_ok=True)
    for hart in range(2):
        stem = out / f"litmus{litmus_id}_hart{hart}"
        elf, binary, hex_file = stem.with_suffix(".elf"), stem.with_suffix(".bin"), stem.with_suffix(".hex")
        command = [
            gcc, "-march=rv32i_zicsr", "-mabi=ilp32", "-O2",
            "-ffreestanding", "-nostdlib", "-fno-builtin", "-fno-pic",
            "-fno-stack-protector", "-msmall-data-limit=0", "-mno-relax",
            f"-DHART_ID={hart}", f"-DLITMUS_ID={litmus_id}",
            str(FW / "crt0.S"), str(FW / "coherent_litmus.c"),
            f"-T{FW / 'link.ld'}", "-Wl,--build-id=none", "-o", str(elf),
        ]
        subprocess.run(command, check=True)
        subprocess.run([objcopy, "-O", "binary", "--only-section=.text", str(elf), str(binary)], check=True)
        binary_to_hex(binary, hex_file)
        outputs.append(hex_file)
    return outputs


def build_fault(mode: int, out: Path) -> list[Path]:
    gcc, objcopy = locate("gcc"), locate("objcopy")
    outputs = []
    out.mkdir(parents=True, exist_ok=True)
    for hart in range(2):
        stem = out / f"fault{mode}_hart{hart}"
        elf, binary, hex_file = stem.with_suffix(".elf"), stem.with_suffix(".bin"), stem.with_suffix(".hex")
        command = [
            gcc, "-march=rv32i_zicsr", "-mabi=ilp32", "-O2", "-ffreestanding",
            "-nostdlib", "-fno-builtin", "-fno-pic", "-fno-stack-protector",
            "-msmall-data-limit=0", "-mno-relax", f"-DHART_ID={hart}", f"-DFAULT_MODE={mode}",
            str(FW / "crt0.S"), str(FW / "coherent_trap.S"), str(FW / "coherent_fault.c"),
            f"-T{FW / 'link.ld'}", "-Wl,--build-id=none", "-o", str(elf),
        ]
        subprocess.run(command, check=True)
        subprocess.run([objcopy, "-O", "binary", "--only-section=.text", str(elf), str(binary)], check=True)
        binary_to_hex(binary, hex_file); outputs.append(hex_file)
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workload", type=int, default=0, choices=range(10))
    parser.add_argument("--optimization", default="-O2", choices=("-O0", "-O2", "-Os"))
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "coherent" / "firmware")
    args = parser.parse_args()
    paths = build(args.workload, args.optimization, args.output)
    print("COHERENT_FIRMWARE|status=PASS|images=" + ",".join(str(p.relative_to(ROOT)) for p in paths))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
