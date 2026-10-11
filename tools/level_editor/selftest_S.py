"""Lane S's selftest group (pass 66): the structured writer (content_io.py), the content operations and routes of
server.py, the vocabularies (vocab.py). Discovered by selftest.py's `extra_checks`; `checks(check, run_node, server)`.

Every write happens on a temporary copy of a few content files (server.CONTENT / GODOT / BACKUPS / LEDGER / UPLOADS /
METHODS re-pointed, as server_checks does); the GETs that read the real content only read. jobs.py is replaced by a
stand-in that records what the server enqueues, so no job ever runs here."""
import json
import os
import shutil
import socket
import tempfile
import threading
import time
import types
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
import content_io as cio  # noqa: E402
import vocab  # noqa: E402


def _lines_diff(a, b):
    """The (old, new) line pairs that differ, plus how many lines each text has."""
    la, lb = a.splitlines(True), b.splitlines(True)
    return [(x, y) for x, y in zip(la, lb) if x != y], len(la), len(lb)


def _read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(text.encode("utf-8"))


def _dump(obj, final_nl=True):
    return json.dumps(obj, indent=2, ensure_ascii=False) + ("\n" if final_nl else "")


# ---------------------------------------------------------------- the writer

def write_checks(check, server):
    real_ls = _read(os.path.join(ROOT, "game", "content", "enemies", "lesser_scorpion", "lesser_scorpion.json"))
    real_sol = _read(os.path.join(ROOT, "game", "content", "characters", "solenne", "solenne.json"))
    for name, src, code in (("lesser_scorpion", real_ls, "LS-B"), ("solenne", real_sol, "SOL-C")):
        lay = cio.layout(src)
        spans = cio.top_spans(src)
        check(lay is not None and lay["unit"] == "  " and spans is not None and set(spans) == set(json.loads(src)),
              "%s: layout and every top-level key found (%s)" % (name, lay))
        t1 = cio.set_variant_entry(src, code, {"note": "CHANGED NOTE"})
        changed, na, nb = _lines_diff(src, t1 or "")
        check(t1 is not None and na == nb and len(changed) == 1 and "CHANGED NOTE" in changed[0][1] and '"note"' in changed[0][0],
              "%s: one entry's note changes exactly one line (%d lines)" % (name, na))
        obj = json.loads(src)
        vs = dict(obj["variants"])
        vs[code] = dict(vs[code], note="CHANGED NOTE")
        t2 = cio.set_top_block(src, "variants", vs)
        check(t2 == t1, "%s: the whole-block rewrite is byte-identical to the entry write (the file is in dump style)" % name)
        check(cio.diff_within_entry(src, t2, code), "%s: diff_within_entry says the block write touched only %s" % (name, code))
        t3 = cio.set_variant_entry(src, "ZZ-Q", {"note": "stub", "recipe": {"a": 1}, "fresh": True})
        check(t3 is not None and json.loads(t3)["variants"]["ZZ-Q"] == {"note": "stub", "recipe": {"a": 1}, "fresh": True}
              and list(json.loads(t3)["variants"].keys())[-1] == "ZZ-Q", "%s: a new entry lands last in the block" % name)
        check(cio.del_variant_entry(t3, "ZZ-Q") == src, "%s: deleting the new entry restores the file byte for byte" % name)
        t4 = cio.del_variant_entry(src, code)
        check(t4 is not None and code not in json.loads(t4)["variants"] and len(json.loads(t4)["variants"]) == len(vs) - 1,
              "%s: an existing entry can be deleted" % name)
        t5 = cio.set_top_block(src, "name", "Other Name")
        changed, na, nb = _lines_diff(src, t5 or "")
        check(t5 is not None and na == nb and len(changed) == 1 and '"name": "Other Name"' in changed[0][1], "%s: a one-line key changes in place" % name)
        t6 = cio.set_top_block(src, "new_after_variants", {"x": [1, 2]}, [("after", "variants")])
        keys = list(json.loads(t6).keys()) if t6 else []
        check(t6 is not None and keys.index("new_after_variants") == keys.index("variants") + 1 and json.loads(t6)["new_after_variants"] == {"x": [1, 2]},
              "%s: a new key goes right after a multi-line key" % name)
        t7 = cio.set_top_block(src, "zzz", 5, [("end", None)])
        check(t7 is not None and list(json.loads(t7).keys())[-1] == "zzz" and t7.endswith("\n}" if not lay["final_nl"] else "\n}\n"),
              "%s: a new key at the end keeps the file's final newline (%s)" % (name, lay["final_nl"]))
        last = list(obj.keys())[-1]
        t8 = cio.del_top_block(src, last)
        check(t8 is not None and last not in json.loads(t8) and json.loads(t8) == {k: v for k, v in obj.items() if k != last},
              "%s: deleting the last key repairs the comma" % name)
        t9 = cio.del_top_block(src, "flavour")
        changed, na, nb = _lines_diff(src, t9 or "")
        check(t9 is not None and nb == na - 1 and "flavour" not in json.loads(t9), "%s: deleting a middle key drops one line" % name)
        t10 = cio.set_variant_entry(t3, "ZZ-Q", {"fresh": cio.REMOVE})
        check(t10 is not None and json.loads(t10)["variants"]["ZZ-Q"] == {"note": "stub", "recipe": {"a": 1}}, "%s: REMOVE drops a key from an entry" % name)
        check(json.loads(t1)["hp" if name == "lesser_scorpion" else "level_heal"] == obj["hp" if name == "lesser_scorpion" else "level_heal"]
              and ('"hp": 10.0' in t1 if name == "lesser_scorpion" else True), "%s: floats elsewhere untouched" % name)

    # a tab-indented file: the unit is a tab and a new entry is indented with tabs
    d = {"id": "t", "name": "T", "hp": 10.0, "variants": {"T-0": {"note": "base"}}, "z": [1, 2]}
    tab = json.dumps(d, indent="\t")
    check(cio.layout(tab)["unit"] == "\t", "a tab unit is read")
    t = cio.set_top_block(tab, "hp", 12.0)
    changed, na, nb = _lines_diff(tab, t or "")
    check(t is not None and na == nb and changed == [('\t"hp": 10.0,\n', '\t"hp": 12.0,\n')], "tab file: one line changes: %s" % changed)
    t = cio.set_variant_entry(tab, "T-A", {"sprite": "a.png"})
    check(t is not None and '\t\t"T-A": {\n\t\t\t"sprite": "a.png"\n\t\t}' in t and json.loads(t)["variants"]["T-A"] == {"sprite": "a.png"},
          "tab file: a new entry is laid out with tabs")
    # a new multi-line key in a tab file
    t = cio.set_top_block(tab, "drops", {"small": 1.0}, [("after", "hp")])
    check(t is not None and '\t"drops": {\n\t\t"small": 1.0\n\t},\n' in t, "tab file: a new block uses the tab unit")

    # CRLF only on the last line (fire_ant, the red goblins): a new key keeps exactly that one CRLF
    mixed = _dump(d, final_nl=False) + "\r\n"
    t = cio.set_top_block(mixed, "blood", "#112233", [("after", "hp")])
    check(t is not None and t.count("\r\n") == 1 and '  "blood": "#112233",\n' in t, "CRLF-on-the-last-line file: the new line is LF, the one CRLF kept")
    t = cio.set_top_block(mixed, "tail", 1, [("end", None)])
    check(t is not None and t.endswith('  "tail": 1\n}\r\n') and t.count("\r\n") == 1, "CRLF-on-the-last-line file: a key at the end keeps the closing CRLF")
    full_crlf = _dump(d).replace("\n", "\r\n")
    t = cio.set_top_block(full_crlf, "variants", {"T-0": {"note": "base"}, "T-A": {"note": "new"}})
    check(t is not None and "\n" not in t.replace("\r\n", "") and json.loads(t)["variants"]["T-A"] == {"note": "new"}, "an all-CRLF file gets CRLF inside a rewritten block")

    # `1.0` kept when another key changes; restore_numbers puts floats back where the page sent whole numbers
    one = _dump({"id": "x", "hp": 1.0, "n": 3})
    t = cio.set_top_block(one, "n", 4)
    check(t is not None and '"hp": 1.0' in t and '"n": 4' in t, "1.0 stays 1.0 when another key changes")
    check(cio.restore_numbers({"hp": 10.0, "a": [1.0, 2], "b": {"c": 2.0}}, {"hp": 10, "a": [1, 2], "b": {"c": 2}}) == {"hp": 10.0, "a": [1.0, 2], "b": {"c": 2.0}}
          and json.dumps(cio.restore_numbers({"hp": 10.0}, {"hp": 10})) == '{"hp": 10.0}', "restore_numbers: the file's floats come back")
    check(cio.restore_numbers({"on": 1.0}, {"on": True}) == {"on": True}, "restore_numbers leaves a bool alone")

    # a compact one-line file is refused and nothing is written
    compact = '{"id": "c", "name": "C", "hp": 3}'
    check(cio.layout(compact) is None and cio.top_spans(compact) is None and cio.set_top_block(compact, "hp", 4) is None
          and cio.del_top_block(compact, "hp") is None and cio.set_variant_entry(compact, "A", {}) is None,
          "a compact one-line file is refused by every writer")
    half = '{\n  "id": "c", "name": "C",\n  "hp": 3\n}\n'
    check(cio.top_spans(half) is None and cio.set_top_block(half, "hp", 4) is None, "two keys on one line: refused (the keys on the lines are not the object's)")
    check(cio.del_top_block(_dump({"only": 1}), "only") is None, "the only key cannot be deleted (an empty object would need a re-dump)")
    # an empty variants object and a one-line entry
    e = _dump({"id": "e", "variants": {}})
    t = cio.set_variant_entry(e, "E-A", {"note": "first"})
    check(t is not None and t == '{\n  "id": "e",\n  "variants": {\n    "E-A": {\n      "note": "first"\n    }\n  }\n}\n',
          "the first entry of an empty variants object opens the block: %r" % t)
    one_line = '{\n  "id": "o",\n  "variants": {\n    "O-A": {"note": "a"},\n    "O-B": {"note": "b"}\n  }\n}\n'
    t = cio.set_variant_entry(one_line, "O-A", {"note": "changed"})
    check(t == one_line.replace('{"note": "a"}', '{"note": "changed"}'), "a one-line entry stays one line when edited")
    vs2 = {"O-A": {"note": "a"}, "O-B": {"note": "changed"}}
    tb = cio.set_top_block(one_line, "variants", vs2)
    check(tb is not None and not cio.diff_within_entry(one_line, tb, "O-B"), "a hand-laid block: the block rewrite would touch other entries (so the entry write is the one to keep)")
    check(cio.del_variant_entry(one_line, "O-A") == '{\n  "id": "o",\n  "variants": {\n    "O-B": {"note": "b"}\n  }\n}\n', "deleting the first of two one-line entries")
    check(cio.del_variant_entry(one_line, "O-B") == '{\n  "id": "o",\n  "variants": {\n    "O-A": {"note": "a"}\n  }\n}\n', "deleting the last of two one-line entries")
    check(cio.del_variant_entry(e.replace("{}", '{"E-A": {}}'), "E-A") == e, "deleting the only entry leaves {}")
    # the duplicate-key and the value-on-the-next-line cases
    dup = '{\n  "id": "d",\n  "id": "e"\n}\n'
    check(cio.top_spans(dup) is None, "a doubled key is refused")
    nxt = '{\n  "id": "n",\n  "anims":\n  {\n    "idle": 2\n  }\n}\n'
    t = cio.set_top_block(nxt, "anims", {"idle": 3})
    check(t is not None and json.loads(t)["anims"] == {"idle": 3}, "a value starting on the next line is still found")
    # redump keeps unit, eol and final newline
    check(cio.redump(tab, json.loads(tab)) == tab, "redump of a tab file reproduces it")
    check(cio.redump(full_crlf, json.loads(full_crlf)) == full_crlf, "redump of a CRLF file reproduces it")
    # the pass 58 wrapper
    check(cio.set_top_key(_dump(d), "variant", "T-0", [("before", "variants")]) is not None, "set_top_key still works as the pass 58 wrapper")


# ---------------------------------------------------------------- a temporary content tree

ENEMY = {"id": "testbeast", "name": "Test Beast", "flavour": "Bites.", "archetype": "walker", "brain": "chase", "hp": 10.0,
         "speed": 2.0, "damage": 3.0, "knockback": 2.94, "radius": 0.5, "size": 1.5, "blood": "#AA1122",
         "pack_size": 4, "drops": {"small": 1.0, "gold": 0.02}, "anims": {"idle": 4, "run": 12, "attack": 2, "hit": 1, "die": 8},
         "frame_px": 128, "strip_cols": 27, "fps": {"run": 15, "die": 8}, "head": 0.8, "sfx": {"die": "en_goblin_die"},
         "placeholder": {"color": "#445566", "glyph": "star"}, "art_prompt": "a test beast", "pose_fit": {"keep": 1},
         "doc": "A beast for the tests.", "variant_base": "TB-0", "variant": "TB-A",
         "variants": {"TB-0": {"note": "base"}, "TB-A": {"note": "a", "sprite": "testbeast_sprite_a.png", "icon": "testbeast_icon_a.png", "strip_cols": 27},
                      "TB-B": {"note": "b", "sprite": "testbeast_sprite_b.png", "fresh": True, "recipe": {"motion": "x"}},
                      "TB-C": {"note": "stub", "recipe": {"motion": "y"}}}}
STUBBY = {"id": "stubby", "name": "Stubby", "flavour": "", "archetype": "walker", "brain": "chase", "hp": 5.0, "damage": 2.0,
          "knockback": 2.5, "size": 1.0, "blood": "#AA1122", "doc": "Nothing special.", "placeholder": {"color": "#111111"}}
BIGBOSS = {"id": "bigboss", "name": "Big Boss", "archetype": "boss", "brain": "boss", "hp": 1000.0, "damage": 20.0, "knockback": 7.0,
           "blood": "#AA1122", "doc": "The boss.", "boss": {"attacks": [{"name": "spawn_ring", "enemy": "stubby", "count": 4}]}}
HERO = {"id": "hero_a", "name": "Hero A", "flavour": "Fast.", "order": 9, "pronoun": "she", "trait": [], "trait_per_level": [],
        "favourite_weapon": "zapper", "start_weapon": "zapper", "specials": [], "frame_px": 256, "anims": {"idle": 4, "run": 24},
        "fps": {"run": 36}, "strip_cols": 62, "placeholder": {"color": "#223344"}, "art_prompt": "a hero", "trait_name": "Quick",
        "trait_text": "Gain speed."}
HERO_HIDDEN = {"id": "hero_b", "name": "Hero B", "flavour": "", "pronoun": "he", "hidden": True, "favourite_weapon": "zapper", "placeholder": {"color": "#223344"}}
WEAPON = {"id": "zapper", "name": "Zapper", "flavour": "Zap.", "rarity": "rare", "weight": 8, "hero": "hero_a", "behavior": "ProjectileEmitter",
          "targeting": "nearest", "tags": ["gun"], "base": {"damage": 10, "cooldown": 1.0, "amount": 1}, "max_level": 5,
          "levels": [[], [{"stat": "damage", "op": "mul", "value": 0.2}], [], [], []], "evolves_with": "", "evolves_into": "zapper_evo",
          "params": {"burst": True}, "sfx": {"fire": "w_pea_fire"}, "placeholder": {"color": "#AABBCC", "glyph": "gun"}, "art_prompt": "a zapper"}
BLASTER = dict(WEAPON, id="blaster", name="Blaster", hero="", evolves_into="")
EVO = {"id": "zapper_evo", "name": "Zapper Evolved", "flavour": "", "rarity": "rare", "is_evolution": True, "evolved_from": "zapper", "max_level": 1,
       "behavior": "ProjectileEmitter", "targeting": "nearest", "base": {"damage": 20}, "params": {}, "levels": [[]], "placeholder": {"color": "#AABBCC", "gold": True}}


def _mut(kind, text="A text.", effects=None, hidden=False):
    d = {"id": "zapper_%s" % kind, "name": "Zapper %s" % kind.capitalize(), "flavour": "", "rarity": "rare", "weight": 8, "weapon": "zapper",
         "kind": kind, "element": "", "hero": "", "text": text, "vfx": "", "effects": effects if effects is not None else [{"stat": "damage", "op": "mul", "value": 0.1}],
         "params": {}, "art_prompt": "", "placeholder": {"color": "#AABBCC", "glyph": "star"}}
    if hidden:
        d["hidden"] = True
    return d


LINE = {"id": "brawny", "name": "Brawny", "flavour": "", "rarity": "common", "weight": 10, "line": True, "max_level": 4,
        "levels": [[{"stat": "might", "op": "mul", "value": 0.1, "target": "player"}]], "repeat_last_level": True, "evolves_into": "brawny_evo",
        "placeholder": {"color": "#FF8040", "glyph": "star"}}
LINE_EVO = {"id": "brawny_evo", "name": "Brawny Evo", "rarity": "rare", "weight": 0, "line": True, "max_level": 1,
            "levels": [[{"stat": "might", "op": "mul", "value": 0.5, "target": "player"}]], "repeat_last_level": False, "evolves_from": "brawny",
            "placeholder": {"color": "#FF8040", "glyph": "star"}}
LUCKY = {"id": "lucky", "name": "Lucky", "flavour": "", "rarity": "uncommon", "weight": 9, "max_level": 3,
         "levels": [[{"stat": "luck", "op": "add", "value": 0.1, "target": "player"}]], "placeholder": {"color": "#00AA00", "glyph": "clover"}}
QUEST = {"id": "unlock_lucky", "name": "Lucky", "condition": {"type": "kills_total", "count": 400}, "unlocks": {"type": "passive", "id": "lucky"},
         "art_prompt": "a clover", "placeholder": {"color": "#C9A227", "glyph": "star"}}
PERK = {"id": "perk_a", "name": "Perk A", "rarity": "rare", "weight": 5, "hero": "hero_a", "text": "A perk.", "effects": []}
MAP = {"id": "testmap", "name": "Test Map", "boss": "bigboss", "skins": {"walker": "testbeast"},
       "timeline_data": {"stage_length": 100, "roster": [{"id": "r1", "t": 0, "enemy": "testbeast", "weights": [[0, 5]], "variant": "TB-A"}],
                         "events": [{"t": 50, "type": "swarm", "enemy": "stubby"}], "specials": {"pool": [{"enemy": "bigboss"}]}}}


def build_tree(root):
    content = os.path.join(root, "content")
    items = [("enemies", ENEMY), ("enemies", STUBBY), ("bosses", BIGBOSS), ("characters", HERO), ("characters", HERO_HIDDEN),
             ("weapons", WEAPON), ("weapons", BLASTER), ("evolutions", EVO), ("mutations", _mut("element")), ("mutations", _mut("volume")),
             ("mutations", _mut("motion")), ("passives", LINE), ("passives", LINE_EVO), ("passives", LUCKY), ("quests", QUEST),
             ("perks", PERK), ("maps", MAP)]
    for t, d in items:
        _write(os.path.join(content, t, d["id"], d["id"] + ".json"), _dump(d))
    folder = os.path.join(content, "enemies", "testbeast")
    for f in ("testbeast_sprite.png", "testbeast_sprite_a.png", "testbeast_icon_a.png", "testbeast_sprite_b.png", "testbeast_icon.png", "testbeast_sprite_d.png"):
        open(os.path.join(folder, f), "wb").close()
    open(os.path.join(folder, "testbeast_sprite_a.png.import"), "wb").close()
    open(os.path.join(folder, "testbeast_b_ai.json"), "wb").close()
    with open(os.path.join(folder, "testbeast.tres"), "wb") as f:
        f.write(b"tres")
    open(os.path.join(content, "characters", "hero_a", "hero_a_sprite.png"), "wb").close()
    os.makedirs(os.path.join(content, "sounds"))
    _write(os.path.join(content, "sounds", "soundmap.json"), _dump({"sounds": {"en_goblin_die": {"file": "real/en_goblin_die.wav"}}}))
    return content


class FakeJobs:
    """A stand-in for jobs.py: records what the server enqueues; one fixed queue for the list shape."""

    def __init__(self):
        self.calls = []
        self.rev = 7
        self.raise_value = False

    def enqueue(self, kind, target, spec, title=None):
        if self.raise_value:
            raise ValueError("bad spec: %s" % kind)
        rec = {"id": "j%d" % (len(self.calls) + 1), "kind": kind, "target": target, "spec": spec, "title": title, "state": "queued"}
        self.calls.append(rec)
        return rec

    def list(self, since_rev=None):
        if since_rev == self.rev:
            return {"rev": self.rev, "unchanged": True}
        return {"rev": self.rev, "jobs": list(self.calls)}

    def get(self, job_id):
        for c in self.calls:
            if c["id"] == job_id:
                return c
        raise KeyError(job_id)

    def cancel(self, job_id):
        raise RuntimeError("job %s is not running" % job_id)

    def edit(self, job_id, spec=None, title=None):
        raise ValueError("a running job cannot be edited")

    def status(self):
        return {"queued": len(self.calls), "running": 0, "waiting": 0, "lanes": {}, "qa_online": None}


class Pointed:
    """Re-points the server's folders at a temp tree for the length of a `with`."""

    def __init__(self, server, content, fake_jobs=None):
        self.server, self.content, self.fake = server, content, fake_jobs

    def __enter__(self):
        s = self.server
        self.saved = (s.CONTENT, s.GODOT, s.BACKUPS, s.LEDGER, s.UPLOADS, s.METHODS, s.JOBS)
        root = os.path.dirname(self.content)
        s.CONTENT = self.content
        s.GODOT = os.path.join(root, "no-godot.exe")
        s.BACKUPS = os.path.join(root, "backups")
        s.LEDGER = os.path.join(root, "jobs", "created.json")
        s.UPLOADS = os.path.join(root, "uploads")
        s.METHODS = os.path.join(root, "no-methods.json")
        s.JOBS = self.fake if self.fake is not None else s.JOBS
        return self

    def __exit__(self, *exc):
        s = self.server
        s.CONTENT, s.GODOT, s.BACKUPS, s.LEDGER, s.UPLOADS, s.METHODS, s.JOBS = self.saved
        return False


# ---------------------------------------------------------------- the content operations

def create_checks(check, server):
    tmp = tempfile.mkdtemp(prefix="le_s_create_")
    fake = FakeJobs()
    try:
        content = build_tree(tmp)
        with Pointed(server, content, fake):
            cpath = os.path.join(content, "enemies", "testbeast", "testbeast.json")
            # records
            recs = {c["id"]: c for c in server.list_creatures()}
            tb = recs["testbeast"]
            codes = [l["code"] for l in tb["looks"]]
            check(codes == ["TB-0", "TB-A", "TB-B", "TB-C"] and tb["variants"] is tb["looks"], "looks: the base and every entry, in order: %s" % codes)
            by = {l["code"]: l for l in tb["looks"]}
            check(by["TB-A"]["ready"] and by["TB-A"]["default"] and by["TB-A"]["strip_cols"] == 27 and by["TB-A"]["imported"] is True
                  and by["TB-A"]["anims"] == ENEMY["anims"], "look TB-A: ready, the default, imported (png.import + a newer .tres), its own strip_cols")
            check(by["TB-B"]["ready"] and by["TB-B"]["fresh"] and by["TB-B"]["has_recipe"] and by["TB-B"]["imported"] is False and by["TB-B"]["strip_cols"] == 0
                  and by["TB-B"]["recipe"] == {"motion": "x"}, "look TB-B: fresh, a recipe, not imported (no .import), strip_cols 0 as JsonContent reads it")
            check(not by["TB-C"]["ready"] and by["TB-C"]["imported"] is None and by["TB-C"]["sprite_mtime"] is None, "look TB-C: a stub (no sprite) is not ready")
            check(by["TB-0"]["base"] and by["TB-0"]["ready"] and by["TB-0"]["strip_cols"] == 27 and by["TB-0"]["note"] == "base", "look TB-0: the base strip with its own entry's note")
            check(tb["combo"] == "chase|" and recs["bigboss"]["combo"] == "boss|boss" and tb["file"].endswith("testbeast.json") and isinstance(tb["mtime"], float),
                  "the record carries combo, file and mtime")
            heroes = {h["id"]: h for h in server.list_heroes()}
            check(heroes["hero_a"]["availability"] == "available" and heroes["hero_b"]["availability"] == "hidden" and heroes["hero_a"]["perks"] == ["perk_a"]
                  and heroes["hero_a"]["weapons"] == ["zapper"] and heroes["hero_a"]["looks"] == [] and heroes["hero_a"]["title"] is None,
                  "heroes: availability derived from hidden, perks and weapons by hero, no looks without variants")
            items = server.list_items()
            z = [w for w in items["weapons"] if w["id"] == "zapper"][0]
            check([m["id"] for m in z["mutations"]] == ["zapper_element", "zapper_volume", "zapper_motion"] and z["evolution"]["id"] == "zapper_evo"
                  and z["path"] == ["element", "volume", "motion"] and z["path_missing"] == [] and z["availability"] == "available",
                  "items: a weapon with its three mutations in kind order and its evolution; nothing missing")
            lucky = [p for p in items["passives"] if p["id"] == "lucky"][0]
            line = [p for p in items["lines"] if p["id"] == "brawny"][0]
            check(lucky["availability"] == "locked" and lucky["locked_by"] == "unlock_lucky" and line["evolved"]["id"] == "brawny_evo" and line["availability"] == "available",
                  "items: a quest-locked passive item, a line with its evolved form")
            check(items["band"] == {"locked": 1, "base": 4, "share": 0.25, "lo": 0.33, "hi": 0.56}, "items: the band counts non-hidden base weapons + base passives: %s" % items["band"])
            check([q["id"] for q in items["quests"]] == ["unlock_lucky"], "items: the quests")
            rc = server.read_content("enemy", "testbeast")
            check(rc["ok"] and rc["refs"]["maps"] == ["testmap: skin walker", "testmap: roster r1"] and rc["deletable"] is False and "testbeast_sprite_a.png" in rc["files"]
                  and rc["editable"] and rc["layout"]["unit"] == "  ", "read_content: refs from the map, files, not deletable, editable")
            check(server.read_content("hero", "hero_a")["refs"] == {"maps": [], "quests": [], "weapons": ["zapper"], "evolutions": [], "mutations": [], "characters": [], "perks": ["perk_a"], "passives": []},
                  "read_content: a hero's refs (its weapon, its perk)")
            check(server.read_content("enemy", "nobody")["status"] == 404, "read_content of an unknown id is a 404")

            # create from a template: reset keys, knockback after damage, ledger, a register job
            res = server.create_content("enemy", "newbeast", "testbeast", "New Beast", "Fresh.", "A new beast for the tests.")
            path = os.path.join(content, "enemies", "newbeast", "newbeast.json")
            check(res["ok"] and os.path.isfile(path), "create: the folder and JSON exist: %s" % res.get("error"))
            d = json.load(open(path, encoding="utf-8"))
            keys = list(d.keys())
            check(d["id"] == "newbeast" and d["name"] == "New Beast" and d["flavour"] == "Fresh." and d["doc"] == "A new beast for the tests."
                  and not any(k in d for k in ("sprite", "icon", "anims", "strip_cols", "fps", "head", "variant", "variant_base", "variants", "note"))
                  and d["hp"] == 10.0 and d["blood"] == "#AA1122" and d["pose_fit"] == {"keep": 1},
                  "create: identity reset, art keys dropped, numbers and blood kept, an unknown key kept")
            check(keys.index("knockback") == keys.index("damage") + 1 and d["knockback"] == server.default_knockback(3.0) == 2.94, "create: knockback right after damage = default_knockback(damage)")
            check(_read(path).endswith("\n") and "\r" not in _read(path) and cio.layout(_read(path))["unit"] == "  ", "create: a new file is indent 2, LF, final newline")
            check(server.ledger_load()["ids"]["newbeast"]["kind"] == "enemy" and server.ledger_load()["ids"]["newbeast"]["template"] == "testbeast", "create: the ledger entry")
            check(res["job"] and res["job"]["kind"] == "register" and res["job"]["spec"] == {"targets": ["enemies/newbeast"]}, "create: a register job with the folder: %s" % res.get("job"))
            check(server.read_content("enemy", "newbeast")["deletable"] is True, "a created id is deletable")
            # a boss from an enemy template takes archetype boss
            res = server.create_content("boss", "newboss", "testbeast", "New Boss", "", "A boss.")
            check(res["ok"] and json.load(open(os.path.join(content, "bosses", "newboss", "newboss.json"), encoding="utf-8"))["archetype"] == "boss", "create a boss from an enemy template: archetype boss")
            # refusals
            check(server.create_content("enemy", "zapper", "testbeast", "X", "", "doc")["status"] == 409, "create: an id of another type is refused")
            check(server.create_content("enemy", "testbeast", "testbeast", "X", "", "doc")["status"] == 409, "create: an existing id is refused")
            check(server.create_content("enemy", "training_dummy_x", "testbeast", "X", "", "doc")["status"] == 400, "create: training_dummy* is refused")
            check(server.create_content("enemy", "Bad-Id", "testbeast", "X", "", "doc")["status"] == 400, "create: a bad id is refused")
            check(server.create_content("enemy", "nodoc", "testbeast", "X", "", "")["status"] == 400, "create: a creature without a doc is refused")
            check(server.create_content("enemy", "noname", "testbeast", "", "", "doc")["status"] == 400, "create: no name is refused")
            check(server.create_content("enemy", "notmpl", "nobody", "X", "", "doc")["status"] == 404, "create: an unknown template is a 404")
            check(server.create_content("elite", "x", "y", "X")["status"] == 400, "create: an unknown kind is refused")
            # a hero: hidden + availability + order
            res = server.create_content("hero", "hero_c", "hero_a", "Hero C", "Flavour", "")
            hc = json.load(open(os.path.join(content, "characters", "hero_c", "hero_c.json"), encoding="utf-8"))
            keys = list(hc.keys())
            check(res["ok"] and hc["hidden"] is True and hc["availability"] == "hidden" and hc["price"] == 0 and hc["currency_type"] == "gold" and hc["order"] == 10
                  and keys.index("hidden") == keys.index("pronoun") + 1 and keys[keys.index("hidden"):keys.index("hidden") + 4] == ["hidden", "availability", "price", "currency_type"]
                  and hc["favourite_weapon"] == "zapper" and "sprite" not in hc and "anims" not in hc,
                  "create a hero: hidden, availability hidden, price 0, gold, order max+1, the template's favourites kept: %s" % keys)
            # a passive item: available, evolution links reset
            res = server.create_content("passive", "newline", "brawny", "New Line", "", "")
            nl = json.load(open(os.path.join(content, "passives", "newline", "newline.json"), encoding="utf-8"))
            check(res["ok"] and "hidden" not in nl and nl["evolves_into"] == "" and nl["line"] is True, "create a passive: available, evolves_into reset")
            # a weapon: hidden with 3 + 1 hidden templates and evolves_into set
            res = server.create_content("weapon", "newgun", "zapper", "New Gun", "", "")
            ng = json.load(open(os.path.join(content, "weapons", "newgun", "newgun.json"), encoding="utf-8"))
            check(res["ok"] and ng["hidden"] is True and ng["evolves_into"] == "newgun_evolved" and ng["evolves_with"] == "" and ng["hero"] == "hero_a",
                  "create a weapon: hidden, evolves_into <id>_evolved")
            check(sorted(res["created"]) == sorted(["weapons/newgun", "mutations/newgun_element", "mutations/newgun_volume", "mutations/newgun_motion", "evolutions/newgun_evolved"])
                  and res["job"]["spec"]["targets"] == res["created"], "create a weapon: five folders in one register job: %s" % res["created"])
            for k in ("element", "volume", "motion"):
                m = json.load(open(os.path.join(content, "mutations", "newgun_%s" % k, "newgun_%s.json" % k), encoding="utf-8"))
                check(m["hidden"] is True and m["weapon"] == "newgun" and m["kind"] == k and m["text"] == "" and m["effects"] == [] and m["params"] == {}
                      and m["placeholder"] == {"color": "#AABBCC", "glyph": "star"} and m["rarity"] == "rare" and m["weight"] == 8, "the %s template mutation (accelerant's shape, hidden)" % k)
            ev = json.load(open(os.path.join(content, "evolutions", "newgun_evolved", "newgun_evolved.json"), encoding="utf-8"))
            check(ev["hidden"] is True and ev["is_evolution"] is True and ev["evolved_from"] == "newgun" and ev["max_level"] == 1 and ev["levels"] == [[]]
                  and ev["base"] == WEAPON["base"] and ev["placeholder"]["gold"] is True and ev["name"] == "" and ev["hero"] == "hero_a",
                  "the template evolution (blunderbuss's shape, hidden, no name yet)")
            miss = server.weapon_path_missing("newgun")
            check(any("hidden" in x for x in miss) and any("no text" in x for x in miss) and any("no name yet" in x for x in miss), "the new weapon's path lists what is missing: %s" % miss)
            check(server.set_availability("weapon", "newgun", {"availability": "available"})["status"] == 409, "the new weapon cannot turn available yet (409 with missing)")
            check(len(server.ledger_load()["ids"]) == 9, "the ledger holds every created id: %s" % sorted(server.ledger_load()["ids"]))
            # copy_art renames the PNGs and the names in the JSON
            res = server.create_content("enemy", "twin", "testbeast", "Twin", "", "A twin.", copy_art=True)
            tw = json.load(open(os.path.join(content, "enemies", "twin", "twin.json"), encoding="utf-8"))
            tfolder = os.path.join(content, "enemies", "twin")
            check(res["ok"] and os.path.isfile(os.path.join(tfolder, "twin_sprite_a.png")) and os.path.isfile(os.path.join(tfolder, "twin_icon.png"))
                  and not os.path.exists(os.path.join(tfolder, "twin_sprite_a.png.import")) and tw["variants"]["TB-A"]["sprite"] == "twin_sprite_a.png"
                  and tw["variants"]["TB-A"]["icon"] == "twin_icon_a.png" and tw["variant"] == "TB-A" and tw["anims"] == ENEMY["anims"] and tw["strip_cols"] == 27,
                  "copy_art: PNGs copied and renamed (no .import), names rewritten in the JSON, the art keys kept: %s" % sorted(res["copied"]))
            # make_path on a weapon without a path
            res = server.make_path("blaster")
            bl = json.load(open(os.path.join(content, "weapons", "blaster", "blaster.json"), encoding="utf-8"))
            check(res["ok"] and bl["evolves_into"] == "blaster_evolved" and res["evolution"] == "blaster_evolved" and len(res["created"]) == 5
                  and os.path.isfile(os.path.join(content, "mutations", "blaster_volume", "blaster_volume.json")), "make_path: 3 + 1 templates and evolves_into set: %s" % res.get("error"))
            check(server.make_path("blaster")["status"] == 409, "make_path again is refused (the ids exist)")
            check(server.make_path("nobody")["status"] == 404, "make_path of an unknown weapon is a 404")

            # retire
            r = server.set_retired("enemy", "testbeast", True)
            check(r["status"] == 409 and r["refs"] == ["testmap: skin walker", "testmap: roster r1"], "retire refused when a map names it: %s" % r.get("refs"))
            r = server.set_retired("enemy", "stubby", True)
            check(r["status"] == 409 and "testmap: event 1 (swarm)" in r["refs"] and "bigboss: spawn_ring" in r["refs"], "retire refused for an event's and a spawn_ring's creature: %s" % r.get("refs"))
            r = server.set_retired("enemy", "newbeast", True)
            nb = json.load(open(path, encoding="utf-8"))
            check(r["ok"] and nb["retired"] is True and list(nb.keys()).index("retired") == list(nb.keys()).index("doc") + 1, "retire: `retired: true` after doc")
            r = server.set_retired("enemy", "newbeast", False)
            check(r["ok"] and "retired" not in json.load(open(path, encoding="utf-8")), "unretire removes the key")
            check(server.set_retired("hero", "hero_a", True)["status"] == 400, "a hero does not retire")

            # delete: ledger only, refs, cascade
            check(server.delete_content("enemy", "testbeast")["status"] == 403, "delete refused outside the ledger")
            r = server.delete_content("weapon", "newgun")
            check(r["status"] == 409 and set(r["refs"]) == {"mutations", "evolutions"}, "delete refused while the templates name the weapon: %s" % r.get("refs"))
            r = server.delete_content("weapon", "newgun", cascade=True)
            check(r["ok"] and sorted(r["deleted"]) == sorted(["newgun", "newgun_element", "newgun_volume", "newgun_motion", "newgun_evolved"])
                  and not os.path.exists(os.path.join(content, "weapons", "newgun")) and os.path.isdir(os.path.join(server.BACKUPS, "deleted", "newgun"))
                  and "newgun" not in server.ledger_load()["ids"] and "newgun_evolved" not in server.ledger_load()["ids"],
                  "delete with cascade moves the weapon and its ledger-held templates to backups/deleted: %s" % r)
            r = server.delete_content("enemy", "newbeast")
            check(r["ok"] and not os.path.exists(path) and os.path.isfile(os.path.join(server.BACKUPS, "deleted", "newbeast", os.listdir(os.path.join(server.BACKUPS, "deleted", "newbeast"))[0], "newbeast", "newbeast.json")),
                  "delete a created creature: the folder is moved whole")

            # codes
            nc = server.next_codes("enemy", "testbeast", 3)
            check(nc["codes"] == ["TB-E", "TB-F", "TB-G"] and nc["base_created"] is False and nc["prefix"] == "TB", "next_codes skips stub entries (TB-C) and a suffix with a PNG on disk (d): %s" % nc)
            check(server.next_codes("hero", "hero_a", 2)["codes"] == ["HA-B", "HA-C"] and server.next_codes("hero", "hero_a", 1)["base_created"] is True, "a hero without variants keeps A for its base: next B")
            check(server.next_codes("enemy", "stubby", 1)["codes"] == ["STU-A"], "a one-word id takes its first three letters")
            real_ant = json.load(open(os.path.join(ROOT, "game", "content", "enemies", "fire_ant", "fire_ant.json"), encoding="utf-8"))
            check(server.code_prefix("enemy", "fire_ant", real_ant) == "ANT", "fire_ant's prefix is ANT (the codes win over variant_base '' and the initials)")
            check(server.code_prefix("enemy", "dune_scorpion", {}) == "DS" and server.code_prefix("hero", "x", {"variant_base": "SOL-A"}) == "SOL", "prefix: initials, else variant_base's")

            # add_look: a stub entry; the first look of a file without variants makes the base
            r = server.add_look("enemy", "stubby", None, "first try", {"motion": "m"})
            st = json.load(open(os.path.join(content, "enemies", "stubby", "stubby.json"), encoding="utf-8"))
            check(r["ok"] and r["code"] == "STU-A" and st["variant_base"] == "STU-0" and list(st["variants"].keys()) == ["STU-0", "STU-A"]
                  and st["variants"]["STU-A"] == {"note": "first try", "recipe": {"motion": "m"}} and "fresh" not in st["variants"]["STU-A"]
                  and st["variants"]["STU-0"]["note"].startswith("the top-level strip") and r["import_ok"] is None,
                  "add_look on a file without variants: STU-0 base + the stub, no import: %s" % r.get("error"))
            check(list(st.keys())[-2:] == ["variant_base", "variants"], "variant_base and variants go at the end of a file that had neither: %s" % list(st.keys())[-3:])
            r = server.add_look("hero", "hero_a", "HA-B", "hero look", None)
            ha = json.load(open(os.path.join(content, "characters", "hero_a", "hero_a.json"), encoding="utf-8"))
            check(r["ok"] and ha["variant_base"] == "HA-A" and list(ha["variants"].keys()) == ["HA-A", "HA-B"], "add_look on a hero: the base is -A")
            check(server.add_look("enemy", "testbeast", "TB-A")["status"] == 409 and server.add_look("enemy", "testbeast", "../x")["status"] == 400, "add_look refuses an existing or a bad code")
            check(server.next_codes("enemy", "stubby", 1)["base_created"] is False, "after the first look the base exists")

            # look ops
            r = server.look_op("enemy", "testbeast", ["TB-B"], "approve")
            d = json.load(open(cpath, encoding="utf-8"))
            check(r["ok"] and "fresh" not in d["variants"]["TB-B"] and d["variants"]["TB-B"]["recipe"] == {"motion": "x"} and r["import_ok"] is None, "approve drops fresh, keeps the recipe, no import")
            check(server.look_op("enemy", "testbeast", ["TB-A"], "shelve")["status"] == 409, "shelve refused for the look in play")
            r = server.look_op("enemy", "testbeast", ["TB-B", "TB-C"], "shelve")
            d = json.load(open(cpath, encoding="utf-8"))
            check(r["ok"] and d["variants"]["TB-B"]["shelved"] is True and d["variants"]["TB-C"]["shelved"] is True and r["import_ok"] is False, "bulk shelve of two codes (the import was attempted: no Godot here)")
            r = server.look_op("enemy", "testbeast", ["TB-C"], "unshelve")
            check(r["ok"] and "shelved" not in json.load(open(cpath, encoding="utf-8"))["variants"]["TB-C"], "unshelve drops the key")
            r = server.look_op("enemy", "testbeast", ["TB-C"], "note", {"note": "renamed"})
            check(r["ok"] and json.load(open(cpath, encoding="utf-8"))["variants"]["TB-C"]["note"] == "renamed", "note op")
            r = server.look_op("enemy", "testbeast", ["TB-C"], "recipe", {"recipe": {"motion": "z", "fps": 20}})
            check(r["ok"] and json.load(open(cpath, encoding="utf-8"))["variants"]["TB-C"]["recipe"] == {"motion": "z", "fps": 20}, "recipe op")
            r = server.look_op("enemy", "testbeast", ["TB-C"], "recipe", {"recipe": None})
            check(r["ok"] and "recipe" not in json.load(open(cpath, encoding="utf-8"))["variants"]["TB-C"], "recipe null drops it")
            check(server.look_op("enemy", "testbeast", ["TB-A"], "remove")["status"] == 409, "remove refused for the look in play")
            check(server.look_op("enemy", "testbeast", ["TB-0"], "remove")["status"] == 409, "remove refused for the base strip's code")
            r = server.look_op("enemy", "testbeast", ["TB-B"], "default")
            d = json.load(open(cpath, encoding="utf-8"))
            check(r["ok"] and d["variant"] == "TB-B" and [l for l in r["looks"] if l["code"] == "TB-B"][0]["default"], "default op sets `variant` (write_variant generalised)")
            r = server.look_op("enemy", "testbeast", ["TB-A"], "remove")
            check(r["status"] == 409 and r["refs"] == ["testmap: roster r1"], "remove refused for a code a map row pins: %s" % r.get("refs"))
            server.look_op("enemy", "testbeast", ["TB-A"], "default")
            r = server.look_op("enemy", "testbeast", ["TB-B"], "remove")
            d = json.load(open(cpath, encoding="utf-8"))
            folder = os.path.dirname(cpath)
            check(r["ok"] and "TB-B" not in d["variants"] and not os.path.exists(os.path.join(folder, "testbeast_sprite_b.png"))
                  and not os.path.exists(os.path.join(folder, "testbeast_b_ai.json")) and len(r["moved"]) == 2 and all("deleted/testbeast" in m for m in r["moved"]),
                  "remove: the entry goes, its PNG and _ai marker move to backups/deleted: %s" % r.get("moved"))
            check(os.path.isfile(os.path.join(folder, "testbeast_sprite_a.png")), "remove left the other looks' files alone")
            check(server.look_op("enemy", "testbeast", ["TB-Z"], "approve")["status"] == 404 and server.look_op("enemy", "testbeast", ["TB-C"], "frobnicate")["status"] == 400,
                  "look op: an unknown code is a 404, an unknown op a 400")

            # write_variant for a hero (and the pass 54 creature route still there)
            open(os.path.join(content, "characters", "hero_a", "hero_a_sprite_b.png"), "wb").close()
            hsrc = _read(os.path.join(content, "characters", "hero_a", "hero_a.json"))
            htext = cio.set_variant_entry(hsrc, "HA-B", {"sprite": "hero_a_sprite_b.png"})
            _write(os.path.join(content, "characters", "hero_a", "hero_a.json"), htext)
            r = server.write_variant_kind("hero", "hero_a", "HA-B")
            check(r["ok"] and json.load(open(os.path.join(content, "characters", "hero_a", "hero_a.json"), encoding="utf-8"))["variant"] == "HA-B", "write_variant_kind on a hero")
            check(server.write_variant("testbeast", "TB-A")["ok"] and not server.write_variant("hero_a", "HA-B")["ok"], "write_variant (pass 54) is creatures only")

            # availability: hero
            hpath = os.path.join(content, "characters", "hero_a", "hero_a.json")
            r = server.set_availability("hero", "hero_a", {"availability": "purchase", "price": 900, "currency_type": "gold"})
            h = json.load(open(hpath, encoding="utf-8"))
            keys = list(h.keys())
            check(r["ok"] and h["hidden"] is True and h["availability"] == "purchase" and h["price"] == 900 and h["currency_type"] == "gold"
                  and keys[keys.index("hidden"):keys.index("hidden") + 4] == ["hidden", "availability", "price", "currency_type"] and keys.index("hidden") == keys.index("pronoun") + 1,
                  "hero availability purchase: hidden true + the three keys after pronoun: %s" % r.get("wrote"))
            r = server.set_availability("hero", "hero_a", {"availability": "available"})
            h = json.load(open(hpath, encoding="utf-8"))
            check(r["ok"] and h["hidden"] is False and h["availability"] == "available" and h["price"] == 900, "hero availability available: hidden false, price kept")
            check(server.set_availability("hero", "hero_a", {"availability": "free"})["status"] == 400 and server.set_availability("hero", "hero_a", {"availability": "purchase", "price": -1})["status"] == 400
                  and server.set_availability("hero", "hero_a", {"availability": "purchase", "currency_type": "gems"})["status"] == 400, "hero availability refuses bad values")
            # availability: items
            r = server.set_availability("passive", "lucky", {"availability": "available"})
            check(r["ok"] and not os.path.exists(os.path.join(content, "quests", "unlock_lucky")) and r["moved_to"] and "quest unlock_lucky removed" in r["wrote"]
                  and server.list_items()["passives"][0]["availability"] == "available", "item available: the unlock quest moves to backups/deleted")
            r = server.set_availability("passive", "lucky", {"availability": "locked", "quest": {"condition": {"type": "open_chests", "count": 12}, "quest_text": "Open twelve chests."}})
            q = json.load(open(os.path.join(content, "quests", "unlock_lucky", "unlock_lucky.json"), encoding="utf-8"))
            check(r["ok"] and r["quest"] == "unlock_lucky" and q["condition"] == {"type": "open_chests", "count": 12} and q["unlocks"] == {"type": "passive", "id": "lucky"}
                  and q["quest_text"] == "Open twelve chests." and q["name"] == "Lucky" and list(q.keys())[:4] == ["id", "name", "condition", "unlocks"]
                  and "unlock_lucky" in server.ledger_load()["ids"], "item locked: a new quest in unlock_adrenaline's shape: %s" % list(q.keys()))
            r = server.set_availability("passive", "lucky", {"availability": "locked", "quest": {"condition": {"type": "kills_total", "count": 50}}})
            q = json.load(open(os.path.join(content, "quests", "unlock_lucky", "unlock_lucky.json"), encoding="utf-8"))
            check(r["ok"] and q["condition"] == {"type": "kills_total", "count": 50} and q["quest_text"] == "Open twelve chests.", "item locked again: the quest's condition is edited in place")
            r = server.set_availability("passive", "lucky", {"availability": "hidden"})
            check(r["ok"] and json.load(open(os.path.join(content, "passives", "lucky", "lucky.json"), encoding="utf-8"))["hidden"] is True, "item hidden: hidden true")
            r = server.set_availability("passive", "lucky", {"availability": "available"})
            check(r["ok"] and "hidden" not in json.load(open(os.path.join(content, "passives", "lucky", "lucky.json"), encoding="utf-8")), "item available again: hidden removed, (quest already gone)")
            check(server.set_availability("mutation", "zapper_element", {"availability": "locked"})["status"] == 400, "a mutation cannot be quest-locked")
            check(server.set_availability("enemy", "testbeast", {"availability": "hidden"})["status"] == 400, "creatures have no availability op")
            r = server.set_availability("weapon", "zapper", {"availability": "locked"})
            check(r["ok"] and os.path.isfile(os.path.join(content, "quests", "unlock_zapper", "unlock_zapper.json")) and r["import_ok"] is False, "a complete weapon can be quest-locked (a default condition)")

            # write_content (Save)
            src = _read(cpath)
            d = json.loads(src)
            cur = server.mtime_of(cpath)
            r = server.write_content("enemy", "testbeast", d, cur - 5)
            check(r["status"] == 409 and r["error"] == "changed on disk" and r["mtime"] == cur and _read(cpath) == src, "save with a stale base_mtime is a 409 and writes nothing")
            r = server.write_content("enemy", "testbeast", d, cur)
            check(r["ok"] and r.get("unchanged") and _read(cpath) == src, "save with nothing changed writes nothing")
            new = json.loads(json.dumps(d))
            new["hp"] = 12
            new["name"] = "Test Beast II"
            new.pop("sfx")
            new.pop("pose_fit")
            new["brand_new"] = {"a": 1}
            new["drops"]["gold"] = 0.05
            r = server.write_content("enemy", "testbeast", new, cur)
            after = _read(cpath)
            a = json.loads(after)
            check(r["ok"] and sorted(r["changed"]) == ["brand_new", "drops", "hp", "name"] and r["removed"] == ["sfx"] and a["hp"] == 12.0 and '"hp": 12.0' in after
                  and "sfx" not in a and a["pose_fit"] == {"keep": 1} and a["brand_new"] == {"a": 1} and list(a.keys())[-1] == "brand_new" and a["drops"]["gold"] == 0.05
                  and r["import_ok"] is False and isinstance(r["mtime"], float), "save: changed keys rewritten (12 stays a float), an owned key removed, an unknown key kept, a new key at the end")
            changed, na, nb = _lines_diff(src, after)
            check(len([f for f in os.listdir(server.BACKUPS) if f.startswith("testbeast-")]) >= 1, "save left a backup")
            new2 = json.loads(after)
            new2 = {k: v for k, v in new2.items()}
            items_ = list(new2.items())
            items_.insert(items_.index(("speed", 2.0)) + 1, ("contact_cd", 0.4))
            new2 = dict(items_)
            r = server.write_content("enemy", "testbeast", new2, server.mtime_of(cpath))
            a = json.loads(_read(cpath))
            check(r["ok"] and list(a.keys()).index("contact_cd") == list(a.keys()).index("speed") + 1, "save: a new key lands after the key before it in the document")
            check(server.write_content("enemy", "testbeast", {"id": "other"}, None)["status"] == 400, "save refuses a document with another id")
            check(server.write_content("enemy", "nobody", {"id": "nobody"}, None)["status"] == 404, "save of an unknown id is a 404")
            compact_path = os.path.join(content, "enemies", "flat", "flat.json")
            _write(compact_path, '{"id": "flat", "name": "Flat", "hp": 1, "damage": 1, "knockback": 2.5, "blood": "#AA1122", "doc": "x"}')
            r = server.write_content("enemy", "flat", {"id": "flat", "name": "Flat", "hp": 2, "damage": 1, "knockback": 2.5, "blood": "#AA1122", "doc": "x"}, None)
            check(r["status"] == 400 and r["error"].startswith("layout:") and _read(compact_path).startswith('{"id": "flat"'), "save on a compact one-line file is refused with nothing written")
            check(not server.write_variant("flat", "X")["ok"], "write_variant on a compact file is refused (no re-dump)")
            check(not server.write_blood("flat", "#123456")["ok"] and _read(compact_path).startswith('{"id": "flat"'), "write_blood on a compact file is refused (no re-dump)")

            # hooks
            hooks = server.HOOKS
            check(hooks["content_path"]("enemy", "testbeast")[0] == "enemies" and hooks.get("content_path")("enemy", "nobody") == (None, None)
                  and hooks.content_path("hero", "hero_a")[1].endswith("hero_a.json"), "hooks: content_path by item and by attribute")
            src = _read(cpath)
            r = hooks.merge_look("enemy", "testbeast", "TB-C", {"sprite": "testbeast_sprite_c.png", "icon": "testbeast_icon_c.png", "anims": {"idle": 4, "run": 12}, "strip_cols": 16, "fps": {"run": 15}, "head": 0.85}, {"renders": {}})
            d = json.loads(_read(cpath))
            e = d["variants"]["TB-C"]
            check(r["ok"] and r["layout"] == "block" and e["note"] == "renamed" and e["sprite"] == "testbeast_sprite_c.png" and e["strip_cols"] == 16 and e["fresh"] is True
                  and list(e.keys())[0] == "note" and r["backup"] and r["keys"] == ["variants"], "merge_look: the sidecar's entry merged over the stub (note kept), fresh, layout block on a dump-style file: %s" % r)
            check(cio.diff_within_entry(src, _read(cpath), "TB-C"), "merge_look touched only the entry's lines")
            r = hooks.merge_look("enemy", "testbeast", "TB-Q", {"sprite": "q.png"}, None)
            d = json.loads(_read(cpath))
            check(r["ok"] and d["variants"]["TB-Q"] == {"sprite": "q.png", "fresh": True}, "merge_look of a code without a stub creates the entry")
            # a hand-laid block: the entry write is the one that fits
            hand = os.path.join(content, "enemies", "handy", "handy.json")
            _write(hand, '{\n  "id": "handy",\n  "name": "Handy",\n  "hp": 1,\n  "variant_base": "HD-0",\n  "variants": {\n    "HD-0": {"note": "base"},\n    "HD-A": {"note": "a", "recipe": {"k": [1, 2]}}\n  }\n}\n')
            r = hooks.merge_look("enemy", "handy", "HD-A", {"sprite": "handy_sprite_a.png"}, None)
            t = _read(hand)
            check(r["ok"] and r["layout"] == "entry" and '"HD-0": {"note": "base"},' in t and json.loads(t)["variants"]["HD-A"] == {"note": "a", "recipe": {"k": [1, 2]}, "sprite": "handy_sprite_a.png", "fresh": True},
                  "merge_look on a hand-laid block: layout entry, the other one-line entry untouched")
            r = hooks.merge_look("enemy", "handy", "HD-B", {"sprite": "handy_sprite_b.png"}, None)
            t = _read(hand)
            check(r["ok"] and r["layout"] == "entry" and '"HD-0": {"note": "base"},' in t and json.loads(t)["variants"]["HD-B"]["fresh"] is True, "merge_look of a new entry into a hand-laid block keeps the old lines")
            bad = os.path.join(content, "enemies", "listy", "listy.json")
            odd = '{\n  "id": "listy", "name": "Listy",\n  "variants": {}\n}\n'
            _write(bad, odd)
            r = hooks.merge_look("enemy", "listy", "LI-A", {"sprite": "x.png"}, None)
            check(not r["ok"] and r["layout"] == "unmerged" and _read(bad) == odd, "merge_look that fits neither way (two keys on one line): unmerged, nothing written")
            r = hooks.redump_merge("enemy", "listy", "LI-A", {"sprite": "x.png"})
            d = json.loads(_read(bad))
            check(r["ok"] and r["layout"] == "redumped" and d["variants"]["LI-A"] == {"sprite": "x.png", "fresh": True} and d["variant_base"] == "LIS-0"
                  and _read(bad).startswith('{\n  "id": "listy",\n  "name": "Listy",\n'), "redump_merge (explicit) re-dumps and lands the entry (a one-word id: LIS-0)")
            listy2 = os.path.join(content, "enemies", "listy2", "listy2.json")
            _write(listy2, '{\n  "id": "listy2",\n  "name": "Listy",\n  "variants": []\n}\n')
            r = hooks.merge_look("enemy", "listy2", "LI-A", {"sprite": "x.png"}, None)
            d = json.loads(_read(listy2))
            check(r["ok"] and d["variant_base"] == "LIS-0" and d["variants"]["LI-A"]["fresh"] is True, "a `variants` that is not an object is replaced by one before the merge")
            r = hooks.merge_look("enemy", "stubby", "STU-A", {"sprite": "stubby_sprite_a.png", "anims": {"idle": 2}}, None)
            d = json.loads(_read(os.path.join(content, "enemies", "stubby", "stubby.json")))
            check(r["ok"] and d["variants"]["STU-A"]["recipe"] == {"motion": "m"} and d["variants"]["STU-A"]["sprite"] == "stubby_sprite_a.png", "merge_look keeps the stub's recipe")
            r = hooks.merge_top("enemy", "stubby", {"anims": {"idle": 4, "run": 8}, "strip_cols": 12, "fps": {"run": 10}, "head": 0.9, "art_prompt": "ignored: there is none? no: set"})
            d = json.loads(_read(os.path.join(content, "enemies", "stubby", "stubby.json")))
            keys = list(d.keys())
            check(r["ok"] and r["layout"] == "block" and d["anims"] == {"idle": 4, "run": 8} and d["strip_cols"] == 12 and d["fps"] == {"run": 10} and d["head"] == 0.9
                  and d["art_prompt"].startswith("ignored") and keys.index("strip_cols") == keys.index("anims") + 1 and keys.index("fps") == keys.index("strip_cols") + 1
                  and keys.index("head") == keys.index("fps") + 1 and sorted(r["keys"]) == ["anims", "art_prompt", "fps", "head", "strip_cols"],
                  "merge_top: anims, strip_cols, fps, head in a row; art_prompt set when absent: %s" % keys)
            r = hooks.merge_top("enemy", "testbeast", {"art_prompt": "not this", "head": 0.8})
            check(r["ok"] and r.get("unchanged") and json.loads(_read(cpath))["art_prompt"] == "a test beast", "merge_top leaves an existing art_prompt and an equal value alone")
            r = hooks.set_recipe("enemy", "testbeast", "TB-C", {"motion": "set by the job"}, note="job note")
            e = json.loads(_read(cpath))["variants"]["TB-C"]
            check(r["ok"] and e["recipe"] == {"motion": "set by the job"} and e["note"] == "job note" and e["sprite"] == "testbeast_sprite_c.png", "set_recipe writes recipe and note into the entry")
            r = hooks.set_recipe("hero", "hero_b", "HB-B", {"pose": "walk"})
            hb = json.loads(_read(os.path.join(content, "characters", "hero_b", "hero_b.json")))
            check(r["ok"] and hb["variant_base"] == "HB-A" and hb["variants"]["HB-B"] == {"recipe": {"pose": "walk"}}, "set_recipe on a hero without variants makes the base and the stub")
            lr = hooks.look_records("enemy", "testbeast")
            check([l["code"] for l in lr] == ["TB-0", "TB-A", "TB-C", "TB-Q"] and lr[2]["fresh"] is True, "hooks.look_records: the current looks: %s" % [l["code"] for l in lr])
            r = hooks.merge_look("hero", "hero_b", "HB-B", {"sprite": "hero_b_sprite_b.png"}, None)
            hb = json.loads(_read(os.path.join(content, "characters", "hero_b", "hero_b.json")))
            check(r["ok"] and hb["variants"]["HB-B"]["fresh"] is True and "frame_px" not in hb["variants"]["HB-B"], "merge_look on a hero (no frame_px in the recipe: none written)")
            hooks.set_recipe("hero", "hero_b", "HB-C", {"frame_px": 320})
            r = hooks.merge_look("hero", "hero_b", "HB-C", {"sprite": "hero_b_sprite_c.png"}, None)
            hb = json.loads(_read(os.path.join(content, "characters", "hero_b", "hero_b.json")))
            check(r["ok"] and hb["variants"]["HB-C"]["frame_px"] == 320, "merge_look on a hero copies the recipe's frame_px into the entry")

            # the jobs stand-in and the enqueue wrapper
            check(server.jobs_module() is fake and server._enqueue("register", {"kind": "enemy", "id": "x"}, {"targets": ["enemies/x"]})["job"]["kind"] == "register", "_enqueue goes through the jobs module")
            fake.raise_value = True
            r = server._enqueue("register", {}, {})
            check(r["job"] is None and "bad spec" in r["error"], "_enqueue never raises: a bad spec comes back as an error")
            fake.raise_value = False
            check(server.jobs_call("get", "nope")[0] == 404 and server.jobs_call("cancel", "j1")[0] == 409 and server.jobs_call("edit", "j1", {})[0] == 400
                  and server.jobs_call("nothing_here")[0] == 501, "jobs_call maps KeyError 404, RuntimeError 409, ValueError 400, a missing function 501")
            server.JOBS = None
            saved_err = server._jobs_error[0]
            # the real jobs.py may be here (lane J): either way the wrapper answers without raising
            m = server.jobs_module()
            check(m is None or hasattr(m, "enqueue"), "jobs_module: the real module or None")
            server.JOBS = fake
            server._jobs_error[0] = saved_err
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- the vocabularies

def vocab_checks(check, server):
    problems = vocab.check_against_source(server.GAME)
    check(problems == [], "vocab.py matches the Godot sources: %s" % problems)
    t = vocab.table(server.CONTENT, server.GAME, {"chase|", "boss|boss"})
    check(t["ok"] and t["note"] == vocab.NOTE and t["brains"][0] == "chase" and len(t["attacks"]) == 14 and t["combos_seen"] == ["boss|boss", "chase|"],
          "the vocab table: brains, 14 attacks, combos_seen sorted")
    check(set(t["params_keys"]) == set(vocab.BEHAVIOURS) | {"*"}, "PARAMS_KEYS covers every behaviour")
    check("en" in t["sounds"] and "w" in t["sounds"] and "all" in t["sounds"] and len(t["sounds"]["all"]) >= 128, "sound ids grouped by prefix from soundmap.json: %s" % sorted(t["sounds"]))
    check(t["elites"] == ["explosive", "shielded", "speedy", "splitter"] and "heart" in t["pickups"], "elite modifier and pickup ids from the folders")
    check(t["rarity_plate"] == {"common": "d2cfc7", "uncommon": "8cc97a", "rare": "6b9fd8", "epic": "a585c8", "legendary": "e0a060"}, "the five plate colours (W.gd)")
    check(len(t["player_stats"]) == len(vocab.PLAYER_DEFAULTS) + 4 and "brand_chance" in t["player_stats"] and t["stat_names"]["might"] == ["attack damage", "pct"],
          "player stats + the four the code reads without a default; TextGen names")
    check(all(a["telegraph"] in vocab.TELEGRAPHS for a in t["attacks"].values()) and t["attacks"]["boulder"]["needs_ring_at_hero"] and not t["attacks"]["slam"]["needs_ring_at_hero"],
          "every attack's default telegraph is a telegraph; ring_at_hero needs marked")
    check(json.dumps(t) and t["quest_types"]["kill_boss"] == ["map", "stage"] and t["currencies"] == ["gold"], "the table is JSON and names the quest keys")
    check(vocab.check_against_source(os.path.join(server.GAME, "nowhere")) != [], "a wrong game folder fails loudly")


# ---------------------------------------------------------------- the routes over HTTP

class _Dummy:
    def __init__(self, command, path):
        self.command, self.path = command, path


def routes_checks(check, server):
    import io
    import sys as _sys
    # quiet log_message
    out = io.StringIO()
    keep = _sys.stdout
    _sys.stdout = out
    try:
        for cmd, p in (("GET", "/api/jobs?since=3"), ("GET", "/api/job/j1"), ("GET", "/dl/drivers/run/meta.json"), ("GET", "/icon/enemy/goblin"),
                       ("GET", "/sprite/hero/solenne"), ("GET", "/art/wanted/hero_astro.png"), ("GET", "/examples/x.png"), ("GET", "/api/status")):
            server.Handler.log_message(_Dummy(cmd, p), "%s")
        quiet = out.getvalue()
        for cmd, p in (("POST", "/api/jobs"), ("GET", "/api/maps"), ("POST", "/api/content/enemy/goblin/save")):
            server.Handler.log_message(_Dummy(cmd, p), "%s")
        loud = out.getvalue()
    finally:
        _sys.stdout = keep
    check(quiet == "" and loud.count("\n") == 3, "log_message is quiet for the polled GETs and says the rest: %r" % loud)

    tmp = tempfile.mkdtemp(prefix="le_s_routes_")
    fake = FakeJobs()
    httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    th = threading.Thread(target=httpd.serve_forever, daemon=True)
    th.start()
    base = "http://127.0.0.1:%d" % httpd.server_address[1]

    def get(url, raw=False):
        try:
            with urllib.request.urlopen(base + url, timeout=30) as r:
                data = r.read()
                return r.status, (data if raw else (json.loads(data.decode("utf-8")) if r.headers.get("Content-Type", "").startswith("application/json") else data.decode("utf-8", "replace"))), dict(r.headers)
        except urllib.error.HTTPError as e:
            data = e.read()
            try:
                return e.code, json.loads(data.decode("utf-8")), dict(e.headers)
            except ValueError:
                return e.code, data, dict(e.headers)

    def post(url, body, headers=None):
        data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
        h = {"Content-Type": "application/json"}
        h.update(headers or {})
        req = urllib.request.Request(base + url, data=data, method="POST", headers=h)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw.decode("utf-8"))
            except ValueError:
                return e.code, raw

    def raw_request(lines):
        s = socket.create_connection(("127.0.0.1", httpd.server_address[1]), timeout=10)
        try:
            s.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("ascii"))
            data = b""
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
                if b"\r\n\r\n" in data:
                    head, _, body = data.partition(b"\r\n\r\n")
                    m = [l for l in head.split(b"\r\n") if l.lower().startswith(b"content-length:")]
                    if m and len(body) >= int(m[0].split(b":")[1]):
                        break
            return data.decode("utf-8", "replace")
        finally:
            s.close()

    try:
        # the real content, read only
        st, body, h = get("/dl/../etc/x.txt")
        check(st == 404, "/dl/../x is a 404 (%s)" % st)
        st, body, h = get("/dl/backup/x.png")
        check(st == 404, "/dl/backup/x is a 404 (an unknown root)")
        st, body, h = get("/dl/drivers/run/meta.json")
        check(st == 200 and isinstance(body, dict) and body.get("frames") == 24 and h.get("Cache-Control") == "max-age=60", "/dl/drivers/run/meta.json is served with max-age=60: %s" % st)
        st, body, h = get("/dl/drivers/run/front/")
        check(st == 200 and body.get("ok") and any(f["name"].startswith("driver_") for f in body["files"]), "/dl/<dir>/ lists the folder as JSON")
        st, body, h = get("/dl/drivers/run/meta.exe")
        check(st == 404, "/dl with an extension outside the list is a 404")
        st, body, h = get("/icon/hero/astro", raw=True)
        check(st == 200 and body[:8] == b"\x89PNG\r\n\x1a\n", "/icon/hero/astro is a PNG")
        st, body, h = get("/icon/weapon/revolver", raw=True)
        check(st == 200 and body[:4] == b"\x89PNG", "/icon/weapon/revolver is a PNG")
        st, body, h = get("/icon/passive/brawn", raw=True)
        check(st == 200, "/icon/passive/brawn 200")
        st, body, h = get("/icon/mutation/accelerant", raw=True)
        check(st == 200, "/icon/mutation/accelerant 200")
        st, body, h = get("/icon/evolution/blunderbuss", raw=True)
        check(st == 200, "/icon/evolution/blunderbuss 200")
        st, body, h = get("/art/wanted/hero_astro.png", raw=True)
        check(st == 200 and body[:4] == b"\x89PNG", "/art/wanted/hero_astro.png is a PNG")
        st, body, h = get("/art/wanted/kind_weapon.png")
        check(st == 404, "/art/wanted serves only hero_<id>.png")
        st, body, h = get("/art/wanted/hero_nobody.png")
        check(st == 404, "a missing cut-out is a 404")
        st, body, h = get("/sprite/hero/solenne/SOL-B", raw=True)
        check(st == 200 and body[:4] == b"\x89PNG" and len(body) > 100000, "/sprite/hero/solenne/SOL-B is the strip (%d bytes)" % len(body))
        st, body, h = get("/sprite/weapon/revolver")
        check(st == 404, "/sprite is for enemies, bosses and heroes only")
        st, body, h = get("/sound/ui_tap", raw=True)
        check(st == 200 and body[:4] == b"RIFF" and h.get("Content-Type") == "audio/wav", "/sound/ui_tap is the wav")
        st, body, h = get("/sound/nope")
        check(st == 404, "an unknown sound id is a 404")
        st, body, h = get("/examples/nope.png")
        check(st == 404, "a missing example is a 404")
        st, body, h = get("/api/items")
        rv = [w for w in body["weapons"] if w["id"] == "revolver"][0]
        check(st == 200 and [m["id"] for m in rv["mutations"] if not m["hidden"]] == ["silver_bullet", "hip_shot", "trick_shot"] and rv["evolution"]["id"] == "golden_revolver"
              and rv["path"] == ["element", "volume", "motion"] and rv["availability"] == "available" and rv["hero"] == "drifter",
              "/api/items groups the Revolver with its mutations (kind order) and the Golden Revolver")
        check(body["band"]["locked"] == 23 and body["band"]["base"] == 67 and 0.33 <= body["band"]["share"] <= 0.56, "the band is 23 of 67 as pass44_test counts it: %s" % body["band"])
        check(len(body["lines"]) == 15 and all(l["evolved"] for l in body["lines"]) and len(body["passives"]) == 31 and len(body["quests"]) == 24, "15 lines with evolved forms, 31 passive items, 24 quests")
        check(all(m["availability"] in ("hidden", "available") for w in body["weapons"] for m in w["mutations"]), "mutations are hidden or available, never locked")
        st, body, h = get("/api/heroes")
        sol = [x for x in body if x["id"] == "solenne"][0]
        check(st == 200 and len(body) == 8 and [x["id"] for x in body[:5]] == ["drifter", "astro", "calavera", "ironwood", "solenne"] and [l["code"] for l in sol["looks"]] == ["SOL-A", "SOL-B", "SOL-C", "SOL-D", "SOL-E"]
              and sol["title"] == "/art/wanted/hero_solenne.png" and sol["hero_mutations"] == ["sun_cocktail"] and sol["weapons"] == ["sun_scepter"] and body[5]["availability"] == "hidden",
              "/api/heroes: the five in play first by order, Solenne's five looks, title, her mutation and weapon, the hidden three after")
        check(sol["looks"][1]["frame_px"] == 256 and sol["looks"][1]["imported"] in (True, False) and sol["looks"][1]["sprite_mtime"], "a hero look record carries frame_px, imported and sprite_mtime")
        st, body, h = get("/api/vocab")
        check(st == 200 and body["ok"] and "brains" in body and body["note"] == vocab.NOTE and len(body["combos_seen"]) >= 5, "/api/vocab")
        st, body, h = get("/api/templates/enemy")
        check(st == 200 and any(t["id"] == "lesser_scorpion" for t in body) and not any(t["id"] == "goblin" for t in body) and not any(t["id"].startswith("training_dummy") for t in body),
              "/api/templates/enemy leaves the retired and the dummies out")
        st, body, h = get("/api/templates/pickup")
        check(st == 404, "/api/templates of a non-edit kind is a 404")
        st, body, h = get("/api/content/enemy/lesser_scorpion")
        check(st == 200 and body["ok"] and body["json"]["id"] == "lesser_scorpion" and body["text"].startswith("{") and len(body["looks"]) == 3 and "lesser_scorpion_sprite_b.png" in body["files"]
              and body["deletable"] is False and isinstance(body["mtime"], float), "/api/content/enemy/lesser_scorpion: text, json, looks, files, mtime")
        st, body, h = get("/api/content/weapon/revolver")
        check(st == 200 and body["refs"]["characters"] == ["drifter"] and "silver_bullet" in body["refs"]["mutations"] and body["path_missing"] == [], "/api/content/weapon/revolver: refs and an empty path_missing")
        st, body, h = get("/api/content/enemy/lesser_scorpion/next_codes?n=2")
        check(st == 200 and body["codes"] == ["LS-D", "LS-E"], "/api/content/.../next_codes?n=2")
        st, body, h = get("/api/content/pickup/heart")
        check(st == 404, "/api/content of a non-edit kind is a 404")
        st, body, h = get("/api/drivers")
        check(st == 200 and any(d["name"] == "run" and d["kind"] == "pose" and d["frames"] == 24 and d["sheet"] == "/dl/drivers/run/all_sheet.png" for d in body)
              and any(d["name"] == "beetle_walk" and d["kind"] == "depth" and "side" in d["views"] for d in body), "/api/drivers: pose and depth drivers from meta.json")
        st, body, h = get("/api/refs")
        check(st == 200 and set(body) == {"2d", "3d"}, "/api/refs")
        st, body, h = get("/api/schema/assets")
        check(st == 200 and isinstance(body, str), "/api/schema/assets is text (the doc or a note that it is missing)")
        st, body, h = get("/api/status")
        check(st == 200 and body["ok"] and "blender" in body and "qa_online" in body and set(body["locks"]) == {"comfy", "godot", "jobs"} and "jobs_available" in body
              and body["godot"] is True, "/api/status: blender, qa_online, locks, jobs")
        # the pass 53/54 routes still answer
        st, body, h = get("/api/enemies")
        sk = [c for c in body if c["id"] == "skeleton"][0]
        check(st == 200 and sk["icon_play"] == "/icon/enemy/skeleton/%s" % sk["play"] and all(k in sk["variants"][0] for k in ("code", "note", "icon", "sprite", "ready", "base"))
              and sk["looks"] == sk["variants"] and all(k in sk["looks"][0] for k in ("anims", "fps", "strip_cols", "frame_px", "head", "front_faces", "back_faces", "shelved", "fresh", "imported", "sprite_mtime", "has_recipe", "recipe")),
              "/api/enemies keeps every pass 54/58 key and the looks carry the pass 66 fields")

        # the jobs wrappers against the stand-in, and the write routes on a temp tree
        content = build_tree(tmp)
        with Pointed(server, content, fake):
            st, body, h = get("/api/jobs")
            check(st == 200 and body["rev"] == 7 and body["jobs"] == [] and body["ok"] is True, "/api/jobs: {rev, jobs}")
            st, body, h = get("/api/jobs?since=7")
            check(st == 200 and body["unchanged"] is True and body["rev"] == 7, "/api/jobs?since=<rev>: {rev, unchanged}")
            st, body = post("/api/jobs", {"kind": "look", "target": {"kind": "enemy", "id": "testbeast", "code": "TB-E"}, "spec": {"method": "creature_proc"}})
            check(st == 200 and body["ok"] and body["job"]["id"] == "j1" and body["job"]["kind"] == "look", "POST /api/jobs enqueues: %s" % body)
            st, body, h = get("/api/job/j1")
            check(st == 200 and body["job"]["id"] == "j1", "/api/job/<id>")
            st, body, h = get("/api/job/nope")
            check(st == 404, "/api/job/<unknown> is a 404")
            st, body = post("/api/jobs/j1/cancel", {})
            check(st == 409 and not body["ok"], "a jobs op the state does not allow is a 409")
            st, body = post("/api/jobs/j1", {"spec": {}})
            check(st == 400, "a bad edit is a 400")
            st, body = post("/api/jobs/j1/frob", {})
            check(st == 404, "an unknown jobs op is a 404")
            st, body = post("/api/jobs", {"target": {}})
            check(st == 400, "POST /api/jobs without a kind is a 400")
            st, body = post("/api/test_launch", {"character": "hero_a", "look": "HA-B", "count": 2})
            check(st == 200 and body["job"]["kind"] == "launch" and body["spec"] == {"map": "red_canyon", "count": 2, "character": "hero_a", "look": "HA-B"}
                  and body["job"]["target"] == {"kind": "hero", "id": "hero_a", "code": "HA-B"}, "/api/test_launch queues a launch job with the hero and the look: %s" % body.get("spec"))
            st, body = post("/api/test_launch", {"enemy": "testbeast", "variant": "TB-A"})
            check(st == 200 and body["spec"]["spawn_enemy"] == "testbeast" and body["spec"]["count"] == 3, "/api/test_launch with a creature: count 3")
            # the status with the stand-in
            st, body, h = get("/api/status")
            check(st == 200 and body["jobs"]["queued"] == 3 and body["jobs_available"], "/api/status carries jobs.status()")
            # methods.json missing -> {methods: []}
            st, body, h = get("/api/methods")
            check(st == 200 and body["methods"] == [] and body["missing"] is True, "/api/methods without the file: {methods: []}")
            # content writes over HTTP
            cpath = os.path.join(content, "enemies", "testbeast", "testbeast.json")
            st, body, h = get("/api/content/enemy/testbeast")
            doc = body["json"]
            doc["hp"] = 11
            st, body = post("/api/content/enemy/testbeast/save", {"json": doc, "base_mtime": 1.0})
            check(st == 409 and body["error"] == "changed on disk" and "mtime" in body, "save with a stale mtime is a 409 over HTTP")
            st, body = post("/api/content/enemy/testbeast/save", {"json": doc, "base_mtime": server.mtime_of(cpath)})
            check(st == 200 and body["ok"] and body["changed"] == ["hp"] and json.load(open(cpath, encoding="utf-8"))["hp"] == 11.0 and body["import_ok"] is False,
                  "save over HTTP writes the one key (no Godot here: import_ok false)")
            st, body = post("/api/content/enemy", {"id": "webbeast", "template": "testbeast", "name": "Web Beast", "doc": "Made over HTTP."})
            check(st == 200 and body["ok"] and os.path.isfile(os.path.join(content, "enemies", "webbeast", "webbeast.json")) and body["job"]["kind"] == "register", "create over HTTP")
            st, body = post("/api/content/enemy", {"id": "webbeast", "template": "testbeast", "name": "Web Beast", "doc": "x"})
            check(st == 409, "create of an existing id over HTTP is a 409")
            st, body = post("/api/content/enemy/testbeast/look/TB-B", {"op": "approve"})
            check(st == 200 and body["ok"] and not [l for l in body["looks"] if l["code"] == "TB-B"][0]["fresh"], "a look op over HTTP")
            st, body = post("/api/content/enemy/testbeast/look", {"op": "shelve", "codes": ["TB-B", "TB-C"]})
            check(st == 200 and body["ok"] and body["codes"] == ["TB-B", "TB-C"], "a bulk look op over HTTP")
            st, body = post("/api/content/enemy/testbeast/look", {"note": "new stub"})
            check(st == 200 and body["ok"] and body["code"] == "TB-E", "add a look over HTTP takes the next code")
            st, body = post("/api/content/enemy/testbeast/look/TB-A", {"op": "shelve"})
            check(st == 409, "shelving the look in play over HTTP is a 409")
            st, body = post("/api/content/enemy/testbeast/retire", {"retired": True})
            check(st == 409 and body["refs"], "retire over HTTP: 409 with refs")
            st, body = post("/api/content/hero/hero_a/availability", {"availability": "purchase", "price": 10})
            check(st == 200 and body["ok"] and sorted(body["wrote"]) == ["availability", "currency_type", "hidden", "price"], "hero availability over HTTP: %s" % body.get("wrote"))
            st, body = post("/api/content/weapon/zapper/make_path", {})
            check(st == 409, "make_path over HTTP on a weapon with a path is a 409")
            st, body = post("/api/content/enemy/webbeast/delete", {})
            check(st == 200 and body["ok"] and not os.path.exists(os.path.join(content, "enemies", "webbeast")), "delete over HTTP")
            st, body = post("/api/content/enemy/testbeast/delete", {})
            check(st == 403, "delete outside the ledger over HTTP is a 403")
            st, body = post("/api/content/hero/hero_a/variant", {"code": "HA-Z"})
            check(st == 400 and "cannot play" in body["error"], "variant op over HTTP refuses an unknown code")
            st, body = post("/api/content/pickup/heart/save", {"json": {}})
            check(st == 404, "a non-edit kind on a POST is a 404")
            # upload: the cap, the missing length, a real small file
            r = raw_request(["POST /api/upload HTTP/1.1", "Host: x", "X-Kind: 2d", "X-Filename: big.png", "Content-Length: 300000000", "Connection: close"])
            check(r.startswith("HTTP/1.0 413") or r.startswith("HTTP/1.1 413"), "an upload over 200 MB is a 413 before any byte is read: %s" % r.split("\r\n")[0])
            r = raw_request(["POST /api/upload HTTP/1.1", "Host: x", "X-Kind: 2d", "X-Filename: nolength.png", "Connection: close"])
            check(" 411 " in r.split("\r\n")[0], "an upload without Content-Length is a 411: %s" % r.split("\r\n")[0])
            png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 3000
            st, body = post("/api/upload", png, {"Content-Type": "application/octet-stream", "X-Kind": "2d", "X-Filename": "ref-pic_1.png"})
            check(st == 200 and body["ok"] and body["url"] == "/dl/uploads/2d/ref-pic_1.png" and os.path.getsize(os.path.join(server.UPLOADS, "2d", "ref-pic_1.png")) == len(png) and body["size"] == len(png),
                  "a 2D upload lands under uploads/2d: %s" % body)
            st, body = post("/api/upload", png, {"Content-Type": "application/octet-stream", "X-Kind": "2d", "X-Filename": "ref-pic_1.png"})
            check(st == 200 and body["name"] == "ref-pic_1_2.png", "a second upload with the same name gets a numbered name")
            st, body = post("/api/upload", b"glTF" + b"\x00" * 100, {"Content-Type": "application/octet-stream", "X-Kind": "3d", "X-Filename": "My Model.glb"})
            check(st == 400, "a 3D name with a space is refused")
            st, body = post("/api/upload", b"glTF" + b"\x00" * 100, {"Content-Type": "application/octet-stream", "X-Kind": "3d", "X-Filename": "MyModel.glb"})
            check(st == 200 and body["slug"] == "mymodel" and os.path.isfile(os.path.join(server.UPLOADS, "3d", "mymodel", "MyModel.glb")) and body["job"]["kind"] == "ref_probe"
                  and body["job"]["spec"] == {"src": "tools/dl/uploads/3d/mymodel/MyModel.glb"} or (st == 200 and body["job"]["kind"] == "ref_probe"),
                  "a 3D upload gets its own folder and a ref_probe job: %s" % body)
            st, body = post("/api/upload", b"x" * 10, {"Content-Type": "application/octet-stream", "X-Kind": "2d", "X-Filename": "evil.exe"})
            check(st == 400, "an upload with the wrong extension is a 400")
            st, body = post("/api/upload", b"x" * 10, {"Content-Type": "application/octet-stream", "X-Kind": "4d", "X-Filename": "a.png"})
            check(st == 400, "an upload with an unknown X-Kind is a 400")
            st, body, h = get("/api/refs")
            check(st == 200 and [x["name"] for x in body["2d"]] == ["ref-pic_1.png", "ref-pic_1_2.png"] and body["3d"][0]["slug"] == "mymodel" and body["3d"][0]["file"] == "MyModel.glb"
                  and body["3d"][0]["probe"] is None, "/api/refs lists the uploads: %s" % [x["name"] for x in body["2d"]])
            st, body, h = get("/dl/uploads/2d/ref-pic_1.png", raw=True)
            check(st == 200 and body == png, "the uploaded picture is served under /dl/uploads/2d/")
    finally:
        httpd.shutdown()
        httpd.server_close()
        shutil.rmtree(tmp, ignore_errors=True)


def checks(check, run_node, server):
    write_checks(check, server)
    create_checks(check, server)
    vocab_checks(check, server)
    routes_checks(check, server)
