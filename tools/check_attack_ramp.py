"""Pass 109 check: every weapon's attack speed (1 / its cooldown as the level effects make it) against a git ref.

Garry: "The starting attack speed of all weapons should be reduced -15%, by upgrade 3 the attack speed is back to being
what it is now on upgrade 3. So the upgrade 2 is supposed to be only -7.5%." So per weapon, new / old attack speed:
level 1 = 0.85, level 2 = 0.925, levels 3-5 = 1.0 (within 0.5%). The orbiters (cooldown = the gap between one blade's
hits on one creature, not an attack clock) keep their numbers, as do the evolutions.

    python tools/check_attack_ramp.py [--ref a60ceda]

The ref is the commit before pass 109 (a60ceda). The cooldown is the weapon sheet's (StatSheet: (base + sum add) x
prod(1 + mul), "set" replacing the base); the hero's own multipliers are all mul and cancel out of the ratio.
"""
import json, os, subprocess, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = sys.argv[sys.argv.index("--ref") + 1] if "--ref" in sys.argv else "a60ceda"
SKIP = {"orbit_saws", "branding_iron", "rattlesnake"}
WANT = [0.85, 0.925, 1.0, 1.0, 1.0]


def eff(d, k):
    b = float(d["base"].get("cooldown", 1.0)); adds = 0.0; mul = 1.0
    for lv in d["levels"][:k]:
        for e in lv:
            if e.get("stat") != "cooldown":
                continue
            if e["op"] == "add":
                adds += e["value"]
            elif e["op"] == "mul":
                mul *= 1.0 + e["value"]
            elif e["op"] == "set":
                b = e["value"]
    return (b + adds) * mul


def at_ref(rel):
    return json.loads(subprocess.check_output(["git", "-C", REPO, "show", f"{REF}:{rel}"]).decode("utf-8"))


bad = 0
wdir = os.path.join(REPO, "game", "content", "weapons")
print(f"{'weapon':14s} {'L1':>6s} {'L2':>6s} {'L3':>6s} {'L4':>6s} {'L5':>6s}   cooldown old -> new per level")
for wid in sorted(os.listdir(wdir)):
    path = os.path.join(wdir, wid, wid + ".json")
    if not os.path.exists(path):
        continue
    rel = f"game/content/weapons/{wid}/{wid}.json"
    new = json.load(open(path, encoding="utf-8"))
    old = at_ref(rel)
    co = [eff(old, k) for k in range(1, 6)]
    cn = [eff(new, k) for k in range(1, 6)]
    ratio = [o / n for o, n in zip(co, cn)]
    want = [1.0] * 5 if wid in SKIP else WANT
    ok = all(abs(r / w - 1.0) <= 0.005 for r, w in zip(ratio, want)) and new["levels"][0] == []
    bad += 0 if ok else 1
    tag = "skip" if wid in SKIP else ("ok" if ok else "FAIL")
    print(f"{wid:14s} " + " ".join(f"{r:6.4f}" for r in ratio) + "   " +
          ", ".join(f"{o:.3f}->{n:.3f}" for o, n in zip(co, cn)) + f"  [{tag}]")

# the evolutions keep today's numbers
edir = os.path.join(REPO, "game", "content", "evolutions")
changed = []
for eid in sorted(os.listdir(edir)):
    path = os.path.join(edir, eid, eid + ".json")
    if not os.path.exists(path):
        continue
    try:
        old = at_ref(f"game/content/evolutions/{eid}/{eid}.json")
    except subprocess.CalledProcessError:
        continue
    new = json.load(open(path, encoding="utf-8"))
    if (old.get("base", {}).get("cooldown"), old.get("levels")) != (new.get("base", {}).get("cooldown"), new.get("levels")):
        changed.append(eid)
print("evolutions with a changed cooldown:", changed or "none")
bad += len(changed)
print("FAILED" if bad else "ALL OK")
sys.exit(1 if bad else 0)
