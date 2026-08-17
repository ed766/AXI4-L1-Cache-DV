#!/usr/bin/env python3
from __future__ import annotations
import csv, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MUTATIONS=["MSI_MUT_SKIP_INVALIDATE","MSI_MUT_SKIP_DOWNGRADE","MSI_MUT_SKIP_INTERVENTION"]
def main()->int:
 rows=[]; checker=ROOT/"build"/"msi_random"/"msi_trace_checker"
 if not checker.exists(): subprocess.run(["python3","scripts/run_msi_random.py","--seeds","1"],cwd=ROOT,check=True)
 for mutation in MUTATIONS:
  build=ROOT/"build"/f"msi_{mutation.lower()}";
  if build.exists():shutil.rmtree(build)
  build.mkdir(parents=True);trace=build/"trace.csv"
  comp=subprocess.run(["verilator","--binary","--timing","--assert","-Wall","-Wno-fatal","-Wno-UNUSEDSIGNAL","-Wno-BLKSEQ","-Wno-SYNCASYNCNET",f"-D{mutation}","--top-module","tb_msi_random","--Mdir",str(build/"obj"),"rtl/coherence/msi_two_cache_subsystem.sv","sim/tb_msi_random.sv"],cwd=ROOT,text=True,capture_output=True)
  detected=False;bucket="compile"
  if comp.returncode==0:
   rtl=subprocess.run([str(build/"obj"/"Vtb_msi_random"),"+SEED=20736","+OPS=120",f"+TRACE_FILE={trace}"],cwd=ROOT,text=True,capture_output=True)
   model=subprocess.run([str(checker),str(trace)],cwd=ROOT,text=True,capture_output=True) if trace.exists() else None
   detected=rtl.returncode!=0 or model is None or model.returncode!=0;bucket="assertion" if rtl.returncode!=0 else "cpp_model"
  rows.append({"mutation":mutation,"status":"DETECTED" if detected else "MISSED","bucket":bucket})
 with (ROOT/"reports"/"msi_mutation_summary.csv").open("w",newline="") as h:w=csv.DictWriter(h,fieldnames=rows[0].keys(),lineterminator="\n");w.writeheader();w.writerows(rows)
 passed=all(r["status"]=="DETECTED" for r in rows);print(f"MSI_MUTATIONS|status={'PASS' if passed else 'FAIL'}|detected={sum(r['status']=='DETECTED' for r in rows)}/{len(rows)}");return 0 if passed else 1
if __name__=="__main__":raise SystemExit(main())
