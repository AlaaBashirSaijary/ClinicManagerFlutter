#!/usr/bin/env python3
"""Takes the two files a doctor sends from the app and builds their page.

usage: python3 ingest.py <slug>.json [<slug>.jpg]
  -> clinics/<slug>.json (+ clinics/<slug>/photo.jpg), then builds out/<slug>/
Copy out/<slug>/ into the clinic-pages repo and push; send the doctor
https://alaabashirsaijary.github.io/clinic-pages/<slug>/
"""
import json, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).parent
src = Path(sys.argv[1]); c = json.loads(src.read_text(encoding="utf-8"))
slug = c["slug"]
assert slug.isalnum(), "unexpected slug"
(HERE / "clinics").mkdir(exist_ok=True)
(HERE / "clinics" / f"{slug}.json").write_text(json.dumps(c, ensure_ascii=False, indent=1), encoding="utf-8")
if len(sys.argv) > 2:
    d = HERE / "clinics" / slug; d.mkdir(exist_ok=True)
    shutil.copy2(sys.argv[2], d / "photo.jpg")
subprocess.run([sys.executable, str(HERE / "build.py"), slug], check=True)
print(f"\nPublish: copy tools/clinic_pages/out/{slug}/ into clinic-pages, push, then send:\nhttps://alaabashirsaijary.github.io/clinic-pages/{slug}/")
