"""Pass 130, lane LE: the Trail tab's hint box and the look card's Facing row.

Groups:
  hints   tools/level_editor/trail_hints.json has an entry (a `what`) for every upgrade type of the game's trail.json; the
          known traps are said (Tempo is a cooldown cut; the Stakes' pay only in the designer's note)
  hint    trail_hint.js under Node on fixtures/trail_sample.json and a small file of its own: the lines of an upgrade node
          (in play, amount, in the file with the sum up to its level), a type looked at in the pick list, the fallback to
          the type's `text`, a choice / optional / needs-others node, an unlock with what it was locked behind
  locks   trail_io.locks on a temporary content tree: a quest that stands, a retired one, a quest added since
  facing  server.look_op `facing` on a temporary creature: a look's own key, inherit, the base look writes the top-level
          key, straight, what is refused; look_records says where each rule comes from
  page    the page loads trail_hint.js, trail.js draws the box, looks.js has the row, strip_player.js plays without the
          pointer, the how-to is in docs/level_editor.md and instructions.js
Nothing here writes under game/.
"""
import json
import os
import shutil
import subprocess
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FIXTURE = os.path.join(HERE, "fixtures", "trail_sample.json")

HINT_JS = r"""
const M = require('./trail_model.js');
const H = require('./trail_hint.js');
const fs = require('fs');
const d = M.normalise(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')));
const hints = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const up = (id, level, kind, type, value, more) => Object.assign({ id, level, kind, gives: { type: 'upgrade', upgrade: type, value } }, more || {});
const own = M.normalise({ upgrades: {
    might: { name: 'Might', kind: 'percent', text: 'Attack damage', effects: [{ stat: 'might', op: 'mul', per: 1 }] },
    tempo: { name: 'Tempo', kind: 'percent', text: 'Attack speed', effects: [{ stat: 'cooldown', op: 'mul', per: -1 }] },
    nohint: { name: 'No Hint', kind: 'count', text: 'Its own words', effects: [{ stat: 'amount', op: 'add', per: 1 }] } },
  nodes: [up('a', 1, 'node', 'might', 0.05), up('b', 2, 'choice', 'might', 0.08, { group: 'g' }), up('c', 2, 'choice', 'might', 0.03, { group: 'g' }),
    up('o', 2, 'optional', 'might', 0.02), up('e', 3, 'node', 'might', 0.1), up('f', 4, 'node', 'tempo', 0.04, { from: ['a', 'e'], need: 'any' }),
    { id: 'u', level: 5, kind: 'node', gives: { type: 'outlaw', id: 'astro' } }, { id: 's', level: 6, kind: 'node', gives: { type: 'stage', map: 'red_canyon', stage: 'dust' } },
    { id: 'w', level: 7, kind: 'node', gives: { type: 'weapon', id: 'tommy_gun' } }, up('n', 8, 'node', 'nohint', 1)] });
const P = { outlaws: [{ id: 'astro', name: 'Astro', price: 1500 }], weapons: [{ id: 'tommy_gun', name: 'Tommy Gun' }],
  maps: [{ id: 'red_canyon', name: 'Red Canyon', stages: [{ id: 'dust', name: 'The Dust Bowl' }] }], locks: { 'outlaw:astro': 'the unlock quest unlock_astro' } };
const line = (h, k) => { const l = h && h.lines.find((x) => x.k === k); return l ? l.text : null; };
const b = (sel, picks) => H.build(M, own, sel, hints, picks === undefined ? P : picks);
const out = {
  keys: b({ id: 'a' }).lines.map((l) => l.k), title: [b({ id: 'a' }).title, b({ id: 'a' }).sub],
  what: line(b({ id: 'a' }), 'what') === hints.might.what, note: line(b({ id: 'a' }), 'note') === hints.might.note,
  reads: line(b({ id: 'f' }), 'reads'), standsA: line(b({ id: 'a' }), 'stands'), standsB: line(b({ id: 'b' }), 'stands'), standsE: line(b({ id: 'e' }), 'stands'),
  sums: [H.sums(M, own, 'might'), H.sums(M, own, 'might', 2), H.sums(M, own, 'tempo', 3)],
  kindPlain: line(b({ id: 'a' }), 'kind'), kindChoice: line(b({ id: 'b' }), 'kind'), kindOptional: line(b({ id: 'o' }), 'kind'), kindNeeds: line(b({ id: 'f' }), 'kind'),
  look: (() => { const h = b({ id: 'a', upgrade: 'tempo' }); return [h.title, h.sub, line(h, 'what') === hints.tempo.what, line(h, 'stands')]; })(),
  typeOnly: (() => { const h = b({ upgrade: 'might' }); return [h.title, h.id, h.lines.map((l) => l.k)]; })(),
  fallback: [line(b({ id: 'n' }), 'what'), line(b({ id: 'n' }), 'note')],
  unknownType: (() => { const h = b({ id: 'a', upgrade: 'nope' }); return [h.sub, line(h, 'reads')]; })(),
  unlockOutlaw: line(b({ id: 'u' }), 'unlock'), unlockStage: line(b({ id: 's' }), 'unlock'), unlockWeapon: line(b({ id: 'w' }), 'unlock'),
  unlockNoLocks: line(b({ id: 'u' }, { outlaws: P.outlaws }), 'unlock'), unlockKeys: b({ id: 'u' }).lines.map((l) => l.k),
  none: [b({ id: 'zzz' }), b(null), H.build(null, own, { id: 'a' }, hints, P)],
  sample: d.nodes.map((n) => { const h = H.build(M, d, { id: n.id }, hints, {}); return h && typeof h.title === 'string' && Array.isArray(h.lines) ? 1 : 0; }).reduce((a, x) => a + x, 0) === d.nodes.length,
  amountWord: H.amountLine({ kind: 'word', effects: [] }), amountNone: H.amountLine(null),
};
process.stdout.write(JSON.stringify(out));
"""


def _read(*parts):
    with open(os.path.join(*parts), "r", encoding="utf-8") as f:
        return f.read()


def _write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(obj if isinstance(obj, str) else json.dumps(obj, indent=2) + "\n")


def hint_words(check):
    hints = json.loads(_read(HERE, "trail_hints.json"))
    trail = json.loads(_read(ROOT, "game", "content", "trail", "trail.json"))
    types_ = list((trail.get("upgrades") or {}).keys())
    missing = [t for t in types_ if not isinstance(hints.get(t), dict) or not str(hints[t].get("what", "")).strip()]
    check(types_ and not missing, "P130LE hints: every upgrade type of trail.json (%d) has a `what` in trail_hints.json; missing: %s" % (len(types_), missing))
    bad = [t for t, h in hints.items() if not t.startswith("_") and (not isinstance(h, dict) or set(h) - {"what", "note"} or not all(isinstance(v, str) for v in h.values()))]
    check(not bad, "P130LE hints: every entry is {what, note?} of plain words: %s" % bad)
    long_ = [t for t, h in hints.items() if isinstance(h, dict) and len(h.get("what", "")) > 330]
    check(not long_, "P130LE hints: a `what` stays short (at most 330 characters): %s" % long_)
    tempo = hints.get("tempo", {})
    check("cooldown" in tempo.get("what", "") and "cooldown cut" in tempo.get("note", ""), "P130LE hints: Tempo says it is a cooldown cut")
    for t in ("stakes", "boss_stakes"):
        h = hints.get(t, {})
        what = h.get("what", "").lower()
        check("xp" not in what and "coin" not in what and "pay" not in what and "tougher" in what and "xp and coins" in h.get("note", "").lower(),
              "P130LE hints: %s says the creatures get tougher, and the extra pay only in the designer's note" % t)
    check("hero" not in json.dumps(hints).lower(), "P130LE hints: the words say Outlaw, never Hero")


def hint_model(check):
    node = shutil.which("node")
    if not node:
        check(True, "P130LE hint: Node is not installed, trail_hint.js not run")
        return
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8", dir=HERE, prefix="_p130le_") as f:
        f.write(HINT_JS)
        runner = f.name
    try:
        p = subprocess.run([node, runner, FIXTURE, os.path.join(HERE, "trail_hints.json")], capture_output=True, text=True, encoding="utf-8", timeout=60, cwd=HERE)
    finally:
        os.unlink(runner)
    if p.returncode != 0 or not p.stdout.strip():
        check(False, "P130LE hint: node ran trail_hint.js: %s" % (p.stderr or p.stdout)[-600:])
        return
    o = json.loads(p.stdout)
    check(o["keys"] == ["what", "note", "reads", "stands"] and o["title"] == ["Might", "Attack damage +5%"], "P130LE hint: a plain upgrade node's lines are in play, note, amount, in the file: %s %s" % (o["keys"], o["title"]))
    check(o["what"] and o["note"], "P130LE hint: the words come from trail_hints.json")
    check("0.03 in the file is \"+3%\"" in o["reads"] and "`cooldown` is multiplied by 1 + the amount × -1" in o["reads"], "P130LE hint: the amount line says how a percent is written and the stat behind it: %s" % o["reads"])
    s_all, s_2, s_t = o["sums"]
    check(s_all == {"count": 5, "sure": 0.15, "choice": 0.08, "optional": 0.02, "max": 0.25} and s_2 == {"count": 4, "sure": 0.05, "choice": 0.08, "optional": 0.02, "max": 0.15} and s_t["count"] == 0,
          "P130LE hint: the sums count plain nodes, a group's best member and optional nodes, whole and up to a level: %s %s" % (s_all, s_2))
    check(o["standsA"].startswith("5 nodes give Might: +25% at most (+15% sure, +8% from choices") and o["standsA"].endswith("Up to and including level 1: +5% over 1 node.")
          and "level 2: +15% over 4 nodes" in o["standsB"] and "level 3: +25% over 5 nodes" in o["standsE"], "P130LE hint: where the file stands with the type: %s | %s" % (o["standsA"], o["standsB"]))
    check(o["kindPlain"] is None and o["kindChoice"].startswith("Choice: the player takes one of the 2 nodes of group g (b, c)") and o["kindOptional"].startswith("Optional: it sits beside level 2")
          and o["kindNeeds"].startswith("Needs others: it opens only when any one of a, e is bought"), "P130LE hint: one line for a choice, an optional node and a node that needs others, none for a plain one: %s" % o["kindNeeds"])
    check(o["look"][0] == "Tempo" and "looking at it for a" in o["look"][1] and o["look"][2] and o["look"][3].startswith("1 node gives Tempo: +4% at most"),
          "P130LE hint: the pick list's type is described for the selected node: %s" % o["look"])
    check(o["typeOnly"] == ["Might", None, ["what", "note", "reads", "stands"]], "P130LE hint: a type alone has no node line: %s" % o["typeOnly"])
    check(o["fallback"] == ["Its own words", None], "P130LE hint: a type without an entry falls back to its text: %s" % o["fallback"])
    check(o["unknownType"][0].startswith("not an upgrade type of this file") and o["unknownType"][1] is None,"P130LE hint: a type the file does not have says so")
    check(o["unlockKeys"] == ["unlock"] and o["unlockOutlaw"].startswith("Unlocks Outlaw: Astro: the outlaw is owned once this node is bought; until then his tile reads \"Reach Trail Level 5\"")
          and "Before the Trail: the unlock quest unlock_astro; then a price of 1500 gold in his own file" in o["unlockOutlaw"], "P130LE hint: an outlaw's node says what it unlocks and what he was locked behind: %s" % o["unlockOutlaw"])
    check("Its other rule stays: the boss of the stage before it must be beaten too" in o["unlockStage"] and o["unlockWeapon"].endswith("Before the Trail: nothing, it was free."),
          "P130LE hint: a stage keeps its boss rule; a thing no quest named was free: %s" % o["unlockWeapon"])
    check("restarted" in o["unlockNoLocks"], "P130LE hint: a server without the locks list (not restarted yet) says so instead of guessing")
    check(o["none"] == [None, None, None] and o["sample"] and o["amountNone"] == "" and "no amount" in o["amountWord"], "P130LE hint: nothing selected gives no hint; every node of the sample file builds one")


def lock_checks(check):
    import trail_io
    tmp = tempfile.mkdtemp(prefix="le_p130_locks_")
    try:
        content = os.path.join(tmp, "content")
        _write(os.path.join(content, "trail", "quests_before.json"), {"_doc": "x", "character:buck": "unlock_buck", "passive:stride": "unlock_stride", "odd:thing": "q"})
        _write(os.path.join(content, "quests", "unlock_stride", "unlock_stride.json"), {"id": "unlock_stride", "name": "The Chariot", "condition": {"type": "survive_minutes_no_lift", "minutes": 2}, "unlocks": {"type": "passive", "id": "stride"}})
        _write(os.path.join(content, "quests", "skin_new", "skin_new.json"), {"id": "skin_new", "name": "New", "condition": {"type": "kills"}, "unlocks": {"type": "skin", "id": "may:MAY-S"}})
        srv = types.SimpleNamespace(CONTENT=content, GAME=tmp)
        got = trail_io.locks(srv)
        check(set(got) == {"outlaw:buck", "passive:stride", "skin:may:MAY-S"}, "P130LE locks: quest types become the Trail's (character -> outlaw), unknown ones are left out: %s" % sorted(got))
        check("unlock_buck" in got.get("outlaw:buck", "") and "retired" in got.get("outlaw:buck", ""), "P130LE locks: a quest whose file is gone was retired: %s" % got.get("outlaw:buck"))
        check('the quest "The Chariot" (unlock_stride: survive_minutes_no_lift (minutes 2))' in got.get("passive:stride", ""), "P130LE locks: a standing quest is named with its condition: %s" % got.get("passive:stride"))
        check("skin_new" in got.get("skin:may:MAY-S", ""), "P130LE locks: a quest added since the Trail arrived counts too")
        check(trail_io.picks(srv).get("locks") == got, "P130LE locks: GET /api/trail's picks carry them")
        check(trail_io.locks(types.SimpleNamespace(CONTENT=os.path.join(tmp, "none"), GAME=tmp)) == {}, "P130LE locks: no file, no locks (never an error)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def facing_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_p130_facing_")
    saved = (server.CONTENT, server.GODOT, server.BACKUPS)
    try:
        server.CONTENT = os.path.join(tmp, "content")
        server.GODOT = os.path.join(tmp, "no-godot.exe")
        server.BACKUPS = os.path.join(tmp, "backups")
        folder = os.path.join(server.CONTENT, "enemies", "p130beast")
        path = os.path.join(folder, "p130beast.json")
        _write(path, {"id": "p130beast", "name": "Beast", "sprite": "p130beast_sprite.png", "anims": {"idle": 2, "run": 4, "run_b": 4}, "variant_base": "PB-A", "variant": "PB-B",
                      "variants": {"PB-A": {"note": "the base"}, "PB-B": {"sprite": "p130beast_sprite_b.png", "note": "b"}, "PB-C": {"sprite": "p130beast_sprite_c.png", "back_faces": "left"}}})
        _write(os.path.join(server.CONTENT, "characters", "p130hero", "p130hero.json"), {"id": "p130hero", "name": "H", "variant_base": "PH-A", "variants": {"PH-A": {"note": "x"}}})
        load = lambda: json.loads(_read(path))
        rec = lambda res, code: next(l for l in res["looks"] if l["code"] == code)
        looks0 = server.look_records("enemy", "p130beast", folder, load(), path)
        src0 = {l["code"]: l.get("faces_src") for l in looks0}
        check(src0.get("PB-B") == {"front": "default", "back": "default"} and src0.get("PB-C") == {"front": "default", "back": "look"}, "P130LE facing: look_records says where each rule comes from: %s" % src0)
        r = server.look_op("enemy", "p130beast", ["PB-B"], "facing", {"view": "back", "value": "left"})
        d = load()
        check(r.get("ok") and d["variants"]["PB-B"].get("back_faces") == "left" and "back_faces" not in d and "front_faces" not in d["variants"]["PB-B"] and d["variants"]["PB-B"]["note"] == "b",
              "P130LE facing: Flip writes the look's own back_faces and nothing else: %s" % (r.get("error") or d["variants"]["PB-B"]))
        check(r.get("ok") and rec(r, "PB-B")["back_faces"] == "left" and rec(r, "PB-B")["faces_src"]["back"] == "look" and r.get("backup"), "P130LE facing: the answer carries the looks again and a backup was kept")
        r = server.look_op("enemy", "p130beast", ["PB-B"], "facing", {"view": "back", "value": "inherit"})
        check(r.get("ok") and "back_faces" not in load()["variants"]["PB-B"], "P130LE facing: Use the creature's drops the look's own key")
        r = server.look_op("enemy", "p130beast", ["PB-A"], "facing", {"view": "back", "value": "left"})
        d = load()
        check(r.get("ok") and d.get("back_faces") == "left" and "back_faces" not in d["variants"]["PB-A"] and list(d).index("back_faces") < list(d).index("variants"),
              "P130LE facing: the base look writes the creature's top-level key (before variants): %s" % (r.get("error") or list(d)))
        check(r.get("ok") and rec(r, "PB-B")["back_faces"] == "left" and rec(r, "PB-B")["faces_src"]["back"] == "creature" and rec(r, "PB-A")["back_faces"] == "left",
              "P130LE facing: a look without its own follows the creature's rule")
        r = server.look_op("enemy", "p130beast", ["PB-A"], "facing", {"view": "front", "value": "straight"})
        d = load()
        check(r.get("ok") and d.get("front_faces") == "straight" and list(d).index("front_faces") < list(d).index("back_faces"), "P130LE facing: Never mirror writes straight; front_faces sits before back_faces")
        r = server.look_op("enemy", "p130beast", ["PB-C"], "facing", {"view": "back", "value": "right"})
        check(r.get("ok") and load()["variants"]["PB-C"]["back_faces"] == "right" and rec(r, "PB-C")["faces_src"]["back"] == "look", "P130LE facing: a look that had its own flips its own")
        before = _read(path)
        bad = [server.look_op("enemy", "p130beast", ["PB-B"], "facing", {"view": "side", "value": "left"}), server.look_op("enemy", "p130beast", ["PB-B"], "facing", {"view": "back", "value": "up"}),
               server.look_op("enemy", "p130beast", ["PB-A"], "facing", {"view": "back", "value": "inherit"}), server.look_op("hero", "p130hero", ["PH-A"], "facing", {"view": "back", "value": "left"})]
        check(all(not x.get("ok") and x.get("status") == 400 for x in bad) and _read(path) == before, "P130LE facing: an unknown view or value, inherit on the base look and an outlaw are refused, nothing written: %s" % [x.get("status") for x in bad])
        check(server.look_op("enemy", "p130beast", ["PB-Z"], "facing", {"view": "back", "value": "left"}).get("status") == 404, "P130LE facing: a look the creature does not have is a 404")
        check("\r" not in _read(path) and json.loads(_read(path))["anims"] == {"idle": 2, "run": 4, "run_b": 4}, "P130LE facing: the file keeps LF and its other keys")
    finally:
        server.CONTENT, server.GODOT, server.BACKUPS = saved
        shutil.rmtree(tmp, ignore_errors=True)


def page_checks(check):
    index = _read(HERE, "index.html")
    check(0 < index.find('src="trail_model.js"') < index.find('src="trail_hint.js"') < index.find('src="trail.js"'), "P130LE page: index.html loads trail_hint.js between trail_model.js and trail.js")
    trail = _read(HERE, "trail.js")
    check("function drawHint()" in trail and "H.build(M, S.doc, sel, S.hints || {}, S.picks)" in trail and "fetch('trail_hints.json'" in trail and "R.hint = el('div', { class: 'trl-hint' })" in trail,
          "P130LE page: trail.js draws the hint box from trail_hint.js and trail_hints.json")
    check("S.look = o ? { id, upgrade: o.id } : null" in trail and "if (S.look) { S.look = null; drawHint(); }" in trail and "S.sel = id;\n    drawHint();" in trail,
          "P130LE page: the box follows the selection and the open pick list, and goes back when the list closes")
    check(".trl-hint" in _read(HERE, "trail.css"), "P130LE page: trail.css styles the box")
    looks = _read(HERE, "looks.js")
    check("function facingRow(kind, id, record, look, s)" in looks and "{ op: 'facing', view, value }" in looks and "if (kind !== 'hero' && !isStub(look)) info.appendChild(facingRow(" in looks,
          "P130LE page: looks.js has the Facing row on a creature's open look (no row for an outlaw), saved through the look op")
    check("if (anims.idle_l > 0 || anims.run_l > 0) {" in looks and "always: true" in looks and "facing, label" in looks and "'Use the creature’s'" in looks,
          "P130LE page: the row previews each view heading left and right, and a look with left-heading sets gets the note instead of the buttons")
    sp = _read(HERE, "strip_player.js")
    check("this.hovered || !!this.opts.always" in sp, "P130LE page: strip_player.js plays a small player without the pointer (`always`)")
    check(".lg-facing" in _read(HERE, "preview.css"), "P130LE page: preview.css styles the row")
    doc = _read(ROOT, "docs", "level_editor.md")
    check("A creature looks the wrong way" in doc and "front_faces" in doc and "trail_hints.json" in doc, "P130LE page: docs/level_editor.md has the how-to and the hint box")
    ins = _read(HERE, "instructions.js")
    check("A creature looks the wrong way" in ins and "<b>Facing</b>" in ins and "<b>Hint</b>" in ins, "P130LE page: instructions.js has the how-to and the hint box's line")
    server_src = _read(HERE, "server.py")
    check('"default", "facing")' in server_src and '"faces_src"' in server_src and 'out["locks"] = locks(srv)' in _read(HERE, "trail_io.py"), "P130LE page: the server knows the facing op, faces_src and the locks list")


def checks(check, run_node, server):
    hint_words(check)
    hint_model(check)
    lock_checks(check)
    facing_checks(check, server)
    page_checks(check)
