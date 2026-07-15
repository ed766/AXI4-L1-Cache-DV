#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "associativity"
REPORTS = ROOT / "reports"
TRACE_ROOT = BUILD / "traces"

GEOMETRIES = {
    "direct_mapped": (128, 1),
    "two_way": (64, 2),
}
DIRECTED = ("smoke", "read_miss", "read_hit", "write_miss", "write_hit",
            "clean_evict", "dirty_evict", "maintenance", "read_error", "write_error")
WORKLOADS = {
    "sequential": {"read": 75, "conflict": 0, "addr": "sequential", "strobe": "full"},
    "uniform": {"read": 50, "conflict": 0, "addr": "uniform", "strobe": "full"},
    "hot_set": {"read": 50, "conflict": 25, "addr": "hot-set", "strobe": "full"},
    "same_set": {"read": 50, "conflict": 100, "addr": "two-line-conflict", "strobe": "full"},
    "read_heavy": {"read": 75, "conflict": 25, "addr": "uniform", "strobe": "full"},
    "write_heavy": {"read": 25, "conflict": 25, "addr": "uniform", "strobe": "full"},
    "mixed_strobes": {"read": 50, "conflict": 25, "addr": "uniform", "strobe": "mixed"},
}


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(command), flush=True)
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=capture)


def compile_variant(name: str, sets: int, ways: int) -> pathlib.Path:
    out = BUILD / name
    out.mkdir(parents=True, exist_ok=True)
    command = [
        "verilator", "--binary", "--sv", "--timing", "--assert", "-Wall",
        "-Wno-UNUSEDSIGNAL", "-Wno-BLKSEQ", "-Wno-SYNCASYNCNET",
        "--top-module", "tb_l1_dcache", "--Mdir", str(out),
        f"-GCACHE_SETS={sets}", f"-GCACHE_WAYS={ways}",
        "rtl/dcache_pkg.sv", "rtl/l1_dcache_top.sv",
        "sim/assertions/dcache_protocol_assertions.sv",
        "sim/monitors/dcache_trace_observer.sv", "sim/tb_l1_dcache.sv",
    ]
    result = run(command)
    if result.returncode:
        raise SystemExit(result.returncode)
    return out / "Vtb_l1_dcache"


def compile_checker() -> pathlib.Path:
    checker = BUILD / "cache_trace_checker"
    result = run(["g++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
                  "model/cache_reference.cpp", "model/cache_trace_checker.cpp",
                  "-o", str(checker)])
    if result.returncode:
        raise SystemExit(result.returncode)
    return checker


def parse_fields(output: str, marker: str) -> dict[str, str]:
    match = re.search(rf"{marker}\|(.*)", output)
    if not match:
        return {}
    return dict(item.split("=", 1) for item in match.group(1).split("|") if "=" in item)


def yosys_proxy(sets: int, ways: int) -> dict[str, str]:
    yosys = shutil.which("yosys")
    if not yosys:
        return {"yosys_status": "SKIP", "yosys_cells": "NA",
                "yosys_area_proxy": "NA", "timing_proxy": "NA"}
    work = BUILD / "yosys" / f"sets{sets}_ways{ways}"
    work.mkdir(parents=True, exist_ok=True)
    script = work / "synth.ys"
    log = work / "synth.log"
    script.write_text(f"""
read_verilog -sv -D FORMAL -D SYNTHESIS rtl/l1_dcache_top.sv
chparam -set SETS {sets} -set WAYS {ways} l1_dcache_top
hierarchy -top l1_dcache_top
proc
memory -nomap
opt
stat
""")
    result = subprocess.run([yosys, "-s", str(script)], cwd=ROOT,
                            text=True, capture_output=True)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        return {"yosys_status": "FAIL", "yosys_cells": "NA",
                "yosys_area_proxy": "NA", "timing_proxy": "NA"}
    cell_match = re.findall(r"Number of cells:\s+([0-9]+)", result.stdout)
    cells = cell_match[-1] if cell_match else "NA"
    return {"yosys_status": "PASS", "yosys_cells": cells,
            "yosys_area_proxy": cells, "timing_proxy": "NA"}


def events(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open() as handle:
        return list(csv.DictReader(handle))


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def check_variants(binaries: dict[str, pathlib.Path], checker: pathlib.Path) -> None:
    rows = []
    for geometry, binary in binaries.items():
        sets, ways = GEOMETRIES[geometry]
        trace_dir = TRACE_ROOT / geometry / "directed"
        trace_dir.mkdir(parents=True, exist_ok=True)
        for test in DIRECTED:
            trace = trace_dir / f"{test}.csv"
            result = run([str(binary), f"+TEST={test}", "+MODEL_FINAL_FLUSH",
                          f"+TRACE_FILE={trace}"], capture=True)
            output = result.stdout + result.stderr
            fields = parse_fields(output, "CACHE_RESULT")
            check = run([str(checker), str(trace), str(sets), str(ways)], capture=True)
            status = "PASS" if result.returncode == 0 and check.returncode == 0 else "FAIL"
            rows.append({"geometry": geometry, "sets": sets, "ways": ways,
                         "test": test, "status": status,
                         "requests": fields.get("requests", "NA"),
                         "responses": fields.get("responses", "NA")})
            if status != "PASS":
                print(output + check.stdout + check.stderr)
    REPORTS.mkdir(exist_ok=True)
    with (REPORTS / "associativity_check.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    passed = sum(row["status"] == "PASS" for row in rows)
    if passed != len(rows):
        raise SystemExit(f"ASSOCIATIVITY_CHECK|status=FAIL|passed={passed}|total={len(rows)}")
    print(f"ASSOCIATIVITY_CHECK|status=PASS|passed={passed}|total={len(rows)}")


def characterize(binaries: dict[str, pathlib.Path], checker: pathlib.Path) -> None:
    rows = []
    synth = {geometry: yosys_proxy(*GEOMETRIES[geometry]) for geometry in GEOMETRIES}
    for geometry, binary in binaries.items():
        sets, ways = GEOMETRIES[geometry]
        trace_dir = TRACE_ROOT / geometry / "workloads"
        trace_dir.mkdir(parents=True, exist_ok=True)
        for workload, cfg in WORKLOADS.items():
            trace = trace_dir / f"{workload}.csv"
            command = [str(binary), "+TEST=performance_workload", "+SEED=20260706",
                       "+OPS=160", f"+READ_PCT={cfg['read']}",
                       f"+CONFLICT_PCT={cfg['conflict']}", "+BP_PCT=25",
                       "+ERROR_PCT=0", "+RESET_OP=-1", f"+STROBE_PROFILE={cfg['strobe']}",
                       f"+ADDR_PROFILE={cfg['addr']}", "+ADDR_BASE=00004000",
                       "+ADDR_SPAN=00010000", "+MODEL_FINAL_FLUSH", f"+TRACE_FILE={trace}"]
            result = run(command, capture=True)
            output = result.stdout + result.stderr
            cache = parse_fields(output, "CACHE_RESULT")
            random = parse_fields(output, "RANDOM_RESULT")
            check = run([str(checker), str(trace), str(sets), str(ways)], capture=True)
            if result.returncode or check.returncode:
                print(output + check.stdout + check.stderr)
                raise SystemExit(f"associativity workload failed: {geometry}/{workload}")

            trace_events = events(trace)
            lookups = [event for event in trace_events if event["event"] == "LOOKUP"]
            hits = sum(int(event["hit"]) for event in lookups)
            misses = len(lookups) - hits
            clean_evictions = sum(not int(event["dirty"]) for event in lookups
                                  if not int(event["hit"]) and int(event["valid"]))
            dirty_evictions = sum(int(event["dirty"]) for event in lookups
                                  if not int(event["hit"]) and int(event["valid"]))
            refill_beats = sum(event["event"] == "AXI_R" for event in trace_events)
            writeback_beats = sum(event["event"] == "AXI_W" for event in trace_events)
            pending: dict[int, int] = {}
            latencies: list[int] = []
            maint_start = None
            maint_latencies: list[int] = []
            for event in trace_events:
                cycle = int(event["cycle"]); event_id = int(event["id"])
                if event["event"] == "CPU_ACCEPT": pending[event_id] = cycle
                elif event["event"] == "CPU_RESPONSE" and event_id in pending:
                    latencies.append(cycle - pending.pop(event_id))
                elif event["event"] == "MAINT_ACCEPT": maint_start = cycle
                elif event["event"] == "MAINT_DONE" and maint_start is not None:
                    maint_latencies.append(cycle - maint_start); maint_start = None
            cycles = int(cache.get("cycles", 0))
            responses = int(cache.get("responses", 0))
            rows.append({
                "geometry": geometry, "capacity_bytes": 4096, "sets": sets, "ways": ways,
                "line_bytes": 32, "workload": workload, "operations": random.get("requested_ops", 0),
                "read_percent": cfg["read"], "conflict_percent": cfg["conflict"],
                "strobe_profile": cfg["strobe"], "hits": hits, "misses": misses,
                "hit_rate_percent": f"{100.0 * hits / max(1, len(lookups)):.2f}",
                "clean_evictions": clean_evictions, "dirty_evictions": dirty_evictions,
                "refill_beats": refill_beats, "writeback_beats": writeback_beats,
                "axi_stall_cycles": random.get("axi_stalls", 0),
                "latency_mean": f"{sum(latencies) / max(1, len(latencies)):.2f}",
                "latency_p50": percentile(latencies, .50), "latency_p95": percentile(latencies, .95),
                "latency_max": max(latencies), "throughput_req_per_cycle": f"{responses / max(1, cycles):.5f}",
                "maintenance_latency": max(maint_latencies) if maint_latencies else "NA",
                "model_check": "PASS", **synth[geometry],
            })

    with (REPORTS / "associativity_characterization.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    write_report(rows)
    same = {row["geometry"]: row for row in rows if row["workload"] == "same_set"}
    if float(same["two_way"]["hit_rate_percent"]) <= float(same["direct_mapped"]["hit_rate_percent"]):
        raise SystemExit("same-set workload did not demonstrate a 2-way hit-rate advantage")
    print(f"ASSOCIATIVITY_CHARACTERIZE|status=PASS|points={len(rows)}")


def write_report(rows: list[dict[str, object]]) -> None:
    docs = ROOT / "docs"
    images = docs / "images"
    images.mkdir(exist_ok=True)
    text = """# Cache Associativity Characterization

Both variants are 4 KiB write-back, write-allocate caches with 32-byte lines. Results are deterministic behavioral Verilator measurements, not silicon timing or implementation signoff.

| Workload | Geometry | Hit rate | Clean evictions | Dirty evictions | p95 latency | Throughput | Yosys cells |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
"""
    for row in rows:
        text += (f"| `{row['workload']}` | `{row['geometry']}` | {row['hit_rate_percent']}% | "
                 f"{row['clean_evictions']} | {row['dirty_evictions']} | {row['latency_p95']} | "
                 f"{row['throughput_req_per_cycle']} | {row['yosys_cells']} |\n")
    synth_rows = {str(row["geometry"]): row for row in rows if row["workload"] == "same_set"}
    text += """

## Implementation Proxy

| Geometry | Yosys status | Cell-count proxy | Area proxy | Timing proxy |
| --- | --- | ---: | ---: | ---: |
""" + "".join(
        f"| `{geometry}` | {row['yosys_status']} | {row['yosys_cells']} | {row['yosys_area_proxy']} | {row['timing_proxy']} |\n"
        for geometry, row in synth_rows.items()
    ) + """

## Interpretation

- The configurations hold capacity and line size constant, isolating associativity and set-count effects.
- Same-set traffic exposes conflict behavior; the 2-way cache can retain two lines per set while direct-mapped placement cannot.
- Refill/writeback traffic and latency are derived from normalized observer traces and checked by the independent C++ model.
- Yosys/OpenSTA numbers are implementation proxies only. `SKIP`/`NA` means the required open-source tool was unavailable in the local environment; no synthesis-cost claim is inferred from simulation.

![Associativity comparison](images/associativity_comparison.svg)
"""
    (docs / "associativity_characterization.md").write_text(text)

    workloads = list(WORKLOADS)
    values = {(str(row["geometry"]), str(row["workload"])): float(row["hit_rate_percent"])
              for row in rows}
    width, height = 980, 430
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<rect width="100%" height="100%" fill="#f7f3ea"/>',
           '<g font-family="DejaVu Sans, sans-serif" fill="#18211d">',
           '<text x="40" y="32" font-size="20" font-weight="700">Equal-capacity cache associativity comparison</text>',
           '<text x="40" y="55" font-size="12">Observed hit rate under identical deterministic workloads</text>',
           '<line x1="60" y1="360" x2="950" y2="360" stroke="#56635d"/>']
    group = 120
    for index, workload in enumerate(workloads):
        x = 80 + index * group
        for offset, geometry, color in ((0, "direct_mapped", "#c84b31"), (32, "two_way", "#167d6d")):
            value = values[(geometry, workload)]
            bar_height = value * 2.6
            svg.append(f'<rect x="{x + offset}" y="{360 - bar_height:.1f}" width="26" height="{bar_height:.1f}" fill="{color}"/>')
        svg.append(f'<text x="{x + 28}" y="382" font-size="10" text-anchor="middle">{workload.replace("_", "-")}</text>')
    svg += ['<rect x="690" y="70" width="14" height="14" fill="#c84b31"/><text x="712" y="82" font-size="11">direct mapped</text>',
            '<rect x="805" y="70" width="14" height="14" fill="#167d6d"/><text x="827" y="82" font-size="11">2-way</text>',
            '</g></svg>']
    (images / "associativity_comparison.svg").write_text("\n".join(svg) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("check", "characterize"))
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True); TRACE_ROOT.mkdir(parents=True, exist_ok=True)
    binaries = {name: compile_variant(name, *geometry) for name, geometry in GEOMETRIES.items()}
    checker = compile_checker()
    if args.mode == "check": check_variants(binaries, checker)
    else: characterize(binaries, checker)


if __name__ == "__main__":
    main()
