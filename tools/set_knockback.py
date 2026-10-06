"""Pass 54 (Garry, 2026-10-06: "every creature gets its own knockback number, set from its damage"): writes an explicit
top-level `"knockback"` (m/s, the shove the hero takes from one bite) into every creature and boss JSON, right after
its top-level `"damage"`, from the same rule as EnemyDef.default_knockback:

    knockback = clamp(3.4 * sqrt(damage / 4), 2.5, 7.0)     (2 decimals)

so a 4-damage bite shoves 3.4 m/s, about 35 % over the old fixed 2.5. A file that already has a top-level `knockback`
is left alone (the Level Editor and Garry tune them from here on), and the training dummies are skipped. The buckshot
dwarf and the rocketeer get one too; their shots keep `ranged.knockback` / `artillery.missile.knockback`.

    python tools/set_knockback.py            # write the missing ones
    python tools/set_knockback.py --check    # list what it would write, nothing written

The insertion is textual (one new line after the top-level damage line, in the file's own indentation and line endings)
so each file keeps its hand formatting; every written file is parsed again and must equal the old one plus the key.
Then run `import_json -- only=enemies,bosses` so the game's .tres carry it.
"""
import glob
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDERS = [os.path.join(ROOT, "game", "content", "enemies"), os.path.join(ROOT, "game", "content", "bosses")]
SKIP_PREFIX = "training_dummy"
KEY_LINE = re.compile(r'^(?P<ind>[ \t]*)"(?P<key>[^"]+)"\s*:')


def default_knockback(damage):
    return round(min(max(3.4 * math.sqrt(max(float(damage), 0.0) / 4.0), 2.5), 7.0), 2)


def creature_files():
    """Each folder's own <id>/<id>.json (the art records `*_ai.json` beside it are not creatures)."""
    out = []
    for folder in FOLDERS:
        for path in sorted(glob.glob(os.path.join(folder, "*", "*.json"))):
            cid = os.path.basename(os.path.dirname(path))
            if os.path.basename(path) == cid + ".json":
                out.append((cid, path))
    return out


def insert_knockback(raw, value):
    """`raw` with a `"knockback": value` line after the top-level damage line, or None when there is no such line. The
    new line ends as the damage line does (a few files mix CRLF and LF)."""
    lines = raw.splitlines(keepends=True)
    top_ind = None
    for line in lines[1:]:
        m = KEY_LINE.match(line)
        if m:
            top_ind = m.group("ind")
            break
    if top_ind is None:
        return None
    for k, line in enumerate(lines):
        m = KEY_LINE.match(line)
        if not m or m.group("ind") != top_ind or m.group("key") != "damage":
            continue
        body = line.rstrip("\r\n")
        end = line[len(body):] or "\n"
        if body.rstrip().endswith(","):
            lines.insert(k + 1, '%s"knockback": %s,%s' % (top_ind, value, end))
        else:
            # damage was the last key: it takes a comma, knockback ends the object
            lines[k] = body.rstrip() + "," + end
            lines.insert(k + 1, '%s"knockback": %s%s' % (top_ind, value, end))
        return "".join(lines)
    return None


def main():
    check = "--check" in sys.argv
    wrote = 0
    for cid, path in creature_files():
        if cid.startswith(SKIP_PREFIX):
            continue
        raw = open(path, encoding="utf-8", newline="").read()
        data = json.loads(raw)
        if "knockback" in data:
            print("  %-22s has knockback %s (kept)" % (cid, data["knockback"]))
            continue
        if "damage" not in data:
            print("  %-22s has no damage: skipped" % cid)
            continue
        value = default_knockback(data["damage"])
        new = insert_knockback(raw, value)
        if new is None:
            print("  %-22s no top-level damage line found: skipped" % cid)
            continue
        back = json.loads(new)
        want = dict(data)
        want["knockback"] = value
        keys = list(back.keys())
        if back != want or keys[keys.index("damage") + 1] != "knockback":
            print("  %-22s the rewrite would change more than the key: skipped" % cid)
            continue
        print("  %-22s damage %-5s -> knockback %s%s" % (cid, data["damage"], value, "" if check else " (written)"))
        if not check:
            open(path, "w", encoding="utf-8", newline="").write(new)
            wrote += 1
    print("set_knockback: %d written%s" % (wrote, " (check only)" if check else ""))


if __name__ == "__main__":
    main()
