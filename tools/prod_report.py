#!/usr/bin/env python3
"""The production build's numbers (pass 81, lane PROD): the prod APK and exe beside the dev ones, where the bytes go,
what the prune and the optimiser took out, and the probes' cold starts, as report.json + report.md in the out folder.

    python tools/prod_report.py --out tools/dl/prod/out [--dev-apk game/export/88fits.apk] [--dev-exe game/export/88fits.exe]
                                [--dev-probe <probe_dev.json>]

Reads <out>/88fits-prod.apk, 88fits-prod.exe, prune.json, optimise.json, probe.json (and the dev probe when given).
Standard library only.
"""
import argparse
import collections
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIB = 1048576.0


def _mib(n):
    return round(n / MIB, 1) if n else 0.0


def _load(p):
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def apk_breakdown(path):
    """{group: compressed bytes} for an APK: the native library, the imported art and sound by source folder."""
    out = collections.Counter()
    if not os.path.isfile(path):
        return {}
    z = zipfile.ZipFile(path)
    src_of = {}
    for i in z.infolist():
        if i.filename.endswith(".import"):
            t = z.read(i).decode("utf-8", "replace")
            for m in re.finditer(r'"(res://\.godot/imported/[^"]+)"', t):
                src_of[m.group(1)[len("res://"):]] = i.filename[len("assets/"):-len(".import")]
    for i in z.infolist():
        n = i.filename
        if n.startswith("lib/"):
            key = "native library"
        elif n.startswith("assets/.godot/imported/"):
            s = src_of.get(n[len("assets/"):], "")
            parts = s.split("/")
            if parts[0] == "content" and len(parts) > 1:
                key = "content/" + parts[1]
            elif parts[0] in ("art", "ui") and len(parts) > 1:
                key = parts[0] + "/" + parts[1]
            else:
                key = "other imported"
        elif n.startswith("assets/"):
            key = "scripts, scenes, data"
        else:
            key = "android (dex, manifest, signature)"
        out[key] += i.compress_size
    return dict(out)


def report(out_dir, dev_apk, dev_exe, dev_probe):
    pa = os.path.join(out_dir, "88fits-prod.apk")
    pe = os.path.join(out_dir, "88fits-prod.exe")
    r = {"apk": {"dev": os.path.getsize(dev_apk) if os.path.isfile(dev_apk) else 0, "prod": os.path.getsize(pa) if os.path.isfile(pa) else 0},
         "exe": {"dev": os.path.getsize(dev_exe) if os.path.isfile(dev_exe) else 0, "prod": os.path.getsize(pe) if os.path.isfile(pe) else 0}}
    bd_dev = apk_breakdown(dev_apk)
    bd_prod = apk_breakdown(pa)
    r["apk_breakdown"] = {k: {"dev": bd_dev.get(k, 0), "prod": bd_prod.get(k, 0)} for k in sorted(set(bd_dev) | set(bd_prod))}
    prune = _load(os.path.join(out_dir, "prune.json"))
    opt = _load(os.path.join(out_dir, "optimise.json"))
    probe = _load(os.path.join(out_dir, "probe.json"))
    dprobe = _load(dev_probe) if dev_probe else {}
    r["prune"] = {"folders": len(prune.get("dirs", [])), "folders_by_type": dict(collections.Counter(d["dir"].split("/")[0] for d in prune.get("dirs", []))),
                  "folders_kept_by_ref": prune.get("dirs_kept_by_ref", []), "look_rewrites": len(prune.get("looks", [])),
                  "look_files": len(prune.get("files", [])), "titles": prune.get("titles", []), "ai_json": prune.get("ai_json", 0),
                  "sounds": len(prune.get("sounds", [])), "bytes": prune.get("bytes", {})}
    r["optimise"] = {"music": opt.get("music", []), "icon": opt.get("icon", {}), "lossy_props": opt.get("lossy_props", [])}
    r["boot"] = {"prod_to_title_ms": probe.get("to_title_ms_median"), "prod_autoloads_ms": probe.get("autoloads_ms_median"),
                 "dev_to_title_ms": dprobe.get("to_title_ms_median"), "dev_autoloads_ms": dprobe.get("autoloads_ms_median")}
    lines = ["# 88fits production build: the numbers", ""]
    lines.append("| | dev | prod | saved |")
    lines.append("|---|---:|---:|---:|")
    for k, label in (("apk", "APK"), ("exe", "EXE")):
        d, p = r[k]["dev"], r[k]["prod"]
        lines.append("| %s | %.1f MiB | %.1f MiB | %s |" % (label, _mib(d), _mib(p), ("%.1f MiB (%d%%)" % (_mib(d - p), round(100.0 * (d - p) / d))) if d and p else "-"))
    b = r["boot"]
    if b["prod_to_title_ms"]:
        lines.append("| cold start to the title (PC, headless) | %s ms | %s ms | %s |" % (b["dev_to_title_ms"] or "-", b["prod_to_title_ms"],
                     ("%d ms" % (b["dev_to_title_ms"] - b["prod_to_title_ms"])) if b["dev_to_title_ms"] else "-"))
    lines += ["", "## Where the APK's bytes go (compressed)", "", "| | dev | prod |", "|---|---:|---:|"]
    for k, v in sorted(r["apk_breakdown"].items(), key=lambda kv: -kv[1]["dev"]):
        lines.append("| %s | %.1f MiB | %.1f MiB |" % (k, _mib(v["dev"]), _mib(v["prod"])))
    p = r["prune"]
    lines += ["", "## What the prune took out", "",
              "- %d content folders (%s)" % (p["folders"], ", ".join("%s %d" % kv for kv in sorted(p["folders_by_type"].items()))),
              "- %d items rewritten without their unused looks, %d look files" % (p["look_rewrites"], p["look_files"]),
              "- %d title cut-outs, %d painters' sidecars (_ai.json), %d sound files the sound map does not name" % (len(p["titles"]), p["ai_json"], p["sounds"]),
              "- %.1f MiB of imported art and sound" % _mib((p["bytes"] or {}).get("imported", 0))]
    for k in p["folders_kept_by_ref"]:
        lines.append("- kept %s (%s): %s names %s" % (k["dir"], k["why"], ", ".join(k["named_by"]), k["file"]))
    o = r["optimise"]
    if o["music"]:
        lines += ["", "## Music to Ogg Vorbis", "", "| track | s | QOA | Ogg |", "|---|---:|---:|---:|"]
        for m in o["music"]:
            lines.append("| %s | %.0f | %.2f MiB | %.2f MiB |" % (m["id"], m["secs"], _mib(m["imported_before"]), _mib(m["ogg"])))
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(r, f, indent=1)
    with open(os.path.join(out_dir, "report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return r, lines


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "tools", "dl", "prod", "out"))
    ap.add_argument("--dev-apk", default=os.path.join(ROOT, "game", "export", "88fits.apk"))
    ap.add_argument("--dev-exe", default=os.path.join(ROOT, "game", "export", "88fits.exe"))
    ap.add_argument("--dev-probe", default="")
    a = ap.parse_args(argv)
    r, lines = report(os.path.abspath(a.out), a.dev_apk, a.dev_exe, a.dev_probe)
    print("\n".join(lines[:8]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
