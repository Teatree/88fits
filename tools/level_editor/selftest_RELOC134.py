"""Pass 134, lane RELOC: the Level Editor's side of the hidden, rarer relocation. selftest.py discovers this file
(`extra_checks`) and hands it its `check` counter, its `run_node(query, runner_src)` and the `server` module. Nothing
here writes.

Groups: the two new rows of the Relocation card (`relocate.hidden`, a box, off by default; `relocate.chance`, a number
0..1, 1 by default; both explained in words, the chance's help naming the 8 s of 0.6), the sink box saying it works only
with Hidden off; model.js's relocateCfg (the chance kept inside 0..1, a word = the default, `hidden` a switch),
relocateText (the hidden move and the chance said in words) and relocateIssues (a chance of 0 warned of); the game's
side (WaveTimeline's defaults and mend, CrowdRelocate's two keys, EnemyManager.burn_out) and Red Canyon's block
(hidden true, chance 0.6); the two docs.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = os.path.join(ROOT, "game")
CONTENT = os.path.join(GAME, "content")

RUNNER = r"""
const path = require('path');
const fs = require('fs');
const vm = require('vm');
const dir = path.dirname(process.argv[2]);
global.U = {};
const Model = require(path.join(dir, 'model.js'));
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(dir, 'fields.js'), 'utf8') + '\nthis.FIELDS_OUT = FIELDS;', ctx);
const FIELDS = ctx.FIELDS_OUT;
let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', () => {
  const q = JSON.parse(src || '{}');
  const out = {};
  const row = (k) => { const d = FIELDS.SCALARS.find((x) => x.key === k); return d ? { key: d.key, group: d.group, type: d.type, def: d.def, min: d.min, max: d.max, label: d.label, help: d.help || '' } : null; };
  out.hidden = row('relocate.hidden');
  out.chance = row('relocate.chance');
  out.sink = row('relocate.sink');
  out.order = FIELDS.SCALARS.filter((d) => d.key.startsWith('relocate.')).map((d) => d.key);
  out.cfgMap = Model.relocateCfg(q.tl || {});
  out.cfgHigh = Model.relocateCfg({ relocate: { chance: 3, hidden: 1 } });
  out.cfgLow = Model.relocateCfg({ relocate: { chance: -0.5 } });
  out.cfgWord = Model.relocateCfg({ relocate: { chance: 'often', hidden: 'yes' } });
  out.textMap = Model.relocateText(q.tl || {});
  out.textSink = Model.relocateText({ relocate: { hidden: false, chance: 1 } });
  out.issuesZero = Model.relocateIssues({ relocate: { chance: 0 } });
  out.issuesMap = Model.relocateIssues(q.tl || {});
  process.stdout.write(JSON.stringify(out));
});
"""


def _read(*parts):
    return open(os.path.join(*parts), encoding="utf-8").read()


def checks(check, run_node, server):
    wt = _read(GAME, "core", "data", "WaveTimeline.gd")
    m = re.search(r"const RELOCATE_DEFAULTS := (\{.*?\})\n", wt)
    dflt = json.loads(m.group(1)) if m else {}
    check(dflt.get("hidden") is False and dflt.get("chance") == 1.0,
          "RELOC134: WaveTimeline.RELOCATE_DEFAULTS name hidden (off) and chance (1): %s" % {k: dflt.get(k) for k in ("hidden", "chance")})
    check('k == "chance"' in wt and "clampf(float(v), 0.0, 1.0)" in wt, "RELOC134: relocate_cfg keeps the chance inside 0..1")
    cr = _read(GAME, "core", "systems", "CrowdRelocate.gd")
    check("var hidden := false" in cr and "var chance := 1.0" in cr and "func spot_seen(" in cr and "func seen(" in cr
          and "em.burn_out(i)" in cr and "pick_spot(ppos, i, true)" in cr,
          "RELOC134: CrowdRelocate plays both keys (the seen tests, the hidden spot, the burn's end)")
    emg = _read(GAME, "core", "systems", "EnemyManager.gd")
    check("func burn_rest(i: int) -> Array:" in emg and "func burn_out(i: int) -> bool:" in emg,
          "RELOC134: EnemyManager deals a burn's rest at once (burn_rest, burn_out)")
    mp = json.loads(_read(CONTENT, "maps", "red_canyon", "red_canyon.json"))
    tl = mp.get("timeline_data", {})
    blk = tl.get("relocate", {})
    check(blk.get("hidden") is True and blk.get("chance") == 0.6, "RELOC134: Red Canyon's block: hidden true, chance 0.6: %s" % {k: blk.get(k) for k in ("hidden", "chance")})
    res = run_node({"tl": tl}, RUNNER)
    if not res:
        check(False, "RELOC134: node ran fields.js and model.js")
    else:
        h = res["hidden"] or {}
        c = res["chance"] or {}
        check(h.get("group") == "Relocation" and h.get("type") == "bool" and h.get("def") is False and h.get("label") == "Hidden",
              "RELOC134: the Relocation card has a Hidden box, off by default: %s" % h)
        hh = h.get("help", "")
        check("off the screen" in hh and "at once" in hh and "passed over" in hh and "burning" in hh and "dies where it stands" in hh,
              "RELOC134: Hidden's help says what it does (off the screen, at once, passed over, the burn)")
        check(c.get("group") == "Relocation" and c.get("type") == "number" and c.get("def") == 1 and c.get("min") == 0 and c.get("max") == 1
              and c.get("label") == "Chance to go", "RELOC134: the Relocation card has a Chance to go box, 0..1, 1 by default: %s" % {k: c.get(k) for k in ("type", "def", "min", "max", "label")})
        ch = c.get("help", "")
        check("0.6" in ch and "8 s" in ch and "starts again from 0" in ch, "RELOC134: Chance to go's help says it in words (0.6 = about 8 s far)")
        check(res["sink"] and res["sink"]["help"].startswith("only when Hidden is off"), "RELOC134: Sinks over says it applies only with Hidden off")
        check(res["order"].index("relocate.hidden") < res["order"].index("relocate.squads") and res["order"].index("relocate.chance") < res["order"].index("relocate.squads"),
              "RELOC134: the two boxes sit in the card before Squads too: %s" % res["order"])
        check(not any("hero" in (x or {}).get("label", "").lower() or "hero" in (x or {}).get("help", "").lower() for x in (h, c, res["sink"])),
              "RELOC134: no new text says hero")
        cm = res["cfgMap"]
        check(cm["hidden"] is True and abs(cm["chance"] - 0.6) < 1e-9, "RELOC134: relocateCfg reads Red Canyon's two keys: %s" % {k: cm[k] for k in ("hidden", "chance")})
        check(res["cfgHigh"]["chance"] == 1 and res["cfgHigh"]["hidden"] is True and res["cfgLow"]["chance"] == 0
              and res["cfgWord"]["chance"] == 1 and res["cfgWord"]["hidden"] is False,
              "RELOC134: relocateCfg mends as the game does (the chance inside 0..1, a word = the default): %s" % [res["cfgHigh"], res["cfgLow"]["chance"], res["cfgWord"]["chance"], res["cfgWord"]["hidden"]])
        tm = res["textMap"]
        check("unseen" in tm and "60%" in tm and "8.3 s" in tm and "stops burning" in tm and "joins the queue" in tm and "hero" not in tm.lower(),
              "RELOC134: the card's line says the hidden move, the chance and the burn: %s" % tm[:200])
        check("sinks over" in res["textSink"] and "unseen" not in res["textSink"], "RELOC134: with Hidden off the line says the sink")
        check(len(res["issuesZero"]) == 1 and "nobody relocates" in res["issuesZero"][0] and res["issuesMap"] == [],
              "RELOC134: a chance of 0 is warned of, Red Canyon's block is clean: %s" % [res["issuesZero"], res["issuesMap"]])
    ws = _read(ROOT, "docs", "waves_schema.md")
    le = _read(ROOT, "docs", "level_editor.md")
    check("`hidden`" in ws and "`chance`" in ws and "Pass 134" in ws, "RELOC134: docs/waves_schema.md names the two keys")
    check("Pass 134" in le and "Chance to go" in le and "Hidden" in le, "RELOC134: docs/level_editor.md names the two boxes")
