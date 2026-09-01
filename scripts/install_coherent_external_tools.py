#!/usr/bin/env python3
"""Install checksum-pinned herdtools7 into a repository-local opam root."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "integration/rv32_coherent/external_tools.lock.json").read_text())
BUILD = ROOT / "build" / "coherent_external"
OPAM_ROOT = BUILD / "opam-root"
SWITCH = BUILD / "herd-switch"


def main() -> int:
    entry = next(item for item in LOCK["tools"] if item["name"] == "opam-bootstrap")
    BUILD.mkdir(parents=True, exist_ok=True)
    opam = BUILD / "opam"
    if not opam.exists():
        subprocess.run(["curl", "-L", "--fail", "--retry", "3", "-o", str(opam), entry["url"]], check=True)
    if hashlib.sha256(opam.read_bytes()).hexdigest() != entry["sha256"]:
        raise SystemExit("opam bootstrap checksum mismatch")
    opam.chmod(0o755)
    gmp_entry = next(item for item in LOCK["tools"] if item["name"] == "libgmp-dev-local")
    gmp_deb = BUILD / "libgmp-dev.deb"
    gmp_root = BUILD / "gmp-root"
    if not gmp_deb.exists():
        subprocess.run(["curl", "-L", "--fail", "--retry", "3", "-o", str(gmp_deb), gmp_entry["url"]], check=True)
    if hashlib.sha256(gmp_deb.read_bytes()).hexdigest() != gmp_entry["sha256"]:
        raise SystemExit("libgmp-dev checksum mismatch")
    if not (gmp_root / "usr/include/x86_64-linux-gnu/gmp.h").exists():
        subprocess.run(["dpkg-deb", "-x", str(gmp_deb), str(gmp_root)], check=True)
    gmp_lib = gmp_root / "usr/lib/x86_64-linux-gnu"
    for name in ("libgmp.so.10.5.0", "libgmpxx.so.4.7.0"):
        target = gmp_lib / name
        if not target.exists():
            source = Path("/usr/lib/x86_64-linux-gnu") / name
            if source.exists(): shutil.copyfile(source, target)
    tool_bin = BUILD / "bin"
    tool_bin.mkdir(exist_ok=True)
    unzip = tool_bin / "unzip"
    if not unzip.exists():
        unzip.write_text("""#!/usr/bin/env python3
import pathlib,sys,zipfile
args=[a for a in sys.argv[1:] if a not in ('-q','-o')]
dest='.'
if '-d' in args:
 i=args.index('-d'); dest=args[i+1]; del args[i:i+2]
archive=args[0]
with zipfile.ZipFile(archive) as z: z.extractall(pathlib.Path(dest))
""")
        unzip.chmod(0o755)
    env = {**os.environ, "OPAMROOT": str(OPAM_ROOT), "OPAMYES": "1",
           "PATH": f"{tool_bin}:{os.environ.get('PATH', '')}",
           "CPATH": str(gmp_root / "usr/include/x86_64-linux-gnu"),
           "LIBRARY_PATH": str(gmp_root / "usr/lib/x86_64-linux-gnu"),
           "PKG_CONFIG_PATH": str(gmp_root / "usr/lib/x86_64-linux-gnu/pkgconfig")}
    if not (OPAM_ROOT / "config").exists():
        subprocess.run([str(opam), "init", "--bare", "--disable-sandboxing", "-y"], env=env, check=True)
    if not SWITCH.exists():
        subprocess.run([str(opam), "switch", "create", str(SWITCH), "ocaml-base-compiler.5.2.1", "-y"], env=env, check=True)
    subprocess.run([str(opam), "install", "--switch", str(SWITCH),
                    "herdtools7.7.58", "--assume-depexts", "-y"], env=env, check=True)
    herd = SWITCH / "_opam" / "bin" / "herd7"
    if not herd.exists(): raise SystemExit("herd7 install did not produce an executable")
    print(f"COHERENT_EXTERNAL_TOOLS|status=PASS|herd7={herd}")
    return 0


if __name__ == "__main__": raise SystemExit(main())
