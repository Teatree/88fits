"""The Level Editor's job runner (pass 66): one art job as a subprocess of tools/level_editor/server.py's jobs queue.

    python -u tools/asset_job.py <job_dir> [--dry-run]

<job_dir>/job.json says which tool to import and what to call, exactly as Claude would type it:
    {"tool": "gen_art" | "gen_ctl" | "gen_edit_stills" | "gen_icon_cands" | "gen_title_heroes" | "gen_badge_cands",
     "call": "process" | "main" | "paint" | "pick",
     "argv": ["--no-import", "--only", "goblin", "--variant=GOB-E"],       # becomes sys.argv[1:] BEFORE the import
     "env": {"ASSET_JOB_SIDECAR": "...", "LOCK_HELD_COMFY": "1"},           # merged into os.environ first
     "equiv": "python tools/gen_art.py --only goblin --variant=GOB-E --no-import",   # printed as the first line
     "type": "enemies", "folder": "game/content/enemies/goblin", "id": "goblin",      # gen_art.process(type, folder, id)
     "key": "magnet", "icon_job": {...}, "seeds": 4, "dev": false, "choice": "2",    # gen_icon_cands paint / pick
     "hid": "astro", "first": 11, "n": 2}                                            # gen_title_heroes paint / pick

The scripts read their flags from sys.argv at import (gen_art), or rewrite sys.argv before importing gen_art (gen_ctl,
gen_edit_stills, gen_badge_cands), so argv is set first and the tool imported after. ASSET_JOB_SIDECAR makes gen_art and
gen_ctl write <job_dir>/result.json instead of the content JSON (gen_art.emit_sidecar). The exit code is the tool's.
gen_art.main() is never called: it pings the server, rewrites game/icon*.png, the review sheets and runs a whole-project
import.

--dry-run (critique 16, "show the words that will be sent"): nothing reaches ComfyUI. gen_art.render, comfy.run,
comfy.upload and the Wan cycles are replaced by stand-ins that record every prompt into <job_dir>/dry_run.json and hand
back the cached painting (tools/dl/ai_raw_anime/<key>.png) or a flat screen-coloured square; clips come back None, so
the strip is packed with procedural frames. The content JSON is never written (the sidecar is on); pass 71: nor is any
file under game/content (gen_art works on a copy of the JSON under <job_dir>/dry_content/: _dry_folder).
Pass 68: a graph's record also names its reference pictures (LoadImage), seed, model file and steps; a candidate tool's
own outputs (the title cut-outs, the badge review sheet, the icon candidates) go under <job_dir>/ instead of tools/dl/,
and a pick is not run at all (it only writes files): the dry run records what it would have installed.

Pass 71 (lane PLE): tool "puppet" runs one phase of a hero_puppet look job: puppet.main(argv) (tools/puppet.py, its stages
on the job's lane; it stops at a pick, at a lane change and after the guides). With --dry-run every puppet stage runs
recorded (puppet.py --dry-run: the paintings, the Hunyuan3D graphs and the Blender commands, the picks c0, stand-ins under
<job_dir>/puppet_dry/), then the walks that follow (job.json "walks": gen_art's argv) dry like a look job's; both lists
go into <job_dir>/dry_run.json (the puppet's first, "phase": "puppet").

The candidate tools (pass 68, D7) take their inputs explicitly: gen_badge_cands --character/--ref/--prompt/--variant,
gen_title_heroes.paint(character=, pose=, holds=, camera=, ref=, extra_ref=, extra_words=, variant=, tag=), gen_icon_cands
JOBS[key] ref/subject/screen/style/file/variant. This runner reads each from the job's argv first, then the job.json keys,
then the job's spec, then the target's look code (badge_argv, title_call, icon_spec), so the queue may write them either
way. A re-run (job.json "attempt" > 1) paints new candidates: --attempt / attempt= move their seeds, and gen_icon_cands
moves the earlier ones aside. The tools' content folder follows job.json "folder", as gen_art's does.
"""
import io
import json
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

TOOLS = ("gen_art", "gen_ctl", "gen_edit_stills", "gen_icon_cands", "gen_title_heroes", "gen_badge_cands", "puppet")


def log(*a):
    print(*a, flush=True)


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def _folder_for(job):
    if job.get("folder"):
        return _abs(job["folder"])
    return os.path.join(ROOT, "game", "content", job.get("type", "enemies"), job["id"])


# ---------------------------------------------------------------- a candidate job's inputs (pass 68, D7)

def _spec(job):
    return job.get("spec") if isinstance(job.get("spec"), dict) else {}


def _given(job, key):
    """An input from the job.json keys, else from the job's spec ("" and None count as not given)."""
    v = job.get(key)
    if v in (None, ""):
        v = _spec(job).get(key)
    return None if v in (None, "") else v


def _has_flag(argv, flag):
    return any(a == flag or a.startswith(flag + "=") for a in argv)


def _look(job):
    """The look a candidate job is for: the job's own "variant" when job.json or the spec names one (an empty one is the
    hero's own), else its target's code ("" for none)."""
    for src in (job, _spec(job)):
        if "variant" in src:
            return str(src.get("variant") or "").strip()
    return str((job.get("target") or {}).get("code") or "").strip()


def badge_argv(job):
    """gen_badge_cands's command line: the job's argv plus what it lacks: --character, --ref and --prompt from the
    job.json keys or the spec, --variant (the target's look), --attempt N for a re-run; a pick gets --tag <the painting
    job's id> (an install job's own id is not the one its candidates were keyed with)."""
    argv = [str(a) for a in (job.get("argv") or [])]
    if _has_flag(argv, "--pick"):
        src = _given(job, "source_job")
        if src and not _has_flag(argv, "--tag"):
            argv += ["--tag", str(src)]
    else:
        for key in ("character", "ref", "prompt"):
            v = _given(job, key)
            if v is not None and not _has_flag(argv, "--" + key):
                argv += ["--" + key, str(v)]
        attempt = int(job.get("attempt") or 1)
        if attempt > 1 and not _has_flag(argv, "--attempt"):
            argv += ["--attempt", str(attempt)]
    look = _look(job)
    if look and not _has_flag(argv, "--variant"):
        argv += ["--variant", look]
    return argv


TITLE_WORDS = ("character", "pose", "holds", "camera", "ref", "extra_ref", "extra_words")


def title_call(job, parse):
    """gen_title_heroes's call: ("pick", [pairs], variant, tag) or ("paint", hid, seeds, first, kwargs). `parse` is its
    parse_args; the argv wins, then the job.json keys (hid, seeds, first, the words), then the spec, then the target.
    The cut-outs are keyed per job (pass 68 review): a pick's tag is the argv's --tag, else the painting job's id
    (source_job; an install job's own id is not the one its candidates were keyed with), else None (a hand run's
    untagged ones); a paint's is the argv's --tag when given (else the tool takes ASSET_JOB_ID)."""
    o = parse([str(a) for a in (job.get("argv") or [])])
    spec = _spec(job)
    look = str(o.get("variant") or "") or _look(job)
    if job.get("call") == "pick" or o.get("pick") is not None:
        pairs = o.get("pick") or []
        if not pairs:
            hid = job.get("hid") or job.get("id")
            pairs = ["%s=%s" % (hid, job.get("choice", job.get("n", spec.get("choice", 0))))]
        tag = o.get("tag") or _given(job, "source_job")
        return "pick", pairs, look, (str(tag) if tag else None)
    hid = str(o.get("only") or "").split(",")[0] or job.get("hid") or job.get("id")
    seeds = int(o.get("seeds") or job.get("seeds") or spec.get("seeds") or 4)
    first = o.get("first_seed")
    if first in (None, ""):
        first = job.get("first", spec.get("first_seed"))
    first = int(first) if first not in (None, "") else 11
    kw = {}
    for k in TITLE_WORDS:
        v = o.get(k) or _given(job, k)
        if v not in (None, ""):
            kw[k] = str(v)
    kw["variant"] = look or None
    kw["attempt"] = int(o.get("attempt") or job.get("attempt") or 1)
    if o.get("tag"):
        kw["tag"] = str(o["tag"])
    return "paint", hid, seeds, first, kw


def icon_spec(job, job_dir=""):
    """gen_icon_cands's JOBS entry: the plan's icon_job, with what it lacks from the spec (subject, ref, style, file,
    screen) and the target's look as "variant" (its pick goes to the look's own icon and entry)."""
    out = dict(job.get("icon_job") or {})
    s = _spec(job)
    for k in ("subject", "ref", "style", "file"):
        if not out.get(k) and s.get(k):
            out[k] = s[k]
    if not out.get("screen") and s.get("screen") and s.get("screen") != "green":
        out["screen"] = s["screen"]
    out.setdefault("kind", job.get("type", ""))
    out.setdefault("id", job.get("id", ""))
    look = str(out.get("variant") or "") or _look(job)
    if look:
        out["variant"] = look
    out.setdefault("set", "_le_" + os.path.basename(job_dir or ""))
    return out


def _dry_folder(job, job_dir, folder):
    """Pass 71 (lane PLE): a dry run never writes into game/content. gen_art saves the strip, the icon and the _ai.json
    marker beside the JSON whatever the sidecar says (the content JSON itself it never writes), so a dry run of a real
    look's job (MAY-Q's, 2026-10-13) overwrote that look's strip with procedural frames. A folder under game/content is
    swapped for <job_dir>/dry_content/<type>/<id>/ holding a copy of the JSON; a folder elsewhere (the selftests' temp
    copies) is used as it is."""
    real = os.path.abspath(os.path.join(ROOT, "game", "content"))
    f = os.path.abspath(folder)
    if not (f == real or f.startswith(real + os.sep)):
        return folder
    cid = os.path.basename(f)
    dst = os.path.join(job_dir, "dry_content", os.path.basename(os.path.dirname(f)), cid)
    os.makedirs(dst, exist_ok=True)
    src = os.path.join(f, cid + ".json")
    if os.path.isfile(src):
        with open(src, "rb") as a, open(os.path.join(dst, cid + ".json"), "wb") as b:
            b.write(a.read())
    log("dry run: gen_art works on a copy of %s.json in %s (game/content is never written)" % (cid, dst))
    return dst


def _content_dir(job, up):
    """The content folder `up` levels above the job's own (job.json "folder"), or None when the job names none."""
    if not job.get("folder"):
        return None
    p = _abs(job["folder"])
    for _ in range(up):
        p = os.path.dirname(p)
    return p


# ---------------------------------------------------------------- dry run stand-ins

class DryRun:
    """Records what would have been sent; answers with cached pictures."""

    def __init__(self, job_dir):
        self.path = os.path.join(job_dir, "dry_run.json")
        self.prompts = []
        self.t0 = time.time()

    def note(self, kind, **kw):
        kw["kind"] = kind
        kw["t"] = round(time.time() - self.t0, 2)
        self.prompts.append(kw)
        self.flush()

    def flush(self):
        with open(self.path, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"dry_run": True, "prompts": self.prompts}, f, indent=1, ensure_ascii=False)

    @staticmethod
    def _graph_prompts(graph):
        try:
            nodes = graph.api()
        except Exception:
            return []
        out = []
        for nid, n in nodes.items():
            if n.get("class_type") in ("CLIPTextEncode",) and isinstance(n.get("inputs", {}).get("text"), str):
                out.append(n["inputs"]["text"])
        return out

    @staticmethod
    def _graph_facts(graph):
        """What else a graph sends (pass 68): its reference pictures (LoadImage), seed, model file and steps."""
        out = {"refs": []}
        try:
            nodes = graph.api()
        except Exception:
            return out
        for n in nodes.values():
            ct, inp = n.get("class_type"), n.get("inputs", {})
            if ct == "LoadImage" and isinstance(inp.get("image"), str):
                out["refs"].append(inp["image"])
            elif ct == "RandomNoise" and "noise_seed" in inp:
                out["seed"] = inp["noise_seed"]
            elif ct == "UNETLoader":
                out["unet"] = inp.get("unet_name")
            elif ct == "Flux2Scheduler":
                out["steps"] = inp.get("steps")
        return out

    def install(self, comfy, gen_art=None, animate=None, artkit=None):
        from PIL import Image
        rec = self

        def flat(width=1024, height=1024, colour=(0, 255, 0)):
            buf = io.BytesIO()
            Image.new("RGB", (width, height), colour).save(buf, "PNG")
            return buf.getvalue()

        def fake_run(graph, timeout=1200):
            texts = rec._graph_prompts(graph)
            rec.note("comfy.run", prompts=texts, **rec._graph_facts(graph))
            # the graph's canvas size when it says one
            w = h = 1024
            try:
                for n in graph.api().values():
                    if n.get("class_type") == "EmptyFlux2LatentImage":
                        w, h = int(n["inputs"].get("width", 1024)), int(n["inputs"].get("height", 1024))
            except Exception:
                pass
            return [flat(w, h)], 0.0

        def fake_upload(png_bytes, name, subfolder="88fits"):
            rec.note("comfy.upload", name=name)
            return (subfolder + "/" if subfolder else "") + name

        def fake_upload_pil(img, name, subfolder="88fits"):
            # pass 68: the top-left pixel too, so a check sees a transparent picture laid on the screen colour
            try:
                corner = list(img.convert("RGB").getpixel((0, 0)))
            except Exception:
                corner = None
            rec.note("comfy.upload", name=name, size=list(img.size), corner=corner)
            return (subfolder + "/" if subfolder else "") + name

        comfy.run = fake_run
        comfy.run_dev = lambda graph, timeout=1500, tries=2: fake_run(graph, timeout)
        comfy.upload = fake_upload
        comfy.upload_pil = fake_upload_pil
        comfy.release_models = lambda: "dry-run"
        comfy.restart_server = lambda: "dry-run"
        comfy.ensure_lock = lambda: None
        comfy.get = lambda path, timeout=120: {"system": {"comfyui_version": "dry-run"}, "devices": [{"name": "none"}]}
        comfy.post = lambda path, obj, timeout=120: {}
        if gen_art is not None:
            real_render = gen_art.render

            def fake_render(key, prompt, refs, expect, seed, width=1024, height=1024, tries=3):
                rec.note("render", key=key, prompt=prompt, refs=list(refs), expect=expect, seed=seed, size=[width, height])
                raw, meta = os.path.join(gen_art.RAW, key + ".png"), os.path.join(gen_art.RAW, key + ".json")
                if os.path.exists(raw) and os.path.exists(meta):
                    cached = json.load(open(meta, encoding="utf-8"))
                    cached["cached"] = True   # as gen_art.render says it (pass 68)
                    return Image.open(raw).convert("RGB"), cached
                # no cache for this key: the item's own front still stands in (a badge or title dry run keeps a figure to
                # key and fit), else a flat square of the screen colour
                parts = key.split("_")
                for n in range(len(parts) - 1, 0, -1):
                    front = os.path.join(gen_art.RAW, "_".join(parts[:n]) + "_front.png")
                    if os.path.exists(front):
                        return Image.open(front).convert("RGB"), {"seed": seed, "prompt": prompt, "refs": list(refs), "qa": {"problems": [], "dry_run": True, "stand_in": os.path.basename(front)}, "attempt": 0}
                colour = (0, 0, 255) if "blue" in prompt.lower().split("background")[0][-80:] else (0, 255, 0)
                img = Image.new("RGB", (width, height), colour)
                return img, {"seed": seed, "prompt": prompt, "refs": list(refs), "qa": {"problems": [], "dry_run": True}, "attempt": 0}

            fake_render.real = real_render
            gen_art.render = fake_render

            def fake_cycle(name):
                def f(still, key, *a, **kw):
                    words = kw.get("motion") or kw.get("prompt_hint") or (a[0] if a and isinstance(a[0], str) else "")
                    rec.note("clip:" + name, key=key, words=words, negative=kw.get("negative_extra", ""))
                    return None
                return f

            gen_art.video_cycle = fake_cycle("free")
            gen_art.pose_cycle = fake_cycle("pose")
            gen_art.death_cycle = fake_cycle("flf")
            gen_art.pose_death = fake_cycle("pose_death")
            gen_art.ensure_anchor_uploaded = lambda: [gen_art.ANCHOR_REF] if gen_art.USE_ANCHOR else []
        if animate is not None and artkit is not None:
            def fake_control(img, key, ctl_dir, seed, prompt="", negative_extra="", **kw):
                rec.note("clip:control", key=key, words=prompt, negative=negative_extra, ctl_dir=ctl_dir, seed=seed)
                frame = artkit.key_background(img.convert("RGB")).convert("RGBA")
                return [frame.copy() for _ in range(12)], {"dry_run": True}

            def fake_oneshot(img, key, ctl_dir, seed, prompt="", negative_extra="", keep=(), **kw):
                rec.note("clip:oneshot_control", key=key, words=prompt, negative=negative_extra, ctl_dir=ctl_dir, seed=seed, keep=list(keep))
                frame = artkit.key_background(img.convert("RGB")).convert("RGBA")
                return [frame.copy() for _ in range(max(1, len(keep) or 8))], {"dry_run": True}

            animate.cycle_control = fake_control
            animate.oneshot_control = fake_oneshot


# ---------------------------------------------------------------- dispatch

def run(job_dir, dry=False):
    job_dir = _abs(job_dir)
    job = json.load(open(os.path.join(job_dir, "job.json"), encoding="utf-8"))
    os.chdir(ROOT)
    for k, v in (job.get("env") or {}).items():
        os.environ[str(k)] = str(v)
    os.environ.setdefault("ASSET_JOB_SIDECAR", os.path.join(job_dir, "result.json"))
    os.environ.setdefault("ASSET_JOB_ID", os.path.basename(job_dir))
    # pass 70 (lane LE): a re-run's number for the candidate tools that take no --attempt (gen_edit_stills, gen_ctl's
    # candidates; tools/cand_seeds.job_attempt), so a re-queued job paints on new seeds
    os.environ.setdefault("ASSET_JOB_ATTEMPT", str(int(job.get("attempt") or 1)))
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    tool, call = job.get("tool", "gen_art"), job.get("call", "process")
    if tool not in TOOLS:
        log("asset_job: unknown tool %r" % tool)
        return 2
    equiv = job.get("equiv") or ("python tools/%s.py %s" % (tool, " ".join(job.get("argv") or [])))
    log("equiv: " + equiv)
    if dry:
        log("dry run: nothing reaches ComfyUI; the words go to %s" % os.path.join(job_dir, "dry_run.json"))
    sys.argv = [tool + ".py"] + [str(a) for a in (job.get("argv") or [])]
    rec = DryRun(job_dir) if dry else None
    import comfy  # noqa: E402
    if dry:
        rec.install(comfy)
    if tool == "gen_art":
        import gen_art  # noqa: E402
        if dry:
            rec.install(comfy, gen_art=gen_art)
        gen_art.process(job.get("type", "enemies"), _dry_folder(job, job_dir, _folder_for(job)) if dry else _folder_for(job), job["id"])
    elif tool == "gen_ctl":
        import gen_ctl  # noqa: E402
        if dry:
            import animate  # noqa: E402
            import artkit  # noqa: E402
            rec.install(comfy, gen_art=gen_ctl.g, animate=animate, artkit=artkit)
        gen_ctl.main()
    elif tool == "gen_edit_stills":
        import gen_edit_stills  # noqa: E402
        if dry:
            rec.install(comfy, gen_art=gen_edit_stills.g)
        gen_edit_stills.main()
    elif tool == "gen_icon_cands":
        import gen_icon_cands as gic  # noqa: E402
        if dry:
            rec.install(comfy, gen_art=gic.ga)
            gic.DL = job_dir     # the candidates under the job's folder, not tools/dl/
        if _content_dir(job, 2):
            gic.CONTENT = _content_dir(job, 2)
        key = job.get("key") or job["id"]
        spec = icon_spec(job, job_dir)
        gic.JOBS[key] = spec
        if call == "pick":
            if dry:
                rec.note("pick", tool=tool, would_install=key + "=" + str(job.get("choice", 0)), job=spec)
            else:
                gic.pick([key + "=" + str(job.get("choice", 0))])
        else:
            gic.paint([key], int(job.get("seeds", 4)), bool(job.get("dev", False)), int(job.get("attempt") or 1))
    elif tool == "gen_title_heroes":
        import gen_title_heroes as gth  # noqa: E402
        if dry:
            rec.install(comfy)
            gth.OUT = os.path.join(job_dir, "title_heroes")
        if _content_dir(job, 1):
            gth.CHARS = _content_dir(job, 1)
        how = title_call(job, gth.parse_args)
        if how[0] == "pick":
            if dry:
                rec.note("pick", tool=tool, would_install=how[1], variant=how[2], tag=how[3])
            else:
                gth.pick(how[1], how[2] or None, how[3])
        else:
            _, hid, seeds, first, kw = how
            log("paint: %s seeds %d first %d %s" % (hid, seeds, first, json.dumps({k: v for k, v in kw.items() if v not in (None, "")}, ensure_ascii=False)))
            gth.paint(hid, seeds, first, **kw)
    elif tool == "puppet":
        import puppet  # noqa: E402
        argv = [str(a) for a in (job.get("argv") or [])]
        if dry:
            # the whole chain recorded (every lane, the picks c0), then the walks dry like a look job's
            root = os.path.join(job_dir, "puppet_dry")
            rc = puppet.main(argv + ["--dry-run", "--out-root", root])
            try:
                with open(os.path.join(root, "dry_run.json"), encoding="utf-8") as f:
                    for n in json.load(f).get("prompts", []):
                        rec.prompts.append(dict(n, phase="puppet"))
                rec.flush()
            except (OSError, ValueError):
                pass
            w = job.get("walks") or {}
            if not rc and w.get("argv"):
                log("dry run: the walks that follow: python tools/gen_art.py %s" % " ".join(str(a) for a in w["argv"]))
                sys.argv = ["gen_art.py"] + [str(a) for a in w["argv"]]
                import gen_art  # noqa: E402
                import animate  # noqa: E402
                import artkit  # noqa: E402
                rec.install(comfy, gen_art=gen_art, animate=animate, artkit=artkit)
                try:
                    wf = _abs(w["folder"]) if w.get("folder") else _folder_for(dict(job, type="characters"))
                    gen_art.process(w.get("type", "characters"), _dry_folder(job, job_dir, wf), w.get("id") or job["id"])
                except (Exception, SystemExit) as e:   # the walks' dry run is a bonus: the puppet's record stands
                    rec.note("walks_error", error="%s: %s" % (type(e).__name__, e))
                    log("dry run: the walks were not recorded (%s: %s); the look's stub is written when a real job is queued" % (type(e).__name__, e))
        else:
            rc = puppet.main(argv)
        if rc:
            return int(rc)
    elif tool == "gen_badge_cands":
        argv = badge_argv(job)
        if argv != [str(a) for a in (job.get("argv") or [])]:
            log("argv: " + " ".join(argv))
        sys.argv = [tool + ".py"] + argv
        import gen_badge_cands  # noqa: E402
        if dry:
            rec.install(comfy, gen_art=gen_badge_cands.g)
            gen_badge_cands.REVIEW = job_dir
        if _content_dir(job, 1):
            gen_badge_cands.CHARS = _content_dir(job, 1)
        if dry and _has_flag(argv, "--pick"):
            rec.note("pick", tool=tool, would_install=argv)
        else:
            gen_badge_cands.main()
    sidecar = os.environ.get("ASSET_JOB_SIDECAR", "")
    if sidecar and not os.path.isfile(sidecar):
        # a tool without a sidecar of its own (an icon pick, a title pick): a small one so the queue sees it finished
        with open(sidecar, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"id": job.get("id") or job.get("hid") or job.get("key", ""), "tool": tool, "call": call, "ok": True,
                       "dry_run": bool(dry)}, f, indent=1)
    return 0


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    dry = "--dry-run" in argv
    try:
        return run(args[0], dry)
    except SystemExit as e:
        code = e.code
        if isinstance(code, str):
            log("asset_job: " + code)
            return 1
        return int(code or 0)
    except Exception:
        traceback.print_exc()
        log("asset_job: FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
