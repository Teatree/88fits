"""Pass 80, lane WATCH: the Watch's launcher (tools/watch.py) and the Sim tab's Watch button (sim.js watchRun ->
POST /api/sim/watch -> sim_io.watch). selftest.py discovers this file (`extra_checks`) and hands it its `check` counter,
its `run_node` and the `server` module. Nothing here starts Godot or a window: the spawn is caught.

Groups: the button and the route are there; sim_io.watch_args turns the tab's settings into watch.py's options (the
Trail (pass 129; the Upgrade board talent by talent until then), the seed, the map, Down!, every bot option); the route
answers 409 while a Watch is open and otherwise starts watch.py without waiting; watch.py's own pieces (the limit's
words, the Trail argument and its old name --board, the Godot-side arguments, the newest Sim result of the same hero and
Trail for --ref auto, its lock).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


class _Srv:
    GAME = os.path.join(ROOT, "game")

    def list_maps(self):
        return [{"id": "red_canyon", "name": "Red Canyon", "file": ""}]


class _FakeProc:
    def __init__(self, cmd, **kw):
        self.cmd = cmd
        self.kw = kw
        self.pid = 4242

    def poll(self):
        return None


def checks(check, run_node, server):
    import sim_io as SIO
    import sim_batch as SB
    import watch as W

    js = _read(HERE, "sim.js")
    check("'/api/sim/watch'" in js and "watchRun" in js and "text: S.watching ? 'Opening…' : 'Watch'" in js,
          "watch80: the Sim tab's head row has the Watch button posting /api/sim/watch")
    src = _read(HERE, "sim_io.py")
    check('if parts == ["watch"]:' in src and "def watch(srv, raw)" in src, "watch80: sim_io routes POST /api/sim/watch to watch()")
    check(os.path.isfile(os.path.join(ROOT, "tools", "watch.cmd")) and "tools\\watch.py" in _read(ROOT, "tools", "watch.cmd"),
          "watch80: tools\\watch.cmd starts tools\\watch.py")
    check(os.path.isfile(os.path.join(ROOT, "game", "tools", "watch", "watch_main.gd")), "watch80: game/tools/watch/watch_main.gd is there")

    # the tab's settings as watch.py's options
    s, probs = SB.clean_settings({"hero": "calavera", "trail": "half", "seed": 7, "death": "keep", "map": "red_canyon",
                                  "bot": {"preset": "careless", "skill": 0.5, "shop": False}})
    a = SIO.watch_args(s)
    check(a[:2] == ["--hero", "calavera"], "watch80: watch_args: the hero (%s)" % a[:2])
    i = a.index("--trail")
    check(a[i + 1] == "half" and "--trail-optional" not in a and "--talents" not in a and "--board" not in a, "watch80: watch_args: half of the Trail (%s)" % a[i + 1])
    check(a[a.index("--seed") + 1] == "7" and a[a.index("--death") + 1] == "keep" and a[a.index("--map") + 1] == "red_canyon",
          "watch80: watch_args: seed, Down! and the map")
    bots = [a[j + 1] for j in range(len(a) - 1) if a[j] == "--bot"]
    check(bots == ["preset=careless", "skill=0.5", "shop=0"] or sorted(bots) == sorted(["preset=careless", "skill=0.5", "shop=0"]),
          "watch80: watch_args: every bot option as --bot key=value (%s)" % bots)
    s2, _ = SB.clean_settings({"hero": "drifter", "trail": "36", "trail_optional": True})
    a2 = SIO.watch_args(s2)
    check(a2[a2.index("--trail") + 1] == "36" and "--trail-optional" in a2, "watch80: watch_args: a Trail Level with the optional nodes (%s)" % a2[a2.index("--trail") + 1])

    # the route: 409 while a Watch is open; else watch.py started, not waited for
    tmp = tempfile.mkdtemp(prefix="le_watch80_")
    keep = (W.lock_status, W.WATCH_DIR, subprocess.Popen)
    started = []
    try:
        W.WATCH_DIR = tmp
        W.lock_status = lambda: {"pid": 99, "alive": True, "owner_file": True}
        st, body = SIO.watch(_Srv(), {"hero": "drifter", "trail": "quarter"})
        check(st == 409 and "open already" in str(body.get("error")), "watch80: the route refuses a second Watch (%s %s)" % (st, body))
        W.lock_status = lambda: None

        def fake(cmd, **kw):
            p = _FakeProc(cmd, **kw)
            started.append(p)
            return p
        subprocess.Popen = fake
        st, body = SIO.watch(_Srv(), {"hero": "drifter", "trail": "quarter", "seed": 3})
        check(st == 200 and body.get("ok") and body.get("pid") == 4242, "watch80: the route starts the Watch (%s %s)" % (st, body))
        cmd = started[0].cmd if started else []
        check(len(cmd) > 2 and cmd[1].endswith(os.path.join("tools", "watch.py")) and "--hero" in cmd and "--seed" in cmd,
              "watch80: the route runs tools/watch.py with the tab's options (%s)" % cmd[:6])
        check(os.path.isdir(os.path.join(tmp, "logs")), "watch80: the launch's output goes to the Watch's logs folder")
        st, body = SIO.watch(_Srv(), {"hero": "nobody_at_all"})
        check(st == 400, "watch80: an unknown hero is refused before anything starts (%s)" % st)
    finally:
        W.lock_status, W.WATCH_DIR, subprocess.Popen = keep

    # watch.py's pieces
    check(W.parse_limit("5:00") == 300 and W.parse_limit("300") == 300 and W.parse_limit("1:02:00") == 3720 and W.parse_limit("0") == 0,
          "watch80: the limit read as seconds")
    lv = SB.trail_levels()
    half = SB.trail_level_of("half", lv)
    t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail="half", trail_optional=False, board=None))
    check((t, opt, ids) == ("half", False, []) and label == "half (Trail Level %d of %d)" % (half, lv) and not probs, "watch80: --trail half is the Sim's half (%s %s)" % (label, probs))
    t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail=None, trail_optional=False, board=None))
    check(t == "quarter" and not probs, "watch80: no --trail plays a quarter")
    t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail=None, trail_optional=False, board="3"))
    check(t == "half" and len(probs) == 1 and "--board is the old name" in probs[0], "watch80: --board is the old name: it plays the same share and says so in one line (%s)" % probs)
    t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail="36", trail_optional=True, board="6"))
    check((t, opt) == ("36", True) and label == "Trail Level 36 of %d, optional nodes too" % lv and not probs, "watch80: --trail wins over --board; a level with the optional nodes (%s)" % label)
    t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail="lots", trail_optional=False, board=None))
    check(t == "quarter" and probs, "watch80: a Trail it cannot read plays a quarter and says so")
    keep_st = SB.save_trail
    try:
        SB.save_trail = lambda: ({"ids": ["n001", "n002"], "level": 2}, "read")
        t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail="save", trail_optional=True, board=None))
        check((t, opt, ids) == ("save", False, ["n001", "n002"]) and label == "my save (Trail Level 2 of %d)" % lv, "watch80: --trail save is the PC save's own nodes (%s)" % label)
        SB.save_trail = lambda: (None, "no save found")
        t, opt, ids, label, probs = W.trail_of(argparse.Namespace(trail="save", trail_optional=False, board=None))
        check(t == "none" and ids == [] and probs == ["no save found"], "watch80: no PC save: none plays, and it says why")
    finally:
        SB.save_trail = keep_st
    a = argparse.Namespace(hero="drifter", seed=5, map="red_canyon", limit="2:00", speed="4", death="end", unlocks="all",
                           mute=False, no_numbers=True, log_speed="30", paused=True, stub=False, bot_preset="expert",
                           bot=["skill=0.7"], autoquit=True, wall=0, shots="", shots_at="", size="1280x720", profile=False,
                           actions="p10:pause", skip_draw="0")
    args = W.build_args(a, ("36", True, [], "Trail Level 36 of 70, optional nodes too"), "C:/x/result.json", "sim1", "C:/locks/watch.lock")
    for want in ["hero=drifter", "seed=5", "trail=36", "trail_optional=1", "limit=120", "speed=4", "paused=1", "numbers=0", "bot.preset=expert",
                 "bot.skill=0.7", "autoquit=1", "ref=C:/x/result.json", "ref_label=sim1", "w=1280", "h=720", "actions=p10:pause",
                 "skip_draw=0", "lock=C:/locks/watch.lock"]:
        check(want in args, "watch80: the Godot side's argument %s" % want)
    check(any(x.startswith("repo=") for x in args) and any(x.startswith("trail_label=Trail Level 36") for x in args)
          and not any(x.startswith(("talents=", "board_label=", "trail_ids=")) for x in args),
          "watch80: the repo (for the record's mirror) and the Trail's words go along")
    args_save = W.build_args(a, ("save", False, ["n001", "n002"], "my save"), None, "", "C:/locks/watch.lock")
    check("trail=save" in args_save and "trail_ids=n001,n002" in args_save, "watch80: my save's own nodes go along")

    # --ref auto: the newest Sim result of the same hero, Trail and map
    sims = tempfile.mkdtemp(prefix="le_watch80_sims_")
    keep_dir = SB.SIM_DIR
    try:
        SB.SIM_DIR = sims
        for name, hero, board, age in (("old", "drifter", "quarter", 300), ("other", "calavera", "quarter", 100), ("new", "drifter", "quarter", 50),
                                       ("half", "drifter", "half", 10), ("board", "drifter", None, 5)):
            d = os.path.join(sims, "runs", name)
            os.makedirs(d)
            # ("board": a sim from before the Trail: its settings have `board`, no `trail`; never a Trail run's grey line)
            sett = {"hero": hero, "trail": board, "trail_optional": False, "map": "red_canyon"} if board else {"hero": hero, "board": 1.5, "map": "red_canyon"}
            SB.write_json(os.path.join(d, "result.json"), {"settings": sett, "t": [0], "series": {}})
            SB.write_json(os.path.join(d, "head.json"), {"settings": sett, "summary": {"ok": 3}})
            SB.write_json(os.path.join(d, "progress.json"), {"started_epoch": time.time() - age, "state": "done"})
        path, label = W.find_ref("drifter", SB.trail_key("quarter"), "red_canyon")
        check(path is not None and os.path.basename(os.path.dirname(path)) == "new" and label == "new",
              "watch80: --ref auto takes the newest Sim of the same hero and Trail, never one from before the Trail (%s)" % label)
        check(W.find_ref("drifter", SB.trail_key("quarter", True), "red_canyon")[0] is None, "watch80: the same level with the optional nodes is another Trail")
        check([r["label"] for r in W.ref_entries()] == ["half", "new", "other", "old"] and W.ref_entries()[0]["trail_key"] == "half",
              "watch80: the pop-up's Sim results carry their Trail's key; a sim from before the Trail is left out")
        path, why = W.find_ref("fadeaway", SB.trail_key("quarter"), "red_canyon")
        check(path is None and "no Sim result" in why, "watch80: --ref auto says when there is none")
    finally:
        SB.SIM_DIR = keep_dir
        shutil.rmtree(sims, ignore_errors=True)

    # the lock: one Watch at a time, a dead owner's lock reclaimed
    keep_lock = W.LOCK
    try:
        W.LOCK = os.path.join(tmp, "watch.lock")
        ok, st = W.lock_take("t")
        check(ok and os.path.isfile(os.path.join(W.LOCK, "owner.json")), "watch80: the lock taken with its owner")
        ok2, st2 = W.lock_take("t2")
        check(not ok2 and st2 and st2.get("alive"), "watch80: a live lock refuses a second Watch")
        W.lock_owner(999999999, "gone")
        ok3, _ = W.lock_take("t3")
        check(ok3, "watch80: a lock whose owner is gone is reclaimed")
        check(W.lock_release() and not os.path.isdir(W.LOCK), "watch80: the lock released")
    finally:
        W.LOCK = keep_lock
        shutil.rmtree(tmp, ignore_errors=True)
