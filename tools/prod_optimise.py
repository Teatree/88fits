#!/usr/bin/env python3
"""The production build's optimiser (pass 81, lane PROD, Garry: "extra optimization for the art and stuff, to make the
build smaller and faster"). Works on the STAGING copy only (tools/prod_stage.py), after tools/prod_prune.py:

    python tools/prod_optimise.py [--stage tools/dl/prod/stage] [--report <optimise.json>] [--ogg-quality 4]

 1. Music (and any sound of 10 s or more that does not loop by itself) to Ogg Vorbis (ffmpeg's libvorbis, quality 4,
    about 110 kbps at the tracks' 32 kHz; the dev build plays them as QOA WAVs, about 200 kbps): music/<id>.ogg, the
    sound map pointed at it, the WAV gone. Audio.gd loops an Ogg track itself (stream.loop).
 2. The project icon (icon.png, 1024 px, also copied raw into the APK and the exe) down to 256 px: it is only the
    window's icon at run time (the launcher icons are icon_192 / icon_fg_432 / icon_bg_432, the exe's is icon.ico).
 3. The few painted prop billboards still imported lossless (art/sprites/props) lossy like the rest (WebP 0.85).
The export preset "Android Prod" also leaves icon.ico out (only the exe uses it). The sprites and icons were lossy
WebP already (tools/lossy_imports.py); the 3D textures keep their VRAM compression and mipmaps; nothing is resized
that the phone shows at full size.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE = os.path.join(ROOT, "tools", "dl", "prod", "stage")
LONG_SECS = 10.0
ICON_PX = 256
PROP_QUALITY = 0.85


def ffmpeg():
    exe = shutil.which("ffmpeg")
    if not exe:
        raise SystemExit("prod_optimise: ffmpeg is not on PATH (needed for the Ogg music)")
    return exe


def wav_secs(p):
    try:
        w = wave.open(p)
        return w.getnframes() / float(w.getframerate())
    except (wave.Error, OSError, EOFError):
        return 0.0


def music_to_ogg(game, quality, log):
    sdir = os.path.join(game, "content", "sounds")
    smap = os.path.join(sdir, "soundmap.json")
    with open(smap, "r", encoding="utf-8") as f:
        d = json.load(f)
    out = []
    for sid, e in (d.get("sounds") or {}).items():
        if not isinstance(e, dict):
            continue
        rel = str(e.get("file", ""))
        if not rel.lower().endswith(".wav"):
            continue
        src = os.path.join(sdir, rel)
        if not os.path.isfile(src):
            continue
        secs = wav_secs(src)
        is_music = str(e.get("category", "")) == "music" or rel.startswith("music/")
        if not is_music and (secs < LONG_SECS or bool(e.get("loop", False))):
            continue
        dst = os.path.splitext(src)[0] + ".ogg"
        cmd = [ffmpeg(), "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-c:a", "libvorbis", "-q:a", str(quality), dst]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.isfile(dst):
            log("prod_optimise: ffmpeg failed on %s: %s" % (rel, (r.stderr or "").strip()[:300]))
            continue
        before = os.path.getsize(src)
        imp = src + ".import"
        qoa = 0
        if os.path.isfile(imp):
            with open(imp, "r", encoding="utf-8", errors="replace") as f:
                s = f.read()
            for m in set(re.findall(r'"res://(\.godot/imported/[^"]+)"', s)):
                p = os.path.join(game, m)
                if os.path.isfile(p):
                    qoa += os.path.getsize(p)
        for q in (src, imp):
            if os.path.isfile(q):
                os.remove(q)
        e["file"] = os.path.splitext(rel)[0] + ".ogg"
        out.append({"id": sid, "file": e["file"], "secs": round(secs, 1), "wav": before, "imported_before": qoa,
                    "ogg": os.path.getsize(dst)})
    with open(smap, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=1, ensure_ascii=False)
        f.write("\n")
    # its .tres still names the WAVs: gone until import_json writes it again (the Registry reads the JSON meanwhile)
    if out and os.path.isfile(os.path.join(sdir, "soundmap.tres")):
        os.remove(os.path.join(sdir, "soundmap.tres"))
    return out


def shrink_icon(game, log):
    p = os.path.join(game, "icon.png")
    if not os.path.isfile(p):
        return {}
    from PIL import Image  # Pillow: the art tools' dependency
    im = Image.open(p)
    before = os.path.getsize(p)
    if max(im.size) <= ICON_PX:
        return {"icon": "already %dx%d" % im.size}
    im = im.convert("RGBA").resize((ICON_PX, ICON_PX), Image.LANCZOS)
    im.save(p, optimize=True)
    return {"from": before, "to": os.path.getsize(p), "px": ICON_PX}


def lossy_props(game, log):
    out = []
    for root, dirs, files in os.walk(os.path.join(game, "art", "sprites", "props")):
        for f in files:
            if not f.endswith(".png.import"):
                continue
            p = os.path.join(root, f)
            with open(p, "r", encoding="utf-8") as fh:
                s = fh.read()
            if "compress/mode=0" not in s:
                continue
            s = s.replace("compress/mode=0", "compress/mode=1")
            s = re.sub(r"compress/lossy_quality=[0-9.]+", "compress/lossy_quality=%s" % PROP_QUALITY, s)
            with open(p, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(s)
            out.append(os.path.relpath(p, game).replace(os.sep, "/")[:-len(".import")])
    return out


def optimise(stage, quality=4, log=print):
    game = os.path.join(stage, "game")
    rep = {"music": music_to_ogg(game, quality, log), "icon": shrink_icon(game, log), "lossy_props": lossy_props(game, log)}
    mb = sum(m["imported_before"] for m in rep["music"]) / 1048576.0
    ma = sum(m["ogg"] for m in rep["music"]) / 1048576.0
    log("prod_optimise: %d tracks to Ogg (%.1f MiB as QOA -> %.1f MiB), icon %s, %d props lossy" % (
        len(rep["music"]), mb, ma, ("%d -> %d bytes" % (rep["icon"]["from"], rep["icon"]["to"])) if "from" in rep["icon"] else rep["icon"],
        len(rep["lossy_props"])))
    return rep


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", default=STAGE)
    ap.add_argument("--report", default="")
    ap.add_argument("--ogg-quality", type=float, default=4)
    a = ap.parse_args(argv)
    stage = os.path.abspath(a.stage)
    if os.path.abspath(os.path.join(stage, "game")) == os.path.abspath(os.path.join(ROOT, "game")):
        raise SystemExit("prod_optimise: refusing to touch the source tree")
    rep = optimise(stage, a.ogg_quality)
    if a.report:
        with open(a.report, "w", encoding="utf-8", newline="\n") as f:
            json.dump(rep, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
