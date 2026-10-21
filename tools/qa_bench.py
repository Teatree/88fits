"""The blind calibration set for visual evaluators (pass 96, lane GATES, gate G2; the assessment's AI-08). The cases are
images under tools/dl/ (git-ignored) whose verdicts the lanes recorded in their status files (never this tool's eye),
copied under BLIND ids (C01.., a fixed shuffle: no hint in a name) to tools/dl/qa_bench/, with the manifest in git
(tools/qa_bench/manifest.json: {id, image, kind, species, expect_legs, verdict, strength, source, rater, origin}). One
hint-free rubric (count the legs per side, ghost legs, smears, the face; JSON only; the species' expected count is the
only anchor, dropped by --unanchored). An evaluator run sees the pixels under an opaque name and the rubric: never a
file name, a status line or a verdict.

    python tools/qa_bench.py prepare                       the manifest + the blind copies (idempotent; says what is missing)
    python tools/qa_bench.py run openai_chat <model> [--unanchored] [--tag T] [--max-tokens N] [--url U] [--only C01,C02] [--repeat N]
                                                           LM Studio (or any OpenAI-chat endpoint) one request per image, temperature 0
    python tools/qa_bench.py run anthropic <model> ...     only when tools/keys/anthropic.env exists (never the harness's own key)
    python tools/qa_bench.py run gemini <model> ...        only when tools/keys/gemini.env exists (G3: none yet)
    python tools/qa_bench.py score [results.json ...]      per run: legs / ghost / face right, clean-vs-defect, the MISS rate (defects
                                                           passed) and the FALSE-ALARM rate (clean flagged), seconds, dollars; the
                                                           run-to-run agreement of a model; writes tools/dl/qa_bench/results/scores.{json,md}
    python tools/qa_bench.py tiers [--write]               the tier table from the scores -> tools/level_editor/request_defaults.json `tiers`

Scoring (strong cases only; weak ones are reported apart): legs = the exact count where one is recorded; ghost / face =
the boolean against the record; flagged = any of (legs != the species' count, ghost, smears, face missing or wrong);
miss = a defect not flagged; false alarm = a clean case flagged; an empty or unparsable answer = no verdict (not
flagged: a miss on a defect, never "ok"). The tiers: tier 0 deterministic (the flags), tier 1 = the local model with the
best miss rate (ties: fewer false alarms, then faster) at zero cost among the configurations that flag at most half of the
clean cases (FA_MAX), on flagged frames + a sample, tier 2 = a cloud eye on contact sheets, off (ceiling 0.0) until a key
exists and its numbers earn it.

When tools/vision_eval.py (lane LOOP's adapter) exists and exposes openai_chat_json, the openai_chat backend goes through
it (the result says so); else this tool posts the same request shape itself.
"""
import base64
import io
import json
import os
import random
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from PIL import Image  # noqa: E402

MANIFEST = os.path.join(HERE, "qa_bench", "manifest.json")
IMAGES = os.path.join(REPO, "tools", "dl", "qa_bench")
RESULTS = os.path.join(IMAGES, "results")
DL = os.path.join(REPO, "tools", "dl")
KEYS = os.path.join(HERE, "keys")
LMSTUDIO = "http://127.0.0.1:1234/v1/chat/completions"
REQUEST_DEFAULTS = os.path.join(HERE, "level_editor", "request_defaults.json")
FA_MAX = 0.5             # a tier-1 candidate may flag at most half of the clean cases
TIER2_MODEL = "claude-haiku-5-5"   # the cheapest current vision-capable Claude model (the claude-api skill's table, 2026-10)
GREY = (128, 128, 128)

# ---------------------------------------------------------------- the cases: where each image comes from and what was recorded
# verdict: legs = the recorded count (None = not recorded), ghost / face / smear = True when that defect was recorded, False when
# the record says clean, None when it says nothing; clean = the record's overall verdict. strength: strong = a recorded verdict
# (a lane's eye, a lane's pick that is in play, or Garry's complaint), weak = inferred (a packed look's frame, a pick's losers).
FS = os.path.join(DL, "frames", "enemy", "desert_spider", "SP-B", "run", "side")
SOURCES = [
    # part D3's sixteen (tools/dl/p95/ASSESS/part_AI.md 1.1): stills on green (Klein side candidates), walk frames (keyed out_05 on grey)
    dict(origin="ai_raw_anime/desert_spider_spf_side_k0.png", kind="still", species="spider", verdict=dict(legs=9, ghost=False, face=False, clean=False), strength="strong",
         source="p93/status_LEGS.md: 'SP-F k0-7 -> pick k6 (8 legs; k0 had 9)'", rater="lane LEGS (p93) by eye"),
    dict(origin="ai_raw_anime/desert_spider_spf_side_k6.png", kind="still", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p93/status_LEGS.md: pick k6 (8 legs)", rater="lane LEGS (p93) by eye; the pick"),
    dict(origin="ai_raw_anime/desert_spider_spe_side_k1.png", kind="still", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p93/status_LEGS.md: 'SP-E k0-3 -> pick k1 (8 legs, grumpy, fuzzy)'", rater="lane LEGS (p93) by eye; the pick"),
    dict(origin="ai_raw_anime/desert_spider_spb_side_k0.png", kind="still", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p92/status_SPIDER.md: 'picks by eye (8 legs counted): SP-B k0'", rater="lane SPIDER (p92) by eye; the pick, in play"),
    dict(origin="p94/REAL/backup/sph_d85b8/desert_spider_sph_side_k1.png", kind="still", species="spider", verdict=dict(legs=11, ghost=False, face=False, clean=False), strength="strong",
         source="p94/status_REAL.md: 'SP-H ... k1 eleven legs'", rater="lane REAL (p94) by eye"),
    dict(origin="p94/REAL/backup/spg_k16/raw/desert_spider_spg_side_k2.png", kind="still", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p94/status_REAL.md: 'SP-G house-style side k0-5: pick k2 (chevrons, fuzzy, 8 legs)'", rater="lane REAL (p94) by eye; the pick"),
    dict(origin="p94/REAL/backup/spg_k16/raw/desert_spider_spg_side_k1.png", kind="still", species="spider", verdict=dict(legs=None, ghost=False, face=True, clean=False), strength="strong",
         source="p94/status_REAL.md: 'k1 skull face'", rater="lane REAL (p94) by eye"),
    dict(origin="p92/SPIDER/negtest/cfg3_neg_seed2.png", kind="still", species="spider", verdict=dict(legs=9, ghost=False, face=False, clean=False), strength="strong",
         source="p92/status_SPIDER.md: 'cfg3 seed2 ~9 legs'", rater="lane SPIDER (p92) by eye"),
    dict(origin="ai_raw_anime/desert_spider_spa_side_k1.png", kind="still", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p92/status_SPIDER.md: 'picks by eye (8 legs counted): SP-A k1'", rater="lane SPIDER (p92) by eye; the pick"),
    dict(origin="p92/SPIDER/before/spa_ctl_front_v1/out_05.png", kind="frame", species="spider", verdict=dict(legs=10, ghost=True, face=False, clean=False), strength="strong",
         source="p92/status_SPIDER.md: 'SP-A front walk: Wan added two ghost legs (grey-green) under the head ... -> 10 legs'", rater="lane SPIDER (p92) by eye"),
    dict(origin="p92/SPIDER/before/spd_v1/desert_spider_spd_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=False, face=True, clean=False), strength="strong",
         source="p92/status_SPIDER.md: 'SP-D front walk (plain drivers) lost its big face'", rater="lane SPIDER (p92) by eye"),
    dict(origin="p93/LEGS/backup/desert_spider_spe_ctl_front_1792412798/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=True, face=False, clean=False), strength="strong",
         source="p93/status_LEGS.md: 'SP-E ... front walk has grey ghost legs at the sides' (the unfitted walk)", rater="lane LEGS (p93) by eye"),
    dict(origin="p93/LEGS/backup/desert_spider_spe_ctl_front_sharp/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=False, face=True, clean=False), strength="strong",
         source="p93/status_LEGS.md: 'fit 1 (no ghosts, face+abdomen lost)'", rater="lane LEGS (p93) by eye"),
    dict(origin="ai_anim/desert_spider_spe_test_fit05/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=False, face=True, clean=False), strength="strong",
         source="p93/status_LEGS.md: 'fit 0.5 (face lost)'", rater="lane LEGS (p93) by eye"),
    dict(origin="ai_anim/desert_spider_spe_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=False, face=False, clean=True), strength="strong",
         source="p93/status_LEGS.md: 'fit+soft10 (face+stripes kept, legs step) -> chosen' (the installed SP-E front)", rater="lane LEGS (p93) by eye; chosen"),
    dict(origin="ai_anim/desert_spider_spg_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=False, face=False, clean=True), strength="strong",
         source="p94/status_REAL.md 2026-10-21: 'SP-G v2 walks checked frame by frame ... the front is fine'", rater="lane REAL (p94) by eye"),
    # the SP-C / SP-D before/ walks (p92): the fronts that lost the face before the drivers were pitched and softened
    dict(origin="p92/SPIDER/before/spc_v1/desert_spider_spc_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=True, clean=False), strength="strong",
         source="p92/status_SPIDER.md: 'SP-C front walk (body 1.6/head 1.1) ... STILL lost the face' (backup before/spc_v1)", rater="lane SPIDER (p92) by eye"),
    dict(origin="p92/SPIDER/before/spc_v1/desert_spider_spc_ctl_front/out_00.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=True, clean=False), strength="strong",
         source="p92/status_SPIDER.md: the same SP-C front walk, its first frame", rater="lane SPIDER (p92) by eye"),
    dict(origin="p92/SPIDER/before/spd_v2/desert_spider_spd_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=True, clean=False), strength="strong",
         source="p92/status_SPIDER.md: 'SP-D v2 front walk (proportions) STILL lost the face' (backup before/spd_v2)", rater="lane SPIDER (p92) by eye"),
    dict(origin="ai_anim/desert_spider_spc_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=False, clean=True), strength="weak",
         source="p92/status_SPIDER.md DONE line: 'C (k1) front ... softened ... all four looks packed' (the installed SP-C front)", rater="inferred from the pack decision"),
    dict(origin="ai_anim/desert_spider_spd_ctl_front/out_05.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=False, clean=True), strength="weak",
         source="p92/status_SPIDER.md: 'whole blur 10px: face kept AND legs move -> recipe ctl_soft' then packed (the installed SP-D front)", rater="inferred from the pack decision"),
    # lane VACE's demo pairs (p95 report_VACE.md section 6, design_VACE.md section 5): the installed SP-B side frames 3-5 (ghost legs), the
    # repaired versions SP-B-2 (seed 24110: 3 and 4 clean, 5 and 9 worse) and SP-B-3 (seed 7: 5 and 9 worse again)
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_03/v001_raw.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=True, face=False, clean=False), strength="strong",
         source="p95/design_VACE.md section 5: the flags do 'not [flag] the ghost-leg frames 3-5' of SP-B's side walk", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_04/v001_raw.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=True, face=False, clean=False), strength="strong",
         source="p95/design_VACE.md section 5: the ghost-leg frames 3-5", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_05/v001_raw.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=True, face=False, clean=False), strength="strong",
         source="p95/design_VACE.md section 5: the ghost-leg frames 3-5", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_03/v002.png", kind="frame", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p95/report_VACE.md section 6: 'slots 3 and 4 came back clean: eight legs where the driver has eight ... no green'", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_04/v002.png", kind="frame", species="spider", verdict=dict(legs=8, ghost=False, face=False, clean=True), strength="strong",
         source="p95/report_VACE.md section 6: slots 3 and 4 clean", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_05/v002.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=True, smear=True, clean=False), strength="strong",
         source="p95/report_VACE.md section 6: 'Slot 5 came back with a flattened, reshaped head and paler patches'", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_09/v002.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=True, face=None, smear=True, clean=False), strength="strong",
         source="p95/report_VACE.md section 6: 'slot 9 as a pale tangle of legs'", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_05/v003.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=None, clean=False), strength="strong",
         source="p95/report_VACE.md section 6: 'Run 2 (seed 7, slots 5 and 9 only): both worse again'", rater="lane VACE (p95) by eye"),
    dict(origin="frames/enemy/desert_spider/SP-B/run/side/slot_09/v003.png", kind="frame", species="spider", verdict=dict(legs=None, ghost=None, face=None, clean=False), strength="strong",
         source="p95/report_VACE.md section 6: run 2 both worse again", rater="lane VACE (p95) by eye"),
    # three other creatures' side candidate sets with a known pick: the still in use is the picked candidate (the same bytes), the look
    # is the one in play (Garry accepted it); the losers are weak 'not chosen' labels (not necessarily defective)
    dict(origin="ai_raw_anime/dune_scorpion_scd_side_k0.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=False, face=False, clean=True), strength="strong",
         source="tools/dl/review/dune_scorpion_scd_side_cands.png: k0 = desert dune_scorpion_scd_side.png (the same bytes), SC-D in play", rater="the pick, in play"),
    dict(origin="ai_raw_anime/dune_scorpion_scd_side_k1.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="dune_scorpion SC-D side candidates: not the pick", rater="a pick's loser"),
    dict(origin="ai_raw_anime/dune_scorpion_scd_side_k2.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="dune_scorpion SC-D side candidates: not the pick", rater="a pick's loser"),
    dict(origin="ai_raw_anime/bull_beetle_bbc_side_k1.png", kind="still", species="beetle", verdict=dict(legs=None, ghost=False, face=False, clean=True), strength="strong",
         source="tools/dl/review/bull_beetle_bbc_side_cands.png: k1 = bull_beetle_bbc_side.png (the same bytes), BB-C in play", rater="the pick, in play"),
    dict(origin="ai_raw_anime/bull_beetle_bbc_side_k0.png", kind="still", species="beetle", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="bull_beetle BB-C side candidates: not the pick", rater="a pick's loser"),
    dict(origin="ai_raw_anime/bull_beetle_bbc_side_k2.png", kind="still", species="beetle", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="bull_beetle BB-C side candidates: not the pick", rater="a pick's loser"),
    dict(origin="ai_raw_anime/lesser_scorpion_lsb_side_k1.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=False, face=False, clean=True), strength="strong",
         source="tools/dl/review/lesser_scorpion_lsb_side_cands.png: k1 = lesser_scorpion_lsb_side.png (the same bytes), LS-B in play", rater="the pick, in play"),
    dict(origin="ai_raw_anime/lesser_scorpion_lsb_side_k0.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="lesser_scorpion LS-B side candidates: not the pick", rater="a pick's loser"),
    dict(origin="ai_raw_anime/lesser_scorpion_lsb_side_k2.png", kind="still", species="scorpion", verdict=dict(legs=None, ghost=None, face=None, clean=None, chosen=False), strength="weak",
         source="lesser_scorpion LS-B side candidates: not the pick", rater="a pick's loser"),
]
EXPECT_LEGS = {"spider": 8, "scorpion": 8, "beetle": 6}
SPECIES_WORDS = {"spider": "a spider", "scorpion": "a scorpion (its two pincers are not legs)", "beetle": "a beetle"}

RUBRIC = ("You are checking ONE frame of a 2D game creature sprite: {species}, as a still painting on a flat colour screen or as one "
          "animation frame pasted on grey. {anchor}Small fangs, pincers, claws or mouthparts at the head are NOT legs. Answer ONLY with one "
          "JSON object, no prose, keys: legs_total (integer: how many legs you can see in total), legs_left (integer: legs on the left half "
          "of the body as drawn), legs_right (integer: legs on the right half), ghost_legs (true if there are faded, translucent, greyish, "
          "blurry or duplicated extra legs beside the solid ones), smears (true if parts of the body or legs are blurred, streaked or "
          "smeared), face (\"ok\" if a face with eyes is drawn where this view should show one, \"missing\" if the head has no face or eyes "
          "although it should, \"wrong\" if the face is not the creature's own, e.g. a skull or a human-like face, \"n/a\" if the view shows "
          "the creature from behind), notes (a string of at most 20 words).")
ANCHORED = "A correct {species_word} has exactly {n} legs, {half} on each side of the body. Count carefully. "
UNANCHORED = "Count every leg you can see, one by one, from left to right; do not assume how many legs this creature should have. "


def log(*a):
    print(*a, flush=True)


def _rel(path):
    try:
        return os.path.relpath(path, REPO).replace("\\", "/")
    except ValueError:   # another drive (a temp folder on C:)
        return os.path.abspath(path).replace("\\", "/")


def rubric(case, unanchored=False):
    sp = case.get("species", "creature")
    n = int(case.get("expect_legs") or EXPECT_LEGS.get(sp, 0) or 0)
    anchor = UNANCHORED if (unanchored or not n) else ANCHORED.format(species_word=SPECIES_WORDS.get(sp, "a " + sp), n=n, half=n // 2)
    return RUBRIC.format(species=SPECIES_WORDS.get(sp, "a " + sp), anchor=anchor)


# ---------------------------------------------------------------- prepare

def prepare(write=True, quiet=False):
    order = list(range(len(SOURCES)))
    random.Random(96).shuffle(order)
    cases, missing = [], []
    os.makedirs(IMAGES, exist_ok=True)
    for k, idx in enumerate(order):
        s = SOURCES[idx]
        cid = "C%02d" % (k + 1)
        src = os.path.join(DL, s["origin"])
        if not os.path.isfile(src):
            missing.append((cid, s["origin"]))
            continue
        dst = os.path.join(IMAGES, cid + ".png")
        if write:
            im = Image.open(src)
            if im.mode == "RGBA":
                bg = Image.new("RGB", im.size, GREY)
                bg.paste(im, (0, 0), im)
                im = bg
            else:
                im = im.convert("RGB")
            im.save(dst)
            size = list(im.size)
        else:
            size = None
        v = dict(s["verdict"])
        cases.append({"id": cid, "image": "tools/dl/qa_bench/%s.png" % cid, "kind": s["kind"], "species": s["species"],
                      "expect_legs": EXPECT_LEGS.get(s["species"]), "verdict": v, "strength": s["strength"], "source": s["source"], "rater": s["rater"],
                      "origin": "tools/dl/" + s["origin"], "size": size})
    man = {"v": 1, "made": time.strftime("%Y-%m-%dT%H:%M:%S"), "images": "tools/dl/qa_bench/", "blind": "ids C01.. are a fixed shuffle (random seed 96) of the sources; a name never carries a verdict",
           "rubric": RUBRIC, "anchored": ANCHORED, "unanchored": UNANCHORED, "expect_legs": EXPECT_LEGS, "cases": cases}
    if write:
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
            json.dump(man, f, indent=1, ensure_ascii=False)
    strong = sum(1 for c in cases if c["strength"] == "strong")
    defects = sum(1 for c in cases if c["strength"] == "strong" and c["verdict"].get("clean") is False)
    if not quiet:
        log("qa_bench: %d cases (%d strong: %d defects, %d clean; %d weak); %d missing%s" % (
        len(cases), strong, defects, strong - defects, len(cases) - strong, len(missing), (": " + ", ".join("%s %s" % m for m in missing)) if missing else ""))
    return man


def manifest():
    with open(MANIFEST, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- backends

def parse_json(txt):
    txt = (txt or "").strip().strip("`")
    if txt.startswith("json"):
        txt = txt[4:]
    i, j = txt.find("{"), txt.rfind("}")
    if i < 0 or j <= i:
        return {}
    try:
        return json.loads(txt[i:j + 1])
    except ValueError:
        return {}


def _key_file(name):
    p = os.path.join(KEYS, name)
    if not os.path.isfile(p):
        return None
    out = {}
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def openai_chat(img_path, question, model, max_tokens, url=None):
    """One OpenAI-chat request with one PNG, temperature 0 (LM Studio's shape; the same body gen_art.vision_json sends).
    Returns {text, parsed, usage, finish_reason, via}."""
    url = url or LMSTUDIO
    via = "direct"
    try:
        import vision_eval  # lane LOOP's adapter, when it has landed
        fn = getattr(vision_eval, "openai_chat_json", None)
    except Exception:
        fn = None
    img = Image.open(img_path).convert("RGB")
    if fn is not None:
        try:
            parsed = fn(img, question, max_tokens, url=url, model=model)
            return {"text": json.dumps(parsed), "parsed": parsed if isinstance(parsed, dict) else {}, "usage": {}, "finish_reason": None, "via": "vision_eval.openai_chat_json"}
        except TypeError:
            pass   # another signature: post it ourselves
        except Exception as e:
            return {"text": "ERROR " + str(e)[:300], "parsed": {}, "usage": {}, "finish_reason": "error", "via": "vision_eval.openai_chat_json"}
    buf = io.BytesIO()
    img.save(buf, "PNG")
    body = {"model": model, "max_tokens": int(max_tokens), "temperature": 0, "messages": [{"role": "user", "content": [
        {"type": "text", "text": question},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}}]}]}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=600))
        msg = r["choices"][0]["message"]
        txt = msg.get("content") or ""
        if not txt.strip():
            txt = msg.get("reasoning_content") or msg.get("reasoning") or ""   # a thinking model that spent its budget: no verdict
        usage = r.get("usage") or {}
        return {"text": txt[:1200], "parsed": parse_json(txt), "usage": usage, "finish_reason": r["choices"][0].get("finish_reason"), "via": via}
    except Exception as e:
        return {"text": "ERROR " + str(e)[:300], "parsed": {}, "usage": {}, "finish_reason": "error", "via": via}


def anthropic_chat(img_path, question, model, max_tokens):
    """The Anthropic Messages API with a pinned model id, only with a key in tools/keys/anthropic.env (never the harness's)."""
    keys = _key_file("anthropic.env")
    if not keys or not keys.get("ANTHROPIC_API_KEY"):
        raise SystemExit("qa_bench: no tools/keys/anthropic.env (ANTHROPIC_API_KEY=...): the Anthropic tier is not run (the harness's own key is never used)")
    try:
        import vision_eval
        be = vision_eval.backend_for("anthropic", model=model)
        res = be.ask(Image.open(img_path).convert("RGB"), question, max_tokens)   # LOOP's adapter shape, when it has one
        return {"text": json.dumps(res), "parsed": res if isinstance(res, dict) else {}, "usage": {}, "finish_reason": None, "via": "vision_eval.AnthropicBackend"}
    except SystemExit:
        raise
    except Exception:
        pass
    buf = io.BytesIO()
    Image.open(img_path).convert("RGB").save(buf, "PNG")
    body = {"model": model, "max_tokens": int(max_tokens), "messages": [{"role": "user", "content": [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": base64.b64encode(buf.getvalue()).decode()}},
        {"type": "text", "text": question}]}]}
    req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "x-api-key": keys["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=120))
        txt = "".join(b.get("text", "") for b in r.get("content", []) if b.get("type") == "text")
        return {"text": txt[:1200], "parsed": parse_json(txt), "usage": r.get("usage") or {}, "finish_reason": r.get("stop_reason"), "via": "direct"}
    except Exception as e:
        return {"text": "ERROR " + str(e)[:300], "parsed": {}, "usage": {}, "finish_reason": "error", "via": "direct"}


def run(backend, model, unanchored=False, tag="", max_tokens=None, url=None, only=None, repeat=1):
    man = manifest()
    if backend == "gemini":
        if not _key_file("gemini.env"):
            raise SystemExit("qa_bench: no tools/keys/gemini.env: the Gemini tier is not run (G3 waits for Garry's AI Studio key with billing)")
        raise SystemExit("qa_bench: the Gemini backend is lane LOOP's adapter's (vision_eval.GeminiBackend); run it through `run openai_chat` with its OpenAI-compatible URL for now")
    if backend not in ("openai_chat", "anthropic"):
        raise SystemExit("qa_bench: backend is openai_chat | anthropic | gemini")
    if max_tokens is None:
        max_tokens = 1500 if "gemma" in model.lower() else 300   # a thinking model spends its budget on hidden reasoning first (part D3's lesson)
    os.makedirs(RESULTS, exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "_", model.lower()).strip("_")[:40]
    paths = []
    for rep in range(int(repeat)):
        name = "%s_%s_%s%s_%s.json" % (backend, slug, "unanchored" if unanchored else "anchored", ("_" + tag) if tag else "", time.strftime("%Y%m%d-%H%M%S"))
        out = {"v": 1, "backend": backend, "model": model, "rubric": "unanchored" if unanchored else "anchored", "max_tokens": max_tokens, "url": url or (LMSTUDIO if backend == "openai_chat" else "api"),
               "started": time.strftime("%Y-%m-%dT%H:%M:%S"), "results": {}}
        t_all = time.time()
        for c in man["cases"]:
            if only and c["id"] not in only:
                continue
            p = os.path.join(REPO, c["image"])
            q = rubric(c, unanchored)
            t0 = time.time()
            if backend == "openai_chat":
                r = openai_chat(p, q, model, max_tokens, url)
            else:
                r = anthropic_chat(p, q, model, max_tokens)
            r["seconds"] = round(time.time() - t0, 2)
            out["results"][c["id"]] = r
            log("%s %6.1fs %s %s" % (c["id"], r["seconds"], ("NO VERDICT" if not r["parsed"] else json.dumps(r["parsed"])[:110]), r.get("via") if r.get("via") != "direct" else ""))
        out["total_seconds"] = round(time.time() - t_all, 1)
        out["via"] = sorted(set(r.get("via") for r in out["results"].values()))
        out["dollars"] = dollars(out)
        path = os.path.join(RESULTS, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(out, f, indent=1, ensure_ascii=False)
        log("qa_bench: wrote %s (%s s, $%.4f, via %s)" % (_rel(path), out["total_seconds"], out["dollars"], ", ".join(out["via"])))
        paths.append(path)
    return paths


PRICES = {"claude-haiku-5-5": (0.10, 0.50), "claude-haiku-4-5": (1.0, 5.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-sonnet-5": (2.0, 10.0)}


def dollars(out):
    if out.get("backend") != "anthropic":
        return 0.0
    pin, pout = PRICES.get(out.get("model"), (0.0, 0.0))
    tot = 0.0
    for r in out["results"].values():
        u = r.get("usage") or {}
        tot += (u.get("input_tokens", 0) * pin + u.get("output_tokens", 0) * pout) / 1e6
    return round(tot, 5)


# ---------------------------------------------------------------- score

def flagged_of(parsed, expect):
    """What the answer flags: {legs, ghost, smears, face_bad, flagged}; None = no verdict."""
    if not isinstance(parsed, dict) or not parsed:
        return None
    legs = parsed.get("legs_total")
    legs = int(legs) if isinstance(legs, (int, float)) and not isinstance(legs, bool) else None
    ghost = bool(parsed.get("ghost_legs"))
    smears = bool(parsed.get("smears"))
    face_bad = str(parsed.get("face", "ok")).lower() in ("missing", "wrong")
    legs_bad = (legs is not None and expect and legs != expect)
    return {"legs": legs, "ghost": ghost, "smears": smears, "face_bad": face_bad, "flagged": bool(legs_bad or ghost or smears or face_bad)}


def score_file(path, man=None):
    man = man or manifest()
    d = json.load(open(path, "r", encoding="utf-8"))
    res = d["results"]
    s = {"file": _rel(path), "backend": d["backend"], "model": d["model"], "rubric": d["rubric"], "seconds": d.get("total_seconds"), "dollars": d.get("dollars", 0.0),
         "via": d.get("via"), "legs": [0, 0], "ghost": [0, 0], "face": [0, 0], "clean_vs_defect": [0, 0], "misses": [0, 0], "false_alarms": [0, 0], "no_verdict": 0,
         "weak": {"not_chosen_flagged": [0, 0], "inferred_clean_flagged": [0, 0]}, "cases": {}}
    for c in man["cases"]:
        r = res.get(c["id"])
        if not r:
            continue
        v = c["verdict"]
        f = flagged_of(r.get("parsed"), c.get("expect_legs"))
        rec = {"strength": c["strength"], "truth_clean": v.get("clean"), "answer": f}
        if f is None:
            s["no_verdict"] += 1
        if c["strength"] != "strong":
            if v.get("chosen") is False:
                s["weak"]["not_chosen_flagged"][1] += 1
                s["weak"]["not_chosen_flagged"][0] += 1 if (f and f["flagged"]) else 0
            elif v.get("clean") is True:
                s["weak"]["inferred_clean_flagged"][1] += 1
                s["weak"]["inferred_clean_flagged"][0] += 1 if (f and f["flagged"]) else 0
            s["cases"][c["id"]] = rec
            continue
        if v.get("legs") is not None:
            s["legs"][1] += 1
            s["legs"][0] += 1 if (f and f["legs"] == v["legs"]) else 0
            rec["legs_ok"] = bool(f and f["legs"] == v["legs"])
        if v.get("ghost") is not None:
            s["ghost"][1] += 1
            s["ghost"][0] += 1 if (f is not None and f["ghost"] == bool(v["ghost"])) else 0
        if v.get("face") is not None:
            s["face"][1] += 1
            s["face"][0] += 1 if (f is not None and f["face_bad"] == bool(v["face"])) else 0
        truth_bad = v.get("clean") is False
        pred_bad = bool(f and f["flagged"])
        s["clean_vs_defect"][1] += 1
        s["clean_vs_defect"][0] += 1 if pred_bad == truth_bad else 0
        if truth_bad:
            s["misses"][1] += 1
            s["misses"][0] += 0 if pred_bad else 1
            rec["outcome"] = "caught" if pred_bad else "MISSED"
        else:
            s["false_alarms"][1] += 1
            s["false_alarms"][0] += 1 if pred_bad else 0
            rec["outcome"] = "FALSE ALARM" if pred_bad else "passed"
        s["cases"][c["id"]] = rec
    n_img = max(1, len([c for c in man["cases"] if c["id"] in res]))
    s["seconds_per_image"] = round((d.get("total_seconds") or 0) / n_img, 2)
    s["miss_rate"] = round(s["misses"][0] / s["misses"][1], 3) if s["misses"][1] else None
    s["false_alarm_rate"] = round(s["false_alarms"][0] / s["false_alarms"][1], 3) if s["false_alarms"][1] else None
    return s


def agreement(a, b):
    """Two scored runs of one model and rubric: the share of cases where the flagged verdict agrees, and where the whole tuple does."""
    ids = [k for k in a["cases"] if k in b["cases"]]
    same_flag = same_all = 0
    for k in ids:
        fa, fb = a["cases"][k]["answer"], b["cases"][k]["answer"]
        if (fa is None) and (fb is None):
            same_flag += 1
            same_all += 1
            continue
        if fa is None or fb is None:
            continue
        same_flag += 1 if fa["flagged"] == fb["flagged"] else 0
        same_all += 1 if (fa["legs"], fa["ghost"], fa["smears"], fa["face_bad"]) == (fb["legs"], fb["ghost"], fb["smears"], fb["face_bad"]) else 0
    n = max(1, len(ids))
    return {"cases": len(ids), "flag": round(same_flag / n, 3), "all_fields": round(same_all / n, 3)}


def score(paths=None):
    man = manifest()
    if not paths:
        paths = sorted(os.path.join(RESULTS, f) for f in os.listdir(RESULTS) if f.endswith(".json") and not f.startswith("scores")) if os.path.isdir(RESULTS) else []
    scored = [score_file(p, man) for p in paths]
    groups = {}
    for s in scored:
        groups.setdefault((s["backend"], s["model"], s["rubric"]), []).append(s)
    per_model = []
    for (backend, model, rub), ss in groups.items():
        agree = [agreement(ss[i], ss[j]) for i in range(len(ss)) for j in range(i + 1, len(ss))]
        mean = lambda key: round(sum((x[key] or 0) for x in ss) / len(ss), 3)  # noqa: E731
        per_model.append({"backend": backend, "model": model, "rubric": rub, "runs": len(ss), "miss_rate": mean("miss_rate"), "false_alarm_rate": mean("false_alarm_rate"),
                          "legs": [sum(x["legs"][0] for x in ss), sum(x["legs"][1] for x in ss)], "ghost": [sum(x["ghost"][0] for x in ss), sum(x["ghost"][1] for x in ss)],
                          "face": [sum(x["face"][0] for x in ss), sum(x["face"][1] for x in ss)], "clean_vs_defect": [sum(x["clean_vs_defect"][0] for x in ss), sum(x["clean_vs_defect"][1] for x in ss)],
                          "no_verdict": sum(x["no_verdict"] for x in ss), "seconds_per_image": mean("seconds_per_image"), "dollars": round(sum(x["dollars"] for x in ss), 5),
                          "agreement": agree[0] if agree else None, "files": [x["file"] for x in ss],
                          "weak": {k: [sum(x["weak"][k][0] for x in ss), sum(x["weak"][k][1] for x in ss)] for k in ("not_chosen_flagged", "inferred_clean_flagged")}})
    strong = [c for c in man["cases"] if c["strength"] == "strong"]
    defects = sum(1 for c in strong if c["verdict"].get("clean") is False)
    out = {"made": time.strftime("%Y-%m-%dT%H:%M:%S"), "cases": len(man["cases"]), "strong": len(strong), "defects": defects, "clean": len(strong) - defects,
           "baseline_say_clean": {"miss_rate": 1.0, "false_alarm_rate": 0.0, "clean_vs_defect": [len(strong) - defects, len(strong)]},
           "per_model": per_model, "runs": scored}
    os.makedirs(RESULTS, exist_ok=True)
    with open(os.path.join(RESULTS, "scores.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    md = scores_markdown(out)
    with open(os.path.join(RESULTS, "scores.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(md)
    print(md)
    return out


def scores_markdown(out):
    lines = ["# qa_bench scores (%s): %d cases, %d strong (%d defects, %d clean), the rest weak" % (out["made"], out["cases"], out["strong"], out["defects"], out["clean"]),
             "", "A 'say clean to everything' evaluator: miss rate 1.0, false alarms 0.0, clean-vs-defect %d/%d." % tuple(out["baseline_say_clean"]["clean_vs_defect"]), "",
             "| backend | model | rubric | runs | miss rate | false alarms | legs | ghost | face | clean-vs-defect | no verdict | s/image | $ | agreement (flag / all) |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for m in out["per_model"]:
        ag = m["agreement"]
        lines.append("| %s | %s | %s | %d | %s | %s | %d/%d | %d/%d | %d/%d | %d/%d | %d | %s | %.4f | %s |" % (
            m["backend"], m["model"], m["rubric"], m["runs"], m["miss_rate"], m["false_alarm_rate"], m["legs"][0], m["legs"][1], m["ghost"][0], m["ghost"][1],
            m["face"][0], m["face"][1], m["clean_vs_defect"][0], m["clean_vs_defect"][1], m["no_verdict"], m["seconds_per_image"], m["dollars"],
            ("%s / %s" % (ag["flag"], ag["all_fields"])) if ag else "one run"))
    lines += ["", "Weak labels (not scored): a pick's losers flagged, an inferred-clean installed frame flagged:", ""]
    for m in out["per_model"]:
        w = m["weak"]
        lines.append("- %s %s (%s): losers flagged %d/%d, inferred-clean flagged %d/%d" % (m["backend"], m["model"], m["rubric"], w["not_chosen_flagged"][0], w["not_chosen_flagged"][1],
                                                                                           w["inferred_clean_flagged"][0], w["inferred_clean_flagged"][1]))
    lines += ["", "Per run:", ""]
    for s in out["runs"]:
        missed = [k for k, c in s["cases"].items() if c.get("outcome") == "MISSED"]
        fa = [k for k, c in s["cases"].items() if c.get("outcome") == "FALSE ALARM"]
        lines.append("- %s: miss %s (%s), false alarms %s (%s), %s s" % (s["file"], s["miss_rate"], " ".join(missed), s["false_alarm_rate"], " ".join(fa), s["seconds"]))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- the tier table

def tiers(write=False, scores=None, quiet=False):
    """request_defaults.json `tiers` (INTERFACES): tier 0 deterministic; tier 1 the local model with the best miss rate (ties: fewer
    false alarms, then faster) at zero cost on flagged frames + a sample; tier 2 the cloud eye on sheets, off (ceiling 0.0) until a
    key exists and the bench ranks it."""
    scores = scores or json.load(open(os.path.join(RESULTS, "scores.json"), "r", encoding="utf-8"))
    # a screen that flags more than half of the clean frames sends everything on: no screen at all, whatever its miss rate
    local = [m for m in scores["per_model"] if m["backend"] == "openai_chat" and m["dollars"] == 0 and (m["false_alarm_rate"] or 0) <= FA_MAX]
    local.sort(key=lambda m: ((m["miss_rate"] if m["miss_rate"] is not None else 1.0), (m["false_alarm_rate"] or 0), m["seconds_per_image"] or 1e9))
    best = local[0] if local else None
    measured = {}
    for m in scores["per_model"]:
        measured.setdefault(m["model"], {})[m["rubric"]] = {"miss_rate": m["miss_rate"], "false_alarm_rate": m["false_alarm_rate"], "seconds_per_image": m["seconds_per_image"],
                                                           "runs": m["runs"], "agreement": m["agreement"], "dollars": m["dollars"]}
    table = {"0": "deterministic",
             "1": {"backend": "openai_chat", "model": best["model"] if best else "qwen2.5-vl-7b-instruct-abliterated", "on": "flagged+sample",
                   "url": LMSTUDIO, "max_tokens": 1500 if (best and "gemma" in best["model"]) else 300, "rubric": (best["rubric"] if best else "anchored"),
                   "miss_rate": (best["miss_rate"] if best else None), "false_alarm_rate": (best["false_alarm_rate"] if best else None)},
             "2": {"backend": "anthropic", "model": TIER2_MODEL, "on": "sheets", "ceiling_dollars": 0.0, "key_file": "tools/keys/anthropic.env"},
             "_measured": {"made": scores["made"], "set": "tools/qa_bench/manifest.json (%d strong cases: %d defects, %d clean)" % (scores["strong"], scores["defects"], scores["clean"]),
                           "models": measured, "note": "tier 1 = the best miss rate at zero cost; no model on this set counts legs or sees ghost legs reliably: "
                                                       "the loop's provisional winner is a staged selection Garry approves, never an install; tier 2 off until a key exists (G3)"}}
    if not write:
        if not quiet:
            print(json.dumps(table, indent=1))
        return table
    doc = {}
    if os.path.isfile(REQUEST_DEFAULTS):
        with open(REQUEST_DEFAULTS, "r", encoding="utf-8") as f:
            doc = json.load(f)   # re-read right before writing: REQ owns the other keys
    doc["tiers"] = table
    tmp = REQUEST_DEFAULTS + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    os.replace(tmp, REQUEST_DEFAULTS)
    print("wrote tiers into %s" % os.path.relpath(REQUEST_DEFAULTS, REPO))
    return table


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv[0] if argv else ""
    if cmd == "prepare":
        prepare(write="--check" not in argv)
    elif cmd == "run":
        backend, model = argv[1], argv[2]
        opt = lambda k, d=None: argv[argv.index(k) + 1] if k in argv else d  # noqa: E731
        run(backend, model, unanchored="--unanchored" in argv, tag=opt("--tag", ""), max_tokens=(int(opt("--max-tokens")) if opt("--max-tokens") else None),
            url=opt("--url"), only=(opt("--only").split(",") if opt("--only") else None), repeat=int(opt("--repeat", 1)))
    elif cmd == "score":
        score([a for a in argv[1:] if not a.startswith("--")] or None)
    elif cmd == "tiers":
        tiers(write="--write" in argv)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
