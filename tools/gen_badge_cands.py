"""Hero badge candidates (pass 66): the round avatar icon a hero wears on his plates and sheet, painted several times from
his front still with the badge's portrait words, each shown inside the round badge so they can be picked by eye (the
vision check cannot tell a good face from a bad one). The pick writes the badge and remembers which painting it came
from, so a later gen_art run makes the same badge (the JSON's "badge" {still, head_width, top_pad}, pass 56).

    python tools/gen_badge_cands.py --id solenne --seeds 4 [--prompt "winking at the viewer"] [--first-seed 0] [--skip-qa]
        -> tools/dl/ai_raw_anime/<id>_portrait_c<k>.png (+ .json) and tools/dl/review/<id>_badge_cands.png
    python tools/gen_badge_cands.py --id solenne --pick 2 [--head-width 0.8 --top-pad 0.05]
        -> game/content/characters/<id>/<id>_icon.png (the old one kept in tools/dl/backup/icons_le/) and
           "badge": {"still": "<id>_portrait_c2", "head_width": .., "top_pad": ..} in the hero JSON; under a Level Editor
           job (ASSET_JOB_SIDECAR) the badge goes into the sidecar's `top.badge` and the JSON is left to the server.

The words: the hero's `portrait_prompt` ("smiling at the viewer") unless --prompt says otherwise, inside gen_art's
portrait wording (head and shoulders, the head filling half the frame, the chest running off the bottom edge). Seeds:
gen_art.seed_for(id) + 40 + 1000 * k, one try each. Both --x value and --x=value work.
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARGS = sys.argv[1:]
sys.argv = ["gen_art.py", "--no-import"] + (["--skip-qa"] if "--skip-qa" in ARGS else [])
sys.path.insert(0, HERE)
import gen_art as g  # noqa: E402
import comfy  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

REVIEW = os.path.join(REPO, "tools", "dl", "review")
PAPER = (243, 230, 200)


def opt(name, default=None):
    for i, a in enumerate(ARGS):
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
        if a == "--" + name and i + 1 < len(ARGS):
            return ARGS[i + 1]
    return default


def hero_folder(hid):
    return os.path.join(REPO, "game", "content", "characters", hid)


def hero_json(hid):
    return json.load(open(os.path.join(hero_folder(hid), hid + ".json"), encoding="utf-8"))


def portrait_prompt(d, words, bg):
    """gen_art's badge wording (process(), the characters branch) round the hero's own portrait words."""
    pp = str(words or d.get("portrait_prompt", "smiling at the viewer"))
    return ("A close-up portrait of this exact character for a mobile game avatar icon: only the head and shoulders, the head filling "
            "half of the frame, " + pp + ", facing the viewer, the shoulders and chest running off the bottom edge of the frame, "
            "expressive and lively, no legs, no full body. Keep the same face, outfit, colors and art style as the reference. " + bg + ".")


def front_still_key(d, hid):
    skeys = d.get("still_keys") if isinstance(d.get("still_keys"), dict) else {}
    return str(skeys.get("front", hid + "_front"))


def sheet(hid, cands, head_width, top_pad):
    """Every candidate (key, image) inside the round badge on the title's paper, numbered."""
    size, pad = 256, 20
    out = Image.new("RGB", (len(cands) * (size + pad) + pad, size * 2 + 3 * pad + 30), PAPER)
    dr = ImageDraw.Draw(out)
    for i, (k, img) in enumerate(cands):
        img = img.convert("RGB")
        x = pad + i * (size + pad)
        out.paste(img.resize((size, size), Image.LANCZOS), (x, pad))
        badge = g.portrait_badge(img, size, head_width, top_pad)
        out.paste(badge, (x, size + 2 * pad), badge)
        dr.text((x + 4, size * 2 + 2 * pad + 6), "#%d  %s" % (i, k), fill=(36, 27, 20))
    os.makedirs(REVIEW, exist_ok=True)
    p = os.path.join(REVIEW, "%s_badge_cands.png" % hid)
    out.save(p)
    return p


def paint(hid, seeds, words="", first=0, head_width=0.0, top_pad=0.03):
    d = hero_json(hid)
    bg = g.bg_for(d, "characters")
    front = Image.open(os.path.join(g.RAW, front_still_key(d, hid) + ".png")).convert("RGB")
    front_ref = comfy.upload_pil(front, hid + "_front.png")
    prompt = portrait_prompt(d, words, bg)
    base = g.seed_for(hid) + 40 + int(first)
    keys, cands = [], []
    for k in range(seeds):
        key = "%s_portrait_c%d" % (hid, k)
        img, inf = g.render(key, prompt, [front_ref], {"subject": g.subject_for(d, "characters"), "view": "front", "subjects_max": 1, "bust": True},
                            base + 1000 * k, tries=1)
        g.log("  badge %s c%d seed %d  %s" % (hid, k, inf.get("seed", base + 1000 * k), ",".join(inf.get("qa", {}).get("problems", [])) or "ok"))
        keys.append(key)
        cands.append((key, img))
    path = sheet(hid, cands, head_width, top_pad)
    g.log("  badge candidates painted: look at %s, then --pick k" % path)
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    if sidecar:
        json.dump({"id": hid, "kind": "hero_badge", "prompt": prompt, "review": path,
                   "choices": [os.path.join(g.RAW, k + ".png") for k in keys]}, open(sidecar, "w", encoding="utf-8", newline="\n"), indent=1)
    return keys, path


def pick(hid, k, head_width=0.0, top_pad=0.03):
    key = "%s_portrait_c%d" % (hid, int(k))
    src = os.path.join(g.RAW, key + ".png")
    if not os.path.isfile(src):
        raise SystemExit("gen_badge_cands: no candidate %s" % src)
    d = hero_json(hid)
    img = Image.open(src).convert("RGB")
    badge = g.portrait_badge(img, 256, head_width, top_pad)
    dst = os.path.join(hero_folder(hid), d.get("icon", hid + "_icon.png"))
    buf = io.BytesIO()
    badge.save(buf, "PNG")
    kept = g.backup_icon(dst, buf.getvalue())
    badge.save(dst)
    top = {"badge": {"still": key, "head_width": float(head_width), "top_pad": float(top_pad)}}
    g.log("installed %s -> %s%s" % (key, dst, (" (old kept: %s)" % kept) if kept else ""))
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    if sidecar:
        # the server writes "badge" into the hero JSON in place
        g.emit_sidecar(hero_folder(hid), hid, "", {}, {"pipeline": "gen_badge_cands", "pick": key, "icon_backup": kept}, top=top)
        return dst
    jpath = os.path.join(hero_folder(hid), hid + ".json")
    src_text = open(jpath, encoding="utf-8").read()
    written = False
    try:
        # the Level Editor's structured writer keeps the file's layout when it is at hand
        sys.path.insert(0, os.path.join(REPO, "tools", "level_editor"))
        import content_io  # noqa: E402
        new = content_io.set_top_block(src_text, "badge", top["badge"], (("after", "portrait_prompt"), ("end", None)))
        if new:
            content_io.write_atomic(jpath, new)
            written = True
    except Exception:
        written = False
    if not written:
        cur = json.loads(src_text)
        cur["badge"] = top["badge"]
        json.dump(cur, open(jpath, "w", encoding="utf-8", newline="\n"), indent=2, ensure_ascii=False)
    g.log("badge written into %s: %s" % (jpath, json.dumps(top["badge"])))
    return dst


def main():
    hid = opt("id")
    if not hid:
        raise SystemExit(__doc__)
    head_width = float(opt("head-width", "0") or 0)
    top_pad = float(opt("top-pad", "0.03") or 0.03)
    if opt("pick") is not None:
        pick(hid, int(opt("pick")), head_width, top_pad)
        return
    paint(hid, int(opt("seeds", "4")), opt("prompt", "") or "", int(opt("first-seed", "0") or 0), head_width, top_pad)


if __name__ == "__main__":
    main()
