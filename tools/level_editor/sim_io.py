"""The Sim tab's routes (pass 77, lane SIMUI). server.py hands /api/sim/... here (api_get / api_post with the handler and
the server module), as it does the boss attacks. The sims themselves are tools/sim_batch.py runs, queued as jobs of
kind "sim" (jobs.py: their own lane, never the Godot lock); this module lists them, serves their results, starts one
(only from the Run sim button: POST /api/sim/run), keeps or deletes one, and cancels one.

    GET  /api/sim/settings        the form's choices and defaults, the last settings, the PC's processors, the measured
                                  speed, the saved map's revision, the sim lock
    POST /api/sim/settings        {settings}: the form's draft remembered (tools/dl/sim/settings.json)
    POST /api/sim/run             {settings}: checked, remembered, queued as a "sim" job (409 while one is queued or runs)
    GET  /api/sim/status          the sim queued or running now (its job and its progress.json), the sim lock
    GET  /api/sim/history         the last sims (head.json or progress.json each), newest first: the newest 10 + kept ones
    GET  /api/sim/result/<id>     a sim's result.json as written
    POST /api/sim/<id>/keep       {keep: true|false}: a kept sim is never pruned from the history
    POST /api/sim/<id>/delete     the sim's folder removed (refused while it runs)
    POST /api/sim/<id>/cancel     the job cancelled (a shell's sim: its driver's process tree killed)
    POST /api/sim/unlock          {force}: the sim lock released when its owner is gone (force: whoever holds it)
    POST /api/sim/watch           {settings}: the Watch (pass 80, tools/watch.py) started with the tab's hero, board, seed
                                  and bot, not waited for (409 while a Watch is open)
    GET  /api/sim/overlay?map=<id>[&id=<sim>][&top=N]   pass 84 (lane SIMVIEW): the newest finished Sim of the map (or the
                                  one asked for) on the map's clock for the Timeline (overlay.json, or worked out from an
                                  older sim's players); always 200: {ok: false, reason} when there is none
"""
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if os.path.join(ROOT, "tools") not in sys.path:
    sys.path.insert(0, os.path.join(ROOT, "tools"))
import sim_batch as SB  # noqa: E402

ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
ACTIVE = ("queued", "running")
HISTORY_N = 10


def _rel(path):
    try:
        return os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:   # another drive (a test's temporary folder)
        return path.replace("\\", "/")


def _game(srv):
    return getattr(srv, "GAME", SB.GAME)


def heroes(srv):
    """[{id, name, hidden}] of game/content/characters (the hidden ones last)."""
    base = os.path.join(_game(srv), "content", "characters")
    out = []
    if not os.path.isdir(base):
        return out
    for cid in sorted(os.listdir(base)):
        d = SB.read_json(os.path.join(base, cid, cid + ".json"), tries=1)
        if not isinstance(d, dict):
            continue
        hidden = str(d.get("availability") or "") == "hidden" or bool(d.get("hidden"))
        out.append({"id": cid, "name": str(d.get("name") or cid), "hidden": hidden, "order": d.get("order", 100)})
    out.sort(key=lambda h: (h["hidden"], h["order"] if isinstance(h["order"], (int, float)) else 100, h["id"]))
    return out


def talents(srv):
    """The Upgrade board's eight talents in the order the presets fill them: [{id, name, flavour, forms [{name, text}],
    ranks}] from game/content/talents."""
    out = []
    for tid in SB.TALENT_ORDER:
        d = SB.read_json(os.path.join(_game(srv), "content", "talents", tid, tid + ".json"), tries=1) or {}
        forms = [{"name": str(f.get("name") or ("AB"[i])), "text": str(f.get("text") or "")} for i, f in enumerate(d.get("forms") or [])][:2]
        while len(forms) < 2:
            forms.append({"name": "AB"[len(forms)], "text": ""})
        out.append({"id": tid, "name": str(d.get("name") or tid.capitalize()), "flavour": str(d.get("flavour") or ""), "forms": forms,
                    "ranks": int(d.get("ranks") or SB.MAX_RANK), "preset_form": SB.TALENT_FORMS[tid]})
    return out


def speed_words(sp, caps):
    """One line on why a sim takes the time it does, from the measured speed."""
    ppw = float(sp.get("play_per_wall") or 2.5)
    k = int(sp.get("workers") or 6)
    run25 = (1500.0 / ppw + float(sp.get("boot_s") or 18.0)) / 60.0
    return ("A sim plays the real game frame by frame (60 frames to a second of play, every rule), headless: on this PC a "
            "run plays about %.1fx faster than real time while %d play side by side%s, so a 25:00 run takes about %d minutes; "
            "the runs play several at once." % (ppw, k, " (measured)" if sp.get("measured") else " (a first guess)", round(run25))
            + (" The runner skips the purely visual work (its sim mode)." if caps.get("fast") else ""))


def maps(srv):
    try:
        return srv.list_maps()
    except Exception:
        return [{"id": "red_canyon", "name": "Red Canyon", "file": ""}]


def _jobs(srv):
    m = srv.jobs_module() if hasattr(srv, "jobs_module") else None
    return m


def sim_jobs(srv):
    """The jobs of kind "sim" (public records), oldest first; [] when the jobs module is not here."""
    m = _jobs(srv)
    if m is None:
        return []
    try:
        lst = m.list()
    except Exception:
        return []
    return [j for j in (lst.get("jobs") or []) if j.get("kind") == "sim"]


def _job_sim_id(j):
    plan = j.get("plan") or {}
    if plan.get("sim_id"):
        return str(plan["sim_id"])
    if plan.get("sim_out"):
        return os.path.basename(str(plan["sim_out"]))
    return ""


def active_job(srv):
    for j in reversed(sim_jobs(srv)):
        if j.get("state") in ACTIVE:
            return j
    return None


def _sim_path(sid):
    if not sid or not ID_RE.match(sid) or sid in (".", ".."):
        return None
    p = os.path.join(SB.runs_dir(), sid)
    return p if os.path.isdir(p) else None


def _state_of(sid, prog, head, job):
    """running | queued | done | partial | stopped | failed | cancelled."""
    if job is not None and job.get("state") in ACTIVE:
        return job["state"]
    ps = (prog or {}).get("state")
    if ps in ("starting", "waiting", "syncing", "importing", "running", "aggregating") and SB.locks.pid_alive((prog or {}).get("driver_pid")):
        return "running"
    if job is not None and job.get("state") in ("cancelled", "interrupted"):
        return "cancelled"
    meta = (head or {}).get("meta") or {}
    summ = (head or {}).get("summary") or {}
    if head and not meta.get("partial"):
        return "done" if summ.get("ok") else "failed"
    if ps == "cancelled":
        return "cancelled"
    if ps == "failed" or (job is not None and job.get("state") == "failed"):
        return "failed" if not head else "partial"
    if head:
        return "partial"
    return "stopped"


def history_record(srv):
    jobs_by = {}
    for j in sim_jobs(srv):
        sid = _job_sim_id(j)
        if sid:
            jobs_by[sid] = j
    out = []
    n = 0
    names = {h["id"]: h["name"] for h in heroes(srv)}   # a sim without its result yet still says the hero's name
    for r in SB.list_sims():
        sid = r["id"]
        if not r["kept"]:
            n += 1
            if n > HISTORY_N:
                continue
        head = SB.read_json(os.path.join(r["path"], "head.json"), tries=2)
        prog = SB.read_json(os.path.join(r["path"], "progress.json"), tries=2) or {}
        job = jobs_by.get(sid)
        meta = (head or {}).get("meta") or {}
        settings = (head or {}).get("settings") or prog.get("settings") or SB.read_json(os.path.join(r["path"], "settings.json"), tries=1) or {}
        out.append({"id": sid, "state": _state_of(sid, prog, head, job), "kept": r["kept"], "job": (job or {}).get("id") or prog.get("job") or meta.get("job", ""),
                    "started": meta.get("started") or prog.get("started") or SB._now_iso(r["started"]), "started_epoch": r["started"],
                    "ended": meta.get("ended", ""), "wall_s": meta.get("wall_s") or prog.get("elapsed_s"), "settings": settings,
                    "hero_name": (head or {}).get("hero_name") or names.get(settings.get("hero", ""), settings.get("hero", "")), "summary": (head or {}).get("summary") or {},
                    "map_rev": meta.get("map_rev") or {}, "version": meta.get("version", ""), "partial": bool(meta.get("partial")),
                    "players_done": meta.get("players_done", prog.get("done", 0)), "players_total": meta.get("players_total", prog.get("total", settings.get("players"))),
                    "has_result": head is not None, "synthetic": bool(meta.get("synthetic") or prog.get("synthetic")), "T": (head or {}).get("T"),
                    "bosses": (head or {}).get("bosses") or [], "board_words": _board_words(settings),
                    "death_words": SB.death_label(settings.get("death", "")),
                    "bot_words": SB.bot_words(settings.get("bot")) if settings.get("bot") else "",
                    # the runs drew everything: the sim mode switched off, or a runner from before it
                    "drawn": meta.get("sim_mode") is False or (meta.get("sim_mode") is None and settings.get("fast") is False)})
    return {"ok": True, "sims": out, "keep": HISTORY_N}


def status_record(srv):
    """The sim queued or running now: its job (when it came from the queue), its progress.json, the sim lock."""
    job = active_job(srv)
    sid = _job_sim_id(job) if job else ""
    prog = None
    if sid:
        p = _sim_path(sid)
        prog = SB.read_json(os.path.join(p, "progress.json"), tries=2) if p else None
    if job is None:
        # a sim started from a shell (python tools/sim_batch.py): its driver alive
        for r in SB.list_sims():
            if r["running"]:
                sid = r["id"]
                prog = SB.read_json(os.path.join(r["path"], "progress.json"), tries=2)
                break
    m = _jobs(srv)
    ro = None
    try:
        ro = (m.status() or {}).get("readonly") if m is not None else None
    except Exception:
        ro = None
    lk = SB.lock_status()
    return {"ok": True, "job": job, "sim_id": sid, "progress": prog, "lock": lk, "jobs": m is not None, "readonly": ro,
            "now": time.time()}


def settings_record(srv):
    saved = SB.read_json(SB.settings_file(), tries=2)
    hs = heroes(srv)
    ms = maps(srv)
    revs = {}
    for mp in ms:
        try:
            revs[mp["id"]] = SB.map_rev(_game(srv), mp["id"])
        except Exception:
            revs[mp["id"]] = {}
    caps = SB.runner_caps(_game(srv))
    save_board, save_note = SB.save_board()
    sp = SB.load_speed()
    return {"ok": True, "defaults": SB.DEFAULTS, "saved": saved if isinstance(saved, dict) else None,
            "boards": [{"value": v, "label": lab} for v, lab in SB.BOARDS],
            # round 2: the board talent by talent, its presets (difficulty_probe's), Garry's own from the PC save
            "talents": talents(srv), "presets": [{"key": key, "label": SB.board_label(m), "board": m, "talents": SB.board_talents(m)} for key, m in SB.PRESETS]
            + ([{"key": "save", "label": "my save", "board": -1, "talents": save_board}] if save_board is not None else []),
            "save_note": save_note, "max_rank": SB.MAX_RANK, "caps": caps,
            # the death policies the runner knows (a policy it does not know would make every run fail)
            "deaths": [{"value": k, "label": lab, "help": h} for k, lab, h in SB.DEATHS if not caps.get("deaths") or k in caps["deaths"]],
            "deaths_all": [{"value": k, "label": lab, "help": h, "runner": not caps.get("deaths") or k in caps["deaths"]} for k, lab, h in SB.DEATHS],
            "auto_workers": SB.auto_workers(SB.DEFAULTS["players"]), "speed_words": speed_words(sp, caps),
            "heroes": hs, "maps": ms, "map_revs": revs, "cores": SB.cores(), "max_workers": SB.max_workers(), "max_players": SB.MAX_PLAYERS,
            "limit_min": SB.LIMIT_MIN, "limit_max": SB.LIMIT_MAX, "speed": sp, "lock": SB.lock_status(),
            # the speed with the runner's sim mode off (the Drawing switch), for the page's ETA
            "speed_off": SB.load_speed(fast=False) if caps.get("fast") else None,
            "snapshot": {"exists": os.path.isdir(os.path.join(SB.snap_game(), ".godot")), "path": _rel(SB.snap_game())},
            "runner": os.path.isfile(os.path.join(_game(srv), "tools", "sim_run.gd")), "dps_window": SB.DPS_WINDOW, "history_keep": HISTORY_N,
            # pass 80 (lane BOT): the bot's presets (their values read off game/tools/bot/Bot.gd) and options
            "bot": bot_record(srv)}


def bot_record(srv):
    """The Sim tab's Bot group: {default, presets [{key, label, help, values}], keys [{key, kind, lo, hi, step, choices,
    label, help}]} (tools/sim_batch.py BOT_PRESETS / BOT_KEYS; the values are the runner's own Bot.gd PRESETS)."""
    pv = SB.bot_presets(_game(srv))
    keys = []
    for k, kind, lo, hi, label, help_ in SB.BOT_KEYS:
        row = {"key": k, "kind": kind, "label": label, "help": help_}
        if kind == "float":
            row.update({"lo": lo, "hi": hi, "step": 5 if k == "stray" else (0.1 if k == "reaction" else 0.05)})
        elif kind == "enum":
            row["choices"] = list(lo)
        keys.append(row)
    return {"default": "explorer", "presets": [{"key": k, "label": lab, "help": h, "values": pv.get(k, {})} for k, lab, h in SB.BOT_PRESETS],
            "keys": keys}


def _check(srv, raw):
    hs = {h["id"] for h in heroes(srv)}
    ms = {m["id"] for m in maps(srv)}
    return SB.clean_settings(raw, heroes=hs or None, maps=ms or None)


def _board_words(settings):
    t = settings.get("talents")
    if not isinstance(t, dict):
        t = SB.board_talents(float(settings.get("board", 0) or 0))
    return SB.board_text(t, settings.get("board_label") or "")


def save_settings(srv, raw):
    s, probs = _check(srv, raw)
    SB.write_json(SB.settings_file(), s, indent=1)
    return {"ok": True, "settings": s, "problems": probs}


def run(srv, raw, title=None):
    """Queue a sim (the Run sim button): (status, body)."""
    s, probs = _check(srv, raw)
    if probs:
        return 400, {"ok": False, "error": "; ".join(probs), "problems": probs}
    if not os.path.isfile(os.path.join(_game(srv), "tools", "sim_run.gd")):
        return 409, {"ok": False, "error": "game/tools/sim_run.gd is not in this checkout: nothing could play the runs"}
    why = SB.caps_problem(s, SB.runner_caps(_game(srv)))
    if why:
        return 409, {"ok": False, "error": why}
    act = active_job(srv)
    if act is not None:
        return 409, {"ok": False, "error": "a sim is already %s (#%s): one at a time" % (act.get("state"), str(act.get("id"))[-4:]), "job": act}
    SB.write_json(SB.settings_file(), s, indent=1)
    if not hasattr(srv, "jobs_call"):
        return 503, {"ok": False, "error": "this server has no job queue"}
    st, body = srv.jobs_call("enqueue", "sim", {"kind": "sim", "id": s["map"], "code": ""}, s, title)
    if st == 200 and isinstance(body, dict) and body.get("job"):
        body["sim_id"] = _job_sim_id(body["job"])
    return st, body


def keep(sid, flag):
    p = _sim_path(sid)
    if not p:
        return 404, {"ok": False, "error": "no sim %s" % sid}
    f = os.path.join(p, "kept")
    if flag:
        with open(f, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(time.strftime("%Y-%m-%dT%H:%M:%S") + "\n")
    elif os.path.isfile(f):
        os.remove(f)
    return 200, {"ok": True, "id": sid, "kept": bool(flag)}


def delete(srv, sid):
    p = _sim_path(sid)
    if not p:
        return 404, {"ok": False, "error": "no sim %s" % sid}
    prog = SB.read_json(os.path.join(p, "progress.json"), tries=2) or {}
    job = next((j for j in sim_jobs(srv) if _job_sim_id(j) == sid), None)
    if _state_of(sid, prog, SB.read_json(os.path.join(p, "head.json"), tries=1), job) in ("running", "queued"):
        return 409, {"ok": False, "error": "the sim %s is running: cancel it first" % sid}
    shutil.rmtree(p, ignore_errors=True)
    return 200, {"ok": not os.path.isdir(p), "id": sid}


def cancel(srv, sid):
    p = _sim_path(sid)
    job = next((j for j in sim_jobs(srv) if _job_sim_id(j) == sid), None)
    if job is not None and job.get("state") in ACTIVE:
        return srv.jobs_call("cancel", job["id"])
    if not p:
        return 404, {"ok": False, "error": "no sim %s" % sid}
    prog = SB.read_json(os.path.join(p, "progress.json"), tries=2) or {}
    pid = prog.get("driver_pid")
    if prog.get("state") in ("starting", "waiting", "syncing", "importing", "running", "aggregating") and SB.locks.pid_alive(pid) \
            and time.time() - float(prog.get("beat") or 0) < 120:
        SB.kill_tree(pid)
        return 200, {"ok": True, "id": sid, "killed": pid}
    return 409, {"ok": False, "error": "the sim %s is not running" % sid}


def unlock(force):
    st = SB.lock_status()
    if st is None:
        return 200, {"ok": True, "lock": None}
    if st.get("owner_file") and st.get("alive") and not force:
        return 409, {"ok": False, "error": "the sim lock is held by %s (pid %s), which is alive: send force to release it anyway" % (st.get("who"), st.get("pid")), "lock": st}
    ok = SB.lock_force_release()
    return (200 if ok else 409), {"ok": ok, "lock": SB.lock_status()}


def watch_args(s):
    """The Watch's command line (tools/watch.py) for the Sim tab's settings `s` (cleaned): the hero, the board talent by
    talent, the seed, the map, Down!'s answer and the bot's options."""
    t = s.get("talents") if isinstance(s.get("talents"), dict) and s.get("talents") else SB.board_talents(float(s.get("board", 0) or 0))
    args = ["--hero", str(s.get("hero", "drifter")), "--talents", SB.talents_arg(t), "--seed", str(int(s.get("seed", 1) or 1)),
            "--map", str(s.get("map", "red_canyon")), "--death", str(s.get("death", "end")), "--stage", str(int(s.get("stage", 1) or 1))]
    for k, v in (s.get("bot") or {}).items():
        args += ["--bot", "%s=%s" % (k, ("1" if v else "0") if isinstance(v, bool) else ("%g" % v if isinstance(v, float) else str(v)))]
    return args


def watch(srv, raw):
    """The Watch button (pass 80, lane WATCH): tools/watch.py started with the tab's hero, board, seed and bot, not waited
    for (it refreshes its snapshot and opens a window). 409 while a Watch is open: one at a time."""
    s, probs = _check(srv, raw)
    if probs:
        return 400, {"ok": False, "error": "; ".join(probs), "problems": probs}
    if not os.path.isfile(os.path.join(ROOT, "tools", "watch.py")):
        return 409, {"ok": False, "error": "tools/watch.py is not in this checkout"}
    import watch as W   # tools/watch.py (pass 80): its lock
    st = W.lock_status()
    if st is not None and st.get("alive"):
        return 409, {"ok": False, "error": "a Watch is open already (pid %s): close its window first" % st.get("pid")}
    import subprocess
    logs = os.path.join(W.WATCH_DIR, "logs")
    os.makedirs(logs, exist_ok=True)
    log = os.path.join(logs, "launch_%s.log" % time.strftime("%Y%m%d-%H%M%S"))
    cmd = [sys.executable, os.path.join(ROOT, "tools", "watch.py")] + watch_args(s)
    flags = (subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "DETACHED_PROCESS", 0x8)) if os.name == "nt" else 0
    with open(log, "w", encoding="utf-8", newline="\n") as lf:
        p = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=lf, stderr=subprocess.STDOUT, creationflags=flags, close_fds=True)
    return 200, {"ok": True, "pid": p.pid, "log": _rel(log), "args": watch_args(s),
                 "message": "the Watch is starting (its snapshot refreshes first; the window opens in a few seconds)"}


# ---------------------------------------------------------------- the Timeline's overlay (pass 84, lane SIMVIEW)

OVERLAY_TOP = 8          # creatures kept by name in alive_by / alive_hell_by; the rest folded into "__other"
OVERLAY_TOP_MAX = 30
_OV_CACHE = {}


def _player_files(folder):
    pdir = os.path.join(folder, "players")
    if not os.path.isdir(pdir):
        return []
    return sorted(f for f in os.listdir(pdir) if re.match(r"^p\d+\.json$", f))


def overlay_of(folder):
    """(overlay, how) of a sim folder: its overlay.json ("result"), else worked out from its players' files ("players":
    a sim from before pass 84), cached until a file changes; (None, "") when there is nothing to show."""
    p = os.path.join(folder, "overlay.json")
    files = _player_files(folder)
    try:
        stamp = (os.path.getmtime(p) if os.path.isfile(p) else 0.0,
                 tuple((f, os.path.getmtime(os.path.join(folder, "players", f))) for f in files))
    except OSError:
        stamp = None
    hit = _OV_CACHE.get(folder)
    if hit is not None and stamp is not None and hit[0] == stamp:
        return hit[1], hit[2]
    ov, how = None, ""
    if os.path.isfile(p):
        ov = SB.read_json(p, tries=3)
        how = "result" if isinstance(ov, dict) else ""
    if not isinstance(ov, dict) and files:
        ps = []
        for f in files:
            d, _ = SB.load_player(os.path.join(folder, "players", f))
            ps.append((int(f[1:-5]), d, {}))
        ov = SB.overlay(ps)
        how = "players" if ov else ""
    if stamp is not None:
        _OV_CACHE[folder] = (stamp, ov, how)
    return ov, how


def fold_by(block, field, top):
    """A breakdown {order, <field>: {id: [values]}} cut to its first `top` ids, the rest summed second by second into
    "__other" (their ids in other_ids)."""
    order = list((block or {}).get("order") or [])
    vals = (block or {}).get(field) or {}
    keep, rest = order[:top], order[top:]
    out = {"order": list(keep), field: {i: vals.get(i) for i in keep}, "other_ids": rest}
    if rest:
        n = max(len(vals.get(i) or []) for i in rest)
        other = []
        for c in range(n):
            s = None
            for i in rest:
                a = vals.get(i) or []
                if c < len(a) and a[c] is not None:
                    s = (s or 0.0) + a[c]
            other.append(SB._r(s))
        out["order"].append("__other")
        out[field]["__other"] = other
    return out


def _finished(r):
    """A sim folder's head.json when it is a finished sim (not running, not partial, at least one run), else None."""
    if r.get("running"):
        return None
    head = SB.read_json(os.path.join(r["path"], "head.json"), tries=2)
    if not isinstance(head, dict):
        return None
    meta = head.get("meta") or {}
    if meta.get("partial") or not (head.get("summary") or {}).get("ok"):
        return None
    return head


def overlay_record(srv, query):
    """GET /api/sim/overlay?map=<id>[&id=<sim>][&top=N]: the newest finished, real (not made-up) Sim of the map, or the
    sim asked for, as the Timeline's overlay (status_SIMVIEW.md "OVERLAY READY"); {ok: false, reason} when none."""
    q = query or {}
    map_id = str((q.get("map") or ["red_canyon"])[0] or "red_canyon")
    sid = str((q.get("id") or [""])[0] or "")
    try:
        top = max(1, min(OVERLAY_TOP_MAX, int((q.get("top") or [OVERLAY_TOP])[0])))
    except (TypeError, ValueError):
        top = OVERLAY_TOP
    pick = None
    if sid:
        folder = _sim_path(sid)
        if folder is None:
            return {"ok": False, "reason": "no sim %s" % sid}
        r = next((x for x in SB.list_sims() if x["id"] == sid), {"id": sid, "path": folder, "running": False})
        head = SB.read_json(os.path.join(folder, "head.json"), tries=2)
        if r.get("running"):
            return {"ok": False, "reason": "sim %s is still running" % sid}
        if not isinstance(head, dict):
            return {"ok": False, "reason": "sim %s has no result yet" % sid}
        pick = (r, head)
    else:
        for r in SB.list_sims():
            head = _finished(r)
            if head is None:
                continue
            st = head.get("settings") or {}
            if str(st.get("map") or "red_canyon") != map_id or (head.get("meta") or {}).get("synthetic"):
                continue
            pick = (r, head)
            break
        if pick is None:
            return {"ok": False, "reason": "no finished Sim of %s yet: run one from the Sim tab" % map_id}
    r, head = pick
    ov, how = overlay_of(r["path"])
    if not ov:
        return {"ok": False, "reason": "sim %s has no runs with a clock to show" % r["id"]}
    meta = head.get("meta") or {}
    st = head.get("settings") or {}
    summ = head.get("summary") or {}
    smap = str(st.get("map") or "red_canyon")
    rev = meta.get("map_rev") or {}
    now = SB.map_rev(_game(srv), smap)
    sha = rev.get("sha", "") if isinstance(rev, dict) else ""
    sim = {"id": r["id"], "started": meta.get("started", ""), "hero": st.get("hero", ""), "hero_name": head.get("hero_name") or st.get("hero", ""),
           "players": summ.get("players"), "ok_players": summ.get("ok"), "board_words": _board_words(st),
           "bot_words": SB.bot_words(st.get("bot")) if st.get("bot") else "", "death": st.get("death", ""), "limit": st.get("limit"),
           "map": smap, "map_rev": sha, "map_rev_now": now.get("sha", ""), "stale": bool(sha) and sha != now.get("sha", ""),
           "map_saved": rev.get("saved", "") if isinstance(rev, dict) else "", "version": meta.get("version", ""),
           "synthetic": bool(meta.get("synthetic")), "partial": bool(meta.get("partial")), "computed": how}
    out = dict(ov)
    out["alive_by"] = fold_by(ov.get("alive_by"), "mean", top)
    out["alive_hell_by"] = fold_by(ov.get("alive_hell_by"), "mean", top)
    ids = set(ov.get("life_by", {}).keys()) | set((ov.get("alive_by") or {}).get("order") or []) | set((ov.get("alive_hell_by") or {}).get("order") or [])
    ids |= {b.get("id") for b in ov.get("bosses") or []} | {d.get("killer") for d in ov.get("deaths") or []}
    for row in ov.get("rows") or []:
        if isinstance(row.get("enemy"), str):
            ids.add(row["enemy"])
    names = SB.content_names(_game(srv), {i for i in ids if i})
    names["__other"] = "Other"
    out["names"] = names
    out["top"] = top
    return {"ok": True, "sim": sim, "overlay": out}


# ---------------------------------------------------------------- the routes

def api_get(h, srv, parts, query):
    if parts == ["settings"]:
        return h._send(200, settings_record(srv))
    if parts == ["status"]:
        return h._send(200, status_record(srv))
    if parts == ["history"]:
        return h._send(200, history_record(srv))
    if parts == ["overlay"]:   # pass 84 (lane SIMVIEW): the Timeline's overlay
        return h._send(200, overlay_record(srv, query))
    if len(parts) == 2 and parts[0] == "result":
        p = _sim_path(parts[1])
        f = os.path.join(p, "result.json") if p else None
        if not f or not os.path.isfile(f):
            return h._error(404, "no result for sim %s (yet)" % parts[1])
        for i in range(10):
            try:
                with open(f, "rb") as fh:
                    data = fh.read()
                return h._send(200, data, "application/json; charset=utf-8")
            except OSError:
                time.sleep(0.05)
        return h._error(503, "the result is being written: try again")
    return h._error(404, "unknown sim API path")


def api_post(h, srv, parts):
    data, err = h._body()
    if err and err != "no body":
        return h._error(400, err)
    data = data if isinstance(data, dict) else {}
    if parts == ["settings"]:
        return h._send(200, save_settings(srv, data.get("settings") or data))
    if parts == ["run"]:
        st, body = run(srv, data.get("settings") or data, data.get("title"))
        return h._send(st, body)
    if parts == ["unlock"]:
        st, body = unlock(bool(data.get("force")))
        return h._send(st, body)
    if parts == ["watch"]:   # pass 80 (lane WATCH): the Watch button
        st, body = watch(srv, data.get("settings") or data)
        return h._send(st, body)
    if len(parts) == 2 and ID_RE.match(parts[0]):
        sid, op = parts
        if op == "keep":
            st, body = keep(sid, bool(data.get("keep", True)))
        elif op == "delete":
            st, body = delete(srv, sid)
        elif op == "cancel":
            st, body = cancel(srv, sid)
        else:
            return h._error(404, "unknown sim op %s" % op)
        return h._send(st, body)
    return h._error(404, "unknown sim API path")


def dumps(obj):
    return json.dumps(obj, ensure_ascii=False)
