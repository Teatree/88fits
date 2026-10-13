"""Pass 70, lane LE: the Level Editor's seven points, checked. selftest.py discovers this file (`extra_checks`) and hands
it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing here writes under game/ or
the real queue: the server's operations run on a temp tree (selftest_S's Pointed), jobs.py on a temp queue and temp
locks, the tools on temp paintings folders.

Groups:
  seeds    tools/cand_seeds.py and every candidate tool (gen_badge_cands, gen_title_heroes, gen_icon_cands, gen_edit_stills,
           gen_ctl's side and view candidates): candidate k a prime past a million from k-1, a job's seeds its own (two
           jobs of one look never share one), a re-run moves them, a hand run keeps base + k * CAND_STEP; gen_edit_stills
           moves its earlier candidates aside before it paints;
  bandit   the Stills slug rule everywhere (vocab, AssetsModel under Node, jobs.validate_spec and requeue, the server's
           recipe op, add_look and Save, gen_edit_stills.check_slug) and comfy.upload_name (a path never reaches ComfyUI);
  base     removing the base look: the server's remove_base on a creature and a hero (the choices, the refusals, the
           top-level art keys rewritten, the other looks' inherited keys pinned, the files and base_<CODE>.json in
           backups/deleted), merge_look mirroring a landing on such a base, set_look_files its icon; May's real JSON
           (MAY-A gone, MAY-G the base, its files on disk);
  picker   jobs.install into any look (options.variant: the target, the plan's argv for a badge, a cut-out named by its
           file, an icon's look), hero records' icon_play (the look he is played in), the page's hooks;
  inherit  the inherited values in their boxes (Forms.inheritable, the recipe editor, the job form, the typed params);
  docs     the Instructions tab's "Pass 70" section, docs/level_editor.md "Pass 70", docs/assets_schema.md, keys_LE.md.
"""
import json
import os
import re
import shutil
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")


def _read(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _jdump(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=2)


def _jload(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _touch(path, data=b"png"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _import_tools():
    """The candidate tools, imported here with sys.argv and sys.path kept (they rewrite sys.argv for gen_art)."""
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
        import comfy
        out["comfy"] = comfy
        import gen_art
        out["ga"] = gen_art
    finally:
        sys.argv = saved_argv
        sys.path[:] = saved_path
    return out


# ---------------------------------------------------------------- 1. distinct seeds per candidate

def seed_checks(check):
    t = _import_tools()
    cs, gbc, gth, gic, ges, ga = t["cs"], t["gbc"], t["gth"], t["gic"], t["ges"], t["ga"]
    C = cs.CAND_STEP
    check(C > 1000000 and all(C % p for p in range(2, 1001)) and cs.JOB_STEP > C, "LE70 seeds: CAND_STEP a prime past a million (%d), JOB_STEP past it" % C)
    check(cs.job_salt("") == 0 and cs.job_salt(None) == 0 and cs.job_salt("x") == 0 and cs.job_salt("j20261012-234602-b9ac") > 0
          and cs.job_salt("j20261012-234602-b9ac") != cs.job_salt("j20261012-235324-aca1"), "LE70 seeds: a hand run has no move, two jobs move differently")
    check(cs.seeds(100, 3) == [100, 100 + C, 100 + 2 * C] and cs.all_apart(cs.seeds(100, 6, "jx")), "LE70 seeds: base + k * CAND_STEP, every two apart")
    # the cause Garry saw: two badge jobs for MAY-E painted 2768, 3768, 4768 twice (j..b9ac and j..aca1)
    a = gbc.badge_seeds("may", 3, 0, 0, 1, "j20261012-234602-b9ac")
    b = gbc.badge_seeds("may", 3, 0, 0, 1, "j20261012-235324-aca1")
    check(cs.all_apart(a) and cs.all_apart(b) and not set(a) & set(b), "LE70 seeds: badge: two jobs of one look on seeds of their own, a million apart: %s / %s" % (a, b))
    check(not set(gbc.badge_seeds("may", 3, 0, 0, 2, "j1")) & set(gbc.badge_seeds("may", 3, 0, 0, 1, "j1")), "LE70 seeds: badge: a re-run (attempt 2) on new seeds")
    a = gth.title_seeds(11, 4, 0, 1, "j20261012-234612-bb01")
    b = gth.title_seeds(11, 4, 0, 1, "j20261012-173701-649d")
    check(cs.all_apart(a) and not set(a) & set(b) and a[0] != 11, "LE70 seeds: title: no more 11, 112, 213, 314 for every job: %s" % a)
    check(gth.title_seeds(11, 2, 0, 1) == [11, 11 + C], "LE70 seeds: title by hand: first + k * CAND_STEP")
    a = gic.candidate_seeds("tb", 4, 1, "jA")
    b = gic.candidate_seeds("tb", 4, 1, "jB")
    check(cs.all_apart(a) and not set(a) & set(b) and not set(gic.candidate_seeds("tb", 4, 2, "jA")) & set(a), "LE70 seeds: icons: per job, per re-run")
    a = ges.candidate_seeds("buckshot_dwarf", "bda", 3, 1, "j20261013-004315-6a12")
    b = ges.candidate_seeds("buckshot_dwarf", "bda", 3, 2, "j20261013-004315-6a12")
    c = ges.candidate_seeds("buckshot_dwarf", "bda", 3, 1, "j20261013-001220-f286")
    check(cs.all_apart(a) and not set(a) & set(b) and not set(a) & set(c), "LE70 seeds: fronts from a picture: per job, per re-run (they were seed_for(id + slug) + 1000 k always)")
    os.environ.pop("ASSET_JOB_ATTEMPT", None)
    check(cs.job_attempt() == 1 and cs.job_attempt("3") == 3 and cs.job_attempt("x") == 1, "LE70 seeds: job_attempt: given, else ASSET_JOB_ATTEMPT, else 1")
    os.environ["ASSET_JOB_ATTEMPT"] = "4"
    try:
        check(cs.job_attempt() == 4, "LE70 seeds: job_attempt reads ASSET_JOB_ATTEMPT (asset_job.py sets it from job.json)")
    finally:
        os.environ.pop("ASSET_JOB_ATTEMPT", None)
    src_aj = _read(os.path.join(TOOLS, "asset_job.py"))
    check('os.environ.setdefault("ASSET_JOB_ATTEMPT"' in src_aj, "LE70 seeds: asset_job.py hands the job's attempt to the tools")
    src_ctl = _read(os.path.join(TOOLS, "gen_ctl.py"))
    check("side_seeds = cand_seeds.seeds(" in src_ctl and "s = side_seeds[k]" in src_ctl and "vseeds = cand_seeds.seeds(" in src_ctl and "seed + 1000 * k" not in src_ctl,
          "LE70 seeds: gen_ctl's side and view candidates on the job's own seeds")
    for name in ("gen_badge_cands", "gen_title_heroes", "gen_icon_cands", "gen_edit_stills"):
        src = _read(os.path.join(TOOLS, name + ".py"))
        check("import cand_seeds" in src and "cand_seeds.seeds(" in src, "LE70 seeds: %s takes its candidates' seeds from cand_seeds" % name)
    # gen_edit_stills: a run paints new candidates (the earlier ones moved aside, never handed back from the cache)
    tmp = tempfile.mkdtemp(prefix="le70_raw_")
    saved_raw = ga.RAW
    try:
        ga.RAW = tmp
        for n in ("bd_bda_front_c0.png", "bd_bda_front_c0.json", "bd_bda_front_c1.png", "bd_bda_front.png", "bd_bdax_front_c0.png"):
            _touch(os.path.join(tmp, n))
        moved = ges.retire("bd_bda_front", "STAMP")
        names = sorted(os.listdir(tmp))
        check(sorted(os.path.basename(m) for m in moved) == ["bd_bda_front_c0_oldSTAMP.json", "bd_bda_front_c0_oldSTAMP.png", "bd_bda_front_c1_oldSTAMP.png"]
              and "bd_bda_front.png" in names and "bd_bdax_front_c0.png" in names and "bd_bda_front_c0.png" not in names,
              "LE70 seeds: gen_edit_stills.retire moves only this slug's candidates aside: %s" % names)
    finally:
        ga.RAW = saved_raw
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 3. the Bandit check

BAD = ["tools/dl/uploads/2d/bandit.png", "bandit.png", "a b", "bdb/x", "..", "x" * 41, "bdb\\x"]
GOOD = ["bdb", "bda", "g", "wwa", "s55", "BD_A2", ""]


def bandit_checks(check, run_node, server):
    import vocab
    import jobs
    t = _import_tools()
    ges, comfy = t["ges"], t["comfy"]
    check(all(vocab.stills_problem(v) for v in BAD) and not any(vocab.stills_problem(v) for v in GOOD) and vocab.stills_problem(None) is None,
          "LE70 bandit: vocab.stills_problem refuses a path, a file name, spaces; a slug or empty passes")
    check(vocab.STILLS_HELP.startswith("Stills is a short name for this look's paintings, like bdb; the picture goes in Reference"),
          "LE70 bandit: the plain words: %s" % vocab.STILLS_HELP)
    check(vocab.STILLS_RE.pattern == ges.SLUG_RE.pattern.replace("{1,40}", "{0,40}") and ges.STILLS_HELP == vocab.STILLS_HELP,
          "LE70 bandit: gen_edit_stills.SLUG_RE is the editor's rule (non-empty)")
    for v in BAD + ["", None]:
        try:
            ges.check_slug(v)
            ok = False
        except SystemExit as e:
            ok = "Stills is a short name" in str(e)
        check(ok, "LE70 bandit: gen_edit_stills refuses --stills %r with the words" % (v,))
    try:
        ges.check_slug("bdb")
        check(True, "LE70 bandit: gen_edit_stills takes a slug")
    except SystemExit as e:
        check(False, "LE70 bandit: gen_edit_stills refused a slug: %s" % e)
    d = {"stills": "ok", "variants": {"BD-A": {"recipe": {"stills": "tools/dl/uploads/2d/bandit.png"}}, "BD-0": {"note": "base"}, "BD-B": {"recipe": {"stills": "bdb"}}}}
    check([w for w, m in vocab.bad_stills(d)] == ["variants.BD-A.recipe.stills"], "LE70 bandit: bad_stills names the look: %s" % vocab.bad_stills(d))
    # comfy.upload_name: a path can never reach ComfyUI as a 500 again
    cases = {"buckshot_dwarf_tools/dl/uploads/2d/bandit.png_ref.png": "buckshot_dwarf_tools_dl_uploads_2d_bandit.png_ref.png",
             "style_anchor.png": "style_anchor.png", "title_ref_may.png": "title_ref_may.png", "a b c.png": "a_b_c.png",
             "..\\x\\y.png": "x_y.png", "weird": "weird.png", "": "upload.png", "88fits/../../etc.png": "88fits_etc.png"}
    got = {k: comfy.upload_name(k) for k in cases}
    check(got == cases, "LE70 bandit: comfy.upload_name: %s" % {k: v for k, v in got.items() if cases[k] != v})
    check(all("/" not in comfy.upload_name(x) and "\\" not in comfy.upload_name(x) and len(comfy.upload_name(x)) <= 120 for x in BAD + ["a/" * 200 + "b.png"]),
          "LE70 bandit: upload names never hold a path, at most 120 characters")
    src = _read(os.path.join(TOOLS, "comfy.py"))
    check("    name = upload_name(name)\n    ensure_lock()" in src, "LE70 bandit: comfy.upload applies upload_name to every upload")
    # jobs.validate_spec and requeue
    for v, ok in (("bdb", True), ("tools/dl/uploads/2d/bandit.png", False), ("a b", False)):
        try:
            jobs.validate_spec("look", {"method": "front_from_picture", "stills": v, "ref": "tools/dl/uploads/2d/bandit.png", "prompt": "a bandit"})
            got = True
        except ValueError as e:
            got = "Stills is a short name" in str(e) and False
        check(got == ok, "LE70 bandit: validate_spec %s stills %r" % ("takes" if ok else "refuses", v))
    try:
        jobs.validate_spec("look", {"method": "creature_free2", "recipe": {"stills": "x/y.png"}})
        check(False, "LE70 bandit: validate_spec refuses a recipe.stills path")
    except ValueError as e:
        check("recipe.stills" in str(e) and "Reference" in str(e), "LE70 bandit: validate_spec refuses a recipe.stills path: %s" % e)
    check('prob = _VOCAB.stills_problem(spec.get("stills") or None)' in _read(os.path.join(HERE, "jobs.py")), "LE70 bandit: requeue refuses a job queued with a path in Stills")
    # the page's rule under Node: AssetsModel.stillsProblem and the error rule agree with vocab.py
    runner = r"""
const path = require('path');
const dir = path.dirname(process.argv[2]);
const M = require(path.join(dir, 'assets_model.js'));
global.AssetsModel = M;
const F = require(path.join(dir, 'assets_fields.js'));
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.problems = q.values.map((v) => M.stillsProblem(v));
  out.bad = M.badStills(q.doc);
  const lists = { heroes: [], items: { weapons: [], evolutions: [], mutations: [], passives: [], quests: [] }, enemies: [] };
  out.enemyErr = M.issues('enemy', Object.assign({ id: 'bd', name: 'Bd', doc: 'x', knockback: 2 }, q.doc), { rules: F.RULES, id: 'bd', kind: 'enemy', lists }).errors.map((e) => e.key + ': ' + e.msg);
  out.heroErr = M.issues('hero', Object.assign({ id: 'hh', name: 'Hh' }, q.doc), { rules: F.RULES, id: 'hh', kind: 'hero', lists }).errors.map((e) => e.key + ': ' + e.msg);
  out.help = M.STILLS_HELP;
  process.stdout.write(JSON.stringify(out));
});
"""
    q = {"values": BAD + GOOD + [None], "doc": d}
    res = run_node(q, runner)
    if res is None:
        check(True, "LE70 bandit: Node not found: the page's rule unchecked")
    else:
        py = [bool(vocab.stills_problem(v)) for v in BAD + GOOD + [None]]
        check([bool(x) for x in res["problems"]] == py and res["help"] == vocab.STILLS_HELP, "LE70 bandit: AssetsModel.stillsProblem is vocab.stills_problem")
        check([b[0] for b in res["bad"]] == ["variants.BD-A.recipe.stills"], "LE70 bandit: AssetsModel.badStills names the look")
        check(any(e.startswith("looks: BD-A stills: Stills is a short name") for e in res["enemyErr"]) and any(e.startswith("looks: BD-A stills") for e in res["heroErr"]),
              "LE70 bandit: an error rule (blocks Save) on an enemy and a hero: %s" % res["enemyErr"])
    # the server: the recipe op, add_look and Save refuse it; a bad value already on disk is not a reason to refuse a Save
    import selftest_S as S
    tmp = tempfile.mkdtemp(prefix="le70_bandit_")
    try:
        content = os.path.join(tmp, "content")
        _jdump(os.path.join(content, "enemies", "bd", "bd.json"), {"id": "bd", "name": "Bd", "doc": "x", "knockback": 2, "variant_base": "BD-0",
                                                                    "variants": {"BD-0": {"note": "base"}, "BD-A": {"recipe": {"stills": "bda"}}}})
        with S.Pointed(server, content, S.FakeJobs()):
            r = server.look_op("enemy", "bd", ["BD-A"], "recipe", {"recipe": {"stills": "tools/dl/uploads/2d/bandit.png"}})
            check(r.get("status") == 400 and "Stills is a short name" in r.get("error", "") and _jload(os.path.join(content, "enemies", "bd", "bd.json"))["variants"]["BD-A"]["recipe"]["stills"] == "bda",
                  "LE70 bandit: the recipe op refuses a picture's path in Stills, the file untouched: %s" % r.get("error"))
            r = server.look_op("enemy", "bd", ["BD-A"], "recipe", {"recipe": {"stills": "bdb"}})
            check(r.get("ok") and _jload(os.path.join(content, "enemies", "bd", "bd.json"))["variants"]["BD-A"]["recipe"]["stills"] == "bdb", "LE70 bandit: a slug is written")
            r = server.add_look("enemy", "bd", None, "x", {"stills": "a/b.png"})
            check(r.get("status") == 400 and "Stills" in r.get("error", ""), "LE70 bandit: add_look refuses it")
            obj = _jload(os.path.join(content, "enemies", "bd", "bd.json"))
            obj["variants"]["BD-A"]["recipe"]["stills"] = "tools/dl/uploads/2d/bandit.png"
            r = server.write_content("enemy", "bd", obj)
            check(r.get("status") == 400 and "Stills is a short name" in r.get("error", ""), "LE70 bandit: Save refuses a new path in Stills: %s" % r.get("error"))
            # a bad value already on disk (written by hand): Save of another key goes through
            p = os.path.join(content, "enemies", "bd", "bd.json")
            raw = _jload(p)
            raw["variants"]["BD-A"]["recipe"]["stills"] = "old/path.png"
            _jdump(p, raw)
            obj = _jload(p)
            obj["name"] = "Bd 2"
            r = server.write_content("enemy", "bd", obj)
            check(r.get("ok"), "LE70 bandit: a bad Stills already on disk does not block a Save of another key (the page's rule points at it): %s" % r.get("error"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- 4. removing the base look

def _tree(content):
    """A creature whose base strip has looks that inherit its anims, a hero whose base is a placeholder (May's case)."""
    cf = os.path.join(content, "enemies", "tbx")
    _jdump(os.path.join(cf, "tbx.json"), {
        "id": "tbx", "name": "Tbx", "doc": "x", "knockback": 2.0, "frame_px": 128, "anims": {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1},
        "fps": {"run": 10}, "head": 0.8, "variant_base": "TX-0", "variant": "TX-A",
        "variants": {"TX-0": {"note": "base"},
                     "TX-A": {"sprite": "tbx_sprite_a.png", "icon": "tbx_icon_a.png", "anims": {"idle": 4, "run": 8, "attack": 2, "hit": 1, "die": 3}, "strip_cols": 12, "fps": {"run": 14}, "head": 0.9, "recipe": {"stills": "a"}},
                     "TX-B": {"sprite": "tbx_sprite_b.png"},
                     "TX-C": {"note": "a draft", "recipe": {"from": "TX-A"}}}})
    for f in ("tbx_sprite.png", "tbx_icon.png", "tbx_sprite_a.png", "tbx_icon_a.png", "tbx_sprite_b.png", "tbx_sprite.png.import", "tbx_ai.json"):
        _touch(os.path.join(cf, f))
    hf = os.path.join(content, "characters", "hh")
    _jdump(os.path.join(hf, "hh.json"), {
        "id": "hh", "name": "Hh", "frame_px": 256, "variant_base": "HH-A", "variant": "HH-G",
        "variants": {"HH-A": {"note": "the top-level strip, before the Level Editor's looks"},
                     "HH-B": {"sprite": "hh_sprite_b.png", "anims": {"idle": 4, "run": 24}, "strip_cols": 62, "fps": {"run": 36}},
                     "HH-G": {"sprite": "hh_sprite_g.png", "anims": {"idle": 4, "run": 24, "cheer": 1}, "strip_cols": 62, "fps": {"run": 36, "hit": 12},
                              "icon": "hh_icon_g.png", "icon_picked": True, "title": "hero_hh_g.png", "recipe": {"stills": "g", "method": "hero_pose5"}}}})
    for f in ("hh_sprite.png", "hh_icon.png", "hh_icon.png.import", "hh_sprite_b.png", "hh_sprite_g.png", "hh_icon_g.png"):
        _touch(os.path.join(hf, f))
    _jdump(os.path.join(content, "maps", "mapx", "mapx.json"), {"id": "mapx", "timeline_data": {"roster": []}})


def base_checks(check, server):
    import selftest_S as S
    tmp = tempfile.mkdtemp(prefix="le70_base_")
    try:
        content = os.path.join(tmp, "content")
        _tree(content)
        cp = os.path.join(content, "enemies", "tbx", "tbx.json")
        hp = os.path.join(content, "characters", "hh", "hh.json")
        with S.Pointed(server, content, S.FakeJobs()):
            r = server.look_op("enemy", "tbx", ["TX-0"], "remove", {})
            check(r.get("status") == 409 and r.get("choices") == ["TX-A", "TX-B"] and r.get("suggest") == "TX-A",
                  "LE70 base: no new_base: 409 with the choices (the look in play first, no draft): %s" % r)
            r = server.look_op("enemy", "tbx", ["TX-0", "TX-B"], "remove", {"new_base": "TX-A"})
            check(r.get("status") == 409 and "on its own" in r.get("error", ""), "LE70 base: the base in a bulk remove is refused")
            for nb, why in (("TX-C", "a draft"), ("TX-Z", "unknown"), ("TX-0", "the base itself")):
                r = server.look_op("enemy", "tbx", ["TX-0"], "remove", {"new_base": nb})
                check(r.get("status") == 400 and not r.get("ok"), "LE70 base: %s cannot become the base: %s" % (why, r.get("error")))
            r = server.look_op("enemy", "tbx", ["TX-A"], "remove", {})
            check(r.get("status") == 409 and "in play" in r.get("error", ""), "LE70 base: the look in play is still refused")
            check(_jload(cp)["variant_base"] == "TX-0", "LE70 base: the refusals wrote nothing")
            r = server.look_op("enemy", "tbx", ["TX-0"], "remove", {"new_base": "TX-A"})
            d = _jload(cp)
            check(r.get("ok") and d["variant_base"] == "TX-A" and "TX-0" not in d["variants"] and d["sprite"] == "tbx_sprite_a.png" and d["icon"] == "tbx_icon_a.png"
                  and d["anims"] == {"idle": 4, "run": 8, "attack": 2, "hit": 1, "die": 3} and d["strip_cols"] == 12 and d["fps"] == {"run": 14} and d["head"] == 0.9,
                  "LE70 base: the top-level art keys are the new base's (sprite, icon, anims, strip_cols, fps, head): %s" % {k: d.get(k) for k in server.BASE_ART_KEYS})
            check(d["variants"]["TX-A"].get("recipe") == {"stills": "a"} and d["variants"]["TX-A"].get("sprite") == "tbx_sprite_a.png",
                  "LE70 base: the new base keeps its entry whole (its recipe, its files)")
            check(d["variants"]["TX-B"].get("anims") == {"idle": 2, "run": 2, "attack": 2, "hit": 1, "die": 1} and d["variants"]["TX-B"].get("fps") == {"run": 10}
                  and d["variants"]["TX-B"].get("head") == 0.8 and r.get("pinned", {}).get("TX-B"),
                  "LE70 base: a look that inherited the old top-level anims, fps and head keeps them in its own entry: %s" % d["variants"]["TX-B"])
            check("frame_px" not in d["variants"]["TX-B"] and d["frame_px"] == 128, "LE70 base: a creature's cell stays the top level's")
            names = sorted(os.listdir(os.path.join(content, "enemies", "tbx")))
            moved = sorted(os.path.basename(m) for m in r.get("moved", []))
            check(moved == ["base_TX-0.json", "tbx_ai.json", "tbx_icon.png", "tbx_sprite.png", "tbx_sprite.png.import"] and "tbx_sprite.png" not in names
                  and "tbx_sprite_a.png" in names and "tbx_sprite_b.png" in names and all("deleted/tbx" in m for m in r.get("moved", [])),
                  "LE70 base: the old base's files nothing names any more (and its marker) moved to backups/deleted: %s" % moved)
            bj = [m for m in r.get("moved", []) if m.endswith("base_TX-0.json")]
            info = _jload(os.path.join(os.path.dirname(os.path.dirname(content)), bj[0])) if bj and os.path.isabs(bj[0]) is False and os.path.isfile(os.path.join(os.path.dirname(os.path.dirname(content)), bj[0])) else None
            if info is None and bj:
                full = bj[0] if os.path.isabs(bj[0]) else os.path.join(ROOT, bj[0])
                info = _jload(full) if os.path.isfile(full) else None
            check(info is not None and info.get("code") == "TX-0" and info.get("new_base") == "TX-A" and info.get("top", {}).get("head") == 0.8,
                  "LE70 base: base_<CODE>.json says what the old base was: %s" % info)
            recs = {x["code"]: x for x in server.look_records("enemy", "tbx", os.path.dirname(cp), d, cp)}
            check(recs["TX-A"]["base"] and recs["TX-A"]["default"] and recs["TX-A"]["sprite_file"] == "tbx_sprite_a.png" and not recs["TX-B"]["base"],
                  "LE70 base: the look records: TX-A is the base and in play, its own strip")
            check(os.path.basename(server.icon_path("enemy", "tbx", "") or "") == "tbx_icon_a.png", "LE70 base: the creature's own icon is the new base's")
            # a job landing on such a base mirrors its art to the top level
            r = server.HOOKS.merge_look("enemy", "tbx", "TX-A", {"sprite": "tbx_sprite_a.png", "icon": "tbx_icon_a.png", "anims": {"idle": 2, "run": 6, "attack": 2, "hit": 1, "die": 3}, "strip_cols": 10, "head": 0.85}, {})
            d = _jload(cp)
            check(r.get("ok") and d["anims"]["run"] == 6 and d["strip_cols"] == 10 and d["head"] == 0.85 and d["variants"]["TX-A"]["anims"]["run"] == 6 and "anims" in r.get("keys", []),
                  "LE70 base: a landing on the base look mirrors its art keys to the top level: %s" % r.get("keys"))
            r = server.HOOKS.merge_look("enemy", "tbx", "TX-B", {"sprite": "tbx_sprite_b.png", "anims": {"idle": 1, "run": 1, "attack": 1, "hit": 1, "die": 1}}, {})
            check(r.get("ok") and _jload(cp)["anims"]["run"] == 6 and r.get("keys") == ["variants"], "LE70 base: a landing on another look leaves the top level alone")
            _touch(os.path.join(content, "enemies", "tbx", "tbx_icon_a2.png"))
            r = server.HOOKS.set_look_files("enemy", "tbx", "TX-A", {"icon": "tbx_icon_a2.png"})
            check(r.get("ok") and _jload(cp)["icon"] == "tbx_icon_a2.png", "LE70 base: an icon picked for such a base is the top level's icon too")
            # the hero: May's case (the base a placeholder, the played look the new base)
            r = server.look_op("hero", "hh", ["HH-A"], "remove", {"new_base": "HH-G"})
            d = _jload(hp)
            check(r.get("ok") and d["variant_base"] == "HH-G" and d["variant"] == "HH-G" and d["sprite"] == "hh_sprite_g.png" and d["icon"] == "hh_icon_g.png"
                  and d["anims"] == {"idle": 4, "run": 24, "cheer": 1} and d["strip_cols"] == 62 and d["fps"] == {"run": 36, "hit": 12} and "HH-A" not in d["variants"],
                  "LE70 base: a hero's base removed, the played look its base: %s" % {k: d.get(k) for k in server.BASE_ART_KEYS})
            check(d["variants"]["HH-G"].get("title") == "hero_hh_g.png" and d["variants"]["HH-B"].get("anims") == {"idle": 4, "run": 24} and not r.get("pinned"),
                  "LE70 base: its cut-out stays its own; HH-B (anims of its own) needs no pin")
            names = sorted(os.listdir(os.path.join(content, "characters", "hh")))
            check("hh_sprite.png" not in names and "hh_icon.png" not in names and "hh_icon.png.import" not in names and "hh_icon_g.png" in names,
                  "LE70 base: the placeholder strip and icon moved to backups/deleted: %s" % names)
            rec = server.hero_record("hh", os.path.dirname(hp), d, hp)
            check(rec.get("icon_play", "").startswith("/icon/hero/hh/HH-G?v="), "LE70 picker: a hero record's icon_play is the played look's: %s" % rec.get("icon_play"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # May's real JSON (pass 70: MAY-A removed through this route, MAY-G her base)
    mp = os.path.join(CONTENT, "characters", "may", "may.json")
    if os.path.isfile(mp):
        d = _jload(mp)
        vs = d.get("variants") or {}
        base = str(d.get("variant_base", ""))
        folder = os.path.dirname(mp)
        check("MAY-A" not in vs and base.startswith("MAY-") and base in vs and os.path.isfile(os.path.join(folder, str(d.get("sprite", "may_sprite.png"))))
              and os.path.isfile(os.path.join(folder, str(d.get("icon", "may_icon.png")))),
              "LE70 base: May: MAY-A gone, her base %s a look of hers, its strip and icon on disk" % base)
        if base in vs and isinstance(vs[base], dict) and vs[base].get("sprite"):
            check(d.get("sprite") == vs[base].get("sprite") and d.get("icon", "") == vs[base].get("icon", d.get("icon", "")),
                  "LE70 base: May's top-level strip and icon are her base look's")
        rec = server.hero_record("may", folder, d, mp)
        play = str(d.get("variant", base))
        check(("/icon/hero/may/%s?v=" % play) in rec.get("icon_play", "") or rec.get("icon_play", "").startswith("/icon/hero/may?v="),
              "LE70 picker: May's list badge is the look she is played in (%s): %s" % (play, rec.get("icon_play")))


# ---------------------------------------------------------------- 2. the picker: install any candidate into any look

def picker_checks(check, server):
    import locks
    import jobs
    import selftest_S as S
    tmp = tempfile.mkdtemp(prefix="le70_pick_")
    saved = {k: getattr(jobs, k) for k in ("JOBS_DIR", "QUEUE_FILE", "RAW", "ANIM", "REVIEW", "LAUNCH_FILE", "DL", "TITLE_OUT", "WANTED")}
    saved_locks = {k: getattr(locks, k) for k in ("LOCK_DIR", "SAVE_DIR", "KEEP_DIR", "RESTORE_PENDING")}
    saved_state = (jobs._state, jobs._hooks, jobs._root, dict(jobs._lane_current))
    try:
        jobs.JOBS_DIR = os.path.join(tmp, "jobs")
        jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
        jobs.DL = os.path.join(tmp, "dl")
        jobs.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        jobs.ANIM = os.path.join(tmp, "dl", "ai_anim")
        jobs.REVIEW = os.path.join(tmp, "dl", "review")
        jobs.TITLE_OUT = os.path.join(tmp, "dl", "title_heroes")
        jobs.WANTED = os.path.join(tmp, "wanted")
        jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
        locks.LOCK_DIR = os.path.join(tmp, "locks")
        locks.SAVE_DIR = os.path.join(tmp, "save")
        locks.KEEP_DIR = os.path.join(tmp, "locks", "save_keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        for p in (jobs.RAW, jobs.ANIM, jobs.REVIEW, locks.SAVE_DIR, os.path.dirname(jobs.LAUNCH_FILE), jobs.JOBS_DIR):
            os.makedirs(p, exist_ok=True)
        content = os.path.join(tmp, "content")
        _tree(content)
        with S.Pointed(server, content, S.FakeJobs()):
            jobs._state = {"rev": 0, "jobs": []}
            jobs._workers.clear()
            jobs.init(server.HOOKS, ROOT)
            done = lambda jid, kind, code, choices, extra=None: dict({"id": jid, "kind": kind, "state": "done", "method": kind, "title": jid, "target": {"kind": "hero", "id": "hh", "code": code},
                                                                       "spec": {"variant": code}, "choices": choices, "attempt": 1, "phase": 1, "created": "2026-10-13T00:00:00"}, **(extra or {}))
            jobs._state["jobs"] += [
                done("j20261012-173701-d4ad", "hero_badge", "HH-G", [{"id": "0", "label": "c0", "url": "/dl/ai_raw_anime/hh_portrait_d4ad_c0.png"}]),
                done("j20261012-173701-649d", "hero_title", "HH-G", [{"id": "2", "label": "#2", "url": "/dl/title_heroes/hh_g_649d_2.png"}]),
                dict(done("j20261012-000000-icon", "icon_cands", "TX-A", [{"id": "1", "label": "c1", "url": "/dl/icons_le_x/tbx_c1.png"}]),
                     target={"kind": "enemy", "id": "tbx", "code": "TX-A"}, plan={"key": "tbx", "icon_job": {"kind": "enemies", "id": "tbx", "subject": "x", "set": "_le_x", "variant": "TX-A"}}),
            ]
            # a badge painted for HH-G installed as HH-B's
            res = jobs.install("j20261012-173701-d4ad", "0", {"variant": "HH-B"})
            argv = res["plan"]["argv"] if isinstance(res.get("plan"), dict) else []
            check(res["kind"] == "install" and res["target"].get("code") == "HH-B" and res["spec"].get("variant") == "HH-B"
                  and argv[argv.index("--variant") + 1] == "HH-B" and argv[argv.index("--tag") + 1] == "j20261012-173701-d4ad" and "--pick" in argv,
                  "LE70 picker: a badge of HH-G's job installed as HH-B's: target, --variant HH-B, the painting job's tag: %s" % argv)
            res = jobs.install("j20261012-173701-d4ad", "0", {"variant": ""})
            argv = res["plan"]["argv"]
            check(res["target"].get("code") == "" and "--variant" not in argv, "LE70 picker: installed as the hero's own (the base look's top-level files): %s" % argv)
            res = jobs.install("j20261012-173701-d4ad", "0", {"variant": "HH-A"})
            check("--variant" not in res["plan"]["argv"], "LE70 picker: the base look's code is the hero's own")
            # a cut-out of HH-G's job installed as HH-B's: named by its file (its stem is HH-G's)
            res = jobs.install("j20261012-173701-649d", "2", {"variant": "HH-B"})
            argv = res["plan"]["argv"]
            check(argv[:2] == ["--pick", "hh=hh_g_649d_2.png"] and argv[argv.index("--variant") + 1] == "HH-B", "LE70 picker: a cut-out installed into another look is named by its file: %s" % argv)
            # an icon of TX-A's job installed as TX-B's, then as the creature's own
            res = jobs.install("j20261012-000000-icon", "1", {"variant": "TX-B"})
            check(res["plan"].get("icon_job", {}).get("variant") == "TX-B", "LE70 picker: an icon installed into another look of the creature: %s" % res["plan"].get("icon_job"))
            res = jobs.install("j20261012-000000-icon", "1", {"variant": ""})
            check("variant" not in res["plan"].get("icon_job", {}), "LE70 picker: an icon installed as the creature's own")
            try:
                jobs.install("j20261012-173701-d4ad", "0", {"variant": "HH-Z"})
                check(False, "LE70 picker: an unknown look is refused")
            except ValueError as e:
                check("no look HH-Z" in str(e), "LE70 picker: an unknown look is refused: %s" % e)
            res = jobs.install("j20261012-173701-d4ad", "0")
            check(res["target"].get("code") == "HH-G" and "variant" not in res["spec"], "LE70 picker: without a look the pick goes where its job was for (pass 68)")
            # the one-view walk: only that view's clip moved aside, the anim seed moved on
            keys = jobs.cache_keys("hero_pose5", {"recipe": {"stills": "g"}}, {"kind": "hero", "id": "hh", "code": "HH-G"}, {})["clips"]
            for k in keys:
                _touch(os.path.join(jobs.ANIM, k, "out_00.png"))
            side = [k for k in keys if jobs.clip_view(k) == "side"]
            res = jobs.enqueue("look", {"kind": "hero", "id": "hh", "code": "HH-G"}, {"method": "hero_pose5", "recipe": {"stills": "g", "method": "hero_pose5"},
                                                                                     "reroll": {"mode": "clip", "view": "side"}})
            left = sorted(os.listdir(jobs.ANIM))
            check(len(side) == 1 and not os.path.isdir(os.path.join(jobs.ANIM, side[0])) and all(os.path.isdir(os.path.join(jobs.ANIM, k)) for k in keys if k not in side)
                  and any(n.startswith(side[0] + "_old") for n in left) and res["spec"]["recipe"].get("anim_seed") == 1,
                  "LE70 reroll: one view's walk: only %s moved aside, the others kept, anim_seed + 1: %s" % (side, left))
            check([jobs.clip_view(k) for k in ("x_g_pose_run_bd", "x_ctl_fd", "x_walk_f", "x_pose_b", "x_walk_side", "x_fall")] == ["bd", "fd", "front", "back", "side", None],
                  "LE70 reroll: clip_view names the view of every clip key")
            for bad, why in (({"mode": "clip", "view": "up"}, "needs reroll.view"), ({"mode": "clip", "view": "side"}, "walks no side")):
                try:
                    jobs.enqueue("look", {"kind": "enemy", "id": "tbx", "code": "TX-A"}, {"method": "creature_free2", "recipe": {"stills": "a"}, "reroll": bad})
                    check(False, "LE70 reroll: refused: %s" % why)
                except ValueError as e:
                    check(why in str(e), "LE70 reroll: refused with the reason (%s): %s" % (why, e))
            # a re-queue reads the look's recipe as its JSON holds it now (a driver changed in the recipe editor is the one walked)
            jobs._state["jobs"].append(done("j20261013-000000-look", "look", "HH-G", [], {"method": "hero_pose5", "spec": {"method": "hero_pose5", "recipe": {"stills": "g", "pose_drivers": {"side": "run"}}}}))
            server.look_op("hero", "hh", ["HH-G"], "recipe", {"recipe": {"stills": "g", "method": "hero_pose5", "pose_drivers": {"side": "run_side_new"}}})
            res = jobs.requeue("j20261013-000000-look", {"clips": [k for k in keys if jobs.clip_view(k) == "back"]})
            hjson = _jload(os.path.join(content, "characters", "hh", "hh.json"))
            check(res["spec"]["recipe"].get("pose_drivers") == {"side": "run_side_new"} and (hjson["variants"]["HH-G"]["recipe"].get("pose_drivers") or {}).get("side") == "run_side_new",
                  "LE70 reroll: a re-queue walks on the driver the look's recipe names now, and never writes the old one back: %s" % res["spec"]["recipe"])
            # the pick race (lead follow-up): a front-from-a-picture pick writes only `stills` into the look's recipe as
            # the JSON holds it now (a look job queued before it keeps its words)
            server.look_op("enemy", "tbx", ["TX-B"], "recipe", {"recipe": {"art_prompt": "a bandit in a sombrero", "motion": "waddling", "stills": "old"}})
            pick_job = {"id": "j20261013-000000-pick", "kind": "look", "method": "front_from_picture", "state": "running", "phase": 2, "attempt": 1,
                        "target": {"kind": "enemy", "id": "tbx", "code": "TX-B"},
                        "spec": {"method": "front_from_picture", "stills": "bdb", "pick": "2", "recipe": {"stills": "bdb", "painter": {"model": "dev"}}, "note": "a pick note"}}
            written, err = jobs._post(pick_job)
            rec = _jload(os.path.join(content, "enemies", "tbx", "tbx.json"))["variants"]["TX-B"]
            check(not err and rec.get("recipe") == {"art_prompt": "a bandit in a sombrero", "motion": "waddling", "stills": "bdb"} and rec.get("note") != "a pick note",
                  "LE70 pick race: the pick merges only stills into the look's current recipe (its words kept, no painter, no note): %s" % rec.get("recipe"))
            r = server.HOOKS.merge_recipe("enemy", "tbx", "TX-B", {"stills": "a/b.png"})
            check(not r.get("ok") and "Stills is a short name" in r.get("error", ""), "LE70 pick race: merge_recipe refuses a bad Stills too")
            r = server.HOOKS.merge_recipe("enemy", "tbx", "TX-B", {"stills": "bdb"})
            check(r.get("ok") and r.get("unchanged"), "LE70 pick race: merge_recipe writes nothing when nothing changes")
            saved_hooks = jobs._hooks
            try:
                jobs._hooks = {k: getattr(server.HOOKS, k) for k in ("content_path", "set_recipe", "look_records", "merge_look", "set_look_files")}   # no merge_recipe: the fallback
                server.look_op("enemy", "tbx", ["TX-B"], "recipe", {"recipe": {"art_prompt": "words 2", "stills": "x"}})
                jobs._post(pick_job)
                rec = _jload(os.path.join(content, "enemies", "tbx", "tbx.json"))["variants"]["TX-B"]
                check(rec.get("recipe") == {"art_prompt": "words 2", "stills": "bdb"}, "LE70 pick race: without the hook the pick reads the recipe fresh and sets only stills: %s" % rec.get("recipe"))
            finally:
                jobs._hooks = saved_hooks
            # the hung step (lead follow-up): a Godot step of an import job is killed after its time limit, the job failed
            # with the reason, the lock freed by the worker
            imp = jobs.enqueue("import", {"kind": "content", "id": "enemies/tbx"}, {"targets": ["enemies/tbx"]})
            jrec = jobs._find(imp["id"])
            check(jobs.step_timeout(jrec, [jobs.GODOT, "--headless", "--import"]) == jobs.GODOT_STEP_TIMEOUT > 0
                  and jobs.step_timeout(jrec, [jobs.PY, "tools/lossy_imports.py"]) == 0
                  and jobs.step_timeout(dict(jrec, spec=dict(jrec["spec"], step_timeout=120)), [jobs.GODOT]) == 120
                  and jobs.step_timeout({"kind": "launch", "spec": {}}, [jobs.GODOT]) == 0,
                  "LE70 timeout: Godot steps of register/import jobs get %d s (the spec's step_timeout wins); other steps and Test in game none" % jobs.GODOT_STEP_TIMEOUT)
            live = jobs.Live(jrec)
            live.logf = open(os.path.join(tmp, "step_log.txt"), "w", encoding="utf-8")
            try:
                import time as _t
                t0 = _t.time()
                rc = jobs._spawn(jrec, live, [sys.executable, "-c", "import time; time.sleep(60)"], timeout=1)
                took = _t.time() - t0
            finally:
                live.logf.close()
            check(took < 20 and live.timed_out and "limit" in live.timed_out, "LE70 timeout: a hung step is killed after its limit (%.1f s): %s" % (took, live.timed_out))
            jobs._after_exit(jrec, rc, live)
            check(jrec["state"] == "failed" and "limit" in (jrec.get("error") or "") and "Re-queue" in jrec["error"], "LE70 timeout: the job is failed with the plain reason, offered for Re-queue: %s" % jrec.get("error"))
            # 6: driver_tweak, one change to a copy of a library driver (Garry fixes one view himself)
            saved_drivers = jobs.DRIVERS
            try:
                jobs.DRIVERS = os.path.join(tmp, "drivers")
                os.makedirs(os.path.join(jobs.DRIVERS, "run"))
                os.makedirs(os.path.join(jobs.DRIVERS, "taken"))
                want = {"scale": ("pose_scale.py", ["scale=0.9", "views=side,fd"]), "spread": ("pose_spread.py", ["spread=0.08"]),
                        "occlude": ("pose_occlude.py", []), "shoulders": ("pose_shoulders.py", ["level=0.2", "views=side,fd", "tuck=25"])}
                for op, (tool, args) in want.items():
                    res = jobs.enqueue("driver_tweak", {"kind": "hero", "id": "hh"}, {"src": "run", "name": "run_" + op, "op": op, "scale": 0.9, "views": "side, fd, nonsense",
                                                                                   "spread": 0.08, "level": 0.2, "tuck": "25"})
                    st = (res.get("plan") or {}).get("steps") or [[]]
                    check(res["lane"] == "local" and len(st) == 1 and os.path.basename(st[0][1]) == tool and st[0][2].endswith("drivers/run") and st[0][3].endswith("drivers/run_" + op) and st[0][4:] == args,
                          "LE70 driver_tweak: %s runs %s %s: %s" % (op, tool, args, st[0][1:]))
                res = jobs.enqueue("driver_tweak", {"kind": "hero", "id": "hh"}, {"src": "run", "name": "taken"})
                check("exists already" in str((res.get("plan") or {}).get("error", "")), "LE70 driver_tweak: a name in use is refused: %s" % (res.get("plan") or {}).get("error"))
                try:
                    jobs.enqueue("driver_tweak", {"kind": "hero", "id": "hh"}, {"src": "run"})
                    check(False, "LE70 driver_tweak: a new name is required")
                except ValueError:
                    check(True, "LE70 driver_tweak: a new name is required")
            finally:
                jobs.DRIVERS = saved_drivers
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        for k, v in saved_locks.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._root, cur = saved_state
        jobs._lane_current.clear()
        jobs._lane_current.update(cur)
        shutil.rmtree(tmp, ignore_errors=True)
    # the tools: a cut-out named by its file; a base that names its own cut-out keeps it; the creature's own icon
    src = _read(os.path.join(TOOLS, "gen_title_heroes.py"))
    check('if n.lower().endswith(".png"):' in src and 'name = os.path.basename(str(bent["title"]))' in src, "LE70 picker: gen_title_heroes picks a cut-out by its file; a base with its own cut-out keeps it")
    check('name = own' in _read(os.path.join(TOOLS, "gen_icon_cands.py")), "LE70 picker: gen_icon_cands writes the creature's own icon to the file its JSON names")
    # the page
    looks = _read(os.path.join(HERE, "looks.js"))
    heroes = _read(os.path.join(HERE, "heroes.js"))
    check("function picker(kind, id, o)" in looks and "options: { variant: code }" in looks and "function pickers(kind, id, look)" in looks
          and "if (!isStub(look)) info.appendChild(pickers(kind, id, look));" in looks, "LE70 picker: the look's stage offers the pickers; Install posts the look as options.variant")
    check("h.icon_play || h.icon" in heroes and "LookGrid.pickers('hero', doc.id, shown)" in heroes and "shown.title_file" in heroes,
          "LE70 picker: the Heroes list shows the played look's badge; the previews show the look's own cut-out and its pickers")
    check("function baseConfirm(kind, id, record, s)" in looks and "new_base: nb" in looks and "'Remove…'" in looks, "LE70 base: the page asks which look becomes the base")


# ---------------------------------------------------------------- 5. inherited values in their boxes

def inherit_checks(check):
    forms = _read(os.path.join(HERE, "forms.js"))
    assets = _read(os.path.join(HERE, "assets.js"))
    jobs_js = _read(os.path.join(HERE, "jobs.js"))
    typed = _read(os.path.join(HERE, "typed_forms.js"))
    check("function inheritable(inp, value, o, onChange, parse, same)" in forms and forms.count("inheritable(inp, value, o, onChange") == 3 and "inheritable(ta, value, o, onChange, null)" in forms
          and "inherit: o.inherit" in forms, "LE70 inherit: Forms' text, textarea and number boxes take o.inherit (the value in the box)")
    check("def2.inherit = { value: inh, from }" in assets and "inherit: def.inherit" in assets and "'↺ inherit'" in assets and "inheritchange" in assets,
          "LE70 inherit: the recipe editor puts the inherited words in the box, marks them, ↺ drops an own value")
    check("inherit: inBox ? { value: inh, from:" in jobs_js and "function inheritIn(" in jobs_js and "inheritchange" in jobs_js,
          "LE70 inherit: the job form's recipe fields too")
    check("inherit: inhBox" in typed and "isInherited" in typed, "LE70 inherit: the typed params (a mutation's weapon params, an evolution's own) too")
    # the logic under Node with a stub element (no DOM): untouched writes nothing, an edit writes, emptying inherits again
    return None


INHERIT_RUNNER = r"""
const path = require('path');
const fs = require('fs');
const dir = path.dirname(process.argv[2]);
// a stub DOM for forms.js's inputs
class Ev { constructor(t, o) { this.type = t; this.detail = o && o.detail; } }
global.CustomEvent = Ev;
function mk(tag, attrs) {
  const n = { tag, value: '', dataset: {}, title: '', classList: { s: new Set(), add(c) { this.s.add(c); }, toggle(c, on) { if (on === undefined ? !this.s.has(c) : on) this.s.add(c); else this.s.delete(c); }, contains(c) { return this.s.has(c); } },
    style: {}, listeners: {}, addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }, dispatchEvent(e) { for (const f of this.listeners[e.type] || []) f(e); }, appendChild() {} };
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') { for (const c of String(v).split(' ')) { if (c) n.classList.add(c); } }
    else if (k === 'value') n.value = v == null ? '' : String(v);
    else n[k] = v;
  }
  return n;
}
const U0 = new Function(fs.readFileSync(path.join(dir, 'util.js'), 'utf8') + '\nreturn U;')();
global.U = Object.assign({}, U0, { el: mk, clear() {} });
global.App = {};
global.requestAnimationFrame = () => 0;
const src = fs.readFileSync(path.join(dir, 'forms.js'), 'utf8');
const Forms = new Function('U', 'App', 'Model', src + '\nreturn Forms;')(global.U, global.App, {});
let q = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { q += c; });
process.stdin.on('end', () => {
  const out = {};
  const writes = [];
  const t = Forms.textInput({ key: 'k' }, null, (v) => writes.push(v), { inherit: { value: 'a mime in stripes', from: 'the hero' } });
  out.prefilled = [t.value, t.classList.contains('inherited')];
  t.value = 'a mime in red stripes'; for (const f of t.listeners.input || []) f(); for (const f of t.listeners.change || []) f();
  t.value = ''; for (const f of t.listeners.change || []) f();
  out.afterEmpty = t.value;
  t.value = 'a mime in stripes'; for (const f of t.listeners.change || []) f();
  out.writes = writes;
  const w2 = [];
  const n = Forms.numberInput({ key: 'n' }, null, (v) => w2.push(v), { inherit: { value: 36, from: 'x' } });
  out.num = n.value;
  n.value = '24'; for (const f of n.listeners.change || []) f();
  n.value = '36'; for (const f of n.listeners.change || []) f();
  out.numWrites = w2;
  const w3 = [];
  const own = Forms.textareaInput({ key: 't' }, 'my own words', (v) => w3.push(v), { inherit: { value: 'the words', from: 'x' } });
  out.own = [own.value, own.classList.contains('inherited')];
  const plain = Forms.textInput({ key: 'p' }, null, () => {}, { placeholder: 'ph' });
  out.plain = plain.value;
  process.stdout.write(JSON.stringify(out));
});
"""


def inherit_node_checks(check, run_node):
    res = run_node({}, INHERIT_RUNNER)
    if res is None:
        check(True, "LE70 inherit: Node not found: Forms.inheritable unchecked")
        return
    check(res.get("prefilled") == ["a mime in stripes", True], "LE70 inherit: an empty box shows the inherited words in it, marked: %s" % res.get("prefilled"))
    check(res.get("writes") == ["a mime in red stripes", None, None] and res.get("afterEmpty") == "a mime in stripes",
          "LE70 inherit: an edit is its own; emptying it inherits again (the words come back); the inherited text typed back is not an own value: %s" % res.get("writes"))
    check(res.get("num") == "36" and res.get("numWrites") == [24, None], "LE70 inherit: a number box too: %s" % res.get("numWrites"))
    check(res.get("own") == ["my own words", False] and res.get("plain") == "", "LE70 inherit: an own value shows as its own; a box with nothing to inherit stays empty")


# ---------------------------------------------------------------- 6. docs

def docs_checks(check):
    instr = _read(os.path.join(HERE, "instructions.js"))
    doc = _read(os.path.join(ROOT, "docs", "level_editor.md"))
    schema = _read(os.path.join(ROOT, "docs", "assets_schema.md"))
    keys = _read(os.path.join(ROOT, "tools", "dl", "p70", "keys_LE.md"))
    check("Pass 70" in instr and "Stills" in instr and "Reference" in instr and "becomes the base" in instr, "LE70 docs: the Instructions tab's Pass 70 section")
    check("## Pass 70" in doc and "bandit.png" in doc and "Choose" in doc and "inherited" in doc, "LE70 docs: docs/level_editor.md Pass 70")
    check("pass 70" in schema.lower() and "new_base" in schema and "icon_play" in schema, "LE70 docs: docs/assets_schema.md rows (remove new_base, icon_play, install variant)")
    if keys:
        check("new_base" in keys and "Choose" in keys, "LE70 docs: tools/dl/p70/keys_LE.md names the new controls")


def run_scale_checks(check):
    """Lead follow-up: lane ART's recipe key run_scale ({view: multiplier}) has a typed row per view, and the docs fix a size
    problem with it (a scaled driver is fitted back to the standing height)."""
    m = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))
    rows = {x["id"]: next((f for f in x.get("recipe_fields", []) if f.get("key") == "run_scale"), None) for x in m["methods"]}
    want = {"hero_pose5": 5, "hero_fit": 5, "creature_free2": 5, "creature_pose2": 5, "creature_free8": 5}
    check(all(rows.get(k) and rows[k]["type"] == "view_numbers" and len(rows[k]["views"]) == n and rows[k]["min"] == 0.5 and rows[k]["max"] == 1.5 and rows[k]["default"] == 1
              for k, n in want.items()) and rows.get("creature_ctl") is None and rows.get("creature_proc") is None,
          "LE70 run_scale: a Run size row per view for the look methods gen_art walks (not gen_ctl, not creature_proc)")
    ga_src = _read(os.path.join(TOOLS, "gen_art.py"))
    check("def run_scale_of(d, view)" in ga_src and "min(1.5, max(0.5" in ga_src, "LE70 run_scale: gen_art reads it per view, clamped 0.5..1.5 (lane ART)")
    check("if (t === 'view_numbers')" in _read(os.path.join(HERE, "assets.js")) and "case 'view_numbers':" in _read(os.path.join(HERE, "jobs.js")),
          "LE70 run_scale: the typed recipe and the job form render a number per view")
    instr = _read(os.path.join(HERE, "instructions.js"))
    check("Run size: side" in instr and "0.9 or 1.1" not in instr and "it does not change the sprite" in instr,
          "LE70 run_scale: the Pass 70 how-to fixes a size with Run size, a scaled driver only keeps a figure inside the clip")
    meth = next(x for x in m["methods"] if x["id"] == "driver_tweak")
    check("run_scale" in meth["summary"] and any("run_scale" in w for w in meth["weaknesses"]), "LE70 run_scale: driver_tweak's card says a size is run_scale's")


def checks(check, run_node, server):
    run_scale_checks(check)
    seed_checks(check)
    bandit_checks(check, run_node, server)
    base_checks(check, server)
    picker_checks(check, server)
    inherit_checks(check)
    inherit_node_checks(check, run_node)
    docs_checks(check)
