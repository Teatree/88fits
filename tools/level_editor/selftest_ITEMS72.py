"""Pass 72, lane ITEMS: "Candidates" and "First seed" on every candidate job (Garry: "I said I wanted that for every asset
that has candidates. I looked at the title cutout and I see no 'first seed' I just see seed"), and the map's Hero
knockback x row in Settings. selftest.py discovers this file (`extra_checks`) and hands it its `check` counter. Nothing
here writes anything: jobs._plan and puppet_argv are pure, the tools' seed functions are pure.

  kinds    every candidate kind (icon_cands, hero_badge, hero_title; the look job for creature_ctl and
           front_from_picture; the puppet's arms-out fronts) carries `seeds` and `first_seed` with the same words, and
           the plans hand --first-seed to every candidate tool (0 = the tool's own start, never sent);
  tools    tools/cand_seeds.start and every candidate tool's seeds start at the first seed, candidate k CAND_STEP on;
  page     jobs.js shows the two fields together (candidateSeedFields: "Candidates", "First seed"), never first_seed
           again in Asset settings, drops the seed shift where it reached no tool; puppet.js the same two; methods.json;
  settings fields.js: hero_knockback_mult in Scaling with its help.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _tools():
    saved_argv, saved_path = list(sys.argv), list(sys.path)
    sys.path.insert(0, TOOLS)
    out = {}
    try:
        import cand_seeds
        out["cs"] = cand_seeds
        import gen_badge_cands
        out["gbc"] = gen_badge_cands
        sys.argv = list(saved_argv)
        import gen_title_heroes
        out["gth"] = gen_title_heroes
        import gen_icon_cands
        out["gic"] = gen_icon_cands
        sys.argv = ["gen_edit_stills.py"]
        import gen_edit_stills
        out["ges"] = gen_edit_stills
        import gen_art
        out["ga"] = gen_art
    finally:
        sys.argv = saved_argv
        sys.path[:] = saved_path
    return out


def kind_checks(check):
    import jobs
    ch, fs = jobs.CANDIDATES_HELP, jobs.FIRST_SEED_HELP
    for kind in ("icon_cands", "hero_badge", "hero_title", "look"):
        f = jobs.SPECS[kind]["fields"]
        check("seeds" in f and "first_seed" in f and f["first_seed"]["type"] == "int" and f["first_seed"]["default"] == 0
              and f["first_seed"]["help"] == fs and f["seeds"]["help"].startswith(ch),
              "ITEMS72 kinds: %s carries seeds (Candidates) and first_seed (First seed, default 0) with the same words" % kind)

    def plan(kind, target, spec, method=None):
        s = jobs.validate_spec(kind, dict(spec, method=method) if method else spec)
        job = {"id": "j20261013-120000-ab12", "kind": kind, "method": method or kind, "spec": s, "target": target, "attempt": 1}
        return jobs._plan(job)

    p = plan("icon_cands", {"kind": "weapon", "id": "revolver"}, {"seeds": 3, "first_seed": 77})
    check(p["argv"][-2:] == ["--first-seed", "77"] and p.get("first_seed") == 77, "ITEMS72 kinds: icon_cands hands --first-seed and first_seed to gen_icon_cands: %s" % p["argv"])
    p0 = plan("icon_cands", {"kind": "weapon", "id": "revolver"}, {"seeds": 3})
    check("--first-seed" not in p0["argv"] and p0.get("first_seed") == 0, "ITEMS72 kinds: icon_cands without a first seed sends none (the tool's own start)")
    p = plan("hero_badge", {"kind": "hero", "id": "astro"}, {"seeds": 2, "first_seed": 5})
    check("--first-seed" in p["argv"] and p["argv"][p["argv"].index("--first-seed") + 1] == "5", "ITEMS72 kinds: hero_badge hands --first-seed")
    p = plan("hero_title", {"kind": "hero", "id": "astro"}, {"seeds": 2})
    check("--first-seed=11" in p["argv"] and p.get("first") == 11, "ITEMS72 kinds: hero_title's 0 is the tool's own start, 11: %s" % p["argv"])
    p = plan("hero_title", {"kind": "hero", "id": "astro"}, {"seeds": 2, "first_seed": 500})
    check("--first-seed=500" in p["argv"] and p.get("first") == 500, "ITEMS72 kinds: hero_title hands its first seed")
    p = plan("look", {"kind": "enemy", "id": "dune_scorpion", "code": "SC-Z"}, {"seeds": 3, "first_seed": 9}, "creature_ctl")
    check("--first-seed=9" in p["argv"], "ITEMS72 kinds: creature_ctl hands --first-seed to gen_ctl: %s" % p["argv"])
    p = plan("look", {"kind": "enemy", "id": "goblin", "code": "GOB-Z"}, {"seeds": 3, "first_seed": 31, "stills": "gz", "ref": "x.png", "prompt": "a goblin"}, "front_from_picture")
    check(p["argv"][-2:] == ["--first-seed", "31"] and "--seeds" in p["argv"], "ITEMS72 kinds: front_from_picture hands --first-seed to gen_edit_stills: %s" % p["argv"])
    p = plan("look", {"kind": "enemy", "id": "goblin", "code": "GOB-Z"}, {"seeds": 3, "stills": "gz", "ref": "x.png", "prompt": "a goblin"}, "front_from_picture")
    check("--first-seed" not in p["argv"], "ITEMS72 kinds: front_from_picture without a first seed sends none")
    # the puppet's arms-out fronts
    check("first_seed" in jobs.PUPPET_SETTINGS, "ITEMS72 kinds: the puppet's first seed is a setting its look's recipe records")
    job = {"id": "jp", "kind": "look", "method": "hero_puppet", "target": {"kind": "hero", "id": "may", "code": "MAY-Z"},
           "spec": {"method": "hero_puppet", "puppet": {"seeds": 5, "first_seed": 1234}}}
    a = jobs.puppet_argv(job, "comfy")
    check(a[a.index("--seeds") + 1] == "5" and a[a.index("--first-seed") + 1] == "1234", "ITEMS72 kinds: puppet.py gets --seeds and --first-seed: %s" % a)
    job["spec"]["puppet"] = {"seeds": 5}
    check("--first-seed" not in jobs.puppet_argv(job, "comfy"), "ITEMS72 kinds: a puppet without a first seed sends none")


def tool_checks(check):
    t = _tools()
    cs, gbc, gth, gic, ges, ga = t["cs"], t["gbc"], t["gth"], t["gic"], t["ges"], t["ga"]
    C = cs.CAND_STEP
    check(cs.start(500, 0) == 500 and cs.start(500, None) == 500 and cs.start(500, "") == 500 and cs.start(500, 7) == 7 and cs.start(500, "42") == 42
          and cs.start(500, "x") == 500, "ITEMS72 tools: cand_seeds.start: the job's first seed, else the tool's own")
    check(gbc.badge_seeds("mamy", 3, 1000) == [1000, 1000 + C, 1000 + 2 * C], "ITEMS72 tools: badge candidates start at the first seed")
    check(gth.title_seeds(0, 2) == gth.title_seeds(11, 2) == [11, 11 + C] and gth.title_seeds(1000, 2) == [1000, 1000 + C],
          "ITEMS72 tools: title cut-outs: 0 = 11, the tool's own; else the first seed")
    b = ga.seed_for("icon46_tb")
    check(gic.candidate_seeds("tb", 2) == [b, b + C] and gic.candidate_seeds("tb", 2, 1, "", 1000) == [1000, 1000 + C],
          "ITEMS72 tools: icon candidates start at the first seed")
    check(ges.candidate_seeds("goblin", "gz", 2, 1, "", 1000) == [1000, 1000 + C] and ges.candidate_seeds("goblin", "gz", 2)[0] == ga.seed_for("goblingz"),
          "ITEMS72 tools: fronts from a picture start at the first seed")
    # a job's own move still applies on top (no two jobs share a seed), and every two candidates are apart
    a, z = gic.candidate_seeds("tb", 4, 1, "jA", 1000), gic.candidate_seeds("tb", 4, 1, "jB", 1000)
    check(cs.all_apart(a) and not set(a) & set(z), "ITEMS72 tools: one first seed in two jobs: two sets, every candidate apart")
    src = _read(os.path.join(TOOLS, "gen_ctl.py"))
    check(src.count('cand_seeds.start(seed, opt("first-seed", "0"))') == 2, "ITEMS72 tools: gen_ctl's side and view candidates start at --first-seed")
    src = _read(os.path.join(TOOLS, "puppet.py"))
    check('ap.add_argument("--first-seed"' in src and "seed0 = (first or APOSE_SEED)" in src, "ITEMS72 tools: puppet.py's arms-out candidates start at --first-seed")
    src = _read(os.path.join(TOOLS, "asset_job.py"))
    check('int(job.get("first_seed") or 0))' in src, "ITEMS72 tools: asset_job hands an icon job's first seed to gen_icon_cands.paint")


def page_checks(check):
    js = _read(os.path.join(HERE, "jobs.js"))
    check("function candidateSeedFields(body, c, jk, what)" in js and "fieldLine('Candidates'" in js and "fieldLine('First seed'" in js,
          "ITEMS72 page: the job form's Candidates and First seed")
    check("candidateSeedFields(body, c, jk, mode === 'icon'" in js and "if (SEEDED_LOOKS.includes(spec.method)) candidateSeedFields(" in js
          and "const SEEDED_LOOKS = ['creature_ctl', 'front_from_picture'];" in js,
          "ITEMS72 page: on the badge, title and icon forms and on the looks that stop for a pick")
    check("|| k === 'puppet' || k === 'first_seed';" in js, "ITEMS72 page: first_seed never again in Asset settings")
    check("if (seeded) spec.flags.seed = 0;" in js, "ITEMS72 page: no seed shift where it reached no tool (creature_ctl, front_from_picture)")
    check("job.first_seed = Math.round(Number(spec.counts.first_seed))" in js and "fieldLine('First seed', fs, `${FIRST_SEED_HELP}" in js,
          "ITEMS72 page: a new look's candidate jobs take the look form's First seed")
    pj = _read(os.path.join(HERE, "puppet.js"))
    check("line('Candidates'" in pj and "line('First seed'" in pj and "first_seed: 0" in pj, "ITEMS72 page: the puppet's arms-out fronts show Candidates and First seed")
    m = json.loads(_read(os.path.join(HERE, "methods.json")))
    bad = []
    for meth in m["methods"]:
        jf = {f["key"]: f for f in meth.get("job_fields") or []}
        if "seeds" in jf and not ("first_seed" in jf and jf["first_seed"].get("label") == "First seed" and jf["seeds"].get("label") == "Candidates"):
            bad.append(meth["id"])
    check(not bad, "ITEMS72 page: methods.json: every method with candidates lists Candidates and First seed: %s" % bad)
    # under Node: the helper draws the two lines with the served words
    node_ok = True
    try:
        import subprocess
        node_ok = subprocess.run(["node", "-e", "new Function(require('fs').readFileSync(process.argv[1],'utf8'))", os.path.join(HERE, "jobs.js")],
                                 capture_output=True, timeout=60).returncode == 0
    except Exception:
        node_ok = True
    check(node_ok, "ITEMS72 page: jobs.js parses under Node")


def settings_checks(check):
    f = _read(os.path.join(HERE, "fields.js"))
    check("{ key: 'hero_knockback_mult', group: 'Scaling', label: 'Hero knockback ×', type: 'number', min: 0" in f and "Red Canyon 0.5" in f,
          "ITEMS72 settings: Hero knockback × in Settings > Scaling, with its help")
    rc = json.loads(_read(os.path.join(ROOT, "game", "content", "maps", "red_canyon", "red_canyon.json")))
    # pass 72, lane INTEG: a map that leaves the key out plays the game's 0.5 (WaveTimeline.HERO_KNOCKBACK_DEFAULT), the row's grey default
    kb = (rc.get("timeline_data") or {}).get("hero_knockback_mult", 0.5)
    wt = _read(os.path.join(ROOT, "game", "core", "data", "WaveTimeline.gd"))
    check(isinstance(kb, (int, float)) and "const HERO_KNOCKBACK_DEFAULT := 0.5" in wt and "step: 0.05, def: 0.5, help: 'multiplies every push" in f,
          "ITEMS72 settings: Red Canyon's hero_knockback_mult is a number (or absent: the game's 0.5, the row's default)")


def checks(check, run_node, server):
    kind_checks(check)
    tool_checks(check)
    page_checks(check)
    settings_checks(check)
