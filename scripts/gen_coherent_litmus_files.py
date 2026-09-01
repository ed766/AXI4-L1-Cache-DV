#!/usr/bin/env python3
"""Emit pinned-input RISC-V litmus files for external herd7 outcome queries."""

from __future__ import annotations

from pathlib import Path

from run_coherent_model import LITMUS

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "integration" / "rv32_coherent" / "litmus"
POINTERS = {"x": "x5", "y": "x6", "z": "x7"}


def instructions(ops) -> tuple[list[str], list[str]]:
    lines, result_regs = [], []
    read_index = 0
    for op in ops:
        if op.kind == "W":
            lines += [f"li x10,{op.value}", f"sw x10,0({POINTERS[op.address]})"]
        elif op.kind == "R":
            reg = f"x{8 + read_index}"
            lines.append(f"lw {reg},0({POINTERS[op.address]})")
            result_regs.append(reg)
            read_index += 1
        else:
            lines.append("fence rw,rw")
    return lines, result_regs


def emit(test) -> None:
    left, lregs = instructions(test.hart0)
    right, rregs = instructions(test.hart1)
    count = max(len(left), len(right))
    left += [""] * (count - len(left)); right += [""] * (count - len(right))
    table = "\n".join(f" {a:<22} | {b:<22} ;" for a, b in zip(left, right))
    conditions = []
    if lregs: conditions.append(f"0:{lregs[0]}=0")
    if rregs: conditions.append(f"1:{rregs[-1]}=0")
    if not conditions: conditions.append("x=0")
    condition_text = " /\\ ".join(conditions)
    text = f"""RISCV {test.name}
{{
0:x5=x; 0:x6=y; 0:x7=z;
1:x5=x; 1:x6=y; 1:x7=z;
}}
 P0                     | P1                     ;
{table}
exists ({condition_text})
"""
    (OUT / f"{test.name}.litmus").write_text(text)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for test in LITMUS: emit(test)
    print(f"COHERENT_LITMUS_FILES|status=PASS|files={len(LITMUS)}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
