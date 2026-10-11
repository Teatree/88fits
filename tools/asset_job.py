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
the strip is packed with procedural frames. The content JSON is never written (the sidecar is on).
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

TOOLS = ("gen_art", "gen_ctl", "gen_edit_stills", "gen_icon_cands", "gen_title_heroes", "gen_badge_cands")


def log(*a):
    print(*a, flush=True)


def _abs(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def _folder_for(job):
    if job.get("folder"):
        return _abs(job["folder"])
    return os.path.join(ROOT, "game", "content", job.get("type", "enemies"), job["id"])


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

    def install(self, comfy, gen_art=None, animate=None, artkit=None):
        from PIL import Image
        rec = self

        def flat(width=1024, height=1024, colour=(0, 255, 0)):
            buf = io.BytesIO()
            Image.new("RGB", (width, height), colour).save(buf, "PNG")
            return buf.getvalue()

        def fake_run(graph, timeout=1200):
            texts = rec._graph_prompts(graph)
            rec.note("comfy.run", prompts=texts)
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
            rec.note("comfy.upload", name=name, size=list(img.size))
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
                    return Image.open(raw).convert("RGB"), json.load(open(meta, encoding="utf-8"))
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
        gen_art.process(job.get("type", "enemies"), _folder_for(job), job["id"])
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
        key = job["key"]
        spec = dict(job.get("icon_job") or {})
        spec.setdefault("set", "_le_" + os.path.basename(job_dir))
        gic.JOBS[key] = spec
        if call == "pick":
            gic.pick([key + "=" + str(job.get("choice", 0))])
        else:
            gic.paint([key], int(job.get("seeds", 4)), bool(job.get("dev", False)))
    elif tool == "gen_title_heroes":
        import gen_title_heroes as gth  # noqa: E402
        if dry:
            rec.install(comfy)
        hid = job.get("hid") or job["id"]
        if call == "pick":
            gth.pick([hid + "=" + str(job.get("choice", job.get("n", 0)))])
        else:
            gth.paint(hid, int(job.get("seeds", 4)), int(job.get("first", 11)))
    elif tool == "gen_badge_cands":
        import gen_badge_cands  # noqa: E402
        if dry:
            rec.install(comfy, gen_art=gen_badge_cands.g)
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
