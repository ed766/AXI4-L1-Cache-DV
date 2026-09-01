#!/usr/bin/env python3
"""Replay executable crossover events through an independent MSI/data model."""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Line:
    state: str = "I"
    tag: int = 0
    data: list[int] = field(default_factory=lambda: [0, 0, 0, 0])


class Checker:
    def __init__(self) -> None:
        self.lines = [[[Line() for _ in range(8)] for _ in range(2)] for _ in range(2)]
        self.memory: dict[int, int] = {}
        self.pending: list[list[tuple[bool, int, str]]] = [[], []]
        self.store_buffer: list[list[tuple[int, int, str]]] = [[], []]
        self.store_fault_pending = [False, False]
        self.transaction_sequence = [0, 0]
        self.store_sequence = [0, 0]
        self.enriched: list[dict[str, object]] = []
        self.mismatches: list[str] = []

    def reset(self) -> None:
        self.lines = [[[Line() for _ in range(8)] for _ in range(2)] for _ in range(2)]
        self.pending = [[], []]
        self.store_buffer = [[], []]
        self.store_fault_pending = [False, False]
        self.transaction_sequence = [0, 0]
        self.store_sequence = [0, 0]

    def enqueue(self, row: dict[str, str]) -> None:
        hart = int(row["hart"])
        store_id = f"e{row['epoch']}:h{hart}:s{self.store_sequence[hart]}"
        self.store_sequence[hart] += 1
        entry = (int(row["address"], 16), int(row["data"], 16) & 0xffff_ffff, store_id)
        row["transaction_id"] = store_id
        if len(self.store_buffer[hart]) >= 2:
            self.mismatches.append(f"cycle_{row['cycle']}_hart{hart}_store_buffer_overflow")
            return
        self.store_buffer[hart].append(entry)
        if int(row["detail0"]) != len(self.store_buffer[hart]):
            self.mismatches.append(
                f"cycle_{row['cycle']}_hart{hart}_occupancy_expected_{len(self.store_buffer[hart])}_observed_{row['detail0']}")

    def drain(self, row: dict[str, str]) -> None:
        hart = int(row["hart"])
        observed = (int(row["address"], 16), int(row["data"], 16) & 0xffff_ffff)
        if not self.store_buffer[hart]:
            self.mismatches.append(f"cycle_{row['cycle']}_hart{hart}_drain_empty")
            return
        expected = self.store_buffer[hart][0]
        row["transaction_id"] = expected[2]
        if observed != expected[:2]:
            self.mismatches.append(
                f"cycle_{row['cycle']}_hart{hart}_drain_expected_{expected}_observed_{observed}")
        if row["detail1"] == "1":
            self.store_fault_pending[hart] = True
        else:
            self.store_buffer[hart].pop(0)
            self.store_fault_pending[hart] = False

    def forward(self, row: dict[str, str]) -> None:
        hart, address = int(row["hart"]), int(row["address"], 16)
        matching = [(data, store_id) for queued_address, data, store_id in self.store_buffer[hart]
                    if queued_address == address]
        if not matching:
            self.mismatches.append(f"cycle_{row['cycle']}_hart{hart}_forward_without_match")
            return
        observed = int(row["data"], 16) & 0xffff_ffff
        row["transaction_id"] = matching[-1][1]
        if observed != matching[-1][0]:
            self.mismatches.append(
                f"cycle_{row['cycle']}_hart{hart}_youngest_expected_{matching[-1][0]:08x}_observed_{observed:08x}")

    def request(self, row: dict[str, str]) -> None:
        hart, bank = int(row["hart"]), int(row["bank"])
        address, write, wdata = int(row["address"], 16), row["detail0"] == "1", int(row["data"], 16)
        other = 1 - hart
        index, tag, word = (address >> 4) & 7, address >> 7, (address >> 2) & 3
        local, remote = self.lines[hart][bank][index], self.lines[other][bank][index]
        victim_state, victim_tag = local.state, local.tag
        local_hit = local.state != "I" and local.tag == tag
        remote_hit = remote.state != "I" and remote.tag == tag
        prior_local, prior_remote = local.state if local_hit else "I", remote.state if remote_hit else "I"

        if not local_hit:
            if local.state == "M":
                old_base = ((local.tag << 3) | index) << 4
                for offset, value in enumerate(local.data): self.memory[old_base + offset * 4] = value
            if remote_hit:
                fill = list(remote.data)
                if remote.state == "M":
                    base = address & ~0xf
                    for offset, value in enumerate(remote.data): self.memory[base + offset * 4] = value
            else:
                base = address & ~0xf
                fill = [self.memory.get(base + offset * 4, 0) for offset in range(4)]
            local.tag, local.data = tag, fill

        source = "local_cache" if local_hit else ("dirty_intervention" if prior_remote == "M" else "home_memory")
        if write:
            if remote_hit: remote.state = "I"
            local.state = "M"; local.data[word] = wdata
            expected = wdata
        else:
            expected = local.data[word]
            # A read hit in Modified remains Modified. Only a read miss installs
            # Shared state and downgrades a remote modified owner.
            if not local_hit:
                local.state = "S"
                if remote_hit: remote.state = "S"
        transaction_id = f"e{row['epoch']}:h{hart}:t{self.transaction_sequence[hart]}"
        self.transaction_sequence[hart] += 1
        self.pending[hart].append((write, expected & 0xffff_ffff, transaction_id))
        cooked = dict(row)
        cooked.update({"transition": f"{prior_local}->{local.state}", "remote_state": prior_remote,
                       "source": source, "local_hit": local_hit, "remote_hit": remote_hit,
                       "victim_state": victim_state, "victim_tag": victim_tag,
                       "transaction_id": transaction_id})
        self.enriched.append(cooked)
        self.check_ownership(address, bank, index, tag)

    def response(self, row: dict[str, str]) -> None:
        hart, error = int(row["hart"]), row["detail1"] == "1"
        if not self.pending[hart]:
            if not error:
                self.mismatches.append(f"cycle_{row['cycle']}_hart{hart}_response_without_request")
            return
        write, expected, transaction_id = self.pending[hart].pop(0)
        row["transaction_id"] = transaction_id
        observed = int(row["data"], 16)
        if not write and not error and observed != expected:
            self.mismatches.append(
                f"cycle_{row['cycle']}_hart{hart}_data_expected_{expected:08x}_observed_{observed:08x}")

    def check_ownership(self, address: int, bank: int, index: int, tag: int) -> None:
        a, b = self.lines[0][bank][index], self.lines[1][bank][index]
        if a.tag == tag and b.tag == tag and a.state == "M" and b.state == "M":
            self.mismatches.append(f"dual_modified_{address:08x}")
        if a.tag == tag and b.tag == tag and ((a.state == "M" and b.state == "S") or
                                               (a.state == "S" and b.state == "M")):
            self.mismatches.append(f"shared_modified_conflict_{address:08x}")

    def final_backing(self, row: dict[str, str]) -> None:
        address = int(row["address"], 16)
        expected = self.memory.get(address, 0) & 0xffff_ffff
        observed = int(row["data"], 16) & 0xffff_ffff
        if observed != expected:
            self.mismatches.append(
                f"final_backing_{address:08x}_expected_{expected:08x}_observed_{observed:08x}")

    def final_line(self, row: dict[str, str]) -> None:
        hart, bank = int(row["hart"]), int(row["bank"])
        slot = int(row["detail1"])
        index, word = slot // 4, slot % 4
        expected = self.lines[hart][bank][index]
        observed_state = {0: "I", 1: "S", 2: "M"}.get(int(row["detail0"]), "?")
        observed_tag = int(row["address"], 16)
        observed_data = int(row["data"], 16) & 0xffff_ffff
        if observed_state != expected.state:
            self.mismatches.append(
                f"final_line_b{bank}_h{hart}_i{index}_state_expected_{expected.state}_observed_{observed_state}")
        if expected.state != "I" and observed_tag != expected.tag:
            self.mismatches.append(
                f"final_line_b{bank}_h{hart}_i{index}_tag_expected_{expected.tag:x}_observed_{observed_tag:x}")
        if expected.state != "I" and observed_data != expected.data[word]:
            self.mismatches.append(
                f"final_line_b{bank}_h{hart}_i{index}_w{word}_expected_{expected.data[word]:08x}_observed_{observed_data:08x}")


def check(path: Path, enriched_path: Path | None = None) -> tuple[bool, str, list[dict[str, object]]]:
    checker = Checker()
    for row in csv.DictReader(path.open()):
        event = row["event"]
        if event == "reset_assert": checker.reset()
        elif event == "memory_init": checker.memory[int(row["address"], 16)] = int(row["data"], 16)
        elif event == "store_enqueue": checker.enqueue(row)
        elif event == "store_drain": checker.drain(row)
        elif event == "load_forward": checker.forward(row)
        elif event == "bank_request": checker.request(row)
        elif event == "fabric_response": checker.response(row)
        elif event == "final_backing": checker.final_backing(row)
        elif event == "final_line": checker.final_line(row)
        checker.enriched.append(dict(row)) if event != "bank_request" else None
    if checker.pending[0] or checker.pending[1]: checker.mismatches.append("outstanding_response_at_end")
    if checker.store_buffer[0] or checker.store_buffer[1]: checker.mismatches.append("store_buffer_not_empty_at_end")
    if enriched_path:
        enriched_path.parent.mkdir(parents=True, exist_ok=True)
        enriched_path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in checker.enriched))
    return not checker.mismatches, checker.mismatches[0] if checker.mismatches else "none", checker.enriched


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(); parser.add_argument("trace", type=Path); parser.add_argument("--enriched", type=Path)
    args = parser.parse_args(); ok, mismatch, _ = check(args.trace, args.enriched)
    print(f"COHERENT_EVENT_MODEL|status={'PASS' if ok else 'FAIL'}|first_mismatch={mismatch}")
    raise SystemExit(0 if ok else 1)
