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
import urllib.error
import urllib.parse

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

    def set_look_files(kind, cid, code, files):
        calls.append(("set_look_files", kind, cid, code, dict(files)))
        jp, d = _load(kind, cid)
        e = (d.get("variants") or {}).get(code)
        if not isinstance(e, dict):
            return {"ok": False, "layout": "unmerged", "error": "no look %s" % code}
        e.update(files)
        _dump(jp, d)
        return {"ok": True, "layout": "entry", "backup": "fake.bak"}

    return {"content_path": content_path, "merge_look": merge_look, "merge_top": merge_top, "set_recipe": set_recipe,
            "look_records": look_records, "set_look_files": set_look_files, "redump_merge": lambda *a: {"ok": False, "error": "not in the fake"}}


def checks(check, run_node, server):
    import locks
    before = threading.active_count()
    import jobs
    check(threading.active_count() == before, "importing jobs starts no thread (%d -> %d)" % (before, threading.active_count()))
    tmp = tempfile.mkdtemp(prefix="le_jobs_")
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
        # pass 66 follow-up: every workflow a job runs also lands in the ComfyUI page's Workflows sidebar; the card's
        # "open in ComfyUI" link; Send to ComfyUI for the ones a run did not push
        check(jobs._user_folder({"id": "jX", "kind": "look", "target": {"kind": "enemy", "id": "dust_mummy", "code": "DM-E"}}) == "dust_mummy_DM-E/jX"
              and jobs._user_folder({"id": "jY", "kind": "hero_badge", "target": {"kind": "hero", "id": "drifter"}}) == "drifter_hero_badge/jY", "the sidebar folder names the look (id_CODE) or the job's kind, then the job (a re-roll never overwrites the earlier copies)")
        check(jobs._comfy_open_url("workflows/88fits/a b/x.json") == jobs.COMFY_SERVER.rstrip("/") + "/?open=workflows%2F88fits%2Fa%20b%2Fx.json", "the open link carries the user-data path, url-encoded: %s" % jobs._comfy_open_url("workflows/88fits/a b/x.json"))
        wd = os.path.join(jobs.JOBS_DIR, j["id"], "workflows")
        os.makedirs(wd, exist_ok=True)
        with open(os.path.join(wd, "01_test_workflow.json"), "w", encoding="utf-8") as fh:
            json.dump({"nodes": [], "links": []}, fh)
        with open(os.path.join(wd, "01_test_api.json"), "w", encoding="utf-8") as fh:
            json.dump({"1": {"class_type": "SaveImage", "inputs": {}}}, fh)
        jb = jobs._find(j["id"])
        h = [o for o in jobs._harvest(jb) if o["type"] == "workflow"]
        check(len(h) == 1 and h[0]["label"] == "01_test" and "open_url" not in h[0] and h[0]["url"].endswith("/workflows/01_test_workflow.json"), "a workflow without a sidebar marker has the file link and no open link: %s" % h)
        check(jobs._workflows_sig(jb) == ("01_test_workflow.json",), "the workflows signature lists the graph files: %s" % (jobs._workflows_sig(jb),))
        put = []
        real_put = jobs._comfy_put_userdata
        jobs._comfy_put_userdata = lambda p, o, timeout=30: (put.append(p), {"path": p, "size": 1})[1]
        try:
            res = jobs.push_workflows(j["id"])
        finally:
            jobs._comfy_put_userdata = real_put
        upath = "workflows/88fits/testbeast_TB-A/%s/01_test.json" % j["id"]
        check(res["pushed"] == [upath] and not res["push_errors"] and put == res["pushed"], "push_workflows saves each unsent workflow under workflows/88fits/<id_CODE>/<job>/: %s %s" % (res["pushed"], res["push_errors"]))
        h = [o for o in res["outputs"] if o["type"] == "workflow"]
        check(len(h) == 1 and h[0].get("userdata") == upath and h[0].get("open_url", "").endswith("?open=" + urllib.parse.quote(upath, safe="")), "after the push the output carries the sidebar path and the open link: %s" % h)
        res2 = jobs.push_workflows(j["id"])
        check(res2["pushed"] == [] and not res2["push_errors"] and os.path.isfile(os.path.join(wd, "01_test_userdata.json")), "a pushed workflow is not pushed again (its marker file stays)")
        check(jobs._workflows_sig(jb) == ("01_test_userdata.json", "01_test_workflow.json"), "the signature sees the marker too: %s" % (jobs._workflows_sig(jb),))
        check(jobs._asset_env(jb).get("ASSET_JOB_NAME") == "testbeast_TB-A/" + j["id"], "the tools get the sidebar folder as ASSET_JOB_NAME: %s" % jobs._asset_env(jb).get("ASSET_JOB_NAME"))
        # a push that fails: an HTTP refusal of one file lets the next through; nothing sent at all is an error the page sees
        with open(os.path.join(wd, "02_two_workflow.json"), "w", encoding="utf-8") as fh:
            json.dump({"nodes": [], "links": []}, fh)
        with open(os.path.join(wd, "03_three_workflow.json"), "w", encoding="utf-8") as fh:
            json.dump({"nodes": [], "links": []}, fh)
        calls_put = []
        def flaky_put(p, o, timeout=10):
            calls_put.append(p)
            if p.endswith("02_two.json"):
                raise urllib.error.HTTPError(p, 500, "boom", {}, None)
            return {"path": p}
        jobs._comfy_put_userdata = flaky_put
        try:
            res = jobs.push_workflows(j["id"])
        finally:
            jobs._comfy_put_userdata = real_put
        check(len(calls_put) == 2 and res["pushed"] == ["workflows/88fits/testbeast_TB-A/%s/03_three.json" % j["id"]] and len(res["push_errors"]) == 1 and "HTTP 500" in res["push_errors"][0],
              "an HTTP refusal is recorded and the next file still goes: %s %s" % (res["pushed"], res["push_errors"]))
        os.remove(os.path.join(wd, "03_three_userdata.json"))
        jobs._comfy_put_userdata = lambda p, o, timeout=10: (_ for _ in ()).throw(urllib.error.URLError("down"))
        try:
            try:
                jobs.push_workflows(j["id"])
                check(False, "nothing sent raises")
            except RuntimeError as e:
                check("nothing was sent" in str(e) and "did not answer" in str(e), "nothing sent is an error the page sees (jobs_call 409): %s" % e)
        finally:
            jobs._comfy_put_userdata = real_put
        for f in ("02_two_workflow.json", "03_three_workflow.json"):
            os.remove(os.path.join(wd, f))
        # a phantom holder of the jobs lock is told from a live editor by its port
        check(jobs._holder_is_editor({"owner_file": False}) is False and jobs._holder_is_editor({"owner_file": True, "alive": False, "pid": 1}) is False, "no owner record or a dead pid = a phantom")
        check(jobs._holder_is_editor({"owner_file": True, "alive": True, "pid": os.getpid(), "note": "the Level Editor that runs the job queue (port 1)"}) is False, "a live pid whose port does not answer as a Level Editor = a phantom")
        check(jobs._holder_is_editor({"owner_file": True, "alive": True, "pid": os.getpid(), "note": ""}) is True, "an older record without a port: a live pid is trusted")
        # a running job of another live editor is never killed: the claimant goes read-only instead
        other = os.getppid()
        saved_jobs = jobs._state["jobs"]
        try:
            jobs._state["jobs"] = saved_jobs + [{"id": "jF", "kind": "look", "lane": "comfy", "state": "running", "server_pid": other, "started": jobs._now(), "pid": 0, "progress": {}, "spec": {}, "target": {}}]
            fr = jobs._foreign_runner()
            check(bool(fr) and fr.get("pid") == other and fr.get("job") == "jF" and isinstance(fr.get("since"), float), "a running job whose server_pid is another live process is a foreign runner: %s" % fr)
            jobs._state["jobs"][-1]["server_pid"] = os.getpid()
            check(jobs._foreign_runner() is None, "a running job taken by this process is not foreign")
            jobs._state["jobs"][-1]["server_pid"] = 999999
            check(jobs._foreign_runner() is None, "a running job whose server is dead is an orphan for recover(), not a foreign runner")
            del jobs._state["jobs"][-1]["server_pid"]
            jobs._state["jobs"][-1]["pid"] = other
            fr = jobs._foreign_runner()
            check(bool(fr) and fr.get("pid") == other, "an older record (no server_pid) whose own process is alive counts as foreign: %s" % fr)
        finally:
            jobs._state["jobs"] = saved_jobs
        check(jobs._epoch("2026-10-11T15:56:22") is not None and jobs._epoch(12.5) == 12.5 and jobs._epoch("") is None, "_epoch reads floats and ISO texts")
        # one Level Editor runs the queue (the `jobs` lock, claimed by init): a second one is read-only
        check(jobs._queue_lock is not None and not jobs.is_readonly() and locks.status("jobs") and locks.status("jobs")["pid"] == os.getpid(), "init claims the jobs lock for this process: %s" % (locks.status("jobs"),))
        check(jobs.claim_queue() is None and jobs.status().get("readonly") is None, "a second claim by the holder is a no-op; status says not read-only")
        saved_ro, saved_sig = jobs._readonly, jobs._disk_sig
        jobs._readonly = {"who": "level_editor", "pid": 4242, "since": time.time() - 60}
        try:
            try:
                jobs.enqueue("look", {"kind": "enemy", "id": "testbeast", "code": "TB-Z"}, {"method": "creature_free2"})
                check(False, "a read-only editor refuses enqueue")
            except ValueError as e:
                check("another Level Editor runs the job queue" in str(e) and "4242" in str(e), "a read-only editor refuses enqueue and names the holder: %s" % e)
            for fn, args in ((jobs.cancel, (j["id"],)), (jobs.move, (j["id"], 1)), (jobs.push_workflows, (j["id"],)), (jobs.delete, (j["id"],))):
                try:
                    fn(*args)
                    check(False, "read-only refuses %s" % fn.__name__)
                except ValueError:
                    check(True, "read-only refuses %s" % fn.__name__)
            rev_before = jobs._state["rev"]
            mt_before = os.path.getmtime(jobs.QUEUE_FILE)
            check(jobs._save() == rev_before and os.path.getmtime(jobs.QUEUE_FILE) == mt_before, "a read-only editor never writes queue.json")
            check(jobs.status().get("readonly", {}).get("pid") == 4242 and jobs.start_workers() == [], "status names the holder; start_workers starts nothing")
            # the read-only editor follows the file: another writer's queue appears on the next list()
            with open(jobs.QUEUE_FILE, "r", encoding="utf-8") as fh:
                orig_text = fh.read()
            q = json.loads(orig_text)
            q["rev"] = 777
            q["jobs"].append({"id": "jOTHER", "kind": "import", "state": "queued", "title": "from the other editor", "target": {}, "spec": {}, "progress": {}, "outputs": []})
            time.sleep(0.05)
            with open(jobs.QUEUE_FILE, "w", encoding="utf-8") as fh:
                json.dump(q, fh)
            jobs._disk_sig = None
            lst = jobs.list()
            check(lst["rev"] == 777 and any(x["id"] == "jOTHER" for x in lst["jobs"]), "a read-only editor shows the queue as the other one writes it: rev %s" % lst["rev"])
        finally:
            jobs._readonly, jobs._disk_sig = saved_ro, saved_sig
            with open(jobs.QUEUE_FILE, "w", encoding="utf-8") as fh:   # the queue as it was before the fake writer
                fh.write(orig_text)
            jobs._load()
        st = jobs.comfy_extension_state(max_age=10 ** 9) if jobs._ext_state["at"] else None
        check(st is None or set(st) >= {"installed", "checked", "server"}, "the extension state record has installed / checked / server")
        ext_dir = os.path.join(ROOT, "tools", "comfy_ext", "88fits_open")
        check(os.path.isfile(os.path.join(ext_dir, "__init__.py")) and os.path.isfile(os.path.join(ext_dir, "js", "open_workflow.js")), "the 88fits_open extension is in the repo (tools/comfy_ext)")
        ns = {}
        with open(os.path.join(ext_dir, "__init__.py"), "r", encoding="utf-8") as fh:
            exec(fh.read(), ns)
        check(ns.get("WEB_DIRECTORY") == "./js" and ns.get("NODE_CLASS_MAPPINGS") == {}, "the extension pack declares WEB_DIRECTORY ./js and no nodes")
        node = shutil.which("node")
        if node:
            tmpm = os.path.join(tempfile.gettempdir(), "open_workflow_check.mjs")
            shutil.copyfile(os.path.join(ext_dir, "js", "open_workflow.js"), tmpm)
            p = subprocess.run([node, "--check", tmpm], capture_output=True, text=True, timeout=60)
            check(p.returncode == 0, "the extension's JS parses as a module: %s" % p.stderr.strip()[:200])
            with open(os.path.join(ext_dir, "js", "open_workflow.js"), "r", encoding="utf-8") as fh:
                ext_src = fh.read()
            check('get(PARAM)' in ext_src and 'PARAM = "open"' in ext_src and "app.loadGraphData(" in ext_src and "/userdata/" in ext_src, "the extension reads ?open=, fetches the user-data file and loads it")
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

        # ---- pass 68: new looks and their seeds, the re-roll modes, the honest painter, the candidates' defaults,
        # the per-look picks, the job's own choices
        _p68_checks(check, jobs, tmp, content, calls)
        # ---- the pass 68 review's fixes: the base look's own front, spent keys, the re-roll stamp on edit, held jobs and
        # the worker's order, a picked icon kept by a recolour
        _review_checks(check, jobs, tmp, content, calls)

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


def _jdump(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=2)


def _jload(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _touch(path, t=None, data=b"png"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    if t is not None:
        os.utime(path, (t, t))


def _seed_p68(content, jobs):
    """Pass 68's temp content: a creature with old and new looks (an own slug, a shared slug, a stub), a hero with its
    base, a painted look and a draft, a hero the title tool's tables know (dad), an item with a 3D render."""
    _jdump(os.path.join(content, "enemies", "p68beast", "p68beast.json"), {
        "id": "p68beast", "name": "P68 Beast", "art_prompt": "a lumpy p68 beast with a spiky tail, standing on its hind legs",
        "motion": "waddling", "placeholder": {"color": "#AA4422"}, "variant_base": "PB-0",
        "variants": {"PB-0": {"note": "base"},
                     "PB-A": {"note": "a", "sprite": "p68beast_sprite_a.png", "recipe": {"motion": "stomping"}},
                     "PB-B": {"note": "b", "sprite": "p68beast_sprite_b.png", "recipe": {"stills": "b"}},
                     "PB-C": {"sprite": "p68beast_sprite_c.png", "recipe": {"stills": "pbshared"}},
                     "PB-D": {"sprite": "p68beast_sprite_d.png", "recipe": {"stills": "pbshared"}},
                     "PB-G": {"sprite": "p68beast_sprite_g.png", "recipe": {"stills": "c"}},
                     "PB-H": {"sprite": "p68beast_sprite_h.png", "recipe": {"motion": "hopping"}},
                     "PB-E": {"note": "a stub", "recipe": {"art_prompt": "a lumpy p68 beast"}}}})
    _jdump(os.path.join(content, "characters", "testhero", "testhero.json"), {
        "id": "testhero", "name": "Test Hero", "art_prompt": "a lanky test hero in a red cape; standing straight, both arms relaxed at his sides",
        "portrait_prompt": "winking at the viewer", "screen": "blue", "variant_base": "TH-A",
        "variants": {"TH-A": {"note": "base"},
                     "TH-B": {"note": "b", "sprite": "testhero_sprite_b.png", "recipe": {"pose_drivers": {"back": "run_occ"}}},
                     "TH-C": {"note": "a draft", "recipe": {"method": "hero_pose5", "from": "TH-B", "art_prompt": "a lanky test hero in a blue cape"}}}})
    _jdump(os.path.join(content, "characters", "dad", "dad.json"), {"id": "dad", "name": "Dad", "art_prompt": "a goofy dad, a proud smile"})
    _jdump(os.path.join(content, "weapons", "p68gun", "p68gun.json"), {"id": "p68gun", "name": "P68 Gun", "art_prompt": "a shiny brass ray gun"})
    for key in ("testhero_front", "dad_front", "p68beast_front", "p68beast_back", "p68beast_dead"):
        _touch(os.path.join(jobs.RAW, key + ".png"))
        _touch(os.path.join(jobs.RAW, key + ".json"), data=b"{}")
    _touch(os.path.join(jobs.DL, "p68gun_ref.png"))


def _p68_checks(check, jobs, tmp, content, calls):
    import zlib
    _seed_p68(content, jobs)
    pb = os.path.join(content, "enemies", "p68beast", "p68beast.json")
    th = os.path.join(content, "characters", "testhero", "testhero.json")
    B = {"kind": "enemy", "id": "p68beast"}
    H = {"kind": "hero", "id": "testhero"}

    # ---- D2: a new look gets its own slug and its own seeds; an existing look keeps the paintings it was made from
    sp = jobs.validate_spec("look", {"method": "creature_free2", "recipe": {}})
    jobs._seed_recipe(dict(B, code="PB-N"), sp)
    r = sp["recipe"]
    check(r.get("stills") == "n" and r.get("seed_offset") == 1 + zlib.crc32(b"PB-N") % 9973 and r.get("method") == "creature_free2"
          and r.get("art_prompt", "").startswith("a lumpy") and r.get("motion") == "waddling",
          "D2: a new creature look: its letter as the slug, seed_offset 1 + crc32(code) %% 9973, the method, the base's words: %s" % r)
    sp2 = jobs.validate_spec("look", {"method": "creature_free2", "recipe": {}})
    jobs._seed_recipe(dict(B, code="PB-M"), sp2)
    check(sp2["recipe"]["seed_offset"] != r["seed_offset"], "D2: two new looks with the same words get different seed offsets (DM-E/DM-F painted the same front)")
    sp = jobs.validate_spec("look", {"method": "creature_free2", "recipe": {"stills": "", "seed_offset": 7}})
    jobs._seed_recipe(dict(B, code="PB-N"), sp)
    check(sp["recipe"]["stills"] == "" and sp["recipe"]["seed_offset"] == 7, "D2: a new look's explicit '' (reuse the paintings) and its own seed_offset are kept: %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "creature_free2", "recipe": {"motion": "stomping"}})
    jobs._seed_recipe(dict(B, code="PB-A"), sp)
    check(sp["recipe"].get("stills") == "" and "seed_offset" not in sp["recipe"], "D2: an existing look (a sprite) gets stills '' (its own paintings), never a letter, and no seed_offset: %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "creature_pose2", "recipe": {}})
    jobs._seed_recipe(dict(B, code="PB-0"), sp)
    check(sp["recipe"].get("stills") == "" and "seed_offset" not in sp["recipe"], "D2: the base strip's own code is an existing look: %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "creature_free2", "recipe": {"stills": None}})
    jobs._seed_recipe(dict(B, code="PB-E"), sp)
    check(sp["recipe"]["stills"] == "e" and sp["recipe"]["seed_offset"] == 1 + zlib.crc32(b"PB-E") % 9973, "D2: a stub (no sprite yet) is a new look; a None slug counts as absent: %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "hero_pose5", "recipe": {}})
    jobs._seed_recipe(dict(H, code="TH-N"), sp)
    check(sp["recipe"].get("stills") == "n" and sp["recipe"].get("seed_offset") and "art_prompt" not in sp["recipe"] and sp["recipe"]["method"] == "hero_pose5",
          "D1/D2: a new hero_pose5 look gets its own slug and seeds (a hero's words stay the hero's): %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "hero_pose5", "recipe": {"pose_drivers": {"back": "run_occ"}}})
    jobs._seed_recipe(dict(H, code="TH-B"), sp)
    check(sp["recipe"].get("stills") == "" and "seed_offset" not in sp["recipe"], "D2: an existing hero look (FAD-B, MAM-B, MAM-C) keeps the hero's own paintings: %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "hero_fit", "recipe": {"method": "hero_pose5", "pose_drivers": {"back": "x"}}})
    jobs._seed_recipe(dict(H, code="TH-N"), sp)
    check(sp["recipe"]["method"] == "hero_fit" and "stills" not in sp["recipe"] and "seed_offset" not in sp["recipe"],
          "D2: hero_fit never gets a slug; the method that runs is the one recorded (the form had changed it): %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "front_from_picture", "stills": "pbx", "ref": "x.png", "prompt": "a beast", "recipe": {"method": "front_from_picture"}})
    jobs._seed_recipe(dict(B, code="PB-X"), sp)
    check("method" not in sp["recipe"] and "stills" not in sp["recipe"], "D2: front_from_picture records no method (it paints a front for the look job after it): %s" % sp["recipe"])
    sp = jobs.validate_spec("look", {"method": "recolour", "recipe": {"recolour": {"from": "PB-A", "to": 300}}})
    jobs._seed_recipe(dict(B, code="PB-R"), sp)
    check(sp["recipe"].get("method") == "recolour" and "painter" not in sp["recipe"] and sp.get("recolour", {}).get("from") == "PB-A",
          "a recolour records its method, no painter; the form's recipe.recolour reaches the plan's spec.recolour: %s" % sp["recipe"])
    check(jobs.implied_method("hero", {"pose_drivers": {"back": "x"}, "still_keys": {"side": "y"}}) == "hero_fit" and jobs.implied_method("hero", {}) == "hero_pose5"
          and jobs.implied_method("enemy", {"drivers": "d"}) == "creature_ctl" and jobs.implied_method("enemy", {}, {"walk": "hop"}) == "creature_proc"
          and jobs.implied_method("enemy", {"pose": "walk"}) == "creature_pose2" and jobs.implied_method("enemy", {"directions": 8}) == "creature_free8"
          and jobs.implied_method("enemy", {"method": "recolour"}) == "recolour" and jobs.implied_method("boss", {}) == "creature_free2",
          "implied_method follows the page's Assets.methodOf")
    # D1: a hero look's keys follow its slug; still_keys still win; no slug = the hero's own
    ck = jobs.cache_keys("hero_pose5", {"recipe": {"stills": "n"}}, dict(H, code="TH-N"))
    check(ck["stills"][:5] == ["testhero_n_front", "testhero_n_back", "testhero_n_side", "testhero_n_fd", "testhero_n_bd"] and "testhero_n_hurt_side" in ck["stills"]
          and ck["stills"][-1] == "testhero_n_dead" and ck["clips"][0] == "testhero_thn_pose_run_back", "D1: a hero look with a slug keys <id>_<slug>_<view>: %s" % ck["stills"][:3])
    ck = jobs.cache_keys("hero_pose5", {"recipe": {"stills": "n", "still_keys": {"side": "testhero_s9_side"}}}, dict(H, code="TH-N"))
    check("testhero_s9_side" in ck["stills"] and "testhero_n_front" in ck["stills"], "D1: still_keys still win per view")
    ck = jobs.cache_keys("hero_pose5", {"recipe": {"stills": ""}}, dict(H, code="TH-B"))
    check(ck["stills"][0] == "testhero_front", "D1: stills '' = the hero's own paintings")

    # ---- D3: the re-roll modes, applied once at enqueue
    stamp_keys = ("p68beast_front", "p68beast_back", "p68beast_dead")
    before = {k: os.path.getmtime(os.path.join(jobs.RAW, k + ".png")) for k in stamp_keys}
    _touch(os.path.join(jobs.RAW, "p68beast_a_front.png"))   # a leftover under the slug PB-A is about to get
    n0 = len(calls)
    j = jobs.enqueue("look", dict(B, code="PB-A"), {"method": "creature_free2", "recipe": {"motion": "stomping"}, "reroll": {"mode": "stills"}})
    rec = j["spec"]["recipe"]
    check(rec["stills"] == "a" and rec["seed_offset"] == 1 + zlib.crc32(b"PB-A") % 9973 and j["spec"]["reroll"].get("applied"),
          "D3 stills: a look that shared the creature's paintings gets its own slug and seeds: %s" % {k: rec.get(k) for k in ("stills", "seed_offset")})
    check(all(os.path.getmtime(os.path.join(jobs.RAW, k + ".png")) == before[k] for k in stamp_keys) and not glob.glob(os.path.join(jobs.RAW, "p68beast_front_old*"))
          and not glob.glob(os.path.join(jobs.RAW, "p68beast_back_old*")), "D3 stills: the shared paintings are never touched")
    check(j["spec"]["keys"] == ["p68beast_a_front"] and "--keys=p68beast_a_front" in j["plan"]["argv"] and glob.glob(os.path.join(jobs.RAW, "p68beast_a_front_old*.png"))
          and j.get("reroll", {}).get("moved"), "D3 stills: a leftover painting under the new slug is copied aside and painted again: %s" % j["spec"].get("keys"))
    w = [c for c in calls[n0:] if c[0] == "set_recipe" and c[3] == "PB-A"]
    check(w and w[-1][4].get("stills") == "a" and w[-1][4].get("seed_offset") == rec["seed_offset"] and _jload(pb)["variants"]["PB-A"]["recipe"]["stills"] == "a",
          "D3: the re-roll's recipe goes through set_recipe like any recipe")
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b"}, "reroll": {"mode": "stills"}})
    check(j["spec"]["recipe"]["stills"] == "b" and j["spec"]["recipe"]["seed_offset"] == 1 and j["spec"]["keys"] == ["p68beast_b_front", "p68beast_b_back", "p68beast_b_dead"],
          "D3 stills: a look with its own slug: seed_offset + 1 and its stills forced: %s %s" % (j["spec"]["recipe"].get("seed_offset"), j["spec"]["keys"]))
    j = jobs.enqueue("look", dict(B, code="PB-C"), {"method": "creature_free2", "recipe": {"stills": "pbshared"}, "reroll": {"mode": "stills"}})
    check(j["spec"]["recipe"]["stills"] == "c2" and j["spec"]["recipe"]["seed_offset"] == 1 + zlib.crc32(b"PB-C") % 9973 and j["spec"]["keys"] == [],
          "D3 stills: a slug another look names is shared: a slug of its own (its letter is PB-G's, so c2): %s" % j["spec"]["recipe"]["stills"])
    for key in ("p68beast_pbb_walk_f", "p68beast_pbb_walk_b"):
        os.makedirs(os.path.join(jobs.ANIM, key), exist_ok=True)
        _touch(os.path.join(jobs.ANIM, key, "cycle.json"), data=b"{}")
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b", "anim_seed": 2}, "reroll": {"mode": "clips"}})
    check(j["spec"]["recipe"]["anim_seed"] == 3 and not j["spec"].get("keys") and not os.path.isdir(os.path.join(jobs.ANIM, "p68beast_pbb_walk_f"))
          and len(glob.glob(os.path.join(jobs.ANIM, "p68beast_pbb_walk_*_old*"))) == 2 and "seed_offset" not in j["spec"]["recipe"],
          "D3 clips: the clip folders moved aside, anim_seed + 1, the stills kept: %s" % j["spec"]["recipe"])
    os.makedirs(os.path.join(jobs.ANIM, "p68beast_pbb_walk_f"), exist_ok=True)
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b", "seed_offset": 4}, "reroll": {"mode": "seeds"}})
    check(j["spec"]["recipe"]["seed_offset"] == 5 and j["spec"]["recipe"]["anim_seed"] == 1 and len(j["spec"]["keys"]) == 3 and not os.path.isdir(os.path.join(jobs.ANIM, "p68beast_pbb_walk_f")),
          "D3 seeds: the stills and the clips again: %s" % j["spec"]["recipe"])
    jid = j["id"]
    e = jobs.edit(jid, spec={"skip_qa": True})
    check(e["spec"]["recipe"]["seed_offset"] == 5 and e["spec"]["recipe"]["anim_seed"] == 1, "D3: an edit does not apply the same re-roll again")
    e = jobs.edit(jid, spec={"reroll": {"mode": "clips"}})
    check(e["spec"]["recipe"]["anim_seed"] == 2 and e["spec"]["reroll"].get("applied"), "D3: an edit with a new re-roll applies it (and the recipe is written)")
    check(calls[-1][0] == "set_recipe" and calls[-1][4].get("anim_seed") == 2, "D3: the edit's re-roll recipe went through set_recipe")
    cj = jobs.enqueue("look", {"kind": "enemy", "id": "p68beast", "code": "PB-K"}, {"method": "creature_ctl", "recipe": {"drivers": "d"}, "use_view": "fd:c1", "reroll": {"mode": "view", "view": "fd,back"}})
    check(cj["spec"]["view_cands"] == "fd,back" and cj["spec"]["use_view"] == "" and "--view-cands=fd,back" in cj["plan"]["argv"], "D3 view: creature_ctl's view candidates: %s" % cj["plan"]["argv"])
    for method, mode, extra, what in (("creature_free2", "view", {"view": "fd"}, "a view re-roll on a gen_art look"),
                                      ("hero_fit", "stills", {}, "hero_fit stills (the hero's own paintings)"),
                                      ("creature_ctl", "seeds", {}, "creature_ctl seeds"),
                                      ("creature_proc", "clips", {}, "creature_proc clips (procedural)"),
                                      ("creature_ctl", "view", {"view": "up"}, "a view that is not a view"),
                                      ("creature_free2", "banana", {}, "an unknown mode")):
        tgt = dict(H, code="TH-B") if method == "hero_fit" else dict(B, code="PB-B")
        try:
            jobs.enqueue("look", tgt, {"method": method, "recipe": {"drivers": "d"} if method == "creature_ctl" else {}, "reroll": dict({"mode": mode}, **extra)})
            check(False, "D3 refuses %s" % what)
        except ValueError as ex:
            check(True, "D3 refuses %s: %s" % (what, ex))

    # a job card's still re-roll (requeue) on a look that shares the creature's paintings forks them: never repaints them
    hj = jobs.enqueue("look", dict(B, code="PB-H"), {"method": "creature_free2", "recipe": {"motion": "hopping"}})
    check(hj["spec"]["recipe"]["stills"] == "" and hj["cache_keys"]["stills"] == ["p68beast_front", "p68beast_back", "p68beast_dead"], "PB-H is painted from the creature's own paintings")
    jobs._find(hj["id"])["state"] = "failed"
    shared_before = {k: os.path.getmtime(os.path.join(jobs.RAW, k + ".png")) for k in stamp_keys}
    n0 = len(calls)
    rq = jobs.requeue(hj["id"], reroll={"stills": ["p68beast_back"]})
    rr = rq.get("reroll") or {}
    check(rq["spec"]["recipe"]["stills"] == "h" and rq["spec"]["recipe"]["seed_offset"] == 1 + zlib.crc32(b"PB-H") % 9973 and rq["spec"]["keys"] == ["p68beast_h_back"]
          and "--keys=p68beast_h_back" in rq["plan"]["argv"] and rq["cache_keys"]["stills"] == ["p68beast_h_front", "p68beast_h_back", "p68beast_h_dead"],
          "requeue's still re-roll on a shared look: a slug of its own, only the asked still painted (under the new key): %s" % rq["spec"].get("keys"))
    check(os.path.isfile(os.path.join(jobs.RAW, "p68beast_h_front.png")) and os.path.isfile(os.path.join(jobs.RAW, "p68beast_h_dead.json"))
          and not os.path.isfile(os.path.join(jobs.RAW, "p68beast_h_back.png")) and rr.get("fork", {}).get("forked") == "h" and sorted(rr["fork"]["copied"]) == ["p68beast_h_dead", "p68beast_h_front"],
          "the paintings it keeps are copied under its own keys: %s" % rr.get("fork"))
    check(all(os.path.getmtime(os.path.join(jobs.RAW, k + ".png")) == shared_before[k] for k in stamp_keys) and not glob.glob(os.path.join(jobs.RAW, "p68beast_back_old*")),
          "the shared paintings are never touched by a look's re-roll")
    check(any(c[0] == "set_recipe" and c[3] == "PB-H" and c[4].get("stills") == "h" for c in calls[n0:]), "the fork's recipe is written through set_recipe")

    # ---- D4: the honest painter at a look's landing
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b"}})
    job = jobs._find(j["id"])
    t0 = time.time() - 30
    job["attempt_started"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0))
    keys = job["cache_keys"]["stills"]
    _touch(os.path.join(jobs.RAW, keys[0] + ".png"), t0 - 600)
    for k in keys[1:]:
        _touch(os.path.join(jobs.RAW, k + ".png"), t0 + 10)
    os.makedirs(os.path.join(jobs.JOBS_DIR, job["id"]), exist_ok=True)
    _jdump(os.path.join(jobs.JOBS_DIR, job["id"], "result.json"), {"entry": {"sprite": "p68beast_sprite_b.png"}, "info": {}})
    written, err = jobs._post(job)
    p = _jload(pb)["variants"]["PB-B"]["recipe"]["painter"]
    check(not err and p.get("stills") == "2 of 3 painted" and p.get("reused") == [keys[0]] and p.get("model") == "klein" and written.get("painter", {}).get("painted") == 2,
          "D4: some stills older than the attempt: painter.stills 'N of M painted' and painter.reused: %s" % p)
    for k in keys:
        os.utime(os.path.join(jobs.RAW, k + ".png"), (t0 - 600, t0 - 600))
    jobs._post(job)
    p = _jload(pb)["variants"]["PB-B"]["recipe"]["painter"]
    check(p.get("stills") == "reused" and p.get("reused") == keys, "D4: every still from the cache: painter.stills 'reused' (MAM-C said dev/32 and painted nothing): %s" % p.get("stills"))
    d = _jload(pb)
    d["variants"]["PB-B"]["recipe"]["note_by_garry"] = "kept"
    _jdump(pb, d)
    for k in keys:
        os.utime(os.path.join(jobs.RAW, k + ".png"), (t0 + 20, t0 + 20))
    n0 = len(calls)
    jobs._post(job)
    r = _jload(pb)["variants"]["PB-B"]["recipe"]
    check("stills" not in r["painter"] and "reused" not in r["painter"] and r.get("note_by_garry") == "kept",
          "D4: every still painted: no marks; the entry's recipe was read again from the file (a hand edit kept): %s" % r["painter"])
    jobs._post(job)
    check(len([c for c in calls[n0:] if c[0] == "set_recipe"]) == 1, "D4: nothing is written when the painter already says it")
    out = [o for o in jobs._harvest(job) if o.get("type") == "still"]
    check(out and not any(o.get("reused") for o in out), "the outputs mark no still reused when all were painted")
    os.utime(os.path.join(jobs.RAW, keys[0] + ".png"), (t0 - 600, t0 - 600))
    out = {o["cache_key"]: o for o in jobs._harvest(job) if o.get("type") == "still"}
    check(out[keys[0]].get("reused") is True and not out[keys[1]].get("reused"), "an output older than the attempt says reused")

    # ---- D6: the candidates' defaults
    ap = jobs.appearance_of
    check(ap("a mime, a star on her cheek; wearing overalls, white laces; standing straight, both arms relaxed at her sides") == "a mime, a star on her cheek; wearing overalls, white laces"
          and ap("a tall man, white wristbands, standing straight and facing the viewer with his arms relaxed at his sides, empty hands") == "a tall man, white wristbands"
          and ap("a lean man in a duster, standing straight with his hands relaxed at his sides") == "a lean man in a duster"
          and ap("a werewolf, long clawed arms") == "a werewolf, long clawed arms" and ap("a dad, a proud smile") == "a dad, a proud smile"
          and ap("standing straight") == "standing straight" and ap("") == "",
          "appearance_of cuts the trailing pose clause only (Mamy's ;-clause, Fadeaway's two, the Drifter's; arms that are part of the body stay)")
    d = jobs.candidate_defaults("hero_badge", dict(H, code=""))
    f = d["fields"]
    check(f["character"] == "a lanky test hero in a red cape" and f["prompt"] == "winking at the viewer" and f["ref"] == "tools/dl/ai_raw_anime/testhero_front.png"
          and f["variant"] == "" and d["ref_exists"] is True and d["ref_url"] == "/dl/ai_raw_anime/testhero_front.png" and "pose clause cut" in d["sources"]["character"],
          "D6 hero_badge, the hero's own: character without the pose, the action, the hero's front still: %s" % f)
    d = jobs.candidate_defaults("hero_badge", dict(H, code="TH-B"))
    check(d["fields"]["variant"] == "TH-B" and d["fields"]["ref"] == "tools/dl/ai_raw_anime/testhero_front.png" and "look's front still" in d["sources"]["ref"],
          "D6 hero_badge, an existing look made from the hero's paintings: its variant, the front it shares: %s" % d["fields"]["ref"])
    d = jobs.candidate_defaults("hero_title", dict(H, code="TH-C"))
    f = d["fields"]
    check(f["ref"] == "tools/dl/ai_raw_anime/testhero_c_front.png" and d["ref_exists"] is False and f["character"] == "a lanky test hero in a blue cape"
          and f["pose"] == "standing confidently in a heroic pose, full body" and f["holds"] == "no weapon" and f["camera"].startswith("facing the viewer") and f["variant"] == "TH-C",
          "D6 hero_title, a draft (new look): its own front still to come, its own words, the full-body default pose: %s" % f)
    d = jobs.candidate_defaults("hero_title", {"kind": "hero", "id": "dad", "code": ""})
    check(d["sources"]["pose"] == "gen_title_heroes POSES" and "mustache" in d["fields"]["pose"] and d["fields"]["character"] == "a goofy dad, a proud smile",
          "D6 hero_title: the tool's own POSES table when the JSON has no title_pose: %s" % d["fields"]["pose"][:40])
    d = jobs.candidate_defaults("icon_cands", dict(B, code="PB-B"))
    f = d["fields"]
    check(f["subject"].startswith("a lumpy p68 beast with a spiky tail") and "standing" not in f["subject"] and f["ref"] == "tools/dl/ai_raw_anime/p68beast_b_front.png"
          and f["file"] == "p68beast_icon_b.png" and f["screen"] == "green", "D6 icon_cands, a creature look: its words, its own front still, its own icon file: %s" % f)
    d = jobs.candidate_defaults("icon_cands", {"kind": "weapon", "id": "p68gun", "code": ""})
    check(d["fields"]["subject"] == "a shiny brass ray gun" and d["fields"]["ref"] == "tools/dl/p68gun_ref.png" and d["ref_exists"] and d["ref_url"] == "/dl/p68gun_ref.png"
          and d["fields"]["file"] == "p68gun_icon.png", "D6 icon_cands, an item: its art_prompt, its 3D render, its icon: %s" % d["fields"])
    for kind, tgt, what in (("icon_cands", dict(H, code=""), "icon_cands for a hero"), ("hero_badge", dict(B, code=""), "a badge for a creature"),
                            ("hero_title", {"kind": "hero", "id": "nobody"}, "an unknown hero"), ("item_icon", dict(H), "a kind without defaults")):
        try:
            jobs.candidate_defaults(kind, tgt)
            check(False, "candidate_defaults refuses %s" % what)
        except ValueError as ex:
            check(True, "candidate_defaults refuses %s: %s" % (what, ex))
    try:
        jobs.enqueue("icon_cands", dict(H, code=""), {"subject": "a hero"})
        check(False, "icon_cands for a hero is refused")
    except ValueError as ex:
        check("hero_badge" in str(ex), "icon_cands for a hero is refused, naming hero_badge: %s" % ex)
    # at enqueue: every empty field filled, the typed ones kept, a space left out of the command
    bj = jobs.enqueue("hero_badge", dict(H, code=""), {"seeds": 2, "prompt": "grinning", "character": " "})
    s = bj["spec"]
    check(s["prompt"] == "grinning" and s["character"] == " " and s["ref"] == "tools/dl/ai_raw_anime/testhero_front.png" and s["defaults_from"].get("ref")
          and "--character" not in bj["plan"]["argv"] and bj["plan"]["argv"][bj["plan"]["argv"].index("--ref") + 1] == "tools/dl/ai_raw_anime/testhero_front.png"
          and "--prompt" in bj["plan"]["argv"], "D6 at enqueue: empty fields filled from the defaults, typed ones kept, a lone space sends no words: %s" % bj["plan"]["argv"])
    try:
        jobs.enqueue("hero_badge", dict(H, code="TH-C"), {"seeds": 2})
        check(False, "a badge whose look has no front still and no look job queued is refused")
    except ValueError as ex:
        check("not on disk" in str(ex), "a candidate job whose reference is not on disk (and no queued look paints it) is refused: %s" % ex)
    lj = jobs.enqueue("look", dict(H, code="TH-C"), {"method": "hero_pose5", "recipe": _jload(th)["variants"]["TH-C"]["recipe"]})
    check(lj["spec"]["recipe"].get("stills") == "c" and lj["spec"]["recipe"].get("from") == "TH-B" and "testhero_c_front" in lj["cache_keys"]["stills"],
          "D5/D2: Generate on a draft: a new look, its own slug; its `from` stays a bookkeeping key: %s" % lj["spec"]["recipe"])
    bj2 = jobs.enqueue("hero_badge", dict(H, code="TH-C"), {"seeds": 3})
    tag = bj2["id"][-4:]
    check(bj2["spec"]["ref"] == "tools/dl/ai_raw_anime/testhero_c_front.png" and bj2["spec"]["variant"] == "TH-C" and bj2["spec"]["character"] == "a lanky test hero in a blue cape"
          and bj2["plan"]["argv"][:4] == ["--id", "testhero", "--seeds", "3"] and bj2["plan"]["argv"][bj2["plan"]["argv"].index("--variant") + 1] == "TH-C",
          "D10: a new look's badge job with empty words takes the look's front still (painted first by the queued look job): %s" % bj2["equiv"])
    check(bj2["cache_keys"]["stills"] == ["testhero_portrait_%s_c%d" % (tag, k) for k in range(3)] and bj2["progress"]["stages"][0]["key"] == "testhero_portrait_%s_c0" % tag
          and bj2["plan"]["tag"] == tag and bj2["plan"]["argv"][-2:] == ["--tag", bj2["id"]] and "--attempt" not in bj2["plan"]["argv"],
          "D7: badge candidates keyed by the job (<id>_portrait_<tag>_c<k>; --tag names it in the command): %s" % bj2["cache_keys"]["stills"])
    tj = jobs.enqueue("hero_title", {"kind": "hero", "id": "dad", "code": ""}, {"seeds": 2})
    jj = _jload(os.path.join(jobs.JOBS_DIR, tj["id"], "job.json"))
    check(jj["hid"] == "dad" and jj["seeds"] == 2 and jj["first"] == 11 and jj["kwargs"]["pose"] == jj["pose"] and "mustache" in jj["pose"] and jj["holds"] == "no weapon"
          and jj["ref"] == "tools/dl/ai_raw_anime/dad_front.png" and "variant" not in jj["kwargs"] and "--pose" in tj["plan"]["argv"] and "--character" in tj["equiv"],
          "D7: a title job hands paint() its words and reference by name (job.json kwargs and fields; the equiv shows the flags): %s" % sorted(jj["kwargs"]))
    ic = jobs.enqueue("icon_cands", dict(B, code="PB-B"), {"seeds": 2})
    check(ic["plan"]["icon_job"] == {"kind": "enemies", "id": "p68beast", "subject": ic["spec"]["subject"], "set": "_le_" + ic["id"], "ref": "tools/dl/ai_raw_anime/p68beast_b_front.png",
                                    "file": "p68beast_icon_b.png"} and ic["spec"]["subject"].startswith("a lumpy"),
          "D6/D7: an icon job with no words for a creature look: its words, its front still, its own icon file: %s" % ic["plan"]["icon_job"])
    try:
        jobs.enqueue("icon_cands", dict(B, code="PB-B"), {"seeds": 2, "ref": "tools/dl/uploads/2d/AnimeMimeCharacterTurnaroundSheet.png"})
        check(False, "a typed reference that is not on disk is refused")
    except ValueError as ex:
        check("AnimeMime" in str(ex), "a typed reference that is not on disk is refused at Queue: %s" % ex)
    e = jobs.edit(ic["id"], spec={"subject": "", "screen": "blue"})
    check(e["spec"]["subject"].startswith("a lumpy") and e["plan"]["icon_job"].get("screen") == "blue", "D6 at edit: an emptied field is filled again, a typed one kept")
    icj = jobs._find(ic["id"])
    icj["state"] = "failed"
    rq = jobs.requeue(ic["id"])
    jj = _jload(os.path.join(jobs.JOBS_DIR, ic["id"], "job.json"))
    check(rq["plan"]["icon_job"]["set"] == "_le_" + ic["id"] and rq["plan"]["argv"][-2:] == ["--attempt", "2"] and jj["attempt"] == 2 and "--attempt 2" in rq["equiv"],
          "D7: a re-run of an icon job is attempt 2 (the tool moves the old candidates into attempt1/ and paints new seeds): %s" % rq["plan"]["argv"])

    # ---- _choices: only this job's candidates
    bjob = jobs._find(bj2["id"])
    for k in (0, 1, 2, 3):
        _touch(os.path.join(jobs.RAW, "testhero_portrait_%s_c%d.png" % (tag, k)))
    _touch(os.path.join(jobs.RAW, "testhero_portrait_c0.png"))
    _touch(os.path.join(jobs.RAW, "testhero_portrait_%s_c1_old20261012-000000.png" % tag))
    ch = jobs._choices(bjob, "badge")
    check([c["id"] for c in ch] == ["0", "1", "2"] and all(tag in c["url"] for c in ch), "badge choices: this job's own portraits, k < seeds: %s" % [c["url"] for c in ch])
    tjob = jobs._find(tj["id"])
    tjob["spec"]["variant"] = "DAD-B"
    tt = jobs._badge_tag(tjob)
    check(tj["plan"]["argv"][-2:] == ["--tag", tj["id"]] and tj["plan"]["tag"] == tt and tj["equiv"].endswith("--tag " + tj["id"]),
          "the review: a title job's cut-outs are keyed by the job too (--tag names it in the command): %s" % tj["equiv"][-40:])
    for name in ("dad_b_%s_0.png" % tt, "dad_b_%s_1.png" % tt, "dad_b_%s_0_raw.png" % tt, "dad_b_view.png", "dad_%s_0.png" % tt, "dad_b_%s_5.png" % tt,
                 "dad_b_%s_1_old2.png" % tt, "dad_b_0.png", "dad_b_1.png", "dad_b_zzzz_0.png"):
        _touch(os.path.join(jobs.TITLE_OUT, name))
    ch = jobs._choices(tjob, "title")
    check([c["url"].rsplit("/", 1)[-1] for c in ch] == ["dad_b_%s_0.png" % tt, "dad_b_%s_1.png" % tt],
          "title choices: <id>_<x>_<tag>_<n> for n < seeds only (another job's, an untagged run's never): %s" % [c["url"] for c in ch])
    tjob["spec"]["variant"] = ""
    ch = jobs._choices(tjob, "title")
    check([c["url"].rsplit("/", 1)[-1] for c in ch] == ["dad_%s_0.png" % tt], "title choices of the hero's own job: <id>_<tag>_<n>: %s" % [c["url"] for c in ch])
    icjob = jobs._find(ic["id"])
    fold = os.path.join(jobs.DL, "icons_le_" + ic["id"])
    for name in ("p68beast_c0.png", "p68beast_c1.png", "p68beast_c7.png", "attempt1/p68beast_c0.png"):
        _touch(os.path.join(fold, *name.split("/")))
    ch = jobs._choices(icjob, "review")
    check([c["id"] for c in ch] == ["0", "1"] and all(c["url"] == "/dl/icons_le_%s/p68beast_c%s.png" % (ic["id"], c["id"]) for c in ch),
          "icon choices: the folder's own candidates, k < seeds (an earlier attempt's sit in attempt1/): %s" % [c["url"] for c in ch])

    # ---- D8: a pick for a look lands in its entry (no fresh, the strip untouched)
    bjob["state"] = "done"
    inst = jobs.install(bjob["id"], "2")
    ijob = jobs._find(inst["id"])
    env = jobs._asset_env(ijob)
    check(inst["plan"]["argv"] == ["--id", "testhero", "--pick", "2", "--variant", "TH-C", "--tag", bjob["id"]] and env["ASSET_JOB_ID"] == bjob["id"] and inst["plan"]["variant"] == "TH-C",
          "D7/D8: the badge pick names the look and the job that painted the candidates (--tag; its id as ASSET_JOB_ID): %s" % inst["plan"]["argv"])
    _jdump(os.path.join(jobs.JOBS_DIR, ijob["id"], "result.json"), {"variant": "TH-C", "entry": {"icon": "testhero_icon_c.png"}, "top": {}})
    n0 = len(calls)
    written, err = jobs._post(ijob)
    ent = _jload(th)["variants"]["TH-C"]
    check(not err and calls[n0:] and calls[n0][0] == "set_look_files" and calls[n0][4] == {"icon": "testhero_icon_c.png"} and ent["icon"] == "testhero_icon_c.png"
          and "fresh" not in ent and written["keys"] == ["variants"], "D8: a badge picked for a look lands in variants[CODE].icon without the fresh mark: %s" % ent)
    tjob["spec"]["variant"] = ""
    tj2 = jobs.enqueue("hero_title", dict(H, code="TH-B"), {"seeds": 2})
    t2 = jobs._find(tj2["id"])
    t2["state"] = "done"
    inst = jobs.install(t2["id"], "1")
    i2 = jobs._find(inst["id"])
    check(inst["plan"]["argv"] == ["--pick", "testhero=1", "--variant", "TH-B", "--tag", t2["id"]] and inst["plan"]["variant"] == "TH-B"
          and jobs._asset_env(i2)["ASSET_JOB_ID"] == t2["id"] and inst["plan"]["source_job"] == t2["id"],
          "D7: the title pick names the look and (the review) the job that painted the cut-outs (--tag; its id as ASSET_JOB_ID): %s" % inst["plan"]["argv"])
    written, err = jobs._post(i2)
    check(err and "named no file" in err, "D8: a pick that wrote nothing for the look says so: %s" % err)
    _touch(os.path.join(jobs.WANTED, "hero_testhero_b.png"))
    written, err = jobs._post(i2)
    check(not err and _jload(th)["variants"]["TH-B"].get("title") == "hero_testhero_b.png" and _jload(th)["variants"]["TH-B"].get("sprite") == "testhero_sprite_b.png",
          "D8: without a sidecar entry the cut-out the tool wrote (hero_<id>_<x>.png) lands in variants[CODE].title; the strip untouched")
    icjob["state"] = "done"
    inst = jobs.install(icjob["id"], "1")
    i3 = jobs._find(inst["id"])
    _touch(os.path.join(os.path.dirname(pb), "p68beast_icon_b.png"))
    n0 = len(calls)
    written, err = jobs._post(i3)
    check(not err and _jload(pb)["variants"]["PB-B"].get("icon") == "p68beast_icon_b.png" and calls[n0][0] == "set_look_files"
          and calls[n0][4] == {"icon": "p68beast_icon_b.png"}, "D8: an icon picked for a creature look lands in its entry's icon (the icon job's file; no fresh)")
    bb = jobs.enqueue("hero_badge", dict(H, code=""), {"seeds": 2})
    bbj = jobs._find(bb["id"])
    bbj["state"] = "done"
    inst = jobs.install(bbj["id"], "0")
    i4 = jobs._find(inst["id"])
    check(inst["plan"]["argv"] == ["--id", "testhero", "--pick", "0", "--tag", bbj["id"]], "the hero's own badge pick names no look: %s" % inst["plan"]["argv"])
    _jdump(os.path.join(jobs.JOBS_DIR, i4["id"], "result.json"), {"top": {"badge": {"still": "testhero_portrait_%s_c0" % bb["id"][-4:], "head_width": 0.0, "top_pad": 0.03}}})
    n0 = len(calls)
    written, err = jobs._post(i4)
    check(not err and calls[n0][0] == "merge_top" and _jload(th).get("badge", {}).get("still", "").startswith("testhero_portrait_"), "the hero's own badge pick writes top.badge as before")
    _jdump(os.path.join(jobs.JOBS_DIR, i4["id"], "result.json"), {"variant": "TH-A", "entry": {"icon": "testhero_icon_a.png"}, "top": {}})
    n0 = len(calls)
    written, err = jobs._post(i4)
    check(not err and calls[n0][0] == "set_look_files" and calls[n0][3] == "TH-A" and _jload(th)["variants"]["TH-A"].get("icon") == "testhero_icon_a.png",
          "D8: a sidecar that names a look and its file lands in that entry (the server follows the tool; since the review the hero tools "
          "name no base code)")
    # a badge job's re-run paints new candidates: its own are moved aside (the cache would hand them back), new seeds
    bt = bb["id"][-4:]
    for k in range(2):
        _touch(os.path.join(jobs.RAW, "testhero_portrait_%s_c%d.png" % (bt, k)))
        _touch(os.path.join(jobs.RAW, "testhero_portrait_%s_c%d.json" % (bt, k)), data=b"{}")
    bbj["state"] = "failed"
    rq = jobs.requeue(bbj["id"])
    check(not glob.glob(os.path.join(jobs.RAW, "testhero_portrait_%s_c[01].png" % bt)) and len(glob.glob(os.path.join(jobs.RAW, "testhero_portrait_%s_c*_old*.png" % bt))) == 2
          and rq["plan"]["argv"][-2:] == ["--attempt", "2"] and len(rq["reroll"]["moved"]) == 4,
          "a badge job's requeue moves its own candidates aside and runs attempt 2 (new seeds): %s" % rq["plan"]["argv"][-4:])


def _review_checks(check, jobs, tmp, content, calls):
    """The pass 68 review's server fixes: a base look's own front still and words as the candidates' defaults, forced keys
    spent at done (the card kept) and on a Re-queue after a stop, the re-roll stamp kept by the page's Save changes, held
    jobs marked and the up/down moves in the worker's order, a picked icon kept by a recolour."""
    B = {"kind": "enemy", "id": "p68beast"}
    raw = lambda k: os.path.join(jobs.RAW, k + ".png")   # noqa: E731

    # ---- a base look whose entry has a recipe (BB-C, LS-B, WW-A): its own front still and words, not <id>_front
    _jdump(os.path.join(content, "enemies", "p68ctl", "p68ctl.json"), {
        "id": "p68ctl", "name": "P68 Ctl", "art_prompt": "a chestnut beetle with dark horns, standing still", "variant_base": "PC-C",
        "variants": {"PC-C": {"note": "the base, a gen_ctl look", "sprite": "p68ctl_sprite.png",
                              "recipe": {"drivers": "beetle_walk", "screen": "blue", "prompt": "a red beetle",
                                         "art_prompt": "a red-shelled beetle with white eyes, standing still"}}}})
    C = {"kind": "enemy", "id": "p68ctl"}
    d = jobs.candidate_defaults("icon_cands", dict(C, code=""))
    check(d["fields"]["ref"] == "tools/dl/ai_raw_anime/p68ctl_front.png" and not d["ref_exists"] and "creature's front still" in d["sources"]["ref"],
          "review: a base look whose own front still is not on disk falls back to <id>_front as before: %s" % d["fields"]["ref"])
    _touch(raw("p68ctl_pcc_front"))
    for code in ("", "PC-C"):
        d = jobs.candidate_defaults("icon_cands", dict(C, code=code))
        f = d["fields"]
        check(f["ref"] == "tools/dl/ai_raw_anime/p68ctl_pcc_front.png" and d["ref_exists"] and "base look's front still" in d["sources"]["ref"]
              and f["subject"] == "a red-shelled beetle with white eyes" and "look's art_prompt" in d["sources"]["subject"]
              and f["screen"] == "blue" and d["sources"]["screen"] == "the look's screen",
              "review: the base look (code %r) of a gen_ctl creature: its own front (<id>_<codepart>_front), its recipe's words and screen: %s"
              % (code, {k: f.get(k) for k in ("ref", "subject", "screen")}))
    _jdump(os.path.join(content, "enemies", "p68wolf", "p68wolf.json"), {
        "id": "p68wolf", "name": "P68 Wolf", "art_prompt": "a grey wolf", "pose": "orc_walk_wolf", "variant_base": "PW-A",
        "variants": {"PW-A": {"sprite": "p68wolf_sprite_a.png", "recipe": {"stills": "pwa", "art_prompt": "a grey wolf"}}}})
    _touch(raw("p68wolf_pwa_front"))
    wj = jobs.enqueue("icon_cands", {"kind": "enemy", "id": "p68wolf", "code": ""}, {"seeds": 2})
    check(wj["spec"]["ref"] == "tools/dl/ai_raw_anime/p68wolf_pwa_front.png" and wj["plan"]["icon_job"].get("ref") == wj["spec"]["ref"],
          "review: a base look with a stills slug (WW-A): its own <id>_<slug>_front; Queue is no longer refused for a missing <id>_front: %s" % wj["spec"]["ref"])
    _jdump(os.path.join(content, "characters", "p68hero", "p68hero.json"), {
        "id": "p68hero", "name": "P68 Hero", "art_prompt": "a short hero in green", "variant_base": "PH-A",
        "variants": {"PH-A": {"note": "base", "recipe": {"stills": "a"}}}})
    _touch(raw("p68hero_front"))
    _touch(raw("p68hero_a_front"))
    d = jobs.candidate_defaults("hero_badge", {"kind": "hero", "id": "p68hero", "code": ""})
    check(d["fields"]["ref"] == "tools/dl/ai_raw_anime/p68hero_a_front.png" and d["fields"]["variant"] == "",
          "review: a hero's base look with a recipe: its own front still, still the hero's own badge (variant ''): %s" % d["fields"]["ref"])

    # ---- forced keys: done spends them without wiping the card; a plain Re-queue after a stop forces only what is left
    keys3 = ["p68beast_b_front", "p68beast_b_back", "p68beast_b_dead"]
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b"}, "keys": list(keys3)})
    job = jobs._find(j["id"])
    for s in job["progress"]["stages"]:
        s["state"] = "done"
    job["progress"]["stages"][0]["note"] = "cached"
    job["state"] = "running"
    jobs._finish(job, "done", save=False)
    check(job["spec"]["keys"] == [] and job["progress"]["total"] > 0 and job["progress"]["done"] == job["progress"]["total"]
          and all(s["state"] == "done" for s in job["progress"]["stages"]) and job["progress"]["stages"][0].get("note") == "cached"
          and "--keys=" + ",".join(keys3) in job["plan"]["argv"] and "--keys=" in job["equiv"],
          "review: done spends the forced keys and keeps the card (every stage done, the cached note, the command that ran): %s"
          % [s["state"] for s in job["progress"]["stages"]][:4])
    rq = jobs.requeue(j["id"])
    check(rq["spec"]["keys"] == [] and not any(a.startswith("--keys") for a in rq["plan"]["argv"]), "review: a Re-queue of a finished re-roll forces nothing")
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b"}, "keys": list(keys3)})
    job = jobs._find(j["id"])
    t0 = time.time() - 120
    job["attempt_started"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t0))
    job["state"] = "interrupted"
    _touch(raw("p68beast_b_front"), t0 + 30)    # painted again by the stopped attempt
    _touch(raw("p68beast_b_back"), t0 - 600)    # not reached: the old painting
    if os.path.isfile(raw("p68beast_b_dead")):
        os.remove(raw("p68beast_b_dead"))       # not reached, not on disk
    rq = jobs.requeue(j["id"])
    check(rq["spec"]["keys"] == ["p68beast_b_back", "p68beast_b_dead"] and "--keys=p68beast_b_back,p68beast_b_dead" in rq["plan"]["argv"],
          "review: a Re-queue after an interruption forces only the stills the stopped attempt did not repaint: %s" % rq["spec"]["keys"])
    jobs._find(j["id"])["state"] = "failed"
    rq = jobs.requeue(j["id"], reroll={"stills": ["p68beast_b_front"]})
    check(rq["spec"]["keys"] == ["p68beast_b_back", "p68beast_b_dead", "p68beast_b_front"],
          "review: an explicit still re-roll keeps the keys and adds its own: %s" % rq["spec"]["keys"])
    check(jobs._unspent_keys(keys3, None) == keys3 and jobs._unspent_keys(["", "x"], "") == ["x"], "review: an attempt that never started spent nothing")

    # ---- the page's Save changes sends its re-roll without the stamp: the same mode is not applied again
    j = jobs.enqueue("look", dict(B, code="PB-B"), {"method": "creature_free2", "recipe": {"stills": "b", "seed_offset": 8}, "reroll": {"mode": "seeds"}})
    r0 = dict(j["spec"]["recipe"])
    stamp = j["spec"]["reroll"].get("applied")
    full = json.loads(json.dumps(j["spec"]))
    full["reroll"] = {"mode": "seeds"}           # jobs.js flatten: {mode} (a view re-roll: {mode, view}), never the stamp
    full["note"] = "typed in the form"
    e = jobs.edit(j["id"], spec=full)
    check(r0["seed_offset"] == 9 and e["spec"]["recipe"]["seed_offset"] == 9 and e["spec"]["recipe"]["anim_seed"] == r0["anim_seed"]
          and e["spec"]["reroll"].get("applied") == stamp and e["spec"]["note"] == "typed in the form" and e.get("reroll") == j.get("reroll"),
          "review: Save changes with the page's whole form keeps the applied re-roll (seed_offset %s -> %s, anim_seed %s -> %s)"
          % (r0["seed_offset"], e["spec"]["recipe"]["seed_offset"], r0["anim_seed"], e["spec"]["recipe"]["anim_seed"]))
    full = json.loads(json.dumps(e["spec"]))
    full["reroll"] = {"mode": "clips"}
    e = jobs.edit(j["id"], spec=full)
    a1 = e["spec"]["recipe"]["anim_seed"]
    full = json.loads(json.dumps(e["spec"]))
    full["reroll"] = {"mode": "clips"}
    e = jobs.edit(j["id"], spec=full)
    check(a1 == r0["anim_seed"] + 1 and e["spec"]["recipe"]["anim_seed"] == a1 and e["spec"]["recipe"]["seed_offset"] == 9,
          "review: a changed mode applies once; the next Save with the same mode does not apply it again (anim_seed %s, %s)" % (a1, e["spec"]["recipe"]["anim_seed"]))
    cj = jobs.enqueue("look", dict(B, code="PB-K"), {"method": "creature_ctl", "recipe": {"drivers": "d"}, "reroll": {"mode": "view", "view": "fd,back"}})
    full = json.loads(json.dumps(cj["spec"]))
    full["reroll"] = {"mode": "view", "view": "fd,back"}
    full["use_view"] = "fd:c1"
    e = jobs.edit(cj["id"], spec=full)
    check(e["spec"]["view_cands"] == "fd,back" and e["spec"]["use_view"] == "fd:c1", "review: the same view re-roll is not applied again (the form's other fields kept)")
    full = json.loads(json.dumps(e["spec"]))
    full["reroll"] = {"mode": "view", "view": "side"}
    e = jobs.edit(cj["id"], spec=full)
    check(e["spec"]["view_cands"] == "side" and e["spec"]["use_view"] == "" and "--view-cands=side" in e["plan"]["argv"],
          "review: another view is a new re-roll, applied once: %s" % e["plan"]["argv"])

    # ---- a recolour keeps a picked icon (icon_picked and the file on disk): only the strip is recoloured
    pb = os.path.join(content, "enemies", "p68beast", "p68beast.json")
    dd = _jload(pb)
    dd["variants"]["PB-P"] = {"note": "a recolour", "sprite": "p68beast_sprite_p.png", "icon": "p68beast_icon_p.png", "icon_picked": True}
    _jdump(pb, dd)
    rp = jobs.enqueue("look", dict(B, code="PB-P"), {"method": "recolour", "recolour": {"from": "PB-A", "to": 300}})
    check(len(rp["plan"]["steps"]) == 2, "review: a picked icon whose file is not on disk is painted (nothing to keep)")
    _touch(os.path.join(os.path.dirname(pb), "p68beast_icon_p.png"))
    rp = jobs.enqueue("look", dict(B, code="PB-P"), {"method": "recolour", "recolour": {"from": "PB-A", "to": 300}})
    check(len(rp["plan"]["steps"]) == 1 and "p68beast_sprite_p.png" in " ".join(rp["plan"]["steps"][0]) and "p68beast_icon_p.png" not in rp["equiv"]
          and len(rp["progress"]["stages"]) == 1, "review: a recolour keeps the look's picked icon (only the strip step): %s" % rp["equiv"])
    dd = _jload(pb)
    dd["variants"]["PB-P"].pop("icon_picked", None)
    _jdump(pb, dd)
    rp = jobs.enqueue("look", dict(B, code="PB-P"), {"method": "recolour", "recolour": {"from": "PB-A", "to": 300}})
    check(len(rp["plan"]["steps"]) == 2 and "p68beast_icon_p.png" in rp["equiv"], "review: an icon not picked is recoloured as before")

    # ---- held jobs and the up/down moves follow the worker's order (front first, then the list; a held job skipped)
    saved_state, saved_lane = jobs._state, jobs._lane_current.get("comfy")
    jobs._state = {"rev": saved_state["rev"], "jobs": []}
    try:
        _jdump(os.path.join(content, "enemies", "p68order", "p68order.json"), {
            "id": "p68order", "name": "P68 Order", "art_prompt": "a round beast", "variant_base": "PO-0", "variants": {"PO-0": {"note": "base"}}})
        a = jobs.enqueue("item_icon", {"kind": "weapon", "id": "p68gun"}, {})
        lk = jobs.enqueue("look", {"kind": "enemy", "id": "p68order", "code": "PO-A"}, {"method": "creature_free2", "recipe": {}})
        h = jobs.enqueue("icon_cands", {"kind": "enemy", "id": "p68order", "code": "PO-A"}, {"seeds": 3})
        b = jobs.enqueue("item_icon", {"kind": "weapon", "id": "p68gun"}, {})
        f = jobs.enqueue("item_icon", {"kind": "weapon", "id": "p68gun"}, {})
        jobs._find(f["id"])["front"] = True          # a picked continuation resuming: the worker takes it first
        pub = {x["id"]: x for x in jobs.list()["jobs"]}
        check(h["spec"]["ref"] == "tools/dl/ai_raw_anime/p68order_a_front.png" and pub[h["id"]]["held"] is True
              and not any(pub[x["id"]]["held"] for x in (a, lk, b, f)) and jobs.get(h["id"])["held"] is True,
              "review: a candidate job waiting for its look's front is marked held in the list: %s" % {k[-4:]: v["held"] for k, v in pub.items()})
        ids = lambda: [x["id"] for x in jobs._state["jobs"]]   # noqa: E731
        o0 = ids()
        jobs.move(b["id"], -1)
        check(ids() == [a["id"], b["id"], h["id"], lk["id"], f["id"]], "review: up on a runnable job passes the held one and swaps with the runnable before it")
        o1 = ids()
        jobs.move(h["id"], -1)
        jobs.move(h["id"], 1)
        jobs.move(f["id"], -1)
        jobs.move(f["id"], 1)
        check(ids() == o1 and o0 != o1, "review: a held job and the only front job have no one to swap with (never across the groups)")
        jobs.move(a["id"], 1)
        check(ids() == [b["id"], a["id"], h["id"], lk["id"], f["id"]], "review: down swaps with the next runnable job")
        jobs._lane_current["comfy"] = None
        order = []
        for _ in range(4):
            nx = jobs._take_next("comfy")
            if nx is None:
                break
            order.append(nx["id"])
            jobs._lane_current["comfy"] = None
        check(order == [f["id"], b["id"], a["id"], lk["id"]], "review: the worker takes them in that order, the held job last (still waiting): %s"
              % [x[-4:] for x in order])
        _touch(raw("p68order_a_front"))
        check(jobs.get(h["id"])["held"] is False and jobs._take_next("comfy")["id"] == h["id"], "review: once the front is painted the held job runs")
    finally:
        jobs._state = saved_state
        jobs._lane_current["comfy"] = saved_lane


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
