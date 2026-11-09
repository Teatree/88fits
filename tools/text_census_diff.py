"""Pass 137 (lane LOCKIT): two text censuses compared (game/tools/text_census.gd writes them).

    python tools/text_census_diff.py <before.json> <after.json> [--strict] [--only a|b|c] [--max 60]

Exit 0 when every text is the same, 1 on any difference in parts a and b (part c, the toasts seen while the screens
played, is timing-dependent: a warning unless --strict), 2 on a bad file. The report names each changed key with its
text before and after, the texts a screen gained or lost, and the keys only one side has.
"""
import json
import sys


def _load(path):
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        print("ERROR %s: %s" % (path, e))
        sys.exit(2)
    if not isinstance(d, dict) or "a" not in d:
        print("ERROR %s: not a text census (no part a)" % path)
        sys.exit(2)
    return d


def _short(s, n=160):
    s = str(s)
    return s if len(s) <= n else s[:n - 1] + "…"


def diff(a, b, only=None):
    """[(part, kind, key, before, after)] for every difference; kind changed | gone | new."""
    out = []
    if only in (None, "a"):
        pa, pb = a.get("a") or {}, b.get("a") or {}
        both = [k for k in pa if k in pb]
        out += [("a", "changed", k, pa[k], pb[k]) for k in both if pa[k] != pb[k]]
        # a key on one side only: the same text may have moved key (rare); reported as gone / new
        out += [("a", "gone", k, pa[k], None) for k in pa if k not in pb]
        out += [("a", "new", k, None, pb[k]) for k in pb if k not in pa]
    if only in (None, "b"):
        ba, bb = a.get("b") or {}, b.get("b") or {}
        for screen in sorted(set(ba) | set(bb)):
            if screen not in ba or screen not in bb:
                # a screen one run did not reach: not a text difference
                out.append(("b", "screen", screen, "present" if screen in ba else "absent",
                            "present" if screen in bb else "absent"))
                continue
            sa, sb = set(ba[screen]), set(bb[screen])
            out += [("b", "gone", screen, t, None) for t in sorted(sa - sb)]
            out += [("b", "new", screen, None, t) for t in sorted(sb - sa)]
    if only in (None, "c"):
        ca, cb = set(a.get("c") or []), set(b.get("c") or [])
        out += [("c", "gone", "toasts", t, None) for t in sorted(ca - cb)]
        out += [("c", "new", "toasts", None, t) for t in sorted(cb - ca)]
    return out


def report(rows, limit=60):
    lines = []
    for part in ("a", "b", "c"):
        mine = [r for r in rows if r[0] == part]
        if not mine:
            continue
        title = {"a": "generated words (exact)", "b": "screens (numbers as #)", "c": "toasts and banners seen (timing-dependent)"}[part]
        lines.append("== part %s, %s: %d difference(s)" % (part, title, len(mine)))
        for _, kind, key, before, after in mine[:limit]:
            if kind == "changed":
                lines.append("  CHANGED %s\n     was: %s\n     now: %s" % (key, _short(before), _short(after)))
            elif kind == "screen":
                lines.append("  SCREEN  %s reached in one run only (before %s, after %s)" % (key, before, after))
            elif kind == "gone":
                lines.append("  GONE    %s: %s" % (key, _short(before)))
            else:
                lines.append("  NEW     %s: %s" % (key, _short(after)))
        if len(mine) > limit:
            lines.append("  ... %d more" % (len(mine) - limit))
    return "\n".join(lines)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    strict = "--strict" in argv
    only = None
    limit = 60
    for i, a in enumerate(argv):
        if a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
        if a == "--max" and i + 1 < len(argv):
            limit = int(argv[i + 1])
    args = [a for a in args if a not in (only, str(limit))]
    if len(args) != 2:
        print(__doc__)
        return 2
    a, b = _load(args[0]), _load(args[1])
    rows = diff(a, b, only)
    counts = {p: len(a.get(p) or {}) for p in ("a", "b", "c")}
    print("text census: %s vs %s (before: %d generated texts, %d screens, %d toasts)" % (args[0], args[1], counts["a"], counts["b"], counts["c"]))
    if not rows:
        print("no difference")
        return 0
    print(report(rows, limit))
    hard = [r for r in rows if r[0] in ("a", "b") and r[1] != "screen" or (strict and r[0] == "c")]
    if not hard:
        print("only part c (or screens reached in one run) differ: not a text change (use --strict to fail on them)")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
