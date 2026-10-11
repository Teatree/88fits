"""The Level Editor's structured JSON writer (pass 66): edits a content JSON as text, in place, so every byte Garry did
not change stays as it was.

A content JSON on disk has one top-level key per line (the content tools' layout: `{`, then `  "key": value,` lines,
then `}`); a value may run over many lines (a `variants` block, a `levels` list). This module finds each top-level key's
value by `json.JSONDecoder.raw_decode` and rewrites only the span it was asked to, with the file's own indent unit, the
line endings of the lines it touches, and the file's final newline (or the lack of one). Everything is parsed back and
compared with the expected object before it is returned; when a write cannot be made line-preserving the function
returns None and the caller refuses (the server says "layout ..."). Nothing here re-dumps a file on its own: `redump`
exists for one explicit click in the page ("Re-dump this file (changes its layout)") and nothing else.

    layout(src) -> {"unit", "eol", "final_nl"} | None
    top_spans(src) -> {key: {"line", "end_line", "key_start", "value_start", "value_end", "comma", "comma_pos"}} | None
    set_top_block(src, key, value, places=()) -> text | None     (a one-line value stays one line)
    del_top_block(src, key) -> text | None
    set_variant_entry(src, code, update) -> text | None          (update: {k: v} merged over the entry; v = REMOVE drops k)
    del_variant_entry(src, code) -> text | None
    set_top_key(src, key, value, places=()) -> text | None        (the pass 58 name, a thin wrapper)
    restore_numbers(old, new) -> new with the file's floats put back where the page sent whole numbers
    write_atomic(path, text), read_text(path), redump(src, obj)

Standard library only (the server imports this).
"""
import json
import os
import re
from difflib import SequenceMatcher

# a value inside an `update` dict handed to set_variant_entry: drop this key from the entry
REMOVE = object()

_DECODER = json.JSONDecoder()
_WS = re.compile(r"[ \t\r\n]*")
_TOP_KEY_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"[ \t]*:[ \t]*')


# ---------------------------------------------------------------- reading the layout

def layout(src):
    """{unit: the top-level indent string (two spaces in every content file today; a tab is fine), eol: the dominant
    line ending, final_nl: whether the file ends with a newline}; None when `src` is not laid out one top-level key per
    line (a compact one-line file, or an empty object)."""
    lines = src.splitlines(True)
    if len(lines) < 2 or lines[0].strip() != "{":
        return None
    m = re.match(r'^([ \t]+)"', lines[1])
    if not m:
        return None
    crlf = src.count("\r\n")
    eol = "\r\n" if crlf and crlf * 2 >= len(lines) else "\n"
    return {"unit": m.group(1), "eol": eol, "final_nl": src.endswith("\n")}


def _ending(line):
    """The line ending of one line as splitlines(True) gives it ('' for the last line of a file without one)."""
    body = line.rstrip("\r\n")
    return line[len(body):]


def _line_starts(src):
    starts = [0]
    for i, ch in enumerate(src):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def _line_of(starts, offset):
    """The index of the line holding character `offset`."""
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= offset:
            lo = mid
        else:
            hi = mid - 1
    return lo


def top_spans(src):
    """Every top-level key with the span of its value: {key: {line, end_line, key_start, value_start, value_end, comma,
    comma_pos}} in file order. None when the file is not one top-level key per line, a key is doubled, or the keys found
    on the lines are not exactly the object's keys (then nothing here may touch the file)."""
    lay = layout(src)
    if lay is None:
        return None
    try:
        obj = json.loads(src)
    except ValueError:
        return None
    if not isinstance(obj, dict) or not obj:
        return None
    unit = lay["unit"]
    lines = src.splitlines(True)
    starts = _line_starts(src)
    spans = {}
    for i, line in enumerate(lines):
        body = line.rstrip("\r\n")
        if not body.startswith(unit + '"'):
            continue
        m = _TOP_KEY_RE.match(body[len(unit):])
        if not m:
            continue
        try:
            key = json.loads('"%s"' % m.group(1))
        except ValueError:
            continue
        key_start = starts[i] + len(unit)
        value_start = _WS.match(src, key_start + m.end()).end()
        try:
            _, value_end = _DECODER.raw_decode(src, value_start)
        except ValueError:
            return None
        after = _WS.match(src, value_end).end()
        comma = src[after:after + 1] == ","
        if key in spans:
            return None
        spans[key] = {"line": i, "end_line": _line_of(starts, value_end - 1 if value_end > 0 else 0),
                      "key_start": key_start, "value_start": value_start, "value_end": value_end,
                      "comma": comma, "comma_pos": after if comma else -1}
    if set(spans) != set(obj):
        return None
    return spans


def _dump(value, unit, indent, one_line, eol):
    """`value` as JSON text to sit where a value starts: one line (compact, the hand-written style) or many, each line
    after the first prefixed by `indent` (the key line's indent) and ended like the file."""
    if one_line:
        return json.dumps(value, ensure_ascii=False)
    text = json.dumps(value, indent=unit, ensure_ascii=False)
    return text.replace("\n", eol + indent)


def _scalar_or_empty(value):
    if isinstance(value, (dict, list)):
        return len(value) == 0
    return True


def _parse_back(text, want_obj, want_order):
    try:
        got = json.loads(text)
    except ValueError:
        return False
    return got == want_obj and list(got.keys()) == list(want_order)


# ---------------------------------------------------------------- top-level keys

def set_top_block(src, key, value, places=()):
    """`src` with its top-level `key` set to `value`, every other byte as it was. A key already there has its value span
    rewritten in place: a one-line value stays one line (compact JSON), a value over several lines is laid out again with
    the file's indent unit. A new key goes at the first of `places` that fits: ("after", k) after key k's value (k may
    run over many lines), ("before", k) before k's line, ("end", None) after the last key; indented like its neighbours,
    with their line ending, the commas set so the object still reads. Parsed back: the old object with only `key` set, in
    the expected key order, else None."""
    lay = layout(src)
    spans = top_spans(src)
    if lay is None or spans is None:
        return None
    obj = json.loads(src)
    unit, eol = lay["unit"], lay["eol"]
    lines = src.splitlines(True)
    order = list(obj.keys())
    if key in spans:
        sp = spans[key]
        old_text = src[sp["value_start"]:sp["value_end"]]
        one_line = "\n" not in old_text
        here_eol = _ending(lines[sp["end_line"]]) or eol
        new_text = _dump(value, unit, unit, one_line, here_eol)
        text = src[:sp["value_start"]] + new_text + src[sp["value_end"]:]
    else:
        body = unit + json.dumps(key, ensure_ascii=False) + ": "
        text = None
        for where, at in places:
            if where == "end":
                where, at = "after", order[-1]
            if where == "after" and at in spans:
                sp = spans[at]
                here_eol = _ending(lines[sp["end_line"]]) or eol
                new_body = body + _dump(value, unit, unit, _scalar_or_empty(value), here_eol)
                if sp["comma"]:
                    cp = sp["comma_pos"] + 1
                    text = src[:cp] + here_eol + new_body + "," + src[cp:]
                else:
                    ve = sp["value_end"]
                    text = src[:ve] + "," + here_eol + new_body + src[ve:]
                order.insert(order.index(at) + 1, key)
                break
            if where == "before" and at in spans:
                sp = spans[at]
                here_eol = _ending(lines[sp["line"]]) or eol
                line_start = sp["key_start"] - len(unit)
                new_body = body + _dump(value, unit, unit, _scalar_or_empty(value), here_eol)
                text = src[:line_start] + new_body + "," + here_eol + src[line_start:]
                order.insert(order.index(at), key)
                break
        if text is None:
            return None
    want = dict(obj)
    want[key] = value
    if not _parse_back(text, want, order):
        return None
    return text


def set_top_key(src, key, value, places=()):
    """The pass 58 name: one top-level key written on its own line (now any value, over one line or many)."""
    return set_top_block(src, key, value, places)


def del_top_block(src, key):
    """`src` without its top-level `key` (its lines gone, the commas repaired); None when the key is not there, it is the
    only key, or the file cannot be edited line by line."""
    spans = top_spans(src)
    if spans is None or key not in spans:
        return None
    obj = json.loads(src)
    order = list(obj.keys())
    if len(order) < 2:
        return None
    lay = layout(src)
    unit = lay["unit"]
    sp = spans[key]
    line_start = sp["key_start"] - len(unit)
    if sp["comma"]:
        # the key's lines up to and including the comma's line ending
        starts = _line_starts(src)
        lines = src.splitlines(True)
        comma_line = _line_of(starts, sp["comma_pos"])
        cut_end = starts[comma_line] + len(lines[comma_line])
        text = src[:line_start] + src[cut_end:]
    else:
        # the last key: from the end of the previous key's value (its comma goes too) to the end of this value
        prev = spans[order[order.index(key) - 1]]
        text = src[:prev["value_end"]] + src[sp["value_end"]:]
    want = {k: v for k, v in obj.items() if k != key}
    order.remove(key)
    if not _parse_back(text, want, order):
        return None
    return text


# ---------------------------------------------------------------- one entry of `variants`

def _members(src, start):
    """The members of the JSON object whose `{` is at `start`: [(key, key_start, value_start, value_end)] in order."""
    if src[start:start + 1] != "{":
        raise ValueError("not an object")
    i = start + 1
    out = []
    while True:
        i = _WS.match(src, i).end()
        if src[i:i + 1] == "}":
            return out, i
        key, kend = _DECODER.raw_decode(src, i)
        if not isinstance(key, str):
            raise ValueError("a key that is not a string")
        j = _WS.match(src, kend).end()
        if src[j:j + 1] != ":":
            raise ValueError("no colon")
        j = _WS.match(src, j + 1).end()
        _, vend = _DECODER.raw_decode(src, j)
        out.append((key, i, j, vend))
        k = _WS.match(src, vend).end()
        if src[k:k + 1] == ",":
            i = k + 1
            continue
        if src[k:k + 1] == "}":
            return out, k
        raise ValueError("neither a comma nor a brace after a value")


def merge_entry(existing, update):
    """{**existing, **update} with REMOVE dropping a key; existing keys keep their place, new ones follow."""
    out = dict(existing) if isinstance(existing, dict) else {}
    for k, v in update.items():
        if v is REMOVE:
            out.pop(k, None)
        else:
            out[k] = v
    return out


def _variants_block(src):
    """(layout, spans, obj, members, close_pos) of the `variants` object, or None."""
    lay = layout(src)
    spans = top_spans(src)
    if lay is None or spans is None or "variants" not in spans:
        return None
    obj = json.loads(src)
    if not isinstance(obj.get("variants"), dict):
        return None
    vs = spans["variants"]
    try:
        members, close = _members(src, vs["value_start"])
    except (ValueError, IndexError):
        return None
    return lay, spans, obj, members, close


def set_variant_entry(src, code, update):
    """`src` with `variants[code]` set to the entry merged with `update` (merge_entry); a new code is inserted before the
    block's closing brace with the comma repaired. Only that entry's text changes. None when the file has no `variants`
    object or cannot be edited line by line."""
    got = _variants_block(src)
    if got is None:
        return None
    lay, spans, obj, members, close = got
    unit, eol = lay["unit"], lay["eol"]
    lines = src.splitlines(True)
    starts = _line_starts(src)
    vs = spans["variants"]
    existing = obj["variants"].get(code, {})
    merged = merge_entry(existing if isinstance(existing, dict) else {}, update)
    by_key = {m[0]: m for m in members}
    if members:
        first = members[0]
        kl = _line_of(starts, first[1])
        indent2 = lines[kl][:first[1] - starts[kl]]
        if indent2.strip():
            indent2 = unit * 2
    else:
        indent2 = unit * 2
    if code in by_key:
        _, ks, vstart, vend = by_key[code]
        one_line = "\n" not in src[vstart:vend]
        here_eol = _ending(lines[_line_of(starts, vend - 1)]) or eol
        text = src[:vstart] + _dump(merged, unit, indent2, one_line, here_eol) + src[vend:]
    elif members:
        last = members[-1]
        here_eol = _ending(lines[_line_of(starts, last[3] - 1)]) or eol
        piece = "," + here_eol + indent2 + json.dumps(code, ensure_ascii=False) + ": " + _dump(merged, unit, indent2, False, here_eol)
        text = src[:last[3]] + piece + src[last[3]:]
    else:
        here_eol = _ending(lines[vs["line"]]) or eol
        inner = indent2 + json.dumps(code, ensure_ascii=False) + ": " + _dump(merged, unit, indent2, False, here_eol)
        text = src[:vs["value_start"]] + "{" + here_eol + inner + here_eol + unit + "}" + src[vs["value_end"]:]
    want = dict(obj)
    want_vs = dict(obj["variants"])
    want_vs[code] = merged
    want["variants"] = want_vs
    if not _parse_back(text, want, list(obj.keys())):
        return None
    try:
        if list(json.loads(text)["variants"].keys()) != list(want_vs.keys()):
            return None
    except (ValueError, KeyError, AttributeError):
        return None
    return text


def del_variant_entry(src, code):
    """`src` without `variants[code]`; None when it is not there or the file cannot be edited line by line."""
    got = _variants_block(src)
    if got is None:
        return None
    lay, spans, obj, members, close = got
    vs = spans["variants"]
    idx = next((i for i, m in enumerate(members) if m[0] == code), None)
    if idx is None:
        return None
    m = members[idx]
    if len(members) == 1:
        text = src[:vs["value_start"]] + "{}" + src[vs["value_end"]:]
    elif idx + 1 < len(members):
        nxt = members[idx + 1]
        text = src[:m[1]] + src[nxt[1]:]
    else:
        prev = members[idx - 1]
        text = src[:prev[3]] + src[m[3]:]
    want = dict(obj)
    want["variants"] = {k: v for k, v in obj["variants"].items() if k != code}
    if not _parse_back(text, want, list(obj.keys())):
        return None
    return text


def diff_within_entry(src, text, code):
    """Whether every line that differs between `src` and `text` lies inside `variants[code]`'s text in `text` (the line
    before it may differ too: the previous entry gains a comma). The block write's test: when it fails, the block had a
    hand layout and the entry write is the one to keep."""
    got = _variants_block(text)
    if got is None:
        return False
    lay, spans, obj, members, close = got
    m = next((m for m in members if m[0] == code), None)
    if m is None:
        return False
    starts = _line_starts(text)
    lo = _line_of(starts, m[1]) - 1
    hi = _line_of(starts, m[3] - 1)
    a, b = src.splitlines(True), text.splitlines(True)
    for tag, i1, i2, j1, j2 in SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        if j1 < lo or j2 - 1 > hi:
            return False
    return True


# ---------------------------------------------------------------- numbers, files

def restore_numbers(old, new):
    """The page's JavaScript turns 1.0 into 1 (it has one number type), so the write puts the float back wherever the file
    on disk had one at the same place (a dict key, a list index, a wave matched by its id). Numbers that are new stay as
    the page sent them."""
    if isinstance(old, bool) or isinstance(new, bool):
        return new
    if isinstance(old, float) and isinstance(new, int):
        return float(new)
    if isinstance(old, dict) and isinstance(new, dict):
        return {k: (restore_numbers(old[k], v) if k in old else v) for k, v in new.items()}
    if isinstance(old, list) and isinstance(new, list):
        by_id = {}
        for o in old:
            if isinstance(o, dict) and isinstance(o.get("id"), str):
                by_id.setdefault(o["id"], o)
        out = []
        for i, v in enumerate(new):
            if isinstance(v, dict) and isinstance(v.get("id"), str) and v["id"] in by_id:
                out.append(restore_numbers(by_id[v["id"]], v))
            elif i < len(old):
                out.append(restore_numbers(old[i], v))
            else:
                out.append(v)
        return out
    return new


def read_text(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def write_atomic(path, text):
    """`text` (its line endings already as the file wants them) written next to `path` and moved over it in one step."""
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(text.encode("utf-8"))
    os.replace(tmp, path)


def redump(src, obj):
    """The whole object dumped again with the file's indent unit, its dominant line ending and its final newline (or
    none). Only for Garry's explicit "Re-dump this file (changes its layout)": a compact array becomes one item a line,
    a hand layout is lost."""
    lay = layout(src) or {"unit": "  ", "eol": "\n", "final_nl": src.endswith("\n")}
    text = json.dumps(obj, indent=lay["unit"], ensure_ascii=False)
    if lay["final_nl"]:
        text += "\n"
    if lay["eol"] == "\r\n":
        text = text.replace("\n", "\r\n")
    return text


def dump_new(obj, unit="  "):
    """A brand-new file: indent 2, LF, a final newline (the one case a dump is allowed: there is no layout to keep)."""
    return json.dumps(obj, indent=unit, ensure_ascii=False) + "\n"
