"""Pass 124: the ideas document's concept art, by Flux.2 Klein on the AI server (docs/ideas/content.py holds the prompts).
Each picture is one render in the game's style (the style anchor as a reference; a map variation repaints the Stage 1 picture),
saved as a 768 px JPEG in docs/ideas/art/<id>.jpg. Fix one with --only <id> [--seed N] --force. A contact sheet goes to
tools/dl/p126/IDEAS/sheet_<n>.jpg for checking by eye. Pass 126: `kind` "building" (the Main Street mock's lots) paints on a blue
screen and also saves <id>.webp keyed, for the page's mocks.

    python tools/gen_ideas_art.py [--only a,b] [--force] [--seed N] [--sheet]
"""
import importlib.util
import io
import os
import sys
import time

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(REPO, "docs", "ideas", "art")
SHEETS = os.path.join(REPO, "tools", "dl", "p126", "IDEAS")
ARGS = sys.argv[1:]
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
FORCE = "--force" in ARGS
SEED = int(ARGS[ARGS.index("--seed") + 1]) if "--seed" in ARGS else 12401

spec = importlib.util.spec_from_file_location("ideas_content", os.path.join(REPO, "docs", "ideas", "content.py"))
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def jobs():
    out = []
    for group, kind in ((C.PAST_FEATURES, None), (C.PAST_CONTENT, None), (C.VARIATIONS, "scene"), (C.GENERATION, None), (C.SNOW_SCENES, "scene"),
                        (C.FODDER, "creature"), (C.SPECIALS, "creature"), (C.UNIQUE, "creature"), (C.OLD_ITEMS, "icon"), (C.NEW_PASSIVES, "icon"),
                        (C.NEW_CARDS, "card"), (C.NEW_WEAPONS, "icon"), (C.TLE_PVE, "scene"), (C.TLE_PVP, "scene"),
                        (C.NEW_MAP_IDEAS, "scene"), (C.STREET_ART, "building")):
        for it in group:
            k = it.get("kind", kind)
            if k == "diagram" or not it.get("art"):
                continue
            out.append(dict(id=it["id"], kind=k, art=it["art"], ref=it.get("ref")))
    return out


def prompt_for(job, ga):
    k = job["kind"]
    if job.get("ref"):
        return ("Keep exactly this camera, framing and the layout of the ground, the small lake and the scattered objects, and repaint it: " + job["art"] +
                ". Same clean anime game art, crisp lines, cel shading. No people, no text.")
    if k == "creature":
        return ("Using the same art style, line art, cel shading and palette as the reference image, draw a new creature for the same game: " + job["art"] +
                ". Full body, seen from the front at a three quarter angle, the whole figure inside the picture. " + ga.STYLE +
                ". On a plain pale blue-grey background with a soft floor shadow. No text, no watermark. Do not copy the reference's subject.")
    if k == "icon":
        return (ga.ICON_STYLE.replace("no background, no scene", "no scene") + ". " + job["art"] +
                ". On a plain dark slate blue background. Do not copy the reference's subject.")
    if k == "building":
        return ("Using the same art style, line art, cel shading and palette as the reference image, draw one thing for a western mobile game's town: " + job["art"] +
                ". Seen from the front and above at a high three quarter angle, all of it inside the picture, standing on its own small patch of pale sand. " + ga.STYLE.replace(". Game asset", "") +
                ". Isolated on a plain flat solid blue background. No people, no text, no letters on any sign, no watermark. Do not copy the reference's subject.")
    if k == "charm":
        return (ga.ICON_STYLE.replace("no background, no scene", "no scene") + ". " + job["art"] + ". On a plain flat solid blue background. Do not copy the reference's subject.")
    if k == "card":
        return ("A mobile game item icon: " + job["art"] + ", the whole card tilted slightly, thick clean black outline, flat cel shading, saturated colours, centred, no words on the card. "
                "On a plain dark slate blue background.")
    return ("Concept art for a western survivor mobile game, using the same art style, line art, cel shading and palette as the reference image: " + job["art"] + ". " + ga.STYLE.replace(". Game asset", "") +
            ", a finished illustration, no text, no letters, no watermark. Do not copy the reference's subject.")


def size_for(job):
    if job.get("ref") or job["kind"] == "scene":
        return 1216, 832
    return 1024, 1024


def sheet():
    os.makedirs(SHEETS, exist_ok=True)
    names = [j["id"] for j in jobs() if os.path.exists(os.path.join(OUT, j["id"] + ".jpg"))]
    per = 30
    font = ImageFont.load_default()
    for n in range(0, len(names), per):
        part = names[n:n + per]
        cell = 230
        cols = 6
        rows = (len(part) + cols - 1) // cols
        im = Image.new("RGB", (cols * cell, rows * (cell + 16)), (16, 20, 40))
        d = ImageDraw.Draw(im)
        for i, nm in enumerate(part):
            a = Image.open(os.path.join(OUT, nm + ".jpg")).convert("RGB")
            a.thumbnail((cell, cell))
            x, y = (i % cols) * cell, (i // cols) * (cell + 16)
            im.paste(a, (x + (cell - a.width) // 2, y + (cell - a.height) // 2))
            d.text((x + 3, y + cell + 2), nm, fill=(255, 255, 255), font=font)
        p = os.path.join(SHEETS, "sheet_%d.jpg" % (n // per))
        im.save(p, "JPEG", quality=82)
        print(p)


def main():
    if "--sheet" in ARGS:
        sheet()
        return
    import comfy
    import gen_art as ga
    os.makedirs(OUT, exist_ok=True)
    anchor = list(ga.ensure_anchor_uploaded())
    uploaded = {}
    all_jobs = jobs()
    t_all = time.time()
    done = 0
    for k, job in enumerate(all_jobs):
        if ONLY and job["id"] not in ONLY:
            continue
        path = os.path.join(OUT, job["id"] + ".jpg")
        if os.path.exists(path) and not FORCE:
            continue
        refs = list(anchor)
        if job.get("ref"):
            if job["ref"] not in uploaded:
                uploaded[job["ref"]] = comfy.upload_pil(Image.open(os.path.join(REPO, job["ref"])).convert("RGB"), "p124_" + os.path.basename(job["ref"]).replace(".jpg", ".png"))
            refs = [uploaded[job["ref"]]]
        w, h = size_for(job)
        t0 = time.time()
        imgs, _ = comfy.run(comfy.klein(prompt_for(job, ga), SEED + k * 131, w, h, refs=refs, prefix="88fits/p124_ideas"))
        img = Image.open(io.BytesIO(imgs[0])).convert("RGB")
        if job["kind"] in ("building", "charm"):
            import artkit
            cut = artkit.crop_alpha(artkit.key_background(img, cut_shadow=False))
            cut.thumbnail((440, 440), Image.LANCZOS)
            cut.save(os.path.join(OUT, job["id"] + ".webp"), "WEBP", quality=82, method=6)
        img.thumbnail((768, 768), Image.LANCZOS)
        img.save(path, "JPEG", quality=84, optimize=True)
        done += 1
        print("%s %.0fs (%d/%d)" % (job["id"], time.time() - t0, k + 1, len(all_jobs)), flush=True)
    print("done %d in %.0f s" % (done, time.time() - t_all), flush=True)
    sheet()


if __name__ == "__main__":
    main()
