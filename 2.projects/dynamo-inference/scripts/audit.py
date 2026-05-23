#!/usr/bin/env python3
"""Audit Docker + SBOM + link coverage across a set of workshop repos.

Usage: audit-workshop-sboms.py <repo1> [repo2] ... > audit.json

Produces a JSON cross-reference of:
  - every Dockerfile (shipping/reference/unclassified)
  - every image ref in yaml + readme
  - every docs/sbom/ dir
  - every CVE report
  - gaps: images without SBOMs, SBOMs without referenced images
  - broken internal links in .md files
"""
import json, pathlib, re, sys, urllib.parse

def audit(rp):
    base = pathlib.Path(rp); repo = base.name
    a = {"dockerfiles":[], "images_in_yaml":set(), "images_in_readme":set(),
         "sbom_dirs":[], "trivy_reports":[], "broken_links":[],
         "images_without_sbom":[], "sboms_without_image":[]}

    for df in base.rglob("Dockerfile*"):
        if ".git" in df.parts or df.is_dir(): continue
        t = df.read_text(errors="ignore")
        a["dockerfiles"].append({
            "path": str(df.relative_to(base)),
            "shipping": "AS security-scan" in t,
            "documented_no_sbom": "NO SBOM by design" in t or "SBOM IS UPSTREAM" in t,
            "build_tags_from_comments": re.findall(r'docker build.*?-t\s+([\w\-./:]+)', t),
            "froms": re.findall(r'^FROM\s+(\S+)', t, re.M),
        })

    for yf in base.rglob("*.yaml"):
        if ".git" in yf.parts: continue
        try: t = yf.read_text()
        except: continue
        for m in re.finditer(r'image:\s*["\']?([^"\'\s]+)', t):
            a["images_in_yaml"].add(m.group(1))

    for md in base.rglob("*.md"):
        if ".git" in md.parts: continue
        try: t = md.read_text()
        except: continue
        for m in re.finditer(r'([\w\-]+(?:-[\w]+)*):v\d+\.?\d*', t):
            ref = m.group(0)
            if ref.startswith(("python:","node:","alpine:","debian:","ubuntu:")): continue
            a["images_in_readme"].add(ref)

    sbom_root = base / "docs" / "sbom"
    if sbom_root.exists():
        for sub in sbom_root.iterdir():
            if sub.is_dir() and sub.name != "trivy":
                a["sbom_dirs"].append(sub.name)
        trivy = sbom_root / "trivy"
        if trivy.exists():
            a["trivy_reports"] = [f.name for f in trivy.iterdir()]

    # Link validation
    LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
    for md in base.rglob("*.md"):
        if ".git" in md.parts: continue
        t = md.read_text()
        for lbl, tgt in LINK_RE.findall(t):
            if tgt.startswith(("http://","https://","mailto:","#")): continue
            tp = urllib.parse.unquote(tgt.split('#')[0].split('?')[0])
            if not tp: continue
            r = (md.parent / tp).resolve()
            try: r.relative_to(base.resolve())
            except ValueError:
                a["broken_links"].append({"file": str(md.relative_to(base)),
                                          "target": tgt, "why": "outside-repo"}); continue
            if not r.exists():
                a["broken_links"].append({"file": str(md.relative_to(base)),
                                          "target": tgt, "why": "missing"})

    # Gaps
    all_images = a["images_in_yaml"] | a["images_in_readme"]
    for img in all_images:
        short = img.split("/")[-1]
        nm = short.split(":")[0]; ver = short.split(":")[1] if ":" in short else ""
        matched = any((nm in d and ver in d) or d == f"{nm}-{ver}" for d in a["sbom_dirs"])
        if not matched and nm not in ("aquasec","anchore","busybox"):
            a["images_without_sbom"].append(img)

    for key in ("images_in_yaml","images_in_readme"):
        a[key] = sorted(a[key])
    a["images_without_sbom"] = sorted(set(a["images_without_sbom"]))
    return {repo: a}

out = {}
for rp in sys.argv[1:]:
    out.update(audit(rp))
json.dump(out, sys.stdout, indent=2)
