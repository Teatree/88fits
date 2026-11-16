"""Pass 153: an Endless window's pulse in the page's model (model.js windowPulse, windowStepper: quiet stretches bring
nothing, the burst x pulse_burst, with a realisation's rng one tab a row and pulse_rows of the rows a pulse; the
estimates keep every row's share), the window head's pulse fields and its quiet shading (boss_fights.js), and the row
card's variation tabs side by side (timeline.js variationGrid; Garry: "When highlighting the enemy node which has
probabilities I need to be able to see how much HP each variation will have, as well as ATK and etc.").

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

RUNNER = r"""
const M = require(process.argv[2]);
let src = '';
process.stdin.on('data', (d) => { src += d; });
process.stdin.on('end', () => {
  const q = JSON.parse(src);
  const out = {};
  out.off = M.windowPulse({ length: 60 }, 'endless');
  out.on = M.windowPulse({ length: 60, pulse_on: 6, pulse_off: 3, pulse_rows: 0.6, pulse_burst: 1.5 }, 'endless');
  out.boss = M.windowPulse({ length: 60, pulse_on: 6, pulse_off: 3 }, 'boss');
  const byId = Object.fromEntries(q.creatures.map((c) => [c.id, c]));
  const play = (b, rng) => {
    let alive = 0;
    const perSec = new Array(60).fill(0);
    const ids = [];
    const W = M.windowStepper(q.tl, b, 'endless', byId, 10, { rng, bodies: () => alive, aliveOf: () => 0,
      put: (x, n) => { alive += n; perSec[Math.min(Math.floor(W.time), 59)] += n; ids.push([W.time, x.r.enemy]); } });
    for (let k = 0; k < 600; k++) { W.begin(); alive *= 0.98; W.spawn(); }
    return { perSec, ids, total: perSec.reduce((a, n) => a + n, 0) };
  };
  out.plain = play(q.plain, null);
  out.pulsed = play(q.pulsed, null);
  let seed = 7;
  const rng = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  out.real = play(q.pulsed, rng);
  process.stdout.write(JSON.stringify(out));
});
"""


def checks(check, run_node, server):
    creatures = [{"id": "a", "hp": 10, "damage": 2, "pack_size": 4, "archetype": "walker", "cap_share": 1},
                 {"id": "b", "hp": 10, "damage": 2, "pack_size": 4, "archetype": "walker", "cap_share": 1}]
    rows = [{"id": "r1", "t": 0, "enemy": "a", "weights": [[0, 1]]}, {"id": "r2", "t": 0, "enemy": "b", "weights": [[0, 1]]}]
    plain = {"length": 60, "max_count": 200, "roster": rows}
    pulsed = dict(plain, pulse_on=6, pulse_off=3, pulse_rows=0.5, pulse_burst=1.5)
    tl = {"hard_cap": 300, "spawn_interval": 0.5, "burst_min": 4, "burst_max": 4}
    res = run_node({"creatures": creatures, "tl": tl, "plain": plain, "pulsed": pulsed}, RUNNER)
    if res is None:
        print("P153: node not found: the pulse's model checks are skipped")
    elif res:
        check(res["off"]["active"] is False and res["off"]["rows"] == 1 and res["off"]["burst"] == 1, "P153: no pulse keys, no pulse: %s" % res["off"])
        check(res["on"] == {"on": 6, "off": 3, "rows": 0.6, "burst": 1.5, "active": True}, "P153: the pulse reads its four keys: %s" % res["on"])
        check(res["boss"]["active"] is False, "P153: a boss fight window never pulses")
        quiet = [s for s in range(60) if s % 9 >= 6]
        check(all(res["pulsed"]["perSec"][s] < 1e-9 for s in quiet), "P153: nothing spawns in the quiet seconds: %s" % [res["pulsed"]["perSec"][s] for s in quiet[:6]])
        check(all(res["plain"]["perSec"][s] > 0 for s in quiet), "P153: without a pulse those seconds spawn")
        on = [s for s in range(60) if s % 9 < 6]
        pa = sum(res["plain"]["perSec"][s] for s in on) / len(on)
        pb = sum(res["pulsed"]["perSec"][s] for s in on) / len(on)
        check(pb > pa * 1.3, "P153: a pulse's seconds spawn more (burst x 1.5 and the room the quiet left): %.1f vs %.1f a second" % (pb, pa))
        # with a realisation, a pulse of 2 rows at 0.5 draws one creature
        per = {}
        for t, e in res["real"]["ids"]:
            per.setdefault(int(t // 9), set()).add(e)
        check(per and all(len(v) == 1 for v in per.values()), "P153: a realised pulse draws one of the two rows: %s" % {k: sorted(v) for k, v in list(per.items())[:4]})
    mdl = open(os.path.join(HERE, "model.js"), encoding="utf-8").read()
    bf = open(os.path.join(HERE, "boss_fights.js"), encoding="utf-8").read()
    tlj = open(os.path.join(HERE, "timeline.js"), encoding="utf-8").read()
    css = open(os.path.join(HERE, "style.css"), encoding="utf-8").read()
    check("'pulse_on', 'pulse_off', 'pulse_rows', 'pulse_burst'" in mdl and "windowPulse," in mdl, "P153: the pulse keys are an Endless window's own")
    for k in ("'pulse_on', 'Spawn for'", "'pulse_off', 'Quiet for'", "'pulse_rows', 'Rows a pulse'", "'pulse_burst', 'Burst ×'", "class: 'bf-quiet'"):
        check(k in bf, "P153: the window head has %s" % k)
    check("function variationGrid(r, t, t0)" in tlj and "else if (Model.hasVariations(r)) box.appendChild(variationGrid(" in tlj,
          "P153: a row with variation tabs shows each tab's numbers in its card")
    check("function variationTip(r, t)" in tlj and "Timeline.variationTip(r, App.stageEnd(s))" in bf, "P153: the variation chip's tooltip names each tab's HP and ATK")
    check(".hovercard.wide" in css and ".hc-tabs" in css, "P153: style.css lays the tabs two a line in a wider card")
    for name in ("selftest_P153.py", "boss_fights.js", "timeline.js", "model.js"):
        with open(os.path.join(HERE, name), "rb") as fh:
            check(b"\r\n" not in fh.read(), "P153: %s has LF line endings" % name)
