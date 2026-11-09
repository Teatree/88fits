"""Pass 137 (lane LOCKIT): the static proof that moving texts into the string table changed none of them.

    python tools/loc_verify.py [--base HEAD] [--files a.gd b.gd ...] [--all-literals] [--quiet]

From `git diff <base>` of the game's .gd files (the working tree against the base; default every changed .gd under
game/), every string literal a change REMOVED that a player could read must be covered by the texts of the keys the
change ADDED in the same file (Loc.t("key"), Loc.t_first([...]), a "key" in a KEY const), as they read in
game/content/strings/en.json:

  - the literal's printf pieces (%d, %s, %.1f, %%) are wildcards; the text's {variables} are wildcards; a {n?one:many}
    selector is tried both ways; the literal must match the whole text ("Fires %d shot%s at ..." against "Fires {amount}
    {amount?shot:shots} at ...") or a piece of it ("a spear", " (%d stacks)" inside a selector's part);
  - a literal that is still in the file's added lines (moved, not removed) is covered;
  - not player text, never checked: no letter in it, a single word in snake_case / CamelCase / with a dot or a slash
    (node names, theme keys, paths, ids, signal names), a res:// path, a format of numbers only.

Every key the added lines name must have a row in en.json. Exit 1 on an uncovered literal or a missing key, with each
one's file and line; 0 when every removed text is accounted for. The wave-2 lanes run it with the census
(tools/text_census_diff.py), which is the runtime proof. Rules: tools/dl/p137/LOC_CONVERT.md.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
EN = os.path.join(ROOT, "game", "content", "strings", "en.json")

_STR = re.compile(r'(?<![&^A-Za-z0-9_])"((?:[^"\\]|\\.)*)"')
_KEYCALL = re.compile(r'Loc\.(?:t|has|t_first)\(\s*(\[[^\]]*\]|"[^"]*")')
_KEYLIT = re.compile(r'"([a-z0-9_]+(?:\.[a-z0-9_%]+)+)"')
_KEYPREFIX = re.compile(r'"((?:[a-z0-9_]+\.)+)"')
# (no space flag: GDScript has none, and "{n}% of" in a template is no printf piece; pass 137, lane W2-TEXTGEN)
_PRINTF = re.compile(r"%[-+0#]*[0-9]*(?:\.[0-9]+)?[a-zA-Z%]")
_BRACE = re.compile(r"\{[a-z_][a-z0-9_]*\}")
ANY = r"[\s\S]*?"
HOLE = ""   # a {variable} in an expanded text
_NOT_TEXT = re.compile(r"^(?:[A-Za-z0-9_]+|[A-Za-z0-9_./:\-]+)$")


def _unescape(s):
    try:
        return json.loads('"%s"' % s.replace("\t", "\\t"))
    except ValueError:
        return s


def literals(line):
    if line.lstrip().startswith("#"):
        return []
    code = line
    # a trailing comment after the code: cut at a # outside strings
    out, i, in_s = [], 0, False
    while i < len(code):
        c = code[i]
        if c == '"' and (i == 0 or code[i - 1] != "\\"):
            in_s = not in_s
        elif c == "#" and not in_s:
            code = code[:i]
            break
        i += 1
    return [_unescape(m.group(1)) for m in _STR.finditer(code)]


def is_player_text(s):
    """"yes" (several words, or one word in capitals or Capitalised: a button's "DEAL", a title's "Extract"), "maybe" (one
    lowercase word: "second" in a table of words, or an id that slipped through; uncovered = a warning), "" (not text)."""
    if s.startswith(("res://", "user://", "uid://")):
        return ""
    t = _PRINTF.sub("", s)
    if not re.search(r"[A-Za-z]", t):
        return ""
    w = s.strip()
    if re.search(r"\s", w):
        return "yes"
    if re.fullmatch(r"[A-Z][A-Z'!?.,:]+|[A-Z][a-z]+[!?.,:]?", w):
        return "yes"
    if re.fullmatch(r"[a-z]{1,3}", w):
        return ""   # a plural's ending ("s", "es", "ies") handed to a %s
    if re.fullmatch(r"[a-z]+", w):
        return "maybe"
    return ""


def _expansions(text, limit=64):
    """The text with every {variable} as \x01 and each selector both ways (at most `limit` forms)."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "level_editor"))
    import strings_io as SI
    segs = SI.parse(text)

    def walk(segs):
        forms = [""]
        for s in segs:
            if isinstance(s, str):
                forms = [f + s for f in forms]
            elif "one" in s:
                alt = walk(s["one"]) + walk(s["many"])
                forms = [f + a for f in forms for a in alt][:limit]
            else:
                forms = [f + "\x01" for f in forms]
        return forms
    return walk(segs)


def _literal_regex(lit):
    """The literal as a regex: each printf piece (%d, %s, %.1f) matches anything, %% is a %; a {variable} the literal
    already held (a word table such as RULE_TEXT whose "{n}" the code replaced) matches anything too."""
    rx, last = "", 0
    pieces = sorted([(m.start(), m.end(), "%" if m.group(0) == "%%" else ANY) for m in _PRINTF.finditer(lit)] +
                    [(m.start(), m.end(), ANY) for m in _BRACE.finditer(lit)])
    for a, b, r in pieces:
        if a < last:
            continue
        rx += re.escape(lit[last:a]) + r
        last = b
    return rx + re.escape(lit[last:])


def covered(lit, forms):
    """The literal matches a form of an added key's text: the whole text, either side's holes taking the other's
    words (a %s that was "a spear", a {who} that was "the nearest enemy"), or a piece of it."""
    lit = lit.strip()
    # pass 137 (lane W2-TEXTGEN): a piece is any literal that does not end a sentence (". ! ?"), a sentence's opening
    # too ("Gain ", "Throws %d frisbees, fanned out,", "EVOLVES "), since a converted sentence holds its pieces in one row
    piece = not lit.endswith((".", "!", "?"))
    lr = _literal_regex(lit)
    bare_lit = _BRACE.sub("", _PRINTF.sub(lambda m: "%" if m.group(0) == "%%" else "", lit))
    # word boundaries only where the literal's own edge is a letter or a digit (", all weapons" sits after "m"), and none
    # before a plural's ending ("s are" after "coin", "es follow" after "echo")
    lead = r"(?<![A-Za-z0-9])" if re.match(r"[A-Za-z0-9]", lit) and not re.match(r"[a-z]{1,3} ", lit) else ""
    tail = r"(?![A-Za-z0-9])" if re.search(r"[A-Za-z0-9]$", lit) else ""
    # a single word the code capitalises (TextGen._sentence: "His" from the row "his") is matched in either case
    alts = [lr] + ([_literal_regex(lit.lower())] if re.fullmatch(r"[A-Z][a-z]+", lit) else [])
    # a piece whose joining punctuation stays in code (", " + Loc.t(...): ", all weapons" -> the row "all weapons")
    if piece and re.match(r"[ ,;:]+[A-Za-z]", lit):
        alts.append(_literal_regex(lit.lstrip(" ,;:")))
    for f in forms:
        bare_f = f.replace(HOLE, "")
        fr = "".join(ANY if ch == HOLE else re.escape(ch) for ch in f)
        if any(re.fullmatch(r, bare_f) for r in alts) or re.fullmatch(fr, bare_lit):
            return True
        # a piece of a sentence ("a spear", "%d spears", "(%d stacks)", "Sets on fire") may sit inside a text
        if piece and any(re.search(lead + r + tail, bare_f) for r in alts):
            return True
    return False


def keys_in(line, consts):
    """(keys a Loc call names, every key-like literal on the line): a call's keys must exist; the others (a key held in a
    const, a key built with % such as "weapon.%s.desc", a prefix that code completes such as "gen.weapon." + shape)
    only widen the texts the removed literals are checked against."""
    called, seen = [], []
    for m in _KEYCALL.finditer(line):
        called += _KEYLIT.findall(m.group(1))
    for m in _KEYLIT.finditer(line):
        seen.append(m.group(1))
    for m in _KEYPREFIX.finditer(line):
        seen.append(m.group(1))
    return called, seen


def diff_files(base, files):
    args = ["git", "-C", ROOT, "diff", "-U0", base, "--"] + (files or ["game/*.gd", "game/**/*.gd"])
    r = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    per = {}
    cur = None
    line_no = 0
    for ln in r.stdout.splitlines():
        if ln.startswith("+++ b/"):
            cur = ln[6:]
            per[cur] = {"removed": [], "added": []}
        elif ln.startswith("@@") and cur:
            m = re.search(r"-(\d+)", ln)
            line_no = int(m.group(1)) if m else 0
        elif cur and ln.startswith("-") and not ln.startswith("---"):
            per[cur]["removed"].append((line_no, ln[1:]))
            line_no += 1
        elif cur and ln.startswith("+") and not ln.startswith("+++"):
            per[cur]["added"].append(ln[1:])
    return per


def verify(base="HEAD", files=None, quiet=False):
    en = json.load(open(EN, encoding="utf-8")) if os.path.isfile(EN) else {}
    problems, warnings, checked = [], [], 0
    for path, d in sorted(diff_files(base, files).items()):
        if not path.endswith(".gd"):
            continue
        added_text = "\n".join(d["added"])
        consts = set(_KEYLIT.findall(added_text)) & set(en)
        called, keys = [], []
        for ln in d["added"]:
            c, k = keys_in(ln, consts)
            called += c
            keys += c + k
        keys = list(dict.fromkeys(keys))
        for k in dict.fromkeys(called):
            if "%" not in k and not k.endswith(".") and k not in en:
                problems.append("%s: the key %s has no row in en.json" % (path, k))
        # keys built from a pattern (gen.word.nth.%d, weapon.%s.desc) or a prefix the code completes ("gen.weapon." +
        # shape) stand for every row they can name
        texts = []
        for k in keys:
            if k.endswith("."):
                texts += [v for kk, v in en.items() if kk.startswith(k)]
            elif "%" in k:
                rx = "^" + re.escape(k).replace("%d", "[0-9]+").replace("%s", "[a-z0-9_]+") + "$"
                texts += [v for kk, v in en.items() if re.match(rx, kk)]
            elif k in en:
                texts.append(en[k])
        forms = []
        for t in texts:
            forms += _expansions(t)
        still = set()
        for ln in d["added"]:
            still.update(literals(ln))
        for line_no, ln in d["removed"]:
            for lit in literals(ln):
                kind = is_player_text(lit)
                if not kind or lit in still:
                    continue
                checked += 1
                if not covered(lit, forms):
                    if kind == "yes":
                        problems.append("%s:%d: the removed text %r is not any added key's text" % (path, line_no, lit))
                    else:
                        warnings.append("%s:%d: the removed word %r is not in any added key's text (an id? then fine)" % (path, line_no, lit))
    if not quiet:
        print("loc_verify: %d removed text(s) checked against the added keys' texts" % checked)
        for w in warnings:
            print("  warning " + w)
        for p in problems:
            print("  " + p)
        print("loc_verify: %s" % ("every removed text is accounted for" if not problems else "%d problem(s)" % len(problems)))
    return problems, checked


def main(argv):
    base = "HEAD"
    files = None
    if "--base" in argv:
        base = argv[argv.index("--base") + 1]
    if "--files" in argv:
        files = [a for a in argv[argv.index("--files") + 1:] if not a.startswith("--")]
    problems, _ = verify(base, files, "--quiet" in argv)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
