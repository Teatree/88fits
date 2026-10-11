"""Lane J's selftest group (pass 66): the jobs queue, its state machine, the progress parser against recorded logs, the
cache-key and stage formulas, the merge through a fake hooks dict, re-rolls, import coalescing, recover(), the stale-lock
rule, and tools/asset_job.py's --dry-run on a temp copy of a creature. Discovered by selftest.py: `checks(check,
run_node, server)`. Everything runs on temp folders: jobs.py's paths and locks.py's lock and save folders are re-pointed
for the duration and put back after; nothing under game/ is touched."""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))


def _fake_hooks(content_dir, calls):
    """The server's hooks on a temp content folder: a plain dict of callables, as server.py hands jobs.init()."""
    import jobs

    def content_path(kind, cid):
        tf = jobs.KIND_FOLDERS.get(kind)
        if not tf:
            return None, None
        return tf, os.path.join(content_dir, tf, cid, cid + ".json")

    def _load(kind, cid):
        tf, jp = content_path(kind, cid)
        return jp, json.load(open(jp, encoding="utf-8"))

    def _dump(jp, d):
        json.dump(d, open(jp, "w", encoding="utf-8", newline="\n"), indent=2)

    def merge_look(kind, cid, code, entry, info):
        calls.append(("merge_look", kind, cid, code, dict(entry)))
        jp, d = _load(kind, cid)
        existing = d.setdefault("variants", {}).get(code) or {}
        merged = dict(existing)
        merged.update(entry)
        d["variants"][code] = merged
        _dump(jp, d)
        return {"ok": True, "layout": "entry", "backup": "fake.bak"}

    def merge_top(kind, cid, top):
        calls.append(("merge_top", kind, cid, dict(top)))
        jp, d = _load(kind, cid)
        for k, v in top.items():
            if k == "art_prompt" and k in d:
                continue
            d[k] = v
        _dump(jp, d)
        return {"ok": True, "layout": "block", "backup": "fake.bak"}

    def set_recipe(kind, cid, code, recipe, note=None):
        calls.append(("set_recipe", kind, cid, code, dict(recipe)))
        jp, d = _load(kind, cid)
        e = d.setdefault("variants", {}).setdefault(code, {})
        e["recipe"] = recipe
        if note:
            e["note"] = note
        _dump(jp, d)
        return {"ok": True}

    def look_records(kind, cid):
        jp, d = _load(kind, cid)
        return [{"code": c, **{k: v for k, v in (e or {}).items() if k in ("anims", "strip_cols", "fps", "head", "note", "recipe", "shelved", "fresh")}}
                for c, e in (d.get("variants") or {}).items()]

    return {"content_path": content_path, "merge_look": merge_look, "merge_top": merge_top, "set_recipe": set_recipe,
            "look_records": look_records, "redump_merge": lambda *a: {"ok": False, "error": "not in the fake"}}


def checks(check, run_node, server):
    import locks
    before = threading.active_count()
    import jobs
    check(threading.active_count() == before, "importing jobs starts no thread (%d -> %d)" % (before, threading.active_count()))
    tmp = tempfile.mkdtemp(prefix="le_jobs_")
    saved = {k: getattr(jobs, k) for k in ("JOBS_DIR", "QUEUE_FILE", "RAW", "ANIM", "REVIEW", "LAUNCH_FILE", "DL", "TITLE_OUT")}
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
        jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
        locks.LOCK_DIR = os.path.join(tmp, "locks")
        locks.SAVE_DIR = os.path.join(tmp, "save")
        locks.KEEP_DIR = os.path.join(tmp, "locks", "save_keep")
        locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
        for p in (jobs.RAW, jobs.ANIM, jobs.REVIEW, locks.SAVE_DIR, os.path.dirname(jobs.LAUNCH_FILE)):
            os.makedirs(p, exist_ok=True)
        open(os.path.join(locks.SAVE_DIR, "save.json"), "w").write('{"fake": 1}')
        content = os.path.join(tmp, "content")
        _seed_content(content)
        calls = []
        hooks = _fake_hooks(content, calls)
        jobs._state = {"rev": 0, "jobs": []}
        jobs._workers.clear()
        n0 = threading.active_count()
        rev0 = jobs.init(hooks, ROOT)
        check(threading.active_count() == n0, "jobs.init starts no thread")
        check(jobs.status()["workers"] == 0 and jobs.status()["queued"] == 0, "status: no workers, empty queue")

        # ---- SPECS
        for kind, spec in jobs.SPECS.items():
            check(spec["lane"] in jobs.LANES and isinstance(spec["fields"], dict), "SPECS[%s] has a lane and fields" % kind)
            for name, f in spec["fields"].items():
                check(all(k in f for k in ("type", "default", "required", "help")), "SPECS[%s].%s has type/default/required/help" % (kind, name))
        for bad in (lambda: jobs.enqueue("nope", {}, {}), lambda: jobs.enqueue("look", {"kind": "enemy", "id": "testbeast"}, {"method": "creature_free2"}),
                    lambda: jobs.enqueue("look", {"kind": "enemy", "id": "testbeast", "code": "TB-A"}, {"method": "banana"}),
                    lambda: jobs.enqueue("icon_cands", {"kind": "weapon", "id": "revolver"}, {}),
                    lambda: jobs.enqueue("look", {"kind": "enemy", "id": "testbeast", "code": "TB-A"}, {"method": "front_from_picture"})):
            try:
                bad()
                check(False, "a bad enqueue raises ValueError")
            except ValueError:
                check(True, "a bad enqueue raises ValueError")

        # ---- round trip, rev, derivation
        j = jobs.enqueue("look", {"kind": "enemy", "id": "testbeast", "code": "TB-A"}, {"method": "creature_free2", "recipe": {"stills": "tba", "motion": "waddling"}, "skip_qa": True})
        check(jobs._state["rev"] > rev0, "enqueue bumps rev")
        check(j["state"] == "queued" and j["lane"] == "comfy" and j["phase"] == 1 and j["attempt"] == 1, "a new look job is queued on the comfy lane")
        check(j["cmd"][0] == sys.executable and j["cmd"][1] == "-u" and j["cmd"][2].endswith("asset_job.py"), "a comfy job runs through asset_job.py: %s" % j["cmd"])
        check(j["equiv"] == "python tools/gen_art.py --no-import --only testbeast --variant=TB-A --skip-qa", "equiv is the command Claude would type: %s" % j["equiv"])
        check(j["title"] == "Test Beast TB-A · creature_free2", "the title names the creature, the code and the method: %s" % j["title"])
        rc = [c for c in calls if c[:4] == ("set_recipe", "enemy", "testbeast", "TB-A")]
        check(rc and rc[0][4].get("stills") == "tba" and rc[0][4].get("motion") == "waddling" and "art_prompt" in rc[0][4], "enqueue writes the recipe through hooks.set_recipe (the base's art words seeded in): %s" % (rc and rc[0][4]))
        # the painter every look job records (pass 66 follow-up: "Looks should contain these settings for all")
        check(rc and rc[0][4].get("painter") == {"model": "klein", "steps": 0}, "a look job records its painter in the recipe (Klein, the default passes): %s" % (rc and rc[0][4].get("painter")))
        sp = jobs.validate_spec("look", {"method": "creature_pose2", "recipe": {"stills": ""}, "model": "dev", "steps": 12, "turbo": False})
        jobs._seed_recipe({"kind": "enemy", "id": "testbeast", "code": "TB-B"}, sp)
        check(sp["recipe"].get("painter") == {"model": "dev", "steps": 12, "guidance": 0.0, "turbo": False}, "a dev job records model, steps, guidance and turbo: %s" % sp["recipe"].get("painter"))
        check(sp["recipe"].get("stills") == "", "an explicit empty stills slug is kept (the creature's own paintings); only an absent key is seeded: %r" % sp["recipe"].get("stills"))
        check(jobs._model_argv(sp) == ["--dev", "--steps=12", "--no-turbo"], "the painter reaches the command: %s" % jobs._model_argv(sp))
        sp = {"method": "recolour", "recipe": {}}
        jobs._seed_recipe({"kind": "enemy", "id": "testbeast", "code": "TB-C"}, sp)
        check("painter" not in sp["recipe"], "a recolour records no painter (it paints nothing): %s" % sp["recipe"])
        sp = {"method": "hero_fit", "recipe": {"still_keys": {"side": "x"}}, "model": "klein", "steps": 6}
        jobs._seed_recipe({"kind": "hero", "id": "solenne", "code": "SOL-X"}, sp)
        check(sp["recipe"].get("painter") == {"model": "klein", "steps": 6} and "stills" not in sp["recipe"], "a hero look records its painter and gets no stills slug: %s" % sp["recipe"])
        jj = json.load(open(os.path.join(jobs.JOBS_DIR, j["id"], "job.json"), encoding="utf-8"))
        check(jj["tool"] == "gen_art" and jj["call"] == "process" and "--variant=TB-A" in jj["argv"] and jj["type"] == "enemies" and jj["id"] == "testbeast",
              "job.json carries tool/call/argv/type/id: %s" % {k: jj[k] for k in ("tool", "call", "argv", "type", "id")})
        check(jj["env"]["ASSET_JOB_SIDECAR"].endswith(os.path.join(j["id"], "result.json")) and jj["env"]["LOCK_HELD_COMFY"] == "1", "job.json env: the sidecar and the lock pass-through")
        rev = jobs._state["rev"]
        check(jobs.list(since_rev=rev).get("unchanged") is True, "list(since_rev=rev) says unchanged")
        check(len(jobs.list()["jobs"]) == 1 and jobs.list()["rev"] == rev, "list() returns the record and the rev")
        check(jobs.get(j["id"])["id"] == j["id"] and jobs.get("nope") is None, "get() by id")
        jobs._state = {"rev": 0, "jobs": []}
        jobs._load()
        check(jobs._state["rev"] == rev and [x["id"] for x in jobs._state["jobs"]] == [j["id"]], "the queue file round-trips (rev %d)" % rev)
        names = [s["name"] for s in jobs.get(j["id"])["progress"]["stages"]]
        check(names == ["front", "back", "walk_f", "walk_b", "dead", "pack"], "creature_free2 stages: %s" % names)
        ck = jobs.get(j["id"])["cache_keys"]
        check(ck["stills"] == ["testbeast_tba_front", "testbeast_tba_back", "testbeast_tba_dead"] and ck["clips"] == ["testbeast_tba_walk_f", "testbeast_tba_walk_b"],
              "creature_free2 cache keys use the stills slug (sk) and the code (ak): %s" % ck)
        check(jobs.get(j["id"])["eta_s"] > 0, "an ETA is estimated: %s s" % jobs.get(j["id"])["eta_s"])

        # ---- stage lists and cache keys per method
        T = {"kind": "enemy", "id": "goblin", "code": "GOB-E"}
        st = [s["name"] for s in jobs.expected_stages("creature_pose2", {"recipe": {"pose": "walk", "death": "pose:death_back"}}, T)]
        check(st == ["front", "back", "pose_f", "pose_b", "dead", "death", "pack"], "creature_pose2 stages: %s" % st)
        st = [s["name"] for s in jobs.expected_stages("creature_free8", {"recipe": {"directions": 8, "death": "clip"}}, T)]
        check(st == ["front", "back", "walk_f", "walk_b", "side", "bd", "fd", "walk_side", "walk_bd", "walk_fd", "dead", "fall", "pack"], "creature_free8 stages: %s" % st)
        st = [s["name"] for s in jobs.expected_stages("creature_proc", {"recipe": {"walk": "hop", "death": "squash"}}, T)]
        check(st == ["front", "back", "dead", "pack"], "creature_proc stages: %s" % st)
        H = {"kind": "hero", "id": "solenne", "code": "SOL-X"}
        st = [s["name"] for s in jobs.expected_stages("hero_pose5", {"recipe": {}}, H)]
        check(len(st) == 18 and st[:6] == ["front", "back", "side", "fd", "bd", "cheer"] and st[6] == "pose_run_back" and st[-2:] == ["dead", "pack"],
              "hero_pose5 stages (a look: no portrait): %d %s" % (len(st), st))
        st0 = [s["name"] for s in jobs.expected_stages("hero_pose5", {"recipe": {}}, {"kind": "hero", "id": "solenne", "code": ""})]
        check("portrait" in st0 and len(st0) == 19, "hero_pose5 base run has the portrait stage: %d" % len(st0))
        st = [s["name"] for s in jobs.expected_stages("hero_fit", {"recipe": {}}, H)]
        check(st == ["pose_run_back", "pose_run_front", "pose_run_side", "pose_run_bd", "pose_run_fd", "pack"], "hero_fit stages: %s" % st)
        C = {"kind": "enemy", "id": "dune_scorpion", "code": "SC-X"}
        st = [s["name"] for s in jobs.expected_stages("creature_ctl", {"recipe": {"drivers": "scorpion_walk", "death_drivers": "scorpion_death"}, "seeds": 3}, C, phase=1)]
        check(st == ["side_k0", "side_k1", "side_k2", "side candidates"], "creature_ctl phase 1 stages (the human stop): %s" % st)
        st = [s["name"] for s in jobs.expected_stages("creature_ctl", {"recipe": {"drivers": "scorpion_walk", "death_drivers": "scorpion_death"}, "seeds": 3, "use_side": "k1"}, C, phase=2)]
        check(st == ["front", "fd", "bd", "back", "ctl_front", "ctl_fd", "ctl_side", "ctl_bd", "ctl_back", "death", "pack"], "creature_ctl phase 2 stages: %s" % st)
        st = [s["name"] for s in jobs.expected_stages("creature_ctl", {"recipe": {"drivers": "x", "directions": 2}, "use_side": "k0"}, C, phase=2)]
        check(st == ["front", "fd", "bd", "back", "ctl_front", "ctl_back", "dead", "fall", "pack"], "creature_ctl two directions, no death driver: %s" % st)
        ck = jobs.cache_keys("creature_free8", {"recipe": {"stills": "c4", "directions": 8}}, T)
        check("goblin_c4_side" in ck["stills"] and "goblin_gobe_walk_side" in ck["clips"] and "goblin_c4_front" in ck["stills"], "8-way keys follow sk/ak (the key fix): %s" % ck)
        ck = jobs.cache_keys("creature_pose2", {"recipe": {"pose": "walk"}}, T)
        check(ck["clips"][:2] == ["goblin_gobe_pose_f", "goblin_gobe_pose_b"], "pose2 clip keys: %s" % ck["clips"])
        ck = jobs.cache_keys("hero_fit", {"recipe": {"still_keys": {"side": "solenne_s55_side"}}}, {"kind": "hero", "id": "solenne", "code": "SOL-B"})
        check("solenne_solb_pose_run_back" in ck["clips"] and "solenne_s55_side" in ck["stills"] and "solenne_front" in ck["stills"] and "solenne_portrait" not in ck["stills"],
              "hero look keys: ck from the code, still_keys honoured, no portrait: %s" % ck)
        ck = jobs.cache_keys("creature_ctl", {"recipe": {"drivers": "scorpion_walk", "death_drivers": "scorpion_death"}}, {"kind": "enemy", "id": "dune_scorpion", "code": "SC-A"})
        check(ck["stills"][0] == "dune_scorpion_sca_side" and "dune_scorpion_sca_ctl_front" in ck["clips"] and "dune_scorpion_sca_death" in ck["clips"], "ctl keys: %s" % ck)

        # ---- the progress parser against the recorded logs
        td = os.path.join(HERE, "testdata")
        fj = jobs.enqueue("look", {"kind": "enemy", "id": "skeleton_raider", "code": "SR-A"}, {"method": "creature_free2", "recipe": {"death": "clip"}})
        fj = jobs._find(fj["id"])
        # the log's keys are the base creature's (no stills slug, clips keyed by the id): point the stages at them
        for s in fj["progress"]["stages"]:
            s["key"] = s["key"].replace("skeleton_raider_sra_", "skeleton_raider_").replace("skeleton_raider_a_", "skeleton_raider_")  # the seeded stills slug too (lead)
        markers = jobs.parse_log(fj, open(os.path.join(td, "gen_art_free2.log"), encoding="utf-8").read())
        done = [s["name"] for s in fj["progress"]["stages"] if s["state"] == "done"]
        check(done == ["front", "back", "walk_f", "walk_b", "dead", "fall", "pack"], "gen_art_free2.log: every stage done: %s" % done)
        check(fj["progress"]["done"] == 7 and fj["progress"]["total"] == 7 and markers == [], "gen_art_free2.log: 7/7, no stop marker (%s)" % markers)
        back = [s for s in fj["progress"]["stages"] if s["name"] == "back"][0]
        check(abs(back["secs"] - 36.8) < 0.01 and back.get("note") == "retry: no-match,view=front", "a retried render keeps its seconds and the verdict: %s" % back)
        check(any("kept the best" in n for n in fj["progress"].get("notes", [])) and fj["sidecar"].endswith("result.json"), "the parser notes the kept-the-best line and the sidecar path")
        dead = [s for s in fj["progress"]["stages"] if s["name"] == "dead"][0]
        check(dead["state"] == "done" and dead.get("clip_kind") is None and [s for s in fj["progress"]["stages"] if s["name"] == "fall"][0]["clip_kind"] == "flf",
              "the fall is a first-last-frame clip, the dead still has no clip kind")
        cj = jobs.enqueue("look", {"kind": "enemy", "id": "bull_beetle", "code": "BB-X"}, {"method": "creature_ctl", "recipe": {"drivers": "beetle_walk", "death_drivers": "beetle_death"}, "seeds": 3})
        cj = jobs._find(cj["id"])
        text = open(os.path.join(td, "gen_ctl_side.log"), encoding="utf-8").read()
        part1 = text.split("--- after the pick")[0]
        markers = jobs.parse_log(cj, part1)
        check(markers == ["side"] and [s["name"] for s in cj["progress"]["stages"] if s["state"] == "done"] == ["side_k0", "side_k1", "side_k2", "side candidates"],
              "gen_ctl_side.log phase 1: three sides and the stop marker (%s)" % markers)
        check(cj["progress"]["stage"] == "side candidates painted", "the stage reads 'side candidates painted': %s" % cj["progress"]["stage"])
        cj["spec"]["use_side"] = "k1"
        cj["phase"] = 2
        jobs._derive(cj)
        markers = jobs.parse_log(cj, text.split("--- after the pick")[1])
        done = [s["name"] for s in cj["progress"]["stages"] if s["state"] == "done"]
        check(done == ["front", "fd", "bd", "back", "ctl_front", "ctl_fd", "ctl_side", "ctl_bd", "ctl_back", "death", "pack"] and markers == [],
              "gen_ctl_side.log phase 2: views, five walks, the death and the pack: %s" % done)
        check([s for s in cj["progress"]["stages"] if s["name"] == "ctl_side"][0]["clip_kind"] == "control", "a Fun Control walk is clip_kind control")
        ij = jobs.enqueue("icon_cands", {"kind": "passive", "id": "hot_streak2", "code": ""}, {"subject": "two dice", "seeds": 4, "key": "hot_streak2"})
        ij = jobs._find(ij["id"])
        markers = jobs.parse_log(ij, open(os.path.join(td, "gen_icon_cands.log"), encoding="utf-8").read())
        check(markers == ["review"] and ij["progress"]["done"] == 5 and ij["progress"]["stage"] == "review sheet", "gen_icon_cands.log: four candidates and the review marker (%s, %d)" % (markers, ij["progress"]["done"]))
        check(jobs.stop_marker("  side candidates painted: look at x, then rerun with --use-side=kN") == "side" and jobs.stop_marker("  pick with --use-view=VIEW:cN[,VIEW:cN]") == "view"
              and jobs.stop_marker("gen_edit_stills: look at D:/x/werewolf_wwa_front_cands.png, then --pick N") == "pick" and jobs.stop_marker("review magnet") == "review"
              and jobs.stop_marker("  badge candidates painted: look at x, then --pick k") == "badge" and jobs.stop_marker("  review: D:/x/review_astro.png") == "title"
              and jobs.stop_marker("  render x seed 1 2.0s  ok") is None, "stop_marker tells the six human stops apart")

        # ---- transitions
        job = jobs._find(j["id"])
        taken = jobs._take_next("comfy")
        check(taken is job and job["state"] == "running" and job["started"] and jobs._lane_current["comfy"] == job["id"], "_take_next runs the oldest queued job of the lane")
        try:
            jobs.edit(job["id"], spec={"seed": 1})
            check(False, "edit refuses a running job")
        except ValueError:
            check(True, "edit refuses a running job")
        try:
            jobs.delete(job["id"])
            check(False, "delete refuses a running job")
        except ValueError:
            check(True, "delete refuses a running job")
        # running -> exit 1 -> failed (the error is the last telling line)
        live = jobs.Live(job)
        live.tail.extend(["  render x seed 1 2.0s ok", "Traceback (most recent call last):", "RuntimeError: ComfyUI timeout after 1200s", "asset_job: FAILED"])
        jobs._after_exit(job, 1, live)
        check(job["state"] == "failed" and job["error"] == "RuntimeError: ComfyUI timeout after 1200s" and job["pid"] is None and job["ended"], "exit 1 -> failed with the exception's line: %s" % job["error"])
        # failed -> requeue -> queued, attempt 2
        r = jobs.requeue(job["id"])
        check(r["state"] == "queued" and r["attempt"] == 2 and r["phase"] == 1 and r["error"] == "" and r["started"] is None, "requeue: queued again, attempt 2")
        # running -> exit 0 + a stop marker -> waiting -> pick -> queued at the front, phase 2
        cjob = jobs._find(cj["id"])
        cjob["spec"]["use_side"] = ""
        cjob["phase"] = 1
        jobs._derive(cjob)
        jobs._lane_current["comfy"] = None
        jobs._take_next("comfy")   # takes the oldest queued: the free2 job again
        cjob["state"] = "running"
        live = jobs.Live(cjob)
        live.marker = "side"
        jobs._after_exit(cjob, 0, live)
        check(cjob["state"] == "waiting" and cjob["waiting_for"] == "side" and cjob["progress"]["stage"] == "pick a side view", "exit 0 + the side marker -> waiting")
        p = jobs.pick(cjob["id"], "k1")
        check(p["state"] == "queued" and p["phase"] == 2 and p["front"] is True and p["spec"]["use_side"] == "k1" and "--use-side=k1" in p["plan"]["argv"],
              "pick -> queued at the front, phase 2, --use-side=k1 in the argv: %s" % p["plan"]["argv"])
        jobs._lane_current["comfy"] = None
        nxt = jobs._take_next("comfy")
        check(nxt["id"] == cjob["id"], "a picked continuation goes first in its lane")
        # a view re-roll pick: "fd:c1,back:c0"
        cjob["state"] = "waiting"
        cjob["waiting_for"] = "view"
        cjob["spec"]["view_cands"] = "fd,back"
        p = jobs.pick(cjob["id"], "fd:c1,back:c0")
        check(p["spec"]["use_view"] == "fd:c1,back:c0" and p["spec"]["view_cands"] == "" and "--use-view=fd:c1,back:c0" in p["plan"]["argv"] and "--view-cands=fd,back" not in p["plan"]["argv"],
              "a view pick sets --use-view and drops --view-cands: %s" % p["plan"]["argv"])
        # edit while waiting -> queued, phase 1, the picks cleared
        cjob["state"], cjob["waiting_for"] = "waiting", "side"
        e = jobs.edit(cjob["id"], spec={"seeds": 4}, title="Beetle X")
        check(e["state"] == "queued" and e["phase"] == 1 and e["spec"]["seeds"] == 4 and e["spec"]["use_side"] == "" and e["title"] == "Beetle X" and "--seeds=4" in e["plan"]["argv"],
              "edit while waiting -> queued at phase 1 with the command re-derived: %s" % e["plan"]["argv"])
        e = jobs.edit(cjob["id"], spec={"recipe": {"drivers": "beetle_walk_amp", "death_drivers": "beetle_death"}})
        check(calls[-1][0] == "set_recipe" and calls[-1][4]["drivers"] == "beetle_walk_amp", "editing a look's recipe writes it through hooks.set_recipe")
        # cancel queued -> cancelled; requeue -> queued
        c = jobs.cancel(cjob["id"])
        check(c["state"] == "cancelled" and c["ended"], "cancel a queued job -> cancelled")
        check(jobs.requeue(cjob["id"])["state"] == "queued", "a cancelled job requeues")
        # exit 0 with a result.json -> merge through the fake hooks, fresh:true, note/recipe/shelved kept, an import job follows
        job = jobs._find(j["id"])
        d0 = json.load(open(os.path.join(content, "enemies", "testbeast", "testbeast.json"), encoding="utf-8"))
        d0["variants"]["TB-A"].update({"note": "my note", "shelved": True})
        json.dump(d0, open(os.path.join(content, "enemies", "testbeast", "testbeast.json"), "w", encoding="utf-8", newline="\n"), indent=2)
        os.makedirs(os.path.join(jobs.JOBS_DIR, job["id"]), exist_ok=True)
        json.dump({"id": "testbeast", "folder": "x", "variant": "TB-A", "entry": {"sprite": "testbeast_sprite_a.png", "icon": "testbeast_icon_a.png", "anims": {"idle": 4}, "strip_cols": 43, "fps": {"run": 15, "die": 8}, "head": 0.8},
                   "top": {}, "info": {"clip_kind": {"front": "free", "back": "free"}, "qa_online": False}}, open(os.path.join(jobs.JOBS_DIR, job["id"], "result.json"), "w"))
        n_before = len(jobs._state["jobs"])
        job["state"] = "running"
        jobs._after_exit(job, 0, jobs.Live(job))
        check(job["state"] == "done" and job["written"]["layout"] == "entry" and job["written"]["keys"] == ["variants"] and job["written"]["file"].endswith("testbeast.json"),
              "exit 0 -> merged -> done, written says how: %s" % job["written"])
        d1 = json.load(open(os.path.join(content, "enemies", "testbeast", "testbeast.json"), encoding="utf-8"))["variants"]["TB-A"]
        check(d1["note"] == "my note" and d1["recipe"].get("stills") == "tba" and d1["recipe"].get("motion") == "waddling" and d1["shelved"] is True and d1["fresh"] is True and d1["sprite"] == "testbeast_sprite_a.png",
              "the merge keeps note/recipe/shelved and marks the look fresh: %s" % d1)
        imports = [x for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued"]
        check(len(jobs._state["jobs"]) == n_before + 1 and len(imports) == 1 and imports[0]["spec"]["targets"] == ["enemies/testbeast"] and imports[0]["lane"] == "godot",
              "a landing queues one import job on the godot lane: %s" % [x["spec"]["targets"] for x in imports])
        check(job["progress"]["done"] == job["progress"]["total"] == 6, "done fills the bar")
        # install from a done icon_cands job; a not-done source is refused
        ijob = jobs._find(ij["id"])
        try:
            jobs.install(ijob["id"], "2")
            check(False, "install refuses a job whose candidates are not done")
        except ValueError:
            check(True, "install refuses a job whose candidates are not done")
        ijob["state"] = "done"
        inst = jobs.install(ijob["id"], "2")
        check(inst["kind"] == "install" and inst["lane"] == "local" and inst["plan"]["tool"] == "gen_icon_cands" and inst["plan"]["call"] == "pick" and inst["plan"]["argv"] == ["--pick", "hot_streak2=2"],
              "install queues a local pick job: %s" % inst["plan"]["argv"])
        check(inst["equiv"].startswith("python tools/gen_icon_cands.py --pick hot_streak2=2"), "install equiv: %s" % inst["equiv"])
        # move among the queued jobs of a lane
        a = jobs.enqueue("import", {}, {"targets": ["enemies/goblin"]})
        b = jobs.enqueue("import", {}, {"targets": ["enemies/imp"]})
        order = [x["id"] for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued"]
        jobs.move(b["id"], -1)
        order2 = [x["id"] for x in jobs._state["jobs"] if x["kind"] == "import" and x["state"] == "queued"]
        check(order2.index(b["id"]) == order.index(b["id"]) - 1, "move(-1) lifts a queued job one place in its lane")
        # import coalescing: the godot lane takes one import with the union of the targets
        jobs._lane_current["godot"] = None
        taken = jobs._take_next("godot")
        check(taken["kind"] == "import" and set(taken["spec"]["targets"]) == {"enemies/testbeast", "enemies/goblin", "enemies/imp"},
              "consecutive queued imports merge their targets: %s" % taken["spec"]["targets"])
        merged = [x for x in jobs._state["jobs"] if x.get("merged_into") == taken["id"]]
        check(len(merged) == 2 and all(x["state"] == "done" for x in merged), "the absorbed imports end done, naming the one that runs")
        check("only=" in " ".join(taken["plan"]["steps"][-1]) and taken["plan"]["steps"][0][-1] == "--import" and os.path.basename(taken["plan"]["steps"][1][1]) == "lossy_imports.py",
              "an import job is --import, lossy_imports, --import, import_json only=: %s" % [jobs._step_name(s) for s in taken["plan"]["steps"]])
        taken["state"] = "done"
        # delete a done job removes its folder
        did = job["id"]
        check(jobs.delete(did) is True and jobs._find(did) is None and not os.path.isdir(os.path.join(jobs.JOBS_DIR, did)), "delete removes the record and its folder")

        # ---- every kind derives a command and an equiv
        kinds = [("item_icon", {"kind": "weapon", "id": "revolver"}, {}, "asset", "python tools/gen_art.py --no-import --only revolver"),
                 ("hero_badge", {"kind": "hero", "id": "solenne"}, {"seeds": 3, "prompt": "winking"}, "asset", "python tools/gen_badge_cands.py --id solenne --seeds 3 --prompt winking"),
                 ("hero_title", {"kind": "hero", "id": "astro"}, {"seeds": 2}, "asset", "python tools/gen_title_heroes.py --only astro --seeds=2 --first-seed=11"),
                 ("register", {}, {"targets": ["enemies/testbeast"]}, "steps", "bash tools/godot.sh --headless --path"),
                 ("driver_pose", {}, {"src": "tools/dl/mixamo/walking.fbx", "name": "walk_test", "frames": 12}, "steps", "--python tools/pose_driver.py -- fbx=tools/dl/mixamo/walking.fbx out=tools/dl/drivers/walk_test frames=12"),
                 ("driver_depth", {}, {"src": "tools/dl/uploads/3d/beetle/beetle.fbx", "name": "beetle_test", "action": "walk"}, "steps", "blender_depth_drivers.py -- src="),
                 ("ref_probe", {}, {"src": "tools/dl/uploads/3d/beetle/beetle.fbx"}, "steps", "blender_ref.py -- src=tools/dl/uploads/3d/beetle/beetle.fbx out=tools/dl/uploads/3d/beetle mode=probe"),
                 ("ref_render", {}, {"src": "tools/dl/uploads/3d/beetle/beetle.fbx", "mode": "icon"}, "steps", "mode=icon"),
                 ("launch", {}, {"character": "solenne", "look": "SOL-B", "spawn_enemy": "goblin", "variant": "GOB-B", "count": 2}, "launch", "res://game/Game.tscn")]
        for kind, target, spec, mode, needle in kinds:
            r = jobs.enqueue(kind, target, spec)
            ok = r["plan"]["mode"] == mode and needle in r["equiv"] and r["lane"] == jobs.SPECS[kind]["lane"]
            check(ok, "%s derives (%s): %s" % (kind, mode, r["equiv"]))
            if kind == "launch":
                check(r["plan"]["steps"][0] == [jobs.GODOT, "--path", jobs.GAME, "res://game/Game.tscn"], "launch runs Game.tscn windowed: %s" % r["plan"]["steps"][0])
                check(r["plan"]["launch"] == {"map": "red_canyon", "arena": True, "spawn": False, "count": 2, "character": "solenne", "look": "SOL-B", "spawn_enemy": "goblin", "variant": "GOB-B"},
                      "the launch file's keys: %s" % r["plan"]["launch"])
            if kind == "register":
                names = [jobs._step_name(s) for s in r["plan"]["steps"]]
                check(names == ["gen_placeholders.gd", "godot --import", "lossy_imports.py", "godot --import", "import_json.gd"], "register's five steps: %s" % names)
        ic = jobs.enqueue("icon_cands", {"kind": "enemy", "id": "goblin"}, {"subject": "a goblin head", "file": "goblin_icon_e.png", "seeds": 2, "screen": "blue"})
        check(ic["plan"]["icon_job"] == {"kind": "enemies", "id": "goblin", "subject": "a goblin head", "set": "_le_" + ic["id"], "screen": "blue", "file": "goblin_icon_e.png"},
              "icon_cands for a creature look: JOBS[key] with kind/id/subject/set/screen/file: %s" % ic["plan"]["icon_job"])
        rc = jobs.enqueue("look", {"kind": "enemy", "id": "goblin", "code": "GOB-R"}, {"method": "recolour", "recolour": {"from": "GOB-D", "ranges": [[55, 135]], "to": 357, "sat": 1.0}})
        check(rc["lane"] == "local" and rc["plan"]["mode"] == "steps" and len(rc["plan"]["steps"]) == 2 and "--ranges" in rc["plan"]["steps"][0] and "55-135" in rc["plan"]["steps"][0],
              "recolour runs recolour_strip.py twice on the local lane: %s" % rc["equiv"])
        ff = jobs.enqueue("look", {"kind": "enemy", "id": "werewolf", "code": "WW-X"}, {"method": "front_from_picture", "stills": "wwx", "ref": "tools/dl/uploads/2d/w.webp", "prompt": "a wolf", "seeds": 2, "keep": "yellow eyes"})
        check(ff["plan"]["tool"] == "gen_edit_stills" and ff["plan"]["argv"] == ["--id", "werewolf", "--stills", "wwx", "--ref", "tools/dl/uploads/2d/w.webp", "--prompt", "a wolf", "--seeds", "2", "--keep", "yellow eyes"],
              "front_from_picture argv: %s" % ff["plan"]["argv"])
        fj2 = jobs._find(ff["id"])
        fj2["state"], fj2["waiting_for"] = "waiting", "pick"
        p = jobs.pick(ff["id"], "1")
        check(p["plan"]["argv"] == ["--id", "werewolf", "--stills", "wwx", "--pick", "1"] and p["phase"] == 2, "front_from_picture's pick argv: %s" % p["plan"]["argv"])

        # ---- requeue with a re-roll: the clip folder moves, the still is copied aside, the seed moves
        key_s, key_c = "testbeast_tba_dead", "testbeast_tba_walk_b"
        open(os.path.join(jobs.RAW, key_s + ".png"), "wb").write(b"png")
        open(os.path.join(jobs.RAW, key_s + ".json"), "w").write("{}")
        os.makedirs(os.path.join(jobs.ANIM, key_c))
        open(os.path.join(jobs.ANIM, key_c, "cycle.json"), "w").write("{}")
        rj = jobs.enqueue("look", {"kind": "enemy", "id": "testbeast", "code": "TB-A"}, {"method": "creature_free2", "recipe": {"stills": "tba"}})
        rjob = jobs._find(rj["id"])
        rjob["state"] = "failed"
        r = jobs.requeue(rj["id"], reroll={"stills": [key_s], "clips": [key_c], "seed": 2})
        check(not os.path.isdir(os.path.join(jobs.ANIM, key_c)) and glob.glob(os.path.join(jobs.ANIM, key_c + "_old*")), "re-roll moves the clip folder to <key>_old<stamp>")
        check(os.path.isfile(os.path.join(jobs.RAW, key_s + ".png")) and glob.glob(os.path.join(jobs.RAW, key_s + "_old*.png")) and key_s in r["spec"]["keys"] and "--keys=" + key_s in r["plan"]["argv"],
              "re-roll copies the still aside and passes --keys: %s" % r["plan"]["argv"])
        check(r["spec"]["seed"] == 2 and "--seed=2" in r["plan"]["argv"] and r["spec"]["recipe"]["anim_seed"] == 1 and calls[-1][0] == "set_recipe" and calls[-1][4].get("anim_seed") == 1,
              "re-roll bumps anim_seed in the recipe (written through the hook) and passes --seed=2")
        check(r["attempt"] == 2 and r["state"] == "queued" and r["reroll"]["moved"], "re-roll: attempt 2, queued, the moved paths listed")

        # ---- recover(): a running job is interrupted, a live pid tree killed, a leftover launch file deleted
        lj = jobs.enqueue("launch", {}, {"character": "solenne"})
        ljob = jobs._find(lj["id"])
        ljob["state"], ljob["pid"] = "running", 999999
        rjob["state"], rjob["pid"] = "running", 999998
        open(jobs.LAUNCH_FILE, "w").write("{}")
        changed = jobs.recover()
        check(set(changed) == {lj["id"], rj["id"]} and ljob["state"] == "interrupted" and rjob["state"] == "interrupted" and ljob["pid"] is None,
              "recover() marks running jobs interrupted: %s" % changed)
        check(not os.path.isfile(jobs.LAUNCH_FILE), "recover() deletes a leftover debug_launch.json")
        check(jobs.requeue(lj["id"])["state"] == "queued", "an interrupted job requeues")
        # a queue file with a running job of a live pid: recover kills the tree
        sleeper = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        ljob["state"], ljob["pid"] = "running", sleeper.pid
        jobs.recover()
        time.sleep(0.5)
        check(sleeper.poll() is not None, "recover() kills a still-running job's process tree")
        if sleeper.poll() is None:
            sleeper.kill()

        # ---- stale locks: a dead pid is reclaimed, a bare mkdir lock is kept
        os.makedirs(os.path.join(locks.LOCK_DIR, "comfy.lock"), exist_ok=True)
        json.dump({"pid": 999999, "who": "a dead script", "since": time.time() - 100, "beat": time.time() - 100}, open(os.path.join(locks.LOCK_DIR, "comfy.lock", "owner.json"), "w"))
        os.makedirs(os.path.join(locks.LOCK_DIR, "godot.lock"), exist_ok=True)
        got = jobs.reclaim_stale_locks()
        check(got == ["comfy"] and not os.path.isdir(os.path.join(locks.LOCK_DIR, "comfy.lock")), "a lock whose owner pid is dead is reclaimed: %s" % got)
        check(os.path.isdir(os.path.join(locks.LOCK_DIR, "godot.lock")) and locks.status("godot")["owner_file"] is False and locks.status("godot")["who"] == "unknown process",
              "a lock without owner.json is kept and reads 'unknown process'")
        os.rmdir(os.path.join(locks.LOCK_DIR, "godot.lock"))
        st = jobs.status()
        check(all(k in st for k in ("queued", "running", "waiting", "lanes", "locks", "blender", "qa_online")) and st["locks"]["comfy"] is None, "status() has the contract's keys: %s" % sorted(st))

        # ---- the launch flow on a stand-in for Godot: the file is written before the spawn and removed after
        lj = jobs.enqueue("launch", {}, {"character": "solenne", "look": "SOL-B"})
        ljob = jobs._find(lj["id"])
        ljob["plan"]["steps"] = [[sys.executable, "-c", "import os, sys, json; print('launch file seen:', os.path.isfile(sys.argv[1]), json.load(open(sys.argv[1]))['character'])", jobs.LAUNCH_FILE]]
        ljob["state"] = "running"
        live = jobs.Live(ljob)
        os.makedirs(os.path.join(jobs.JOBS_DIR, ljob["id"]), exist_ok=True)
        live.logf = open(os.path.join(jobs.JOBS_DIR, ljob["id"], "log.txt"), "a", encoding="utf-8", newline="\n")
        rc = jobs._run_launch(ljob, ljob["plan"], live)
        live.logf.close()
        logtxt = open(os.path.join(jobs.JOBS_DIR, ljob["id"], "log.txt"), encoding="utf-8").read()
        check(rc == 0 and "launch file seen: True solenne" in logtxt and not os.path.isfile(jobs.LAUNCH_FILE), "launch: the file is there for the game and gone after: %s" % logtxt.strip().splitlines()[-2:])
        check(os.path.isfile(os.path.join(locks.SAVE_DIR, "save.json")) and open(os.path.join(locks.SAVE_DIR, "save.json")).read() == '{"fake": 1}' and not os.path.isfile(locks.RESTORE_PENDING),
              "launch keeps the PC save aside and puts it back")
        jobs._after_exit(ljob, rc, live)
        check(ljob["state"] == "done" and ljob["progress"]["stage"] == "the window closed", "a closed window ends the launch job done")

        # ---- asset_job.py --dry-run: a temp copy of the Blue Slime with a stub look, cached stills, nothing to ComfyUI
        _dry_run_check(check, tmp)
    finally:
        for k, v in saved.items():
            setattr(jobs, k, v)
        for k, v in saved_locks.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._root, cur = saved_state
        jobs._lane_current.update(cur)
        jobs._live.clear()
        shutil.rmtree(tmp, ignore_errors=True)


def _seed_content(content):
    folder = os.path.join(content, "enemies", "testbeast")
    os.makedirs(folder)
    d = {"id": "testbeast", "name": "Test Beast", "hp": 10.0, "damage": 3, "frame_px": 128, "variant_base": "TB-0",
         "variants": {"TB-0": {"note": "base"}, "TB-A": {"note": "a look"}}, "art_prompt": "a goofy beast"}
    json.dump(d, open(os.path.join(folder, "testbeast.json"), "w", encoding="utf-8", newline="\n"), indent=2)


def _dry_run_check(check, tmp):
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        check(True, "asset_job dry run skipped: numpy/Pillow not in this interpreter")
        return
    src = os.path.join(ROOT, "game", "content", "enemies", "blue_slime", "blue_slime.json")
    raw = os.path.join(ROOT, "tools", "dl", "ai_raw_anime")
    if not os.path.isfile(src) or not all(os.path.isfile(os.path.join(raw, "blue_slime_sla1_" + v + ".png")) for v in ("front", "back", "dead")):
        check(True, "asset_job dry run skipped: the Blue Slime or its cached stills are not on this PC")
        return
    folder = os.path.join(tmp, "copy", "enemies", "blue_slime")
    os.makedirs(folder)
    d = json.load(open(src, encoding="utf-8"))
    d["variants"]["SL-X"] = {"note": "lane J's dry run", "recipe": {"stills": "sla1", "walk": "hop", "death": "squash", "art_prompt": d["variants"]["SL-A"]["recipe"].get("art_prompt", d.get("art_prompt", ""))}}
    jp = os.path.join(folder, "blue_slime.json")
    json.dump(d, open(jp, "w", encoding="utf-8", newline="\n"), indent=2)
    before = open(jp, "rb").read()
    job_dir = os.path.join(tmp, "jobs", "jdry")
    os.makedirs(job_dir)
    json.dump({"tool": "gen_art", "call": "process", "type": "enemies", "folder": folder, "id": "blue_slime",
               "argv": ["--no-import", "--only", "blue_slime", "--variant=SL-X", "--skip-qa"],
               "env": {"ASSET_JOB_SIDECAR": os.path.join(job_dir, "result.json")},
               "equiv": "python tools/gen_art.py --no-import --only blue_slime --variant=SL-X --skip-qa"},
              open(os.path.join(job_dir, "job.json"), "w"), indent=1)
    t0 = time.time()
    p = subprocess.run([sys.executable, "-u", os.path.join(ROOT, "tools", "asset_job.py"), job_dir, "--dry-run"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", cwd=ROOT, timeout=300, env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    out = p.stdout.splitlines()
    check(p.returncode == 0, "asset_job --dry-run exits 0 (%.0f s): %s" % (time.time() - t0, (p.stdout + p.stderr).strip().splitlines()[-3:]))
    check(out and out[0] == "equiv: python tools/gen_art.py --no-import --only blue_slime --variant=SL-X --skip-qa", "the first line is equiv: %s" % (out[:1]))
    res_p = os.path.join(job_dir, "result.json")
    res = json.load(open(res_p, encoding="utf-8")) if os.path.isfile(res_p) else {}
    check(res.get("variant") == "SL-X" and res.get("entry", {}).get("sprite") == "blue_slime_sprite_x.png" and res["entry"].get("icon") == "blue_slime_icon_x.png"
          and set(res["entry"]) >= {"anims", "strip_cols", "fps", "head"}, "result.json carries the entry gen_art would have written: %s" % sorted(res.get("entry", {})))
    check(res.get("info", {}).get("clip_kind", {}).get("front") == "procedural" and res["info"]["clip_kind"].get("die") == "procedural" and res["info"].get("recipe_ran", {}).get("walk") == "hop",
          "the sidecar's info says procedural clips and the recipe that ran: %s" % res.get("info", {}).get("clip_kind"))
    check(open(jp, "rb").read() == before, "the content JSON's bytes never changed")
    check(os.path.isfile(os.path.join(folder, "blue_slime_sprite_x.png")) and os.path.isfile(os.path.join(folder, "blue_slime_icon_x.png")) and os.path.isfile(os.path.join(folder, "blue_slime_x_ai.json")),
          "the strip, the icon and the _ai.json marker land in the (copy) folder")
    dr_p = os.path.join(job_dir, "dry_run.json")
    dr = json.load(open(dr_p, encoding="utf-8")) if os.path.isfile(dr_p) else {}
    renders = [x for x in dr.get("prompts", []) if x.get("kind") == "render"]
    check([x["key"] for x in renders] == ["blue_slime_sla1_front", "blue_slime_sla1_back", "blue_slime_sla1_dead"] and all(x.get("prompt") for x in renders),
          "dry_run.json records the three stills' words: %s" % [x.get("key") for x in renders])
    check(not any(x.get("kind") == "comfy.run" for x in dr.get("prompts", [])), "nothing was sent to ComfyUI (no comfy.run recorded)")
