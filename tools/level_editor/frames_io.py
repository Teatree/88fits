"""The frames store's routes (pass 95, lane VACE): the Frames view of a look (every frame of every animation, the
versions of each frame, staging, repair with VACE, copies from other looks, the export). server.py hands
/api/frames/... here (api_get / api_post with the handler and the server module), as it does the drivers and the sims.
The store itself is tools/frames_store.py; the repairs tools/vace_repair.py (a "frames_repair" job on the comfy lane),
the export a "frames_export" job (tools/frames_store.py export, then the Level Editor merges the entry and imports).

    GET  /api/frames/<kind>/<id>/<code>                        the look's groups (animation x view): counts, staged, flags
    GET  /api/frames/<kind>/<id>/<code>/<anim>/<view>          one group: every slot with its versions, choices, flags, driver
    GET  /api/frames/<kind>/<id>/<code>/<anim>/<view>/others   the same animation x view in every other look of the asset
    POST /api/frames/<kind>/<id>/<code>/<anim>/<view>/stage    {slot, version}    the choice staged (the preview plays it)
    POST .../unstage   {slot?}                                 one slot's staging dropped, or every slot's (Undo)
    POST .../pin       {slot, pinned}                          a human's choice a re-roll never replaces
    POST .../copy      {slot, from: {code, slot, version}}     a version of another look copied in (a new version here), staged
    POST .../repair    {slots: [..], prompt?, seed?, window?}  a frames_repair job queued (VACE on the comfy lane)
    POST .../ask       {slot, version?}                        the local vision model (LM Studio) asked about one frame
    POST .../delete    {slot, version}                         RETIRED (pass 96): always refused, versions are never deleted
    GET  /api/frames/<kind>/<id>/<code>/batch                  pass 96: what the next Export replaces (every staged change as a
                                                               before / after pair in Garry's label form, the flag deltas, the
                                                               pinned slots re-applied, in_play, the backup folder)
    POST /api/frames/<kind>/<id>/<code>/export {confirm?}      a frames_export job queued (the strip packed, merged, imported);
                                                               EVERY export that replaces an installed strip needs confirm: true
                                                               (pass 96: the answer without it carries `batch`, the page shows one
                                                               box for the whole batch, one click approves it all)
    POST /api/frames/<kind>/<id>/<code>/register               the look registered again (force: the fit and clip re-read)

Pictures come as /dl/frames/<...> (the store lives under tools/dl/frames) and /dl/drivers/..., /dl/ai_raw_anime/...

Pass 95 resume (the assessment's engineering items): a `repair` rule per method in methods.json (vace yes / conditional
/ no; fill still / cell / none) read here (repair_rule, repairable): a repair on a procedural animation (no clip, no
driver) or on a method whose rule says no is refused unless `free_fill: true` is sent on purpose; the repair job's
versions are staged at the landing by stage_versions (one writer of staged.json); rollback() undoes an export whose
merge or import failed; the picker marks removed looks.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if os.path.join(ROOT, "tools") not in sys.path:
    sys.path.insert(0, os.path.join(ROOT, "tools"))
import frames_store as FS  # noqa: E402

ID_RE = re.compile(r"^[a-z0-9_]+$")
CODE_RE = re.compile(r"^[A-Za-z0-9_-]+$")
KINDS = ("enemy", "boss", "hero")
VIEWS = ("front", "fd", "side", "bd", "back")
ANIMS = ("idle", "run", "attack", "hit", "die", "turn", "cheer")
# the question the local vision model is asked about one frame (honestly labelled on the page: it misses extra limbs)
ASK = ("You are checking one frame of a 2D game sprite animation of %s. Answer ONLY with one JSON object, no prose, with keys: "
       "limbs (integer: how many legs or arms you can count), broken (true if a limb, the head or the body is cut, detached, "
       "smeared, doubled or missing), ghost (true if a faint or see-through duplicate of a part is visible), colour (true if a "
       "patch has a colour the rest of the figure lacks), note (a few words on what looks wrong, or \"fine\").")


DL_DIR = os.path.join(ROOT, "tools", "dl")   # the server's DL (the selftest points it at a temporary folder)
METHODS_JSON = os.path.join(HERE, "methods.json")
DEFAULT_RULE = {"vace": "conditional", "fill": "cell", "note": "no repair rule in methods.json for this method: a repair runs where a clip or a driver exists"}
_RULES = {"mtime": None, "rules": {}}


def repair_rule(method):
    """methods.json's `repair` rule of a method (pass 95 resume, AN-01): {vace: yes|conditional|no, fill: still|cell|none,
    note}; the catalogue is re-read when its file changes."""
    try:
        mt = os.path.getmtime(METHODS_JSON)
    except OSError:
        return dict(DEFAULT_RULE)
    if _RULES["mtime"] != mt:
        rules = {}
        try:
            with open(METHODS_JSON, "r", encoding="utf-8") as f:
                for m in (json.load(f).get("methods") or []):
                    if isinstance(m, dict) and isinstance(m.get("repair"), dict):
                        rules[str(m.get("id"))] = m["repair"]
        except (OSError, ValueError):
            rules = {}
        _RULES.update(mtime=mt, rules=rules)
    r = _RULES["rules"].get(str(method or ""))
    return dict(r) if r else dict(DEFAULT_RULE)


def repairable(g, method=None):
    """Whether a VACE repair of this group runs without free_fill: {ok, why, rule, procedural}. Refused when the method's
    rule says no, or when the animation has neither a clip cache nor a driver (a procedural idle, attack, hit: VACE
    would have nothing to follow; the still is the thing to fix)."""
    m = method or g.meta.get("method") or ""
    rule = repair_rule(m)
    procedural = not g.meta.get("clip") and not g.meta.get("driver")
    if str(rule.get("vace")) == "no":
        return {"ok": False, "rule": rule, "procedural": procedural,
                "why": "%s: VACE is off for this method (%s); fill freely on purpose if you must" % (m or "this method", rule.get("note") or "its frames come from one painting")}
    if procedural:
        return {"ok": False, "rule": rule, "procedural": True,
                "why": "%s has no clip cache and no driver (a procedural animation): VACE would have nothing to follow; fix the still and re-run the look, or fill freely on purpose" % g.key}
    return {"ok": True, "rule": rule, "procedural": False, "why": ""}


def _dl_url(path):
    """A file under tools/dl as the server serves it: /dl/<rel>?v=<mtime>."""
    try:
        rel = os.path.relpath(path, DL_DIR).replace("\\", "/")
    except ValueError:   # pass 96: Windows, a store on another drive than DL_DIR (a script's temp store): never a 400
        rel = os.path.basename(path)
    try:
        v = int(os.path.getmtime(path))
    except OSError:
        v = 0
    return "/dl/%s?v=%d" % (rel, v)


def _check(kind, cid, code, base=None, view=None):
    if kind not in KINDS or not ID_RE.match(cid or "") or not CODE_RE.match(code or ""):
        return "bad look %s/%s/%s" % (kind, cid, code)
    if base is not None and base not in ANIMS:
        return "unknown animation %s" % base
    if view is not None and view not in VIEWS:
        return "unknown view %s" % view
    return ""


def _group(kind, cid, code, base, view):
    look = FS.Look(kind, cid, code)
    g = FS.Group(look, base, view)
    if not g.exists():
        FS.register_look(kind, cid, code)
        g = FS.Group(look, base, view)
    if not g.exists():
        raise ValueError("%s %s has no %s %s animation" % (cid, code, base, view))
    return look, g


def summary(kind, cid, code):
    try:
        s = FS.look_summary(kind, cid, code)
    except ValueError as e:
        return {"ok": False, "error": str(e), "groups": []}
    if s.get("ok"):
        s["rule"] = repair_rule(s.get("method") or "")
    return s


def detail(kind, cid, code, base, view):
    look, g = _group(kind, cid, code, base, view)
    d = g.detail(_dl_url)
    d["note"] = str(look.entry.get("note", ""))
    d["is_base"] = look.is_base
    d["anims"] = look.anims
    d["repairable"] = repairable(g)
    return d


def others(kind, cid, code, base, view):
    """The other looks' same group: {code, note, n, frame_px, compatible: [...warnings], slots: [{slot, versions: [...]}]}."""
    look = FS.Look(kind, cid, code)
    out = []
    for o in FS.other_looks(kind, cid, code, base, view):
        g = o["group"]
        warns = []
        if o["frame_px"] != look.frame_px:
            warns.append("its cells are %d px, this look's %d: a copied cell is resized" % (o["frame_px"], look.frame_px))
        n_here = int(look.anims.get(FS.anim_key(kind, base, view), 0) or 0)
        if o["n"] != n_here:
            warns.append("it has %d frames in this animation, this look %d: slot numbers do not line up" % (o["n"], n_here))
        if (g.meta.get("driver") or {}).get("name") and (g.meta.get("driver") or {}).get("name") != ((FS.Group(look, base, view).meta.get("driver") or {}).get("name")):
            warns.append("walked on another driver (%s): the poses may differ" % g.meta["driver"]["name"])
        slots = []
        for k in range(g.n):
            vs = []
            for v in g.versions(k):
                vs.append({"id": v["id"], "label": v["label"], "n": v["n"], "source": v.get("source"), "space": v.get("space"), "time": v.get("time"),
                           "url": _dl_url(g.cell_url_file(k, v)), "raw": bool(v.get("raw") or v.get("space") == "raw"),
                           "name": g.name_of(k, v), "from": v.get("from"), "seed": v.get("seed"), "driver": v.get("driver")})   # pass 96: Garry's label + the picker's filters
            eff, how = g.effective(k)
            slots.append({"slot": k, "versions": vs, "effective": eff["id"] if eff else None})
        if o.get("removed"):
            warns.append("a removed look: the JSON no longer lists it (its strip is under backups/deleted/); its frames stay copyable")
        out.append({"code": o["code"], "note": o["note"], "n": o["n"], "frame_px": o["frame_px"], "warnings": warns, "slots": slots,
                    "driver": (g.meta.get("driver") or {}).get("name"), "removed": bool(o.get("removed"))})
    return {"ok": True, "looks": out}


def stage(kind, cid, code, base, view, body):
    look, g = _group(kind, cid, code, base, view)
    slot = int(body.get("slot"))
    vid = str(body.get("version") or "")
    rec = g.stage(slot, vid, why=str(body.get("why") or "chosen"))
    _ev("stage", kind, cid, code, base, view, slot=slot, version=vid, why=str(body.get("why") or "chosen"))   # pass 97 (lane PROGRESS, WF-02)
    return {"ok": True, "slot": slot, "staged": rec, "group": g.detail(_dl_url)}


def unstage(kind, cid, code, base, view, body):
    look, g = _group(kind, cid, code, base, view)
    slot = body.get("slot")
    g.unstage(None if slot is None else int(slot))
    _ev("unstage", kind, cid, code, base, view, slot=slot)   # pass 97 (lane PROGRESS, WF-02)
    return {"ok": True, "group": g.detail(_dl_url)}


def pin(kind, cid, code, base, view, body):
    look, g = _group(kind, cid, code, base, view)
    slot = int(body.get("slot"))
    if body.get("version"):
        g.select(slot, str(body["version"]), by="human", pinned=bool(body.get("pinned", True)))
    rec = g.pin(slot, bool(body.get("pinned", True)))
    _ev("pin", kind, cid, code, base, view, slot=slot, version=body.get("version"), pinned=bool(body.get("pinned", True)), ok=rec is not None)   # pass 97 (lane PROGRESS)
    return {"ok": rec is not None, "slot": slot, "selected": rec, "group": g.detail(_dl_url)}


def copy(kind, cid, code, base, view, body):
    look, g = _group(kind, cid, code, base, view)
    slot = int(body.get("slot"))
    frm = body.get("from") if isinstance(body.get("from"), dict) else {}
    src_code = str(frm.get("code") or "")
    if not CODE_RE.match(src_code):
        return {"ok": False, "error": "from.code is the other look's code"}
    src_look = FS.Look(kind, cid, src_code)
    sg = FS.Group(src_look, str(frm.get("base") or base), str(frm.get("view") or view))
    if not sg.exists():
        FS.register_look(kind, cid, src_code)
        sg = FS.Group(src_look, str(frm.get("base") or base), str(frm.get("view") or view))
    if not sg.exists():
        return {"ok": False, "error": "%s has no %s %s animation" % (src_code, base, view)}
    src_slot = int(frm.get("slot", slot))
    vid = str(frm.get("version") or "")
    if not vid:
        eff, _ = sg.effective(src_slot)
        vid = eff["id"] if eff else ""
    v = FS.copy_version(g, sg, src_slot, vid, slot, by="human")
    staged = None
    if body.get("stage", True):
        staged = g.stage(slot, v["id"], why="copied from %s" % v.get("from", {}).get("label", src_code))
    _ev("copy", kind, cid, code, base, view, slot=slot, version=v["id"], label=v.get("label"), source=frm, staged=staged is not None)   # pass 97 (lane PROGRESS)
    return {"ok": True, "slot": slot, "version": {"id": v["id"], "label": v["label"], "n": v["n"]}, "staged": staged, "group": g.detail(_dl_url)}


def ask(kind, cid, code, base, view, body):
    """The local vision model on one frame (gen_art.vision_json): its answer kept in the version's qa.vision."""
    look, g = _group(kind, cid, code, base, view)
    slot = int(body.get("slot"))
    vid = str(body.get("version") or "")
    v = g.version(slot, vid) if vid else g.effective(slot)[0]
    if not v:
        return {"ok": False, "error": "no such version"}
    try:
        import gen_art
    except Exception as e:
        return {"ok": False, "error": "gen_art could not be imported: %s" % e}
    noun = look.d.get("noun") or look.d.get("anim_hint") or str(look.d.get("art_prompt", "")).split(",")[0][:80] or "a creature"
    cell = g.cell_of(slot, v)
    # the figure on grey, three times the size: the model reads a 160 px cell badly
    from PIL import Image
    big = cell.resize((cell.width * 3, cell.height * 3), Image.LANCZOS)
    bg = Image.new("RGBA", big.size, (110, 110, 120, 255))
    bg.alpha_composite(big)
    try:
        # pass 96 (lane LOOP, AI-01): through the one adapter (tools/vision_eval.py), the same question (the `frame_ask`
        # rubric is ASK word for word), the same request body, the same fields back; the ledger is told
        import vision_eval
        ans = vision_eval.openai_chat_json(bg.convert("RGB"), vision_eval.rubric_text("frame_ask", noun=noun), max_tokens=200,
                                           url=getattr(gen_art, "LMSTUDIO", vision_eval.LMSTUDIO), model=getattr(gen_art, "VISION_MODEL", vision_eval.VISION_MODEL))
    except Exception as e:
        return {"ok": False, "error": "the vision model did not answer: %s" % e, "online": False}
    rec = dict(v.get("qa") or {})
    rec["vision"] = {"answer": ans, "model": getattr(gen_art, "VISION_MODEL", "?"), "time": FS._now(),
                     "note": "LM Studio's answer: it cannot count limbs reliably and passes extra ears, horns and arms; a hint, not a verdict"}
    g.update_version(slot, v["id"], qa=rec)
    return {"ok": True, "slot": slot, "version": v["id"], "vision": rec["vision"]}


def repair_job(srv, kind, cid, code, base, view, body):
    """A frames_repair job: the repair's keys written to the job's folder as repair.json by the plan (jobs.py reads
    spec), queued on the comfy lane."""
    look, g = _group(kind, cid, code, base, view)
    slots = body.get("slots")
    if isinstance(slots, str):
        slots = FS_parse_slots(slots, g.n)
    slots = sorted(set(int(s) for s in (slots or []) if 0 <= int(s) < g.n))
    if not slots:
        return {"ok": False, "error": "which frames? (slots 0..%d)" % (g.n - 1)}
    if g.n < 2:
        return {"ok": False, "error": "%s %s is one frame: nothing to pin it between; repaint it instead" % (base, view)}
    if len(slots) >= g.n:
        return {"ok": False, "error": "every frame: that is a new clip, re-roll the look instead"}
    rep = repairable(g)
    free_fill = body.get("free_fill") is True
    if not rep["ok"] and not free_fill:
        return {"ok": False, "error": rep["why"], "rule": rep["rule"], "needs_free_fill": True, "procedural": rep["procedural"]}
    spec = {"kind": kind, "id": cid, "code": code, "anim": base, "view": view, "slots": slots, "prompt": str(body.get("prompt") or ""),
            "seed": int(body.get("seed") or 0) or None, "window": str(body.get("window") or "auto"), "note": str(body.get("note") or ""),
            "guide": "free" if str(body.get("guide") or "") == "free" or (free_fill and not g.meta.get("driver")) else "driver", "free_fill": free_fill}
    if body.get("size"):
        spec["size"] = int(body["size"])
    target = {"kind": kind, "id": cid, "code": code}
    title = "repair %s %s %s/%s frames %s (VACE)" % (cid, code, base, view, ",".join(str(s) for s in slots))
    res = srv._enqueue("frames_repair", target, spec, title)
    if res.get("job") is None:
        return {"ok": False, "error": res.get("error") or "the queue is not here"}
    return {"ok": True, "job": res["job"], "slots": slots}


def FS_parse_slots(text, n):
    import vace_repair
    return vace_repair.parse_slots(text, n)


def batch(kind, cid, code):
    """pass 96 (Garry's decision 5): what the next Export replaces, for the one confirm box: every staged change as a
    before / after pair in Garry's label form with the flag deltas, the pinned slots the export packs again, whether the
    game plays the look, the backup folder. GET /api/frames/<kind>/<id>/<code>/batch (the request card's Approve box
    reads it too)."""
    try:
        b = FS.staged_batch(kind, cid, code, _dl_url)
    except ValueError as e:
        return {"ok": False, "error": str(e), "items": []}
    b["lines"] = [batch_line(i) for i in b.get("items") or []]
    return b


def batch_line(i):
    """One change as a line: `Run / Side / Frame 07 <- SP-A / Run / Side / Frame 07 / v2 (VACE)`."""
    to = i.get("to") or {}
    src = {"installed": "the strip", "reroll": "re-rolled", "vace": "VACE", "copied": "copied", "repaint": "repainted", "neighbour": "filled from a neighbour",
           "old_roll": "an old roll", "archived": "archived"}.get(str(to.get("source") or ""), str(to.get("source") or "?"))
    here = " / ".join(str(i.get("name") or "").split(" / ")[1:]) or str(i.get("name") or "")
    return "%s <- %s (%s%s)" % (here, to.get("name") or to.get("label") or "?", src, "; re-applied pin" if i.get("why") == "pinned" else "")


def export_job(srv, kind, cid, code, body):
    s = summary(kind, cid, code)
    if not s.get("ok"):
        return s
    if not s.get("staged") and not body.get("force"):
        return {"ok": False, "error": "nothing is staged for %s: choose frames first" % code}
    n = int(s.get("staged", 0) or 0)
    if body.get("confirm") is not True:
        # pass 96 (Garry's decision 5; pass 95 asked only for the look in play): EVERY export that replaces an installed
        # strip is confirmed first, one box for the whole staged batch; the route refuses without confirm: true
        b = batch(kind, cid, code)
        return {"ok": False, "needs_confirm": True, "in_play": bool(s.get("in_play")), "batch": b,
                "error": "%s%s: Export replaces the installed strip %s (%d frame%s changed%s; the old strip is kept under %s). Confirm the batch first." % (
                    code, " is the look the game plays" if s.get("in_play") else "", s.get("strip_file") or "", n, "" if n == 1 else "s",
                    ", %d pinned re-applied" % b.get("pinned_reapply") if b.get("pinned_reapply") else "", "tools/level_editor/backups/%s/" % cid)}
    target = {"kind": kind, "id": cid, "code": code}
    title = "export %s %s: %d frame%s changed" % (cid, code, n, "" if n == 1 else "s")
    res = srv._enqueue("frames_export", target, {"kind": kind, "id": cid, "code": code, "note": str(body.get("note") or ""), "in_play": bool(s.get("in_play"))}, title)
    if res.get("job") is None:
        return {"ok": False, "error": res.get("error") or "the queue is not here"}
    _ev("export", kind, cid, code, None, None, job=(res.get("job") or {}).get("id"), staged=n, in_play=bool(s.get("in_play")))   # pass 97 (lane PROGRESS)
    return {"ok": True, "job": res["job"], "staged": n, "in_play": bool(s.get("in_play"))}


def stage_versions(kind, cid, code, base, view, versions):
    """pass 95 resume (AN-08, one writer of staged.json): a repair job's versions staged at its landing. A version is
    staged when it asked to be (stage_wanted: not empty, the slot not pinned when it was made), the slot is still not
    pinned, and no hand choice was staged on that slot meanwhile (then it is left unstaged and said). Returns
    {staged: [...], skipped: [{slot, id, why}]}."""
    look, g = _group(kind, cid, code, base, view)
    sel, st = g.selected(), g.staged()
    staged, skipped = [], []
    for v in versions or []:
        try:
            slot = int(v.get("slot", -1))
        except (TypeError, ValueError):
            slot = -1
        vid = str(v.get("id") or "")
        rec = {"slot": slot, "id": vid, "label": v.get("label")}
        if slot < 0 or not g.version(slot, vid):
            skipped.append(dict(rec, why="no such version"))
            continue
        if not v.get("stage_wanted"):
            skipped.append(dict(rec, why="an empty frame" if v.get("empty") else "the slot was pinned" if v.get("pinned") else "not asked to be staged"))
            continue
        if (sel.get(str(slot)) or {}).get("pinned"):
            skipped.append(dict(rec, why="the slot is pinned (a human's choice)"))
            continue
        cur = st.get(str(slot))
        if cur and cur.get("id") != vid and not str(cur.get("why") or "").startswith("vace"):
            skipped.append(dict(rec, why="a choice was staged by hand meanwhile (%s)" % cur.get("why")))
            continue
        g.stage(slot, vid, why="vace (staged at the job's landing)")
        staged.append(rec)
    return {"ok": True, "staged": staged, "skipped": skipped}


def rollback(kind, cid, code, backup, changed, job=None, why=""):
    """pass 95 resume (AN-09): an export undone by the Level Editor when its merge or import failed (the strip from the
    backup, the exported choices staged again; the old entry is merged back by the caller through merge_look)."""
    r = FS.rollback_export(kind, cid, code, backup, changed=changed, job=job, why=why)
    _ev("rollback", kind, cid, code, None, None, job=job, why=why, ok=(r or {}).get("ok"))   # pass 97 (lane PROGRESS, WF-02)
    return r


def delete(kind, cid, code, base, view, body):
    """RETIRED (pass 96, Garry's decision 10): the route answers the refusal; no version is ever removed."""
    look, g = _group(kind, cid, code, base, view)
    slot = int(body.get("slot"))
    r = FS.delete_version(g, slot, str(body.get("version") or ""))
    if r.get("ok"):
        r["group"] = g.detail(_dl_url)
    return r


def _default_enqueue():
    """server.py's _enqueue (the module function) when the server is the caller; None in a script."""
    srv = sys.modules.get("server")
    fn = getattr(srv, "_enqueue", None) if srv else None
    return fn if callable(fn) else None


def on_look_landed(kind, cid, code, enqueue=None):
    """A look's strip landed (merge_look): its groups synced, so the installed cells are versions (selected unless the
    slot is pinned). Pass 96 (Garry's decision 4): a pinned slot the landing's strip does not show is RE-APPLIED: a
    `frames_export` is queued that packs the pinned versions with the new cells (no confirm: F3's N1 default, it
    restores his choice; the card note "re-applied N pinned frames"); pins that no longer fit (the slot count shrank,
    frame_px changed) are reported, their versions kept. Never raises: a landing must not fail on the store."""
    try:
        look = FS.Look(kind, cid, code)
        if not look.has_strip():
            return None
        r = FS.register_look(kind, cid, code)
        if not r.get("ok"):
            return r
        pinned = []
        misfit = []
        for gr in r.get("groups") or []:
            pinned += [(gr.get("group"), k) for k in (gr.get("pinned_differs") or [])]
            misfit += [dict(m, group=gr.get("group")) for m in (gr.get("misfit") or [])]
        r["misfit"] = misfit
        r["misfit_text"] = FS.misfit_text(misfit)
        if pinned:
            names = []
            for key, k in pinned:
                base, view = FS.anim_parts(kind, key)
                g = FS.Group(look, base, view)
                v = g.version(k, (g.selected().get(str(k)) or {}).get("id"))
                names.append(g.name_of(k, v) if v else g.name_of(k))
            note = "re-applied %d pinned frame%s" % (len(pinned), "" if len(pinned) == 1 else "s")
            enq = enqueue or _default_enqueue()
            spec = {"kind": kind, "id": cid, "code": code, "note": note, "in_play": bool(look.in_play),
                    "reapply": {"pinned": len(pinned), "slots": [[key, k] for key, k in pinned], "names": names}}
            title = "export %s %s: %s" % (cid, code, note)
            res = enq("frames_export", {"kind": kind, "id": cid, "code": code}, spec, title) if enq else {"job": None, "error": "no queue (a script): run `python tools/frames_store.py export %s %s %s`" % (kind, cid, code)}
            job = (res or {}).get("job") if isinstance(res, dict) else res
            r["reapply"] = {"pinned": len(pinned), "names": names, "note": note, "job": (job.get("id") if isinstance(job, dict) else job),
                            "error": (res or {}).get("error") if isinstance(res, dict) and not job else ""}
        return r
    except Exception as e:   # noqa: BLE001
        return {"ok": False, "error": "%s: %s" % (type(e).__name__, e)}


# ---------------------------------------------------------------- the routes

def _use(srv):
    global DL_DIR
    DL_DIR = getattr(srv, "DL", DL_DIR)


def api_get(h, srv, parts, query=None):
    """parts after /api/frames/: [kind, id, code], [kind, id, code, anim, view], [kind, id, code, anim, view, "others"]."""
    _use(srv)
    if len(parts) < 3:
        return h._error(404, "frames paths are /api/frames/<kind>/<id>/<code>[/<anim>/<view>[/others]]")
    kind, cid, code = parts[0], parts[1], parts[2]
    is_batch = len(parts) == 4 and parts[3] == "batch"   # pass 96: /batch is a look route, not an animation
    err = _check(kind, cid, code, parts[3] if len(parts) > 3 and not is_batch else None, parts[4] if len(parts) > 4 else None)
    if err:
        return h._error(400, err)
    try:
        if len(parts) == 3:
            res = summary(kind, cid, code)
        elif is_batch:
            res = batch(kind, cid, code)   # pass 96: the staged batch the confirm box lists, without queuing anything
        elif len(parts) == 5:
            res = detail(kind, cid, code, parts[3], parts[4])
        elif len(parts) == 6 and parts[5] == "others":
            res = others(kind, cid, code, parts[3], parts[4])
        else:
            return h._error(404, "unknown frames route")
    except ValueError as e:
        return h._error(400, str(e))
    return h._send(200 if res.get("ok", True) else 400, res)


def api_post(h, srv, parts, body=None):
    """parts after /api/frames/: [kind, id, code, "export" | "register"], [kind, id, code, anim, view, op]."""
    _use(srv)
    body = body if isinstance(body, dict) else {}
    if len(parts) < 4:
        return h._error(404, "unknown frames route")
    kind, cid, code = parts[0], parts[1], parts[2]
    try:
        if len(parts) == 4:
            err = _check(kind, cid, code)
            if err:
                return h._error(400, err)
            if parts[3] == "export":
                res = export_job(srv, kind, cid, code, body)
            elif parts[3] == "register":
                res = FS.register_look(kind, cid, code, force=bool(body.get("force")))
            else:
                return h._error(404, "unknown frames op %s" % parts[3])
        elif len(parts) == 6:
            base, view, op = parts[3], parts[4], parts[5]
            err = _check(kind, cid, code, base, view)
            if err:
                return h._error(400, err)
            fn = {"stage": stage, "unstage": unstage, "pin": pin, "copy": copy, "ask": ask, "delete": delete}.get(op)
            if fn:
                res = fn(kind, cid, code, base, view, body)
            elif op == "repair":
                res = repair_job(srv, kind, cid, code, base, view, body)
            else:
                return h._error(404, "unknown frames op %s" % op)
        else:
            return h._error(404, "unknown frames route")
    except ValueError as e:
        return h._error(400, str(e))
    except (TypeError, KeyError) as e:
        return h._error(400, "bad body: %s" % e)
    return h._send(200 if res.get("ok") else 400, res)


def _ev(op, kind, cid, code, base, view, job=None, **fields):
    """pass 97 (lane PROGRESS, WF-02): one `frames` event (the page's verbs and the loop's, which call the same
    functions); never raises; nothing outside the server."""
    try:
        m = sys.modules.get("events") or sys.modules.get("le_events")
        if m is None or not hasattr(m, "emit"):
            import jobs as _j
            m = _j._ev()
        if m is not None:
            group = "%s/%s" % (base, view) if base and view else None
            m.emit("frames", op, job=job, look=m.look_of(kind, cid, code), group=group, **fields)
    except Exception:   # noqa: BLE001
        pass
