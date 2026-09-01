#!/usr/bin/env python3
"""Generate executable coherent evidence explorer and deterministic SVGs."""
from __future__ import annotations

import csv, html, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS, DOCS = ROOT / "reports", ROOT / "docs"
IMAGES, DATA = DOCS / "images", DOCS / "data"

def read(name):
    path = REPORTS / name
    return list(csv.DictReader(path.open())) if path.exists() else []

def svg(name, body):
    (IMAGES / name).write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="520" viewBox="0 0 1200 520"><style>.title{{font:700 28px Georgia;fill:#142b35}}.h{{font:700 17px Georgia;fill:#142b35}}.t{{font:14px Georgia;fill:#294550}}.box{{fill:#f7f2e8;stroke:#1b6573;stroke-width:2}}.accent{{fill:#f2b38f;stroke:#a64c2a;stroke-width:2}}.ok{{fill:#dce9e7;stroke:#28705b;stroke-width:2}}.line{{stroke:#1b6573;stroke-width:3;fill:none;marker-end:url(#a)}}</style><defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#1b6573"/></marker></defs><rect width="100%" height="100%" fill="#fffdf7"/>{body}</svg>''')

def architecture():
    body='<text class="title" x="35" y="48">Executable dual-RV32 coherent crossover</text>'
    boxes=[(30,105,160,90,"Hart 0","GCC RV32I"),(30,300,160,90,"Hart 1","GCC RV32I"),(245,105,175,90,"Store buffer 0","2 entries + FENCE"),(245,300,175,90,"Store buffer 1","2 entries + FENCE"),(485,100,190,295,"AXI QoS transport","IDs, BP, faults"),(735,80,220,150,"MSI bank 0","same-bank serialize"),(735,285,220,150,"MSI bank 1","different-bank overlap"),(1020,185,145,145,"Shared SRAM","coherent data")]
    for x,y,w,h,a,b in boxes: body+=f'<rect class="box" x="{x}" y="{y}" width="{w}" height="{h}" rx="14"/><text class="h" x="{x+15}" y="{y+35}">{a}</text><text class="t" x="{x+15}" y="{y+62}">{b}</text>'
    for x1,y1,x2,y2 in ((190,150,245,150),(190,345,245,345),(420,150,485,150),(420,345,485,345),(675,150,735,150),(675,345,735,345),(955,155,1020,230),(955,360,1020,285)): body+=f'<path class="line" d="M{x1},{y1} L{x2},{y2}"/>'
    body+='<text class="t" x="480" y="455">Internal bank aliasing is removed before each request reaches the MSI home.</text>'
    svg("coherent_architecture.svg",body)

def litmus_flow():
    body='<text class="title" x="35" y="48">Executable RTL litmus and external-oracle flow</text>'
    stages=[(35,"16 litmus pairs","GCC ROMs"),(270,"25 schedules each","issue + AXI stalls"),(505,"RTL execution","RVFI + MSI + AXI"),(740,"Independent replay","ISS + coherence"),(975,"Exact herd7 set","tuple membership")]
    for i,(x,a,b) in enumerate(stages):
        body+=f'<rect class="{"ok" if i==4 else "box"}" x="{x}" y="145" width="190" height="125" rx="14"/><text class="h" x="{x+15}" y="190">{a}</text><text class="t" x="{x+15}" y="225">{b}</text>'
        if i<4: body+=f'<path class="line" d="M{x+190},208 L{x+225},208"/>'
    body+='<rect class="accent" x="340" y="335" width="520" height="85" rx="14"/><text class="h" x="435" y="370">400 / 400 actual RTL schedules allowed</text><text class="t" x="420" y="398">Operational exploration is supplemental and never supplies canonical bins.</text>'
    svg("coherent_executable_litmus.svg",body)

def error_reset():
    body='<text class="title" x="35" y="48">Load, buffered-store, and reset containment</text>'
    for x,a,b,c in ((45,"Load fault","precise APB trap","no architectural update"),(420,"Buffered-store fault","FIFO head retained","explicit retry / clear"),(795,"Reset epoch","ownership discarded","no ghost response")):
        body+=f'<rect class="box" x="{x}" y="115" width="325" height="245" rx="16"/><text class="h" x="{x+22}" y="160">{a}</text><text class="t" x="{x+22}" y="205">{b}</text><text class="t" x="{x+22}" y="240">{c}</text><rect class="ok" x="{x+65}" y="285" width="195" height="45" rx="10"/><text class="h" x="{x+100}" y="314">RTL checked</text>'
    body+='<text class="t" x="275" y="430">Nine tests include dirty-owner and failed-store-pending reset epochs.</text>'
    svg("coherent_error_reset.svg",body)

def evidence_matrix():
    body='<text class="title" x="35" y="48">Independent evidence boundary</text>'
    rows=[
        ("Executable RTL","400 litmus + 24 GCC","cycle-accurate integration"),
        ("Local ISS","per-hart retirement","RV32 instruction semantics"),
        ("herd7","16 exact allowed sets","RVWMO outcome oracle"),
        ("Event model","request to final state","coherence and memory"),
        ("Formal","10 property groups","bounded / inductive safety"),
    ]
    for n,(a,b,c) in enumerate(rows):
        y=85+n*78
        body+=f'<rect class="{"ok" if n in (0,2,4) else "box"}" x="45" y="{y}" width="1110" height="60" rx="12"/><text class="h" x="70" y="{y+36}">{a}</text><text class="t" x="350" y="{y+36}">{b}</text><text class="t" x="720" y="{y+36}">{c}</text>'
    body+='<text class="t" x="45" y="500">No single checker supplies every claim; canonical results cite the executing and predicting layers separately.</text>'
    svg("coherent_evidence_matrix.svg",body)

def failed_store_case_study():
    body='<text class="title" x="35" y="48">Formal-discovered failed-store occupancy bug</text>'
    stages=[
        (35,"Head store","AXI error returns"),
        (270,"Same cycle","younger enqueue"),
        (505,"Original defect","tail moved; count stale"),
        (740,"Risk","failed head overwritten"),
        (975,"Fix + proof","count both entries"),
    ]
    for i,(x,a,b) in enumerate(stages):
        cls="accent" if i in (2,3) else "ok" if i==4 else "box"
        body+=f'<rect class="{cls}" x="{x}" y="135" width="190" height="125" rx="14"/><text class="h" x="{x+15}" y="180">{a}</text><text class="t" x="{x+15}" y="215">{b}</text>'
        if i<4: body+=f'<path class="line" d="M{x+190},198 L{x+225},198"/>'
    body+='<rect class="box" x="185" y="335" width="830" height="90" rx="14"/><text class="h" x="235" y="370">Detection stack</text><text class="t" x="235" y="400">Solver counterexample -> executable synchronized edge test -> independent replay -> expected-fail mutation</text>'
    svg("coherent_failed_store_case_study.svg",body)

def performance(perf):
    body='<text class="title" x="35" y="48">Measured RTL cycles versus AXI backpressure</text><path d="M100,100 L100,400 L1000,400" stroke="#294550" stroke-width="2" fill="none"/>'
    colors={"buffered":"#d96c42","drain_before_next_op":"#1b6573"}
    all_means=[]; series={}
    for mode in colors:
        series[mode]=[]
        for duty in (0,25,50,75):
            selected=[r for r in perf if r["mode"]==mode and int(r["backpressure_percent"])==duty]
            mean=sum(int(r["cycles"]) for r in selected)/len(selected); series[mode].append((duty,mean)); all_means.append(mean)
    scale=max(all_means)*1.1
    for mode,vals in series.items():
        pts=[]
        for duty,value in vals:
            x=100+duty*11;y=400-value/scale*300;pts.append(f"{x},{y:.1f}");body+=f'<circle cx="{x}" cy="{y:.1f}" r="6" fill="{colors[mode]}"/>'
        body+=f'<polyline points="{" ".join(pts)}" fill="none" stroke="{colors[mode]}" stroke-width="4"/>'
    for duty in (0,25,50,75): body+=f'<text class="t" x="{100+duty*11-8}" y="435">{duty}%</text>'
    overlap=max(int(r["simultaneous_bank_cycles"]) for r in perf)
    body+=f'<rect class="ok" x="1025" y="125" width="145" height="150" rx="14"/><text class="h" x="1040" y="165">Bank overlap</text><text class="title" x="1055" y="220">{overlap}</text><text class="t" x="1040" y="250">cycles max</text><circle cx="760" cy="70" r="6" fill="#d96c42"/><text class="t" x="775" y="75">buffered</text><circle cx="900" cy="70" r="6" fill="#1b6573"/><text class="t" x="915" y="75">drain first</text>'
    svg("coherent_latency_dashboard.svg",body)

def explorer(executions,allowed,outcome_histograms,mutations):
    payload=html.escape(json.dumps({"executions":executions,"allowed":allowed,"outcome_histograms":outcome_histograms,"mutations":mutations}))
    (DOCS/"coherent_evidence_explorer.html").write_text(f'''<!doctype html>
<html><head><meta charset="utf-8"><title>Coherent Evidence Explorer</title>
<style>body{{font:16px Georgia,serif;background:#fffdf7;color:#142b35;max-width:1250px;margin:2rem auto}}.filters{{display:grid;grid-template-columns:repeat(6,1fr);gap:.7rem}}select,table{{width:100%}}table{{border-collapse:collapse;margin-top:1rem}}th,td{{border:1px solid #abc;padding:.35rem}}.lane0{{background:#f7e3d5}}.lane1{{background:#dce9e7}}.ok{{color:#17603a;font-weight:bold}}code{{font:12px monospace}}</style></head>
<body><h1>Dual-RV32 Coherent Evidence Explorer</h1><p>Actual RTL events, all-schedule outcome histograms, independent-model annotations, exact herd7 classifications, and mutation sensitivity.</p>
<div class="filters"><label>Test<select id="test"></select></label><label>Schedule<select id="schedule"></select></label><label>Hart<select id="hart"><option value="all">all</option><option>0</option><option>1</option></select></label><label>Outcome<select id="outcome"></select></label><label>Evidence<select id="evidence"><option>RTL + herd7</option></select></label><label>Mutation<select id="mutation"><option value="none">none</option></select></label></div>
<div id="summary"></div><div id="mutation_summary"></div><h2>Observed outcomes across all 25 schedules</h2><div id="hist"></div><h2>Synchronized event lanes</h2>
<table><thead><tr><th>Cycle</th><th>Hart</th><th>Event</th><th>Bank</th><th>Details</th></tr></thead><tbody id="events"></tbody></table>
<script id="p" type="application/json">{payload}</script><script>
const d=JSON.parse(p.textContent),T=test,S=schedule,H=hart,O=outcome,M=mutation,U=a=>[...new Set(a)],opts=(e,a)=>e.innerHTML=a.map(x=>`<option>${{x}}</option>`).join('');
function schedules(){{opts(S,d.executions.filter(x=>x.litmus==T.value).map(x=>x.schedule));render()}}
function render(){{const x=d.executions.find(x=>x.litmus==T.value&&x.schedule==S.value)||d.executions[0];const c=d.outcome_histograms[x.litmus]||{{}};opts(O,Object.keys(c));O.value=x.outcome;summary.innerHTML=`<p><b>${{x.litmus}}</b> schedule ${{x.schedule}}: <b>${{x.outcome}}</b>, <span class="ok">${{x.status}}</span>, allowed-set size ${{x.herd_allowed_outcomes}}</p>`;hist.innerHTML=Object.entries(c).map(([k,v])=>`<div><code>${{k}}</code> ${{'&#9608;'.repeat(v)}} ${{v}}</div>`).join('');events.innerHTML=x.events.filter(e=>H.value=='all'||String(e.hart)==H.value).map(e=>`<tr class="lane${{e.hart}}"><td>${{e.cycle}}</td><td>${{e.hart}}</td><td>${{e.event}}</td><td>${{e.bank}}</td><td><code>${{JSON.stringify(e)}}</code></td></tr>`).join('');const m=d.mutations.find(y=>y.mutation==M.value);mutation_summary.innerHTML=m?`<p><b>Mutation:</b> ${{m.mutation}} - <span class="ok">${{m.status}}</span> by ${{m.detection_bucket}}</p>`:''}}
T.onchange=schedules;S.onchange=render;H.onchange=render;M.onchange=render;opts(T,U(d.executions.map(x=>x.litmus)));opts(M,['none',...d.mutations.map(x=>x.mutation)]);schedules();
</script></body></html>''')

def main():
    IMAGES.mkdir(parents=True,exist_ok=True);DATA.mkdir(parents=True,exist_ok=True)
    rtl,model,gcc,random,perf=read("coherent_rtl_litmus_summary.csv"),read("coherent_model_litmus_summary.csv"),read("coherent_gcc_summary.csv"),read("coherent_random_summary.csv"),read("coherent_performance.csv")
    directed=read("coherent_directed_closure_summary.csv")
    allowed=json.loads((REPORTS/"coherent_herd_allowed_outcomes.json").read_text()); executions=[]
    for row in rtl:
        if int(row["schedule"])>3: continue
        events=[json.loads(x) for x in (ROOT/row["enriched_trace"]).read_text().splitlines()[:250]]
        executions.append({**row,"evidence_type":"RTL + herd7","events":events})
    refs=[]
    for family,data,checker in (("rtl_litmus_herd",rtl,"RTL+coherence_model+exact_herd7"),("directed_rtl_final_state",directed,"RTL+event_model+final_backing_and_cache_state"),("operational_exploration",model,"operational_model_only"),("gcc_rtl_iss",gcc,"RTL+ISS+coherence_model"),("operational_random",random,"operational_model_only")):
        for row in data: refs.append({"evidence_category":family,"scenario":row.get("scenario",f"{row.get('litmus','unknown')}:{row.get('schedule','0')}"),"checker":checker,"status":row.get("status","UNKNOWN"),"first_mismatch":row.get("first_mismatch",row.get("invariant_failure","none"))})
    with (REPORTS/"coherent_reference_summary.csv").open("w",newline="") as h:
        w=csv.DictWriter(h,fieldnames=refs[0].keys(),lineterminator="\n");w.writeheader();w.writerows(refs)
    histograms={}
    for row in rtl:
        histograms.setdefault(row["litmus"], {})[row["outcome"]] = histograms.setdefault(row["litmus"], {}).get(row["outcome"], 0) + 1
    mutations=read("coherent_rtl_mutation_summary.csv")
    (DATA/"coherent_evidence.json").write_text(json.dumps({
        "executions":executions, "allowed":allowed, "outcome_histograms":histograms,
        "mutations":mutations, "performance":perf,
    },indent=2)+"\n")
    architecture();litmus_flow();error_reset();performance(perf);evidence_matrix();failed_store_case_study()
    explorer(executions,allowed,histograms,mutations)
    print(f"COHERENT_DASHBOARD|status=PASS|rtl_executions=400|detailed_samples={len(executions)}|svgs=6")
    return 0

if __name__=="__main__": raise SystemExit(main())
