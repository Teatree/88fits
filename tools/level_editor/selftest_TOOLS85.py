"""Pass 85, lane TOOLS: the Timeline's right-button pan in the Spawn rows (timeline.js onPanDown / panTo), and the Watch's
launcher (tools/watch.py): sound off by default, the Hero Settings pop-up's setup file (the board presets, the PC save's
board, the Sim results for the grey line) and `--go`. selftest.py discovers this file (`extra_checks`). Nothing here
starts Godot or a window.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def _pan_checks(check):
    tl = _read(HERE, "timeline.js")
    for frag in ["scrollBox.addEventListener('pointerdown', onPanDown, true);", "const PAN_AREA = '.tl-sec-rows .tl-sec-body';",
                 "if (e.button !== 2 || drag || pan || !inPanArea(e.target)) return;", "document.body.classList.add('tl-panning');",
                 "if (inPanArea(e.target) || pan || performance.now() - panEndT < 400) e.preventDefault();",
                 "if (drag || pan || !App.S.map) return;", "panTo, get panning()"]:
        check(frag in tl, "tools85: timeline.js has %s" % frag)
    css = _read(HERE, "style.css")
    check("body.tl-panning, body.tl-panning * { cursor: grabbing !important;" in css, "tools85: the grab cursor while panning")
    check("hold the right mouse button and drag to pan" in _read(HERE, "fields.js"), "tools85: the Spawn rows section's help says the pan")
    ins = _read(HERE, "instructions.js")
    check("Hold the right mouse button in the Spawn rows and drag" in ins and "hold the right mouse button and drag to pan (time and rows)" in ins,
          "tools85: the Instructions say the pan (the keys table and the Timeline's words)")
    # panTo's maths under Node: the content follows the pointer, never past the start
    m = re.search(r"function panTo\(p, cx, cy\) \{[^\n]*\}", tl)
    check(m is not None, "tools85: panTo is one line")
    node = shutil.which("node")
    if m and node:
        src = m.group(0) + "\nconst out = [panTo({x: 100, y: 100, left: 500, top: 300}, 40, 160), panTo({x: 100, y: 100, left: 20, top: 10}, 300, 400)];\n" \
              "process.stdout.write(JSON.stringify(out));"
        p = subprocess.run([node, "-e", src], capture_output=True, text=True, encoding="utf-8", timeout=30)
        got = json.loads(p.stdout or "null")
        check(got == [{"left": 560, "top": 240}, {"left": 0, "top": 0}], "tools85: a drag left and down scrolls right and up; never below 0 (%s)" % got)


def _watch_checks(check):
    import watch as W
    import sim_batch as SB
    a = argparse.Namespace(hero="drifter", seed=5, map="red_canyon", limit="0", speed="1", death="end", unlocks="all", mute=False,
                           no_numbers=False, log_speed="30", paused=False, stub=False, bot_preset="", bot=[], autoquit=False, wall=0,
                           shots="", shots_at="", size="", profile=False, actions="", skip_draw="1")
    args = W.build_args(a, {}, "none", None, "", "C:/locks/watch.lock")
    check("sound=0" in args, "tools85: the sound is off by default (%s)" % [x for x in args if x.startswith("sound=")])
    a.sound = True
    check("sound=1" in W.build_args(a, {}, "none", None, "", "C:/l"), "tools85: --sound turns it on")
    a.sound = False
    a.mute = True
    check("sound=0" in W.build_args(a, {}, "none", None, "", "C:/l"), "tools85: --mute still means off")
    a.mute = False
    # the pop-up opens unless --go (or a check that closes itself: --autoquit)
    check(not any(x.startswith("go=") for x in W.build_args(a, {}, "none", None, "", "C:/l")), "tools85: the pop-up opens by default")
    a.go = True
    check("go=1" in W.build_args(a, {}, "none", None, "", "C:/l"), "tools85: --go starts the run at once")
    a.go = False
    a.autoquit = True
    check("go=1" in W.build_args(a, {}, "none", None, "", "C:/l"), "tools85: --autoquit starts the run at once too")
    a.autoquit = False
    # the setup file: the presets talent by talent, the PC save's board (or why not), the Sim results for the grey line
    tmp = tempfile.mkdtemp(prefix="le_tools85_")
    try:
        p = os.path.join(tmp, "setup.json")
        keep = W.SB.save_board, W.SB.list_sims
        W.SB.save_board = lambda: ({"grit": "AB"}, "")
        W.SB.list_sims = lambda: []
        try:
            W.write_setup(p)
        finally:
            W.SB.save_board, W.SB.list_sims = keep
        d = json.load(open(p, encoding="utf-8"))
        pre = d.get("presets", {})
        check(pre.get("none") == {} and pre.get("quarter") == SB.board_talents(1.5) and pre.get("half") == SB.board_talents(3.0)
              and pre.get("full") == SB.board_talents(6.0) and pre.get("save") == {"grit": "AB"},
              "tools85: the setup's presets: none, quarter, half, full and the PC save's (%s)" % sorted(pre))
        check(isinstance(d.get("refs"), list), "tools85: the setup lists the Sim results")
        check(any(x.startswith("setup=") for x in W.build_args(a, {}, "none", None, "", "C:/l", setup=p)), "tools85: the setup file goes along")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    _pan_checks(check)
    _watch_checks(check)
