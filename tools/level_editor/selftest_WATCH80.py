"""Pass 80, lane WATCH: the Watch's launcher (tools/watch.py) and the Sim tab's Watch button (sim.js watchRun ->
POST /api/sim/watch -> sim_io.watch). selftest.py discovers this file (`extra_checks`) and hands it its `check` counter,
its `run_node` and the `server` module. Nothing here starts Godot or a window: the spawn is caught.

Groups: the button and the route are there; sim_io.watch_args turns the tab's settings into watch.py's options (the
board talent by talent, the seed, the map, Down!, every bot option); the route answers 409 while a Watch is open and
otherwise starts watch.py without waiting; watch.py's own pieces (the limit's words, the boards, the Godot-side
arguments, the newest Sim result of the same hero and board for --ref auto, its lock).
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
    s, probs = SB.clean_settings({"hero": "calavera", "board": 3.0, "seed": 7, "death": "keep", "map": "red_canyon",
                                  "bot": {"preset": "careless", "skill": 0.5, "shop": False}})
    a = SIO.watch_args(s)
    check(a[:2] == ["--hero", "calavera"], "watch80: watch_args: the hero (%s)" % a[:2])
    i = a.index("--talents")
    check(a[i + 1] == SB.talents_arg(SB.board_talents(3.0)), "watch80: watch_args: the half board talent by talent (%s)" % a[i + 1])
    check(a[a.index("--seed") + 1] == "7" and a[a.index("--death") + 1] == "keep" and a[a.index("--map") + 1] == "red_canyon",
          "watch80: watch_args: seed, Down! and the map")
    bots = [a[j + 1] for j in range(len(a) - 1) if a[j] == "--bot"]
    check(bots == ["preset=careless", "skill=0.5", "shop=0"] or sorted(bots) == sorted(["preset=careless", "skill=0.5", "shop=0"]),
          "watch80: watch_args: every bot option as --bot key=value (%s)" % bots)
    s2, _ = SB.clean_settings({"hero": "drifter", "talents": {"grit": "AAB"}})
    a2 = SIO.watch_args(s2)
    check(a2[a2.index("--talents") + 1] == "grit:AAB", "watch80: watch_args: a custom board as given (%s)" % a2[a2.index("--talents") + 1])

    # the route: 409 while a Watch is open; else watch.py started, not waited for
    tmp = tempfile.mkdtemp(prefix="le_watch80_")
    keep = (W.lock_status, W.WATCH_DIR, subprocess.Popen)
    started = []
    try:
        W.WATCH_DIR = tmp
        W.lock_status = lambda: {"pid": 99, "alive": True, "owner_file": True}
        st, body = SIO.watch(_Srv(), {"hero": "drifter", "board": 1.5})
        check(st == 409 and "open already" in str(body.get("error")), "watch80: the route refuses a second Watch (%s %s)" % (st, body))
        W.lock_status = lambda: None

        def fake(cmd, **kw):
            p = _FakeProc(cmd, **kw)
            started.append(p)
            return p
        subprocess.Popen = fake
        st, body = SIO.watch(_Srv(), {"hero": "drifter", "board": 1.5, "seed": 3})
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
    ns = argparse.Namespace(talents="", board="half")
    t, label, probs = W.board_of(ns)
    check(t == SB.board_talents(3.0) and label == "half" and not probs, "watch80: --board half is the Sim's half (%s %s)" % (label, probs))
    ns = argparse.Namespace(talents="grit:AB,drive:A", board="quarter")
    t, label, probs = W.board_of(ns)
    check(t == {"grit": "AB", "drive": "A"} and label == "custom", "watch80: --talents wins over --board (%s)" % t)
    ns = argparse.Namespace(talents="", board="lots")
    t, label, probs = W.board_of(ns)
    check(t == SB.board_talents(1.5) and probs, "watch80: a board it cannot read plays a quarter and says so")
    a = argparse.Namespace(hero="drifter", seed=5, map="red_canyon", limit="2:00", speed="4", death="end", unlocks="all",
                           mute=False, no_numbers=True, log_speed="30", paused=True, stub=False, bot_preset="expert",
                           bot=["skill=0.7"], autoquit=True, wall=0, shots="", shots_at="", size="1280x720", profile=False,
                           actions="p10:pause", skip_draw="0")
    args = W.build_args(a, {"grit": "AA"}, "custom", "C:/x/result.json", "sim1", "C:/locks/watch.lock")
    for want in ["hero=drifter", "seed=5", "talents=grit:AA", "limit=120", "speed=4", "paused=1", "numbers=0", "bot.preset=expert",
                 "bot.skill=0.7", "autoquit=1", "ref=C:/x/result.json", "ref_label=sim1", "w=1280", "h=720", "actions=p10:pause",
                 "skip_draw=0", "lock=C:/locks/watch.lock"]:
        check(want in args, "watch80: the Godot side's argument %s" % want)
    check(any(x.startswith("repo=") for x in args) and any(x.startswith("board_label=custom") for x in args),
          "watch80: the repo (for the record's mirror) and the board's words go along")

    # --ref auto: the newest Sim result of the same hero, board and map
    sims = tempfile.mkdtemp(prefix="le_watch80_sims_")
    keep_dir = SB.SIM_DIR
    try:
        SB.SIM_DIR = sims
        for name, hero, board, age in (("old", "drifter", 1.5, 300), ("other", "calavera", 1.5, 100), ("new", "drifter", 1.5, 50),
                                       ("half", "drifter", 3.0, 10)):
            d = os.path.join(sims, "runs", name)
            os.makedirs(d)
            sett = {"hero": hero, "board": board, "talents": SB.board_talents(board), "map": "red_canyon"}
            SB.write_json(os.path.join(d, "result.json"), {"settings": sett, "t": [0], "series": {}})
            SB.write_json(os.path.join(d, "head.json"), {"settings": sett, "summary": {"ok": 3}})
            SB.write_json(os.path.join(d, "progress.json"), {"started_epoch": time.time() - age, "state": "done"})
        path, label = W.find_ref("drifter", SB.board_talents(1.5), "red_canyon")
        check(path is not None and os.path.basename(os.path.dirname(path)) == "new" and label == "new",
              "watch80: --ref auto takes the newest Sim of the same hero and board (%s)" % label)
        path, why = W.find_ref("fadeaway", SB.board_talents(1.5), "red_canyon")
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
