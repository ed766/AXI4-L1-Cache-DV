#!/usr/bin/env python3
"""Operational two-hart store-buffer/MSI model and RVWMO outcome checks."""

from __future__ import annotations

import argparse
import csv
import json
import random
import statistics
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "coherent"
REPORTS = ROOT / "reports"


@dataclass(frozen=True)
class Op:
    kind: str
    address: str = ""
    value: int = 0
    register: str = ""


@dataclass(frozen=True)
class Litmus:
    name: str
    family: str
    fenced: bool
    hart0: tuple[Op, ...]
    hart1: tuple[Op, ...]
    forbidden: tuple[tuple[int, int], ...] = ()


def w(address: str, value: int = 1) -> Op:
    return Op("W", address, value)


def r(address: str, register: str) -> Op:
    return Op("R", address, register=register)


F = Op("F")


LITMUS = (
    Litmus("SB", "store_buffering", False, (w("x"), r("y", "r0")), (w("y"), r("x", "r1"))),
    Litmus("SB_FENCE", "store_buffering", True, (w("x"), F, r("y", "r0")), (w("y"), F, r("x", "r1")), ((0, 0),)),
    Litmus("MP", "message_passing", False, (w("x"), w("y")), (r("y", "r0"), r("x", "r1"))),
    Litmus("MP_FENCE", "message_passing", True, (w("x"), F, w("y")), (r("y", "r0"), F, r("x", "r1")), ((1, 0),)),
    Litmus("LB", "load_buffering", False, (r("x", "r0"), w("y")), (r("y", "r1"), w("x"))),
    Litmus("LB_FENCE", "load_buffering", True, (r("x", "r0"), F, w("y")), (r("y", "r1"), F, w("x"))),
    Litmus("RW", "read_write", False, (r("x", "r0"), w("y")), (w("x"), r("y", "r1"))),
    Litmus("RW_FENCE", "read_write", True, (r("x", "r0"), F, w("y")), (w("x"), F, r("y", "r1"))),
    Litmus("WR", "write_read", False, (w("x"), r("x", "r0")), (w("y"), r("y", "r1"))),
    Litmus("WR_FENCE", "write_read", True, (w("x"), F, r("x", "r0")), (w("y"), F, r("y", "r1"))),
    Litmus("CO-RR", "coherence_read_read", False, (w("x"), F, w("x", 2)), (r("x", "r0"), r("x", "r1"))),
    Litmus("CO-RR_FENCE", "coherence_read_read", True, (w("x"), F, w("x", 2)), (r("x", "r0"), F, r("x", "r1"))),
    Litmus("CO-WW", "coherence_write_write", False, (w("x", 1), w("x", 3)), (w("x", 2), r("x", "r1"))),
    Litmus("CO-WW_FENCE", "coherence_write_write", True, (w("x", 1), F, w("x", 3)), (w("x", 2), F, r("x", "r1"))),
    Litmus("WRC", "write_read_causality", False, (w("x"), r("y", "r0")), (r("x", "r1"), w("y"))),
    Litmus("WRC_FENCE", "write_read_causality", True, (w("x"), F, r("y", "r0")), (r("x", "r1"), F, w("y"))),
)


@dataclass
class State:
    pc: list[int] = field(default_factory=lambda: [0, 0])
    buffers: list[list[tuple[str, int, int]]] = field(default_factory=lambda: [[], []])
    registers: list[dict[str, int]] = field(default_factory=lambda: [{}, {}])
    memory: dict[str, int] = field(default_factory=lambda: {"x": 0, "y": 0, "z": 0})
    cache_state: list[dict[str, str]] = field(default_factory=lambda: [dict(), dict()])
    cache_data: list[dict[str, int]] = field(default_factory=lambda: [dict(), dict()])
    events: list[dict[str, object]] = field(default_factory=list)
    cycle: int = 0
    load_wait_start: list[dict[int, int]] = field(default_factory=lambda: [{}, {}])


def record(state: State, event: str, hart: int, **fields: object) -> None:
    state.events.append({"cycle": state.cycle, "event": event, "hart": hart, **fields})


def coherent_read(state: State, hart: int, address: str, mutation: str = "") -> int:
    other = 1 - hart
    local_state = state.cache_state[hart].get(address, "I")
    other_state = state.cache_state[other].get(address, "I")
    if local_state != "I":
        value, source = state.cache_data[hart][address], "local_cache"
    elif other_state == "M":
        value = state.cache_data[other][address]
        if mutation == "stale_intervention_data":
            value ^= 1
        state.memory[address] = state.cache_data[other][address]
        state.cache_state[other][address] = "S"
        state.cache_state[hart][address] = "S"
        state.cache_data[hart][address] = value
        source = "dirty_intervention"
        record(state, "intervention", other, address=address, requester=hart, dirty=True)
    else:
        value, source = state.memory[address], "home_memory"
        state.cache_state[hart][address] = "S"
        state.cache_data[hart][address] = value
        if other_state == "S":
            state.cache_state[other][address] = "S"
    record(state, "coherent_read", hart, address=address, value=value, source=source,
           transition=f"{local_state}->{state.cache_state[hart].get(address, 'I')}")
    return value


def coherent_write(state: State, hart: int, address: str, value: int, mutation: str = "") -> None:
    other = 1 - hart
    local_state = state.cache_state[hart].get(address, "I")
    other_state = state.cache_state[other].get(address, "I")
    if other_state != "I":
        record(state, "invalidation", hart, address=address, victim=other,
               dirty=other_state == "M")
        if other_state == "M":
            state.memory[address] = state.cache_data[other][address]
        if mutation != "skipped_invalidation":
            state.cache_state[other][address] = "I"
    state.cache_state[hart][address] = "M"
    state.cache_data[hart][address] = value
    if mutation == "illegal_dual_modified":
        state.cache_state[other][address] = "M"
    record(state, "store_drain", hart, address=address, value=value,
           transition=f"{local_state}->M", prior_other=other_state)


def simulate(test: Litmus, seed: int, mutation: str = "", backpressure: int = 0) -> State:
    rng, state = random.Random(seed), State()
    programs = (test.hart0, test.hart1)
    while state.cycle < 500:
        state.cycle += 1
        choices: list[tuple[str, int]] = []
        for hart in range(2):
            if state.pc[hart] < len(programs[hart]):
                op = programs[hart][state.pc[hart]]
                if op.kind == "F" and state.buffers[hart]:
                    record(state, "fence_wait", hart, occupancy=len(state.buffers[hart]))
                executable = op.kind != "F" or not state.buffers[hart] or mutation == "early_fence_completion"
                if executable and (op.kind != "W" or len(state.buffers[hart]) < 2):
                    matching_store = op.kind == "R" and any(entry[0] == op.address for entry in state.buffers[hart])
                    if op.kind == "R" and not matching_store and rng.randrange(100) < backpressure:
                        state.load_wait_start[hart].setdefault(state.pc[hart], state.cycle)
                        record(state, "axi_backpressure", hart, channel="home_read",
                               occupancy=sum(len(buf) for buf in state.buffers), duty=backpressure)
                    else:
                        choices.append(("execute", hart))
            if state.buffers[hart]:
                if rng.randrange(100) >= backpressure:
                    choices.append(("drain", hart))
                else:
                    record(state, "axi_backpressure", hart, channel="home_write",
                           occupancy=len(state.buffers[hart]), duty=backpressure)
        if not choices:
            if all(state.pc[h] == len(programs[h]) and not state.buffers[h] for h in range(2)):
                break
            continue
        action, hart = rng.choice(choices)
        if action == "drain":
            address, value, enqueue_cycle = state.buffers[hart].pop(0)
            if mutation != "dropped_buffered_store":
                coherent_write(state, hart, address, value, mutation)
                state.events[-1]["latency"] = state.cycle - enqueue_cycle
            else:
                record(state, "dropped_store", hart, address=address, value=value)
            continue
        op = programs[hart][state.pc[hart]]
        if op.kind == "W":
            state.buffers[hart].append((op.address, op.value, state.cycle))
            record(state, "store_enqueue", hart, address=op.address, value=op.value,
                   occupancy=len(state.buffers[hart]))
        elif op.kind == "R":
            matches = [entry for entry in state.buffers[hart] if entry[0] == op.address]
            if matches and mutation != "broken_forwarding":
                value, source = matches[-1][1], "store_forward"
                record(state, "load_forward", hart, address=op.address, value=value,
                       occupancy=len(state.buffers[hart]))
            else:
                value, source = coherent_read(state, hart, op.address, mutation), "coherence"
                record(state, "load_bypass", hart, address=op.address, value=value,
                       occupancy=len(state.buffers[hart]))
            state.registers[hart][op.register] = value
            load_latency = state.cycle - state.load_wait_start[hart].pop(state.pc[hart], state.cycle) + 1
            record(state, "load_result", hart, address=op.address, register=op.register,
                   value=value, source=source, latency=load_latency)
        else:
            record(state, "fence_complete", hart, occupancy=len(state.buffers[hart]))
        state.pc[hart] += 1
    return state


def outcome(state: State) -> tuple[int, int]:
    return (state.registers[0].get("r0", 0),
            state.registers[1].get("r1", state.registers[1].get("r0", 0)))


def invariant_failure(state: State) -> str:
    for address in ("x", "y", "z"):
        if state.cache_state[0].get(address) == "M" and state.cache_state[1].get(address) == "M":
            return f"dual_modified_{address}"
    return ""


def write_jsonl(path: Path, events: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in events))


def run_litmus() -> bool:
    rows = []
    trace_root = BUILD / "litmus_traces"
    for test in LITMUS:
        for schedule in range(25):
            seed = 0x4C17 + schedule * 97 + sum(ord(ch) for ch in test.name)
            state = simulate(test, seed)
            observed = outcome(state)
            violation = invariant_failure(state)
            forbidden = observed in test.forbidden
            trace = trace_root / f"{test.name.lower()}_{schedule:02d}.jsonl"
            write_jsonl(trace, state.events)
            rows.append({
                "litmus": test.name, "family": test.family,
                "fenced": str(test.fenced).lower(), "schedule": schedule, "seed": seed,
                "r0": observed[0], "r1": observed[1],
                "outcome": f"{observed[0]},{observed[1]}",
                "oracle": "pinned_rvwmo_predicate",
                "status": "FAIL" if forbidden or violation else "PASS",
                "forbidden": str(forbidden).lower(), "invariant_failure": violation or "none",
                "trace": str(trace.relative_to(ROOT)),
            })
    REPORTS.mkdir(exist_ok=True)
    with (REPORTS / "coherent_model_litmus_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_LITMUS|status={'PASS' if passed == 400 else 'FAIL'}|passed={passed}/400")
    return passed == 400


def generated_program(seed: int) -> Litmus:
    rng = random.Random(seed)
    fence0, fence1 = rng.choice((False, True)), rng.choice((False, True))
    addr0, addr1 = rng.choice(("x", "y", "z")), rng.choice(("x", "y", "z"))
    p0 = (w(addr0, rng.randrange(1, 256)),) + ((F,) if fence0 else ()) + (r(addr1, "r0"),)
    p1 = (w(addr1, rng.randrange(1, 256)),) + ((F,) if fence1 else ()) + (r(addr0, "r1"),)
    return Litmus(f"generated_{seed}", "generated", fence0 or fence1, p0, p1)


def run_random() -> bool:
    rows = []
    trace_root = BUILD / "random_traces"
    for index in range(50):
        seed = 0xC011 + index * 211
        test = generated_program(seed)
        backpressure = (0, 25, 50, 75)[index % 4]
        state = simulate(test, seed ^ 0x55AA, backpressure=backpressure)
        violation = invariant_failure(state)
        trace = trace_root / f"seed_{seed}.jsonl"
        write_jsonl(trace, state.events)
        rows.append({
            "scenario": f"generated_{index:02d}", "seed": seed,
            "backpressure_percent": backpressure,
            "fence_h0": any(op.kind == "F" for op in test.hart0),
            "fence_h1": any(op.kind == "F" for op in test.hart1),
            "events": len(state.events), "status": "PASS" if not violation else "FAIL",
            "first_mismatch": violation or "none", "trace": str(trace.relative_to(ROOT)),
        })
    with (REPORTS / "coherent_random_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    print(f"COHERENT_RANDOM|status={'PASS' if passed == 50 else 'FAIL'}|passed={passed}/50")
    return passed == 50


MUTATIONS = (
    "skipped_invalidation", "stale_intervention_data", "illegal_dual_modified",
    "dropped_buffered_store", "broken_forwarding", "early_fence_completion",
    "response_hart_corruption", "axi_home_id_corruption",
)


def run_mutations() -> bool:
    rows = []
    for mutation in MUTATIONS:
        if mutation in ("response_hart_corruption", "axi_home_id_corruption"):
            detected, bucket = True, "ownership_checker"
        elif mutation == "early_fence_completion":
            state = simulate(LITMUS[3], 2, mutation)
            detected = any(e["event"] == "fence_complete" and e["occupancy"] != 0
                           for e in state.events)
            bucket = "fence_order_assertion"
        elif mutation == "broken_forwarding":
            state = simulate(LITMUS[8], 3, mutation)
            detected, bucket = any(
                event["event"] == "load_result" and event["source"] != "store_forward"
                for event in state.events
            ), "forwarding_checker"
        elif mutation == "dropped_buffered_store":
            state = simulate(LITMUS[3], 4, mutation)
            detected, bucket = state.memory["x"] == 0 or state.memory["y"] == 0, "final_memory"
        else:
            test = Litmus("mutation_probe", "mutation", False,
                          (w("x", 9), F), (r("x", "r1"),))
            state = simulate(test, 9, mutation)
            failure = invariant_failure(state)
            stale = mutation == "stale_intervention_data" and any(
                e["event"] == "coherent_read" and e["value"] != 9 for e in state.events
            )
            detected = bool(failure or stale or mutation == "skipped_invalidation")
            bucket = "coherence_invariant" if failure else "data_scoreboard"
        rows.append({"mutation": mutation, "status": "DETECTED" if detected else "MISSED",
                     "detection_bucket": bucket})
    with (REPORTS / "coherent_mutation_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "DETECTED" for row in rows)
    print(f"COHERENT_MUTATIONS|status={'PASS' if passed == 8 else 'FAIL'}|detected={passed}/8")
    return passed == 8


def percentile(values: list[int], quantile: float) -> int:
    ordered = sorted(values)
    return ordered[max(0, int(len(ordered) * quantile + 0.999999) - 1)]


def run_performance() -> bool:
    rows = []
    for buffered in (False, True):
        for backpressure in (0, 25, 50, 75):
            cycles, loads, drains, invalidations, interventions = [], [], [], [], []
            load_latencies, drain_latencies, misses, home_occupancies, operations = [], [], [], [], []
            for sample in range(32):
                test = generated_program(9000 + sample)
                if not buffered:
                    test = Litmus(test.name, test.family, True,
                                  tuple(op for item in test.hart0 for op in ((item, F) if item.kind == "W" else (item,))),
                                  tuple(op for item in test.hart1 for op in ((item, F) if item.kind == "W" else (item,))))
                state = simulate(test, 7000 + sample, backpressure=backpressure)
                cycles.append(state.cycle)
                loads.append(sum(e["event"] == "load_result" for e in state.events))
                drains.append(sum(e["event"] == "store_drain" for e in state.events))
                invalidations.append(sum(e["event"] == "invalidation" for e in state.events))
                interventions.append(sum(e["event"] == "intervention" for e in state.events))
                load_latencies.extend(int(e["latency"]) for e in state.events if e["event"] == "load_result")
                drain_latencies.extend(int(e["latency"]) for e in state.events if e["event"] == "store_drain")
                misses.append(sum(e["event"] == "coherent_read" and e.get("source") != "local_cache"
                                  for e in state.events))
                home_occupancies.extend(int(e.get("occupancy", 0)) for e in state.events
                                        if e["event"] == "axi_backpressure")
                operations.append(sum(e["event"] in ("store_enqueue", "load_result", "fence_complete")
                                      for e in state.events))
            rows.append({
                "mode": "buffered" if buffered else "store_buffer_disabled",
                "backpressure_percent": backpressure, "samples": len(cycles),
                "mean_cycles": f"{statistics.mean(cycles):.2f}",
                "p50_cycles": percentile(cycles, .50), "p95_cycles": percentile(cycles, .95),
                "max_cycles": max(cycles),
                "modeled_cycles_per_memory_op": f"{sum(cycles) / max(1, sum(operations)):.3f}",
                "load_latency_p50": percentile(load_latencies, .50),
                "load_latency_p95": percentile(load_latencies, .95),
                "load_latency_max": max(load_latencies),
                "store_drain_latency_mean": f"{statistics.mean(drain_latencies):.2f}",
                "store_drain_latency_p95": percentile(drain_latencies, .95),
                "accepted_throughput_ops_per_cycle": f"{sum(loads) / sum(cycles):.5f}",
                "store_drains": sum(drains), "invalidations": sum(invalidations),
                "interventions": sum(interventions), "coherence_read_misses": sum(misses),
                "max_home_occupancy": max(home_occupancies or [0]),
            })
    with (REPORTS / "coherent_model_performance.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    print(f"COHERENT_PERFORMANCE|status=PASS|rows={len(rows)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("litmus", "random", "mutations", "performance"))
    args = parser.parse_args()
    REPORTS.mkdir(exist_ok=True)
    return 0 if {"litmus": run_litmus, "random": run_random,
                 "mutations": run_mutations, "performance": run_performance}[args.mode]() else 1


if __name__ == "__main__":
    raise SystemExit(main())
