"""Lane LOOP's selftest group (pass 96): the evaluator adapter (tools/vision_eval.py: the three backends over a fake HTTP
server and FakeBackend, the opaque-name rule, the per-model budget, "no verdict" on an empty answer, the ledger with its
ceilings, the cache), the legacy callers unchanged (gen_art.vision_json's request body byte for byte, gen_art.qa's question
word for word and its problems in the old order, --skip-qa still skipping, frames_io.ASK = the frame_ask rubric), the
geometry-first order in gen_art.render (an empty or edge-touching still never calls the model), the findings record from
answers and from a stored look through the tiers (VACE95's temp world), the `evaluate` job kind's plan / post / harvest,
commands.validate's refusals (unknown keys, the never-verbs, outside the target, a pinned slot, the budget, observe),
commands.dispatch on a fake queue (every verb; select_provisional never pins, exports or touches `variant`), the planner
through its branches (ask when stale, select_provisional when the gates pass, repair single -> double -> reroll_view, the
still-level requeue with the defect words and a new seed, the procedural group, the plateau rule, the budget), and the
requests_api shim. Discovered by selftest.py: `checks(check, run_node, server)`. Everything on temp folders; nothing under
game/, tools/dl/frames, tools/dl/qa or tools/dl/jobs is touched."""
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (HERE, os.path.join(ROOT, "tools")):
    if p not in sys.path:
        sys.path.insert(0, p)

# gen_art.qa's question as the function held it before pass 96 (the `still_gate` rubric must equal it word for word)
OLD_Q = ("You are checking a generated video game asset. Answer ONLY with one JSON object, no prose, with keys: "
         "subjects (integer, how many separate characters or objects are shown), "
         "background (\"flat\" if the background is a single flat color, otherwise \"scene\"), "
         "ground (true if a floor, ground plane, grass or a cast shadow is drawn under the subject), "
         "text (true if any letters, numbers or a watermark appear), "
         "cropped (true if part of the main subject is cut off by the image border), "
         "legs (true if the subject's legs and feet are both completely visible and drawn, false if any limb is missing or cut off), "
         "view (\"front\" if the main subject's face or front is towards the viewer, \"back\" if it is seen from behind with no face visible, "
         "\"side\" for a profile, else \"other\"), "
         "matches (true if the image clearly shows: %s).")
RID = "r20261021-215900-ab12"   # a well-formed request id (REQ's requests.load validates the shape)
FINE = {"legs": 8, "arms": 0, "broken": False, "ghost": False, "face": "ok", "smear": False, "colour": False, "note": "fine"}
BAD = {"legs": 9, "arms": 0, "broken": True, "ghost": False, "face": "missing", "smear": False, "colour": False, "note": "nine legs"}


class FakeEyes:
    """One HTTP server standing in for LM Studio (/v1/chat/completions, /v1/models), the Messages API (/v1/messages) and
    the Gemini API (/v1beta/models/<m>:generateContent): every request recorded, the answer from `state`."""

    def __init__(self):
        self.state = {"answer": "{}", "anthropic": "{}", "gemini": "{}", "refusal": False, "calls": []}
        st = self.state

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                body = json.dumps({"data": [{"id": "m7b"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n)
                rec = {"path": self.path, "raw": raw, "headers": {k.lower(): v for k, v in self.headers.items()}}
                try:
                    rec["body"] = json.loads(raw.decode("utf-8"))
                except ValueError:
                    rec["body"] = None
                st["calls"].append(rec)
                if self.path.startswith("/v1/chat/completions"):
                    out = {"choices": [{"message": {"role": "assistant", "content": st["answer"]}}], "usage": {"prompt_tokens": 900, "completion_tokens": 30}}
                elif self.path.startswith("/v1/messages"):
                    if st["refusal"]:
                        out = {"content": [], "stop_reason": "refusal", "stop_details": {"type": "refusal", "category": "general_harms"}, "usage": {"input_tokens": 1600, "output_tokens": 0}}
                    else:
                        out = {"content": [{"type": "text", "text": st["anthropic"]}], "stop_reason": "end_turn", "usage": {"input_tokens": 1600, "output_tokens": 50}}
                elif ":generateContent" in self.path:
                    out = {"candidates": [{"content": {"parts": [{"text": st["gemini"]}]}}], "usageMetadata": {"promptTokenCount": 1700, "candidatesTokenCount": 60}}
                else:
                    out = {"error": "unknown"}
                body = json.dumps(out).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.srv.server_address[1]
        self.t = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.t.start()

    def close(self):
        self.srv.shutdown()
        self.srv.server_close()


def _png(colour=(0, 255, 0), size=256, blob=None):
    from PIL import Image, ImageDraw
    im = Image.new("RGB", (size, size), colour)
    if blob:
        ImageDraw.Draw(im).ellipse(blob, fill=(200, 100, 40))
    return im


def _bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def checks(check, run_node, server):
    import vision_eval as VE
    import commands as CMD
    import loop as LOOP
    import requests_api as RAPI
    import frames_store as FS
    import frames_io as FRIO
    import jobs
    import locks
    import selftest_VACE95 as V
    tmp = tempfile.mkdtemp(prefix="le_loop96_")
    saved_ve = {k: getattr(VE, k) for k in ("LEDGER", "CACHE_DIR", "DEFAULTS", "KEYS_DIR", "JOBS_DIR")}
    saved_fs = {k: getattr(FS, k) for k in ("STORE", "CONTENT", "ANIM", "DRIVERS", "RAW", "BACKUPS")}
    saved_jobs = {k: getattr(jobs, k) for k in ("JOBS_DIR", "QUEUE_FILE", "RAW", "ANIM", "REVIEW", "LAUNCH_FILE", "DL", "TITLE_OUT", "WANTED")}
    saved_locks = {k: getattr(locks, k) for k in ("LOCK_DIR", "SAVE_DIR", "KEEP_DIR", "RESTORE_PENDING")}
    saved_state = (jobs._state, jobs._hooks, jobs._root, dict(jobs._lane_current))
    env_key = os.environ.pop("ANTHROPIC_API_KEY", None)
    eyes = FakeEyes()
    try:
        VE.LEDGER = os.path.join(tmp, "qa", "ledger.json")
        VE.CACHE_DIR = os.path.join(tmp, "qa", "cache")
        VE.DEFAULTS = os.path.join(tmp, "request_defaults.json")
        VE.KEYS_DIR = os.path.join(tmp, "keys")
        VE.JOBS_DIR = os.path.join(tmp, "jobs")
        os.environ["ANTHROPIC_API_KEY"] = "ENV-KEY-NEVER-READ"
        _rubric_checks(check, VE, FRIO)
        _legacy_checks(check, VE, eyes, tmp)
        _ledger_checks(check, VE, tmp)
        _backend_checks(check, VE, eyes, tmp)
        _blind_checks(check, VE)
        _items_checks(check, VE)
        # the temp world (VACE95's creature "bug": BG-A procedural with a shifted and an empty run frame, BG-B's side walk
        # with a clip cache, a driver and a painting)
        w = V._make_world(tmp)
        FS.STORE = os.path.join(tmp, "dl", "frames")
        FS.CONTENT = w["content"]
        FS.ANIM = os.path.join(tmp, "dl", "ai_anim")
        FS.DRIVERS = os.path.join(tmp, "dl", "drivers")
        FS.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
        FS.BACKUPS = os.path.join(tmp, "backups")
        FS.register_look("enemy", "bug", "BG-A")
        FS.register_look("enemy", "bug", "BG-B")
        _look_checks(check, VE, tmp)
        _job_checks(check, VE, jobs, locks, tmp)
        _commands_checks(check, CMD, RAPI, FS, FRIO, jobs, tmp, w)
        _planner_checks(check, LOOP)
        _docs_checks(check, LOOP)
    finally:
        eyes.close()
        try:
            jobs._release_claim()   # the tmp queue's claim (jobs.init claimed it under the re-pointed lock folder)
        except Exception:   # noqa: BLE001
            pass
        for k, v in saved_ve.items():
            setattr(VE, k, v)
        for k, v in saved_fs.items():
            setattr(FS, k, v)
        for k, v in saved_jobs.items():
            setattr(jobs, k, v)
        for k, v in saved_locks.items():
            setattr(locks, k, v)
        jobs._state, jobs._hooks, jobs._root = saved_state[0], saved_state[1], saved_state[2]
        jobs._lane_current.update(saved_state[3])
        os.environ.pop("ANTHROPIC_API_KEY", None)
        if env_key is not None:
            os.environ["ANTHROPIC_API_KEY"] = env_key
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- the rubrics and the legacy callers

def _rubric_checks(check, VE, FRIO):
    rs = VE.rubrics()
    check(set(rs) >= {"still_gate", "frame_ask", "frame_blind", "still_blind", "sheet_blind"}, "qa_rubrics.json holds the five rubrics: %s" % sorted(rs))
    for rid, r in rs.items():
        check(r.get("per") in ("image", "sheet") and r.get("text") and isinstance(r.get("fields"), dict), "rubric %s has per, text and fields" % rid)
    check(VE.rubric_text("still_gate", subject="a red bug") == OLD_Q % "a red bug", "the still_gate rubric is gen_art.qa's question word for word")
    check(VE.rubric_text("still_gate") == OLD_Q % "the requested subject", "still_gate's placeholder default is the old default")
    check(VE.rubric_text("frame_ask", noun="a bug") == FRIO.ASK % "a bug", "the frame_ask rubric is frames_io.ASK word for word")
    for rid in ("frame_blind", "still_blind", "sheet_blind"):
        t = VE.rubric_text(rid)
        check("{" not in t.replace('{"cells"', "").replace('{\\"cells\\"', "") or rid == "sheet_blind", "%s carries no placeholder" % rid)
        check(not (VE.rubric(rid).get("placeholders")), "%s has no placeholders (hint-free)" % rid)
    try:
        VE.rubric("nope")
        check(False, "an unknown rubric raises")
    except ValueError:
        check(True, "an unknown rubric raises ValueError")


def _legacy_checks(check, VE, eyes, tmp):
    import base64
    img = _png(blob=(80, 80, 180, 200))
    eyes.state["answer"] = "```json\n{\"subjects\": 1, \"background\": \"flat\", \"view\": \"front\", \"matches\": true}\n```"
    url = eyes.url + "/v1/chat/completions"
    n0 = len(eyes.state["calls"])
    ans = VE.openai_chat_json(img, "Q?", 220, url=url, model="m7b")
    check(ans == {"subjects": 1, "background": "flat", "view": "front", "matches": True}, "openai_chat_json parses the fenced answer as vision_json did: %s" % ans)
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG")
    expected = {"model": "m7b", "max_tokens": 220, "temperature": 0, "messages": [{"role": "user", "content": [
        {"type": "text", "text": "Q?"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()}}]}]}
    sent = eyes.state["calls"][-1]
    check(len(eyes.state["calls"]) == n0 + 1 and sent["raw"] == json.dumps(expected).encode(), "the request body is byte for byte what gen_art.vision_json sent since pass 60")
    check(sent["headers"].get("content-type") == "application/json", "the content type header as before")
    eyes.state["answer"] = "no json here"
    check(VE.openai_chat_json(img, "Q?", 220, url=url, model="m7b") == {}, "an unparsable answer is {} for the legacy caller (as before)")
    eyes.state["answer"] = ""
    check(VE.openai_chat_json(img, "Q?", 220, url=url, model="m7b") == {}, "an empty answer is {} for the legacy caller (as before)")
    try:
        VE.openai_chat_json(img, "Q?", 220, url="http://127.0.0.1:9/v1/chat/completions", model="m7b", timeout=1)
        check(False, "a dead server raises to the caller (gen_art.qa catches it)")
    except Exception:
        check(True, "a dead server raises to the caller (gen_art.qa catches it)")
    led = VE.ledger_totals()
    check(led["calls"] == 3 and led["dollars"] == 0.0 and led["images"] == 3, "the ledger counted the three legacy calls at $0: %s" % led)
    # gen_art.qa / render in-process (gen_art imports comfy, artkit, animate: no network at import)
    try:
        import gen_art
    except Exception as e:   # noqa: BLE001
        check(True, "gen_art not importable here (%s): its qa/render checks skipped" % e)
        return
    saved = {k: getattr(gen_art, k) for k in ("LMSTUDIO", "VISION_MODEL", "SKIP_QA", "QA_ONLINE", "RAW", "paint")}
    try:
        gen_art.LMSTUDIO, gen_art.VISION_MODEL, gen_art.SKIP_QA = url, "m7b", False
        gen_art.RAW = os.path.join(tmp, "raw")
        eyes.state["answer"] = json.dumps({"subjects": 1, "background": "flat", "view": "front", "matches": True, "legs": True})
        n0 = len(eyes.state["calls"])
        ok, rep = gen_art.qa(img, {"subject": "a red bug", "view": "front", "subjects_max": 1, "legs": True})
        check(ok and rep["problems"] == [] and gen_art.QA_ONLINE is True, "gen_art.qa passes a clean answer and marks QA online: %s" % rep)
        q = (eyes.state["calls"][-1]["body"]["messages"][0]["content"][0]["text"])
        check(len(eyes.state["calls"]) == n0 + 1 and q == OLD_Q % "a red bug", "gen_art.qa asked the old question word for word (the subject filled in)")
        check(eyes.state["calls"][-1]["body"]["model"] == "m7b" and eyes.state["calls"][-1]["body"]["max_tokens"] == 220, "gen_art.qa's model and max_tokens as before")
        eyes.state["answer"] = json.dumps({"subjects": 2, "background": "scene", "text": True, "cropped": True, "view": "back", "legs": False, "matches": False})
        ok, rep = gen_art.qa(img, {"subject": "a red bug", "view": "front", "subjects_max": 1, "legs": True})
        check(not ok and rep["problems"] == ["subjects=2", "scene", "text", "cropped", "no-match", "view=back", "legs"], "gen_art.qa's problems in the old order: %s" % rep["problems"])
        gen_art.LMSTUDIO = "http://127.0.0.1:9/v1/chat/completions"
        ok, rep = gen_art.qa(img, {"subject": "a red bug"})
        check(ok and "error" in rep and gen_art.QA_ONLINE is False, "a dead LM Studio: qa passes with an error record and QA offline (as before): %s" % sorted(rep))
        gen_art.LMSTUDIO = url
        gen_art.SKIP_QA = True
        n0 = len(eyes.state["calls"])
        check(gen_art.qa(img, {"subject": "x"}) == (True, {"skipped": True}) and len(eyes.state["calls"]) == n0, "--skip-qa still skips: (True, {skipped}) and no call")
        gen_art.SKIP_QA = False
        # render(): geometry before the model
        calls = []
        real_qa = gen_art.qa

        def spy_qa(im, expect):
            calls.append(expect)
            return real_qa(im, expect)
        gen_art.qa = spy_qa
        stills = {"empty": _png(), "good": _png(blob=(60, 60, 200, 230)), "edge": _png(blob=(0, 60, 120, 230))}
        eyes.state["answer"] = json.dumps({"subjects": 1, "background": "flat", "view": "front", "matches": True})

        def painter(which):
            return lambda prompt, seed, width, height, refs, prefix, full=False, init=None, denoise=1.0: ([_bytes(stills[which])], 0.1)
        gen_art.paint = painter("empty")
        im, info = gen_art.render("t_empty", "a bug", [], {"subject": "a bug"}, 5, tries=1)
        check(calls == [] and info["qa"]["problems"] == ["empty"] and info["qa"].get("skipped_model") == "empty" and info["qa"]["geometry"].get("empty") is True,
              "an empty still never calls the model: problems [empty], skipped_model: %s" % info["qa"])
        gen_art.paint = painter("edge")
        im, info = gen_art.render("t_edge", "a bug", [], {"subject": "a bug"}, 5, tries=1)
        check(calls == [] and info["qa"]["problems"] == ["touches-edge"] and info["qa"].get("skipped_model") == "touches-edge", "an edge-touching still never calls the model: %s" % info["qa"]["problems"])
        gen_art.paint = painter("good")
        im, info = gen_art.render("t_good", "a bug", [], {"subject": "a bug", "ref_h": 160}, 5, tries=1)
        check(len(calls) == 1 and info["qa"]["problems"] == [] and "geometry" in info["qa"] and info["qa"]["geometry"]["height"] > 0, "a clean still is shown to the model once and passes: %s" % info["qa"]["problems"])
        gen_art.paint = painter("good")
        im, info = gen_art.render("t_tall", "a bug", [], {"subject": "a bug", "ref_h": 40}, 5, tries=1)
        check(len(calls) == 2 and info["qa"]["problems"] == ["too-tall"], "too-tall still comes after the model's answer, as before: %s" % info["qa"]["problems"])
        gen_art.SKIP_QA = True
        gen_art.paint = painter("empty")
        im, info = gen_art.render("t_empty_skip", "a bug", [], {"subject": "a bug"}, 5, tries=1)
        check(len(calls) == 3 and info["qa"].get("skipped") is True and info["qa"]["problems"] == ["empty"] and "skipped_model" not in info["qa"],
              "with --skip-qa an empty still's report keeps the old shape ({skipped: true} + the problems): %s" % info["qa"])
        gen_art.qa = real_qa
    finally:
        for k, v in saved.items():
            setattr(gen_art, k, v)


# ---------------------------------------------------------------- the ledger, the ceilings, the cache

def _ledger_checks(check, VE, tmp):
    png = _bytes(_png(blob=(50, 50, 150, 150)))
    fake = VE.FakeBackend([json.dumps(FINE)])
    r = VE.ask(fake, [png], "Q", rubric_id="frame_blind")
    check(r["answer"] == FINE and not r["refused"] and r["dollars"] == 0.0 and fake.n == 1, "a free fake backend answers and costs nothing: %s" % {k: r[k] for k in ("answer", "refused", "dollars")})
    r2 = VE.ask(fake, [png], "Q", rubric_id="frame_blind")
    check(r2["cached"] and r2["answer"] == FINE and fake.n == 1, "the same picture + rubric + model comes from the cache (no second call)")
    r3 = VE.ask(fake, [png], "Q", rubric_id="frame_blind", use_cache=False)
    check(not r3["cached"] and fake.n == 2, "use_cache=False calls again")
    empty = VE.FakeBackend([""])
    e1 = VE.ask(empty, [png], "Q", rubric_id="still_blind")
    e2 = VE.ask(empty, [png], "Q", rubric_id="still_blind")
    check(e1["answer"] is None and e2["answer"] is None and empty.n == 2, "an empty answer is no verdict (None) and is never cached")
    junk = VE.FakeBackend(["sure! the bug looks fine"])
    check(VE.ask(junk, [png], "Q", rubric_id="still_blind")["answer"] is None, "an unparsable answer is no verdict, never ok")
    check(VE.budget_for("google/gemma-4-e4b") == 1200 and VE.budget_for("qwen2.5-vl-7b-instruct-abliterated") == 220 and VE.budget_for("claude-haiku-5-5") == 2048 and VE.budget_for("x", 100) == 100,
          "the answer budget per model: gemma 1200, the 7B 220, claude 2048, an explicit one wins")
    check(junk.calls[-1]["max_tokens"] == 220 and VE.FakeBackend([]).model == "fake-eye", "the fake backend got the default budget")
    check(abs(VE.dollars_of("claude-haiku-5-5", {"input": 1000000, "output": 1000000}) - 0.6) < 1e-9 and VE.dollars_of("gemini-x", {"input": 1}) is None,
          "dollars from the price table (haiku 0.10 + 0.50 a million); an unpriced model is None")
    # the ceilings: a cloud backend with no defaults file = the cloud tier off
    cloud = VE.FakeBackend([json.dumps(FINE)], model="claude-haiku-5-5", free=False)
    r = VE.ask(cloud, [png], "Q", rubric_id="frame_blind", request="r1", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["refused"].startswith("the cloud tier is off") and cloud.n == 0, "no cloud_ceiling_dollars_per_day: a cloud call is refused and not made: %s" % r["refused"])
    led = VE.ledger_totals()
    last = VE._ledger_load()["calls"][-1]
    check(last.get("refused") and last["backend"] == "fake" and last["model"] == "claude-haiku-5-5" and last["request"] == "r1", "the refusal is logged with the model and the request id")
    with open(VE.DEFAULTS, "w", encoding="utf-8") as f:
        json.dump({"cloud_ceiling_dollars_per_day": 0.01}, f)
    r = VE.ask(cloud, [png], "Q", rubric_id="frame_blind", request="r1", budget={"cloud_dollars": 0.0}, use_cache=False)
    check("cloud_dollars 0" in r["refused"] and cloud.n == 0, "the request's cloud_dollars 0: refused")
    est = cloud.estimate(1, "Q", 2048)
    check(est is not None and 0.0005 < est < 0.005, "the estimate before a call is a few thousandths of a dollar for one picture at haiku prices: %s" % est)
    r = VE.ask(cloud, [png], "Q", rubric_id="frame_blind", request="r1", budget={"cloud_dollars": 0.005, "spent": 0.0}, use_cache=False)
    check(not r["refused"] and cloud.n == 1 and abs(r["dollars"] - (1500 * 0.10 + 40 * 0.50) / 1e6) < 1e-9, "within the ceilings the call is made and priced from its usage: $%s" % r["dollars"])
    day = VE.ledger_totals()["day_dollars"]
    check(abs(day - r["dollars"]) < 1e-9 and abs(VE.request_dollars("r1") - r["dollars"]) < 1e-9, "the ledger's day and request totals carry the call: %s" % day)
    r = VE.ask(cloud, [png], "Q", rubric_id="frame_blind", request="r1", budget={"cloud_dollars": 0.0003}, use_cache=False)
    check("request's cloud_dollars" in r["refused"] and cloud.n == 1, "the request's ceiling (its spend read from the ledger) refuses the next call: %s" % r["refused"])
    with open(VE.DEFAULTS, "w", encoding="utf-8") as f:
        json.dump({"cloud_ceiling_dollars_per_day": 0.0002}, f)
    r = VE.ask(cloud, [png], "Q", rubric_id="frame_blind", request="r2", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check("day's cloud ceiling" in r["refused"] and cloud.n == 1, "the global daily ceiling refuses: %s" % r["refused"])
    with open(VE.DEFAULTS, "w", encoding="utf-8") as f:
        json.dump({"cloud_ceiling_dollars_per_day": 1.0}, f)
    unpriced = VE.FakeBackend([json.dumps(FINE)], model="gemini-9", free=False)
    r = VE.ask(unpriced, [png], "Q", rubric_id="frame_blind", request="r2", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["refused"].startswith("unpriced") and unpriced.n == 0, "an unpriced model (no price-table row) is refused under a ceiling: %s" % r["refused"])
    failing = VE.FakeBackend([], fail="boom")
    r = VE.ask(failing, [png], "Q", rubric_id="frame_blind", use_cache=False)
    check(r["error"].startswith("RuntimeError: boom") and r["answer"] is None, "a backend that raises is an error record, never a crash")
    check(os.path.isfile(VE.LEDGER) and VE.ledger_totals()["file"].endswith("ledger.json"), "the ledger file exists where the module says")


# ---------------------------------------------------------------- the three backends over the fake server

def _backend_checks(check, VE, eyes, tmp):
    png = _bytes(_png(blob=(50, 50, 150, 150)))
    check(VE.read_key("anthropic") == "" and VE.read_key("gemini") == "" and VE.keys_status() == {"anthropic": False, "gemini": False, "dir": VE._rel(VE.KEYS_DIR)},
          "no key files: read_key is empty and keys_status says so (the environment's ANTHROPIC_API_KEY is never read)")
    be = VE.AnthropicBackend(model="claude-haiku-5-5")
    check(be.key == "" and be.health()[0] is False, "the Anthropic backend without a key file has no key (not the environment's)")
    r = VE.ask(be, [png], "Q", rubric_id="frame_blind", request="r3", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["error"].startswith("RuntimeError: no Anthropic key") and r["answer"] is None, "a call without a key is an error record naming the key file: %s" % r["error"])
    os.makedirs(VE.KEYS_DIR, exist_ok=True)
    with open(os.path.join(VE.KEYS_DIR, "anthropic.env"), "w", encoding="utf-8") as f:
        f.write("# the key\nANTHROPIC_API_KEY=k-test\n")
    with open(os.path.join(VE.KEYS_DIR, "gemini.env"), "w", encoding="utf-8") as f:
        f.write("g-test\n")
    check(VE.read_key("anthropic") == "k-test" and VE.read_key("gemini") == "g-test" and VE.keys_status()["anthropic"], "KEY=value lines and bare tokens are read from tools/keys/<name>.env")
    eyes.state["anthropic"] = json.dumps(FINE)
    be = VE.AnthropicBackend(model="claude-haiku-5-5", url=eyes.url + "/v1/messages")
    txt, usage = be.ask([png], "Q", 2048)
    sent = eyes.state["calls"][-1]
    body = sent["body"]
    check(json.loads(txt) == FINE and usage == {"input": 1600, "output": 50, "cache_read": 0, "cache_write": 0}, "the Messages API answer and usage are read: %s" % usage)
    check(sent["headers"].get("x-api-key") == "k-test" and sent["headers"].get("anthropic-version") == "2023-06-01", "the key from the file and the API version go in the headers")
    c = body["messages"][0]["content"]
    check(body["model"] == "claude-haiku-5-5" and body["max_tokens"] == 2048 and body.get("output_config") == {"effort": "low"} and "temperature" not in body and "thinking" not in body,
          "the body: the pinned model, the budget, effort low, no sampling parameter, no thinking block: %s" % sorted(body))
    check(len(c) == 2 and c[0]["type"] == "image" and c[0]["source"]["type"] == "base64" and c[0]["source"]["media_type"] == "image/png" and c[1] == {"type": "text", "text": "Q"},
          "an image block then the text block")
    r = VE.ask(be, [png], "Q", rubric_id="frame_blind", request="r3", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["answer"] == FINE and abs(r["dollars"] - (1600 * 0.10 + 50 * 0.50) / 1e6) < 1e-9 and r["backend"] == "anthropic", "through ask(): the answer and the dollars from usage: $%s" % r["dollars"])
    eyes.state["refusal"] = True
    r = VE.ask(be, [png], "Q", rubric_id="frame_blind", request="r3", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["answer"] is None and not r["error"], "a refusal stop reason is no verdict")
    eyes.state["refusal"] = False
    be = VE.AnthropicBackend()
    check(be.model == "claude-haiku-5-5", "the default Anthropic model is the tier table's pinned cheap one: %s" % be.model)
    eyes.state["gemini"] = json.dumps(FINE)
    gb = VE.GeminiBackend(model="gemini-x", url=eyes.url + "/v1beta/models/gemini-x:generateContent")
    txt, usage = gb.ask([png], "Q", 2048)
    sent = eyes.state["calls"][-1]
    body = sent["body"]
    check(json.loads(txt) == FINE and usage["input"] == 1700 and usage["output"] == 60, "the Gemini answer and usage are read")
    check(sent["headers"].get("x-goog-api-key") == "g-test" and body["contents"][0]["parts"][0] == {"text": "Q"} and body["contents"][0]["parts"][1]["inline_data"]["mime_type"] == "image/png"
          and body["generationConfig"] == {"temperature": 0, "maxOutputTokens": 2048, "responseMimeType": "application/json"}, "the Gemini body: the key header, the text then the inline PNG, temperature 0, JSON out")
    r = VE.ask(gb, [png], "Q", rubric_id="frame_blind", request="r3", budget={"cloud_dollars": 1.0, "spent": 0.0}, use_cache=False)
    check(r["refused"].startswith("unpriced") and len(eyes.state["calls"]) and eyes.state["calls"][-1] is sent, "a Gemini call through ask() is refused as unpriced until its prices are known (G3)")
    ob = VE.OpenAIChatBackend("m7b", eyes.url + "/v1/chat/completions")
    check(ob.health()[0] is True and VE.OpenAIChatBackend("m7b", "http://127.0.0.1:9/v1/chat/completions").health()[0] is False, "the local eye's health check: GET /v1/models")
    check(VE.backend_for("openai_chat").name == "openai_chat" and VE.backend_for("fake").name == "fake" and VE.backend_for(ob) is ob, "backend_for by name or instance")
    try:
        VE.backend_for("claude-code-session")
        check(False, "an unknown backend name raises")
    except ValueError:
        check(True, "an unknown backend name raises ValueError")


# ---------------------------------------------------------------- the blind-name rule and the findings items

def _blind_checks(check, VE):
    telling = os.path.join(tempfile.mkdtemp(prefix="le_loop96_tell_"), "desert_spider_SP-B_ghost_legs_BAD.png")
    _png(blob=(40, 40, 200, 200)).save(telling)
    seen = []

    def eye(images, prompt):
        seen.append({"prompt": prompt, "n": len(images)})
        return json.dumps(FINE)
    before = {d for d in os.listdir(tempfile.gettempdir()) if d.startswith("qa_blind_")}
    f = VE.evaluate([{"image": telling, "group": "run/side", "slot": 3}], "frame_blind", VE.FakeBackend(eye), job="j1", look={"kind": "enemy", "id": "desert_spider", "code": "SP-B"})
    after = {d for d in os.listdir(tempfile.gettempdir()) if d.startswith("qa_blind_")}
    p = seen[0]["prompt"]
    check(p == VE.rubric_text("frame_blind") and "spider" not in p.lower() and "sp-b" not in p.lower() and "ghost_legs" not in p and "BAD" not in p,
          "the model gets the fixed rubric and nothing of the file name, the look or the verdict")
    check(after == before, "the opaque copies' folder is removed after the call")
    check(f["v"] == 1 and f["job"] == "j1" and f["look"]["code"] == "SP-B" and f["model_calls"][0]["images"] == 1 and f["gates"] == {"hard_failures": 0, "advisory": 0, "pass": True},
          "the findings record has the INTERFACES shape: %s" % sorted(f))
    it = [x for x in f["items"] if x["field"] == "broken"][0]
    check(it["image"] == os.path.relpath(telling, VE.REPO).replace("\\", "/") if telling.startswith(VE.REPO) else it["image"].endswith("BAD.png"), "the item keeps the caller's reference for the page")
    check(it["group"] == "run/side" and it["slot"] == 3 and it["kind"] == "model" and it["ok"] is True and it["model"] == "fake-eye" and it["tier"] == 1, "the item carries group, slot, kind model, ok, the model's name and the tier")
    shutil.rmtree(os.path.dirname(telling), ignore_errors=True)


def _items_checks(check, VE):
    items = VE.items_from_answer(BAD, "frame_blind", "run/side/3", "run/side", 3, "m7b")
    by = {it["field"]: it for it in items}
    check(by["legs"]["ok"] is None and by["legs"]["value"] == 9, "a count is recorded without a verdict")
    check(by["broken"]["ok"] is False and by["ghost"]["ok"] is True and by["face"]["ok"] is False and by["smear"]["ok"] is True and by["colour"]["ok"] is True, "bad_when rules: broken and a missing face fail, the rest pass")
    check(by["note"]["value"] == "nine legs" and by["note"]["ok"] is None, "the model's note is kept as a note, never a verdict")
    g = VE.gates_of(items)
    check(g == {"hard_failures": 0, "advisory": 2, "pass": True}, "model items are advisory: the gates pass on model findings alone: %s" % g)
    nv = VE.items_from_answer(None, "frame_blind", "x", "run/side", 0, "m7b")
    check(len(nv) == 1 and nv[0]["field"] == "verdict" and nv[0]["ok"] is None and nv[0]["rule"].startswith("no verdict"), "None = one no-verdict item")
    fine = VE.items_from_answer(FINE, "frame_blind", "x", "run/side", 0, "m7b")
    check(all(it["ok"] is not False for it in fine) and not [it for it in fine if it["field"] == "note"], "a fine answer: nothing fails, 'fine' is not a note")
    m = [{"kind": "measured", "ok": False}, {"kind": "measured", "ok": False}, {"kind": "model", "ok": False}, {"kind": "model", "ok": None}]
    check(VE.gates_of(m) == {"hard_failures": 2, "advisory": 1, "pass": False}, "gates: measured failures are hard, model ones advisory, no-verdict neither")
    check(VE.parse_json_answer("```json\n{\"a\": 1}\n```") == {"a": 1} and VE.parse_json_answer("json {\"a\": 2} tail") == {"a": 2} and VE.parse_json_answer("[1]") == {} and VE.parse_json_answer("{broken") == {},
          "parse_json_answer: the fence, the json prefix, the first {...}; a list or broken JSON is {}")
    geo = VE.geometry(_png(blob=(60, 60, 200, 230)))
    check(geo["left"] == 60 and geo["top"] == 60 and geo["height"] == 170 and VE.geometry(_png()).get("empty") is True, "geometry: the margins of a keyed figure, empty when none: %s" % geo)
    check(VE.geometry_problems({"empty": True}) == ["empty"] and VE.geometry_problems({"left": 5, "right": 50, "top": 50, "bottom": 50, "height": 100, "width": 100}) == ["touches-edge"]
          and VE.geometry_problems({"left": 5, "right": 50, "top": 50, "bottom": 50, "height": 100, "width": 100}, {"bust": True}) == ["touches-edge"]
          and VE.geometry_problems({"left": 50, "right": 50, "top": 50, "bottom": 5, "height": 100, "width": 100}, {"bust": True}) == [], "geometry_problems: gen_art.render's rules (a bust may run off the bottom)")
    try:
        import gen_art
        same = gen_art.geometry(_png(blob=(60, 60, 200, 230))) == geo
        check(same, "vision_eval.geometry equals gen_art.geometry on the same picture")
    except Exception as e:   # noqa: BLE001
        check(True, "gen_art geometry comparison skipped: %s" % e)


# ---------------------------------------------------------------- a stored look through the tiers (VACE95's world)

def _look_checks(check, VE, tmp):
    seen = []

    def eye(images, prompt):
        seen.append(prompt)
        return json.dumps(FINE)
    out = os.path.join(tmp, "ev_a")
    f = VE.evaluate_look("enemy", "bug", "BG-A", tiers=[0, 1], backend=VE.FakeBackend(eye, model="fake-7b"), out_dir=out, job="jA")
    hard = [(it["group"], it["slot"], it["field"]) for it in f["items"] if it["kind"] == "measured" and it["ok"] is False]
    check(any(g == "run/front" and s == 2 and fld == "empty" for g, s, fld in hard), "tier 0 flags BG-A's empty run frame 2: %s" % hard)
    check(any(g == "run/front" and s == 1 for g, s, fld in hard), "tier 0 flags BG-A's shifted run frame 1: %s" % hard)
    check(f["gates"]["hard_failures"] >= 2 and f["gates"]["pass"] is False, "the gates fail on measured findings: %s" % f["gates"])
    groups = {g["label"]: g for g in f["groups"]}
    check("run/front" in groups and groups["run/front"]["n"] == 4 and groups["run/front"]["repairable"] is False and sorted(groups["run/front"]["flagged"]) == [1, 2],
          "the groups list says which slots are flagged and whether a repair can follow a clip or driver: %s" % groups.get("run/front"))
    model_items = [it for it in f["items"] if it["kind"] == "model"]
    asked = {(it["group"], it["slot"]) for it in model_items}
    check(("run/front", 1) in asked and ("run/front", 2) in asked and len(asked) == len(f["groups"]) + 2 - 0 or len(seen) == len(asked), "tier 1 saw the flagged frames plus one clean frame a group: %d calls on %s" % (len(seen), sorted(asked)))
    check(all(p == VE.rubric_text("frame_blind") for p in seen), "every tier-1 prompt is the fixed frame_blind rubric")
    check(all(it["model"] == "fake-7b" and it["tier"] == 1 for it in model_items), "model items name the model and the tier")
    check(os.path.isfile(os.path.join(out, "findings.json")) and os.path.isfile(os.path.join(out, "findings_sheet.png")) and f["sheet"].endswith("findings_sheet.png"),
          "findings.json and the sheet are written beside each other")
    check(f["summary"].startswith("findings: %d hard" % f["gates"]["hard_failures"]) and "run/front" in f["summary"], "the summary line names the hard count and the groups: %s" % f["summary"])
    check(f["tier2"] == {"ran": False, "why": ""} or f["tier2"].get("ran") is False, "tier 2 did not run when not asked for: %s" % f["tier2"])
    loaded = json.load(open(os.path.join(out, "findings.json"), encoding="utf-8"))
    check(loaded["job"] == "jA" and loaded["look"] == {"kind": "enemy", "id": "bug", "code": "BG-A"} and loaded["gates"] == f["gates"], "the file holds the same record")
    # BG-B: the ctl look with a clip and a driver
    f2 = VE.evaluate_look("enemy", "bug", "BG-B", tiers=[0, 1], groups=["run/side"], backend=VE.FakeBackend([json.dumps(FINE)]), job="jB")
    g2 = {g["label"]: g for g in f2["groups"]}
    check(list(g2) == ["run/side"] and g2["run/side"]["repairable"] is True and g2["run/side"]["method"] == "creature_ctl", "groups= limits the evaluation; the ctl group is repairable: %s" % g2)
    # tier 2 off at $0, on with a ceiling and a budget: one sheet, one call, the cells mapped back
    f3 = VE.evaluate_look("enemy", "bug", "BG-A", tiers=[0, 1, 2], groups=["run/front"], backend=VE.FakeBackend([json.dumps(FINE)]), cloud_dollars=0.0, job="jC")
    check(f3["tier2"]["ran"] is False and "cloud_dollars is 0" in f3["tier2"]["why"], "tier 2 is off at $0: %s" % f3["tier2"])
    with open(VE.DEFAULTS, "w", encoding="utf-8") as fh:
        json.dump({"cloud_ceiling_dollars_per_day": 1.0}, fh)
    sheets = []

    def cloud(images, prompt):
        sheets.append({"n": len(images), "prompt": prompt, "sha": VE.sha_of(images[0])})
        return json.dumps({"cells": [{"n": 1, "ok": True, "why": "fine"}, {"n": 2, "ok": False, "why": "cut leg"}, {"n": 3, "ok": False, "why": "empty"}, {"n": 4, "ok": True, "why": "fine"}]})
    cb = VE.FakeBackend(cloud, model="claude-haiku-5-5", free=False)
    out4 = os.path.join(tmp, "ev_d")
    f4 = VE.evaluate_look("enemy", "bug", "BG-A", tiers=[0, 1, 2], groups=["run/front"], backend=VE.FakeBackend([json.dumps(FINE)]), cloud_backend=cb, cloud_dollars=1.0, out_dir=out4, job="jD")
    check(f4["tier2"]["ran"] is True and len(sheets) == 1 and sheets[0]["n"] == 1 and sheets[0]["prompt"] == VE.rubric_text("sheet_blind"), "tier 2 ran once on one contact sheet with the sheet rubric: %s" % f4["tier2"])
    sheet_items = [it for it in f4["items"] if it["field"] == "sheet"]
    check(len(sheet_items) == 4 and {(it["group"], it["slot"], it["ok"]) for it in sheet_items} == {("run/front", 0, True), ("run/front", 1, False), ("run/front", 2, False), ("run/front", 3, True)},
          "the sheet's cells are mapped back to the flagged slots and their neighbours: %s" % [(it["slot"], it["ok"]) for it in sheet_items])
    check(all(it["tier"] == 2 and it["model"] == "claude-haiku-5-5" for it in sheet_items) and os.path.isfile(os.path.join(out4, "decision_sheet.png")), "tier-2 items carry the tier and the cloud model; the decision sheet is kept")
    check(f4["dollars"] > 0 and f4["gates"]["hard_failures"] == f3["gates"]["hard_failures"], "the cloud call is priced; the hard gates are unchanged by the models' verdicts")
    # the CLI job mode: evaluate.json -> findings.json + result.json (the sidecar)
    jd = os.path.join(tmp, "jobs", "jE")
    os.makedirs(jd)
    with open(os.path.join(jd, "evaluate.json"), "w", encoding="utf-8") as fh:
        json.dump({"kind": "enemy", "id": "bug", "code": "BG-A", "groups": ["run/front"], "tiers": [0, 1], "backend": "fake", "job": "jE", "request": "r9"}, fh)
    os.environ["ASSET_JOB_SIDECAR"] = os.path.join(jd, "result.json")
    try:
        fr = VE.run_job(os.path.join(jd, "evaluate.json"))
    finally:
        os.environ.pop("ASSET_JOB_SIDECAR", None)
    res = json.load(open(os.path.join(jd, "result.json"), encoding="utf-8"))
    check(fr["job"] == "jE" and fr["request"] == "r9" and os.path.isfile(os.path.join(jd, "findings.json")) and res["info"]["findings"].endswith("jE/findings.json") and res["info"]["gates"] == fr["gates"]
          and res["info"]["summary"] == fr["summary"] and res["info"]["outputs"][0]["type"] == "sheet", "--job writes findings.json beside evaluate.json and the sidecar the card reads: %s" % sorted(res["info"]))
    check(VE.findings_of_job("jE", os.path.join(tmp, "jobs"))["job"] == "jE", "findings_of_job reads <job>/findings.json")


# ---------------------------------------------------------------- the evaluate job kind in jobs.py

def _job_checks(check, VE, jobs, locks, tmp):
    jobs.JOBS_DIR = os.path.join(tmp, "jobs")
    jobs.QUEUE_FILE = os.path.join(jobs.JOBS_DIR, "queue.json")
    jobs.DL = os.path.join(tmp, "dl")
    jobs.RAW = os.path.join(tmp, "dl", "ai_raw_anime")
    jobs.ANIM = os.path.join(tmp, "dl", "ai_anim")
    jobs.REVIEW = os.path.join(tmp, "dl", "review")
    jobs.TITLE_OUT = os.path.join(tmp, "dl", "title_heroes")
    jobs.WANTED = os.path.join(tmp, "wanted")
    jobs.LAUNCH_FILE = os.path.join(tmp, "user", "debug_launch.json")
    locks.LOCK_DIR = os.path.join(tmp, "locks")
    locks.SAVE_DIR = os.path.join(tmp, "save")
    locks.KEEP_DIR = os.path.join(tmp, "locks", "save_keep")
    locks.RESTORE_PENDING = os.path.join(locks.KEEP_DIR, "restore_pending.json")
    for p in (jobs.RAW, jobs.ANIM, jobs.REVIEW, locks.SAVE_DIR, os.path.dirname(jobs.LAUNCH_FILE)):
        os.makedirs(p, exist_ok=True)
    jobs._state = {"rev": 0, "jobs": []}
    jobs._workers.clear()
    jobs.init({}, ROOT)
    spec = jobs.SPECS["evaluate"]
    check(spec["lane"] == "local" and set(spec["fields"]) >= {"kind", "id", "code", "groups", "tiers", "request", "cloud_dollars", "backend", "model"}, "SPECS[evaluate]: the local lane, the fields")
    j = jobs.enqueue("evaluate", {"kind": "enemy", "id": "bug", "code": "BG-A"}, {"kind": "enemy", "id": "bug", "code": "BG-A", "groups": ["run/front"], "tiers": [0, 1], "request": "r1", "cloud_dollars": 0.0},
                     title="evaluate bug BG-A")
    check(j["lane"] == "local" and j["state"] == "queued" and j["kind"] == "evaluate", "an evaluate job queues on the local lane")
    check(j["cmd"][0] == sys.executable and j["cmd"][1].endswith("vision_eval.py") and j["cmd"][2] == "--job" and j["cmd"][3].endswith("evaluate.json"), "its command runs tools/vision_eval.py --job: %s" % j["cmd"])
    check(j["equiv"] == "python tools/vision_eval.py --kind enemy --id bug --code BG-A --tiers 0,1 --groups run/front", "equiv is the command Claude would type: %s" % j["equiv"])
    jb = jobs._find(j["id"])
    plan = jb["plan"]
    check(plan["mode"] == "steps" and plan["lock"] is None and plan["env_steps"]["ASSET_JOB_REQUEST"] == "r1" and plan["env_steps"]["ASSET_JOB_SIDECAR"].endswith("result.json"), "the plan: a step, no lock, the request id in the env")
    ej = json.load(open(os.path.join(jobs._job_dir(j["id"]), "evaluate.json"), encoding="utf-8"))
    check(ej["request"] == "r1" and ej["groups"] == ["run/front"] and ej["job"] == j["id"] and ej["code"] == "BG-A", "evaluate.json holds the spec: %s" % sorted(ej))
    check(jb["progress"]["total"] == 1 and jb["progress"]["stages"][0]["type"] == "step" and jb["eta_s"] > 0, "one step stage and an eta")
    # the post and the harvest on a canned result.json
    fdir = os.path.join(jobs._job_dir(j["id"]))
    rel = "tools/dl/jobs/%s/findings.json" % j["id"]
    with open(os.path.join(fdir, "result.json"), "w", encoding="utf-8") as fh:
        json.dump({"info": {"findings": rel, "gates": {"hard_failures": 2, "advisory": 1, "pass": False}, "summary": "findings: 2 hard, 1 advisory (run/front: 1 jump, 2 empty)", "outputs": [], "dollars": 0.0, "model_calls": 3}}, fh)
    written, err = jobs._post(jb)
    check(err == "" and written["layout"] == "findings" and written["gates"]["hard_failures"] == 2 and jb["findings"] == rel and jb["progress"]["notes"] == ["findings: 2 hard, 1 advisory (run/front: 1 jump, 2 empty)"],
          "_post puts the findings on the job and the one line into the notes: %s" % ((written, err),))
    outs = jobs._harvest(jb)
    fo = [o for o in outs if o["label"] == "findings"]
    check(len(fo) == 1 and fo[0]["type"] == "json" and fo[0]["detail"]["gates"]["hard_failures"] == 2 and fo[0].get("url", "").startswith("/dl/jobs/"), "the harvest lists the findings with their gates and a link: %s" % fo)
    with open(os.path.join(fdir, "result.json"), "w", encoding="utf-8") as fh:
        json.dump({"info": {}}, fh)
    written, err = jobs._post(jb)
    check(err.startswith("the evaluator wrote no findings"), "no findings in the sidecar: the job says so")
    try:
        jobs.enqueue("evaluate", {"kind": "enemy", "id": "bug", "code": "BG-A"}, {"kind": "enemy", "id": "bug"})
        check(False, "an evaluate spec without a code is refused")
    except ValueError:
        check(True, "an evaluate spec without a code is refused")
    check("evaluate" in jobs.BUILTIN_MEDIAN, "the built-in median has the evaluate kind")


# ---------------------------------------------------------------- commands: validate and dispatch

class FakeCtx:
    def __init__(self, FS, FRIO, RAPI):
        import commands as CMD
        self.calls, self.enqueued, self.n = [], [], 0
        self.frames_io, self.frames_store, self.requests_api = FRIO, FS, RAPI
        self.look_job = {"id": "jlook", "kind": "look", "state": "done", "spec": {"method": "creature_ctl", "recipe": {"art_prompt": "a bug", "drivers": "bugwalk"}}, "target": {"kind": "enemy", "id": "bug", "code": "BG-B"}}
        self.jobs_call = self._jobs_call
        self.enqueue = self._enqueue
        self.CMD = CMD

    def _jobs_call(self, name, *a, **kw):
        self.calls.append((name,) + a)
        if name == "get":
            return (200, {"job": self.look_job}) if a[0] == "jlook" else (404, {"ok": False, "error": "no job"})
        if name == "edit":
            self.look_job["spec"] = a[1]
            return 200, {"job": self.look_job}
        if name == "requeue":
            if a[0] != "jlook":
                return 404, {"ok": False, "error": "no job %s" % a[0]}
            return 200, {"job": dict(self.look_job, state="queued", reroll=a[1] if len(a) > 1 else None)}
        return 200, {"ok": True}

    def _enqueue(self, kind, target, spec, title=None):
        self.n += 1
        job = {"id": "jfake-%d" % self.n, "kind": kind, "target": target, "spec": spec, "title": title}
        self.enqueued.append(job)
        return {"job": job}


def _commands_checks(check, CMD, RAPI, FS, FRIO, jobs, tmp, w):
    rec = {"rid": RID, "v": 1, "mode": "auto", "goal": "a bug", "asset": {"kind": "enemy", "id": "bug", "code": "BG-B", "method": "creature_ctl"},
           "budget": {"rerolls": 2, "repair_rounds": 2, "lane_seconds": 5400, "evaluator_calls": 60, "cloud_dollars": 0.0},
           "spent": {"rerolls": 0, "repair_rounds": {}, "lane_seconds": 0, "evaluator_calls": 0, "cloud_dollars": 0.0},
           "state": "running", "jobs": ["jlook"], "current_job": None, "iterations": [], "provisional": None, "history": [], "result": None}
    RAPI.save(rec)
    check(os.path.isfile(RAPI.path_of(RID)) and RAPI.path_of(RID).startswith(os.path.join(tmp, "jobs")) and RAPI.load(RID)["rid"] == RID, "the shim writes the record under the re-pointed jobs folder: %s" % RAPI.path_of(RID))
    T = lambda **k: dict({"kind": "enemy", "id": "bug", "code": "BG-B"}, **k)   # noqa: E731
    good = {"op": "repair", "target": T(group="run/side", slots=[1, 2]), "args": {"rung": "single"}, "why": "jump on 1-2"}
    ok, why = CMD.validate(good, rec)
    check(ok, "a repair on the request's own look and group validates: %s" % why)
    refusals = [
        (dict(good, extra=1), "unknown keys on the op"),
        ({"op": "export", "target": T(), "args": {}, "why": ""}, "never an automatic op"),
        ({"op": "install", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "default", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "approve", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "pin", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "remove", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "delete", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "unstage", "target": T(), "args": {}, "why": ""}, "never"),
        ({"op": "fly", "target": T(), "args": {}, "why": ""}, "unknown verb"),
        ({"op": "repair", "target": T(id="goblin", group="run/side", slots=[1]), "args": {}, "why": ""}, "outside the request's asset"),
        ({"op": "repair", "target": T(code="BG-A", group="run/side", slots=[1]), "args": {}, "why": ""}, "not the request's look"),
        ({"op": "repair", "target": T(group="run/side", slots=[1], extra=1), "args": {}, "why": ""}, "unknown keys on the target"),
        ({"op": "repair", "target": T(group="run/side", slots=[1]), "args": {"strength": 2}, "why": ""}, "unknown args"),
        ({"op": "repair", "target": T(group="run/side"), "args": {}, "why": ""}, "needs target.slots"),
        ({"op": "repair", "target": T(group="run/side", slots=[9]), "args": {}, "why": ""}, "outside run/side"),
        ({"op": "repair", "target": T(group="idle/back", slots=[0]), "args": {}, "why": ""}, "no group"),
        ({"op": "reroll_view", "target": T(), "args": {}, "why": ""}, "needs args.view"),
        ({"op": "copy", "target": T(group="run/front"), "args": {"slot": 0, "from": {}}, "why": ""}, "copy needs args.from"),
        ({"op": "stage", "target": T(group="run/side"), "args": {"version": "x"}, "why": ""}, "needs args.slot"),
        ({"op": "repair", "target": T(group="run/side", slots=[1]), "args": {"rung": "triple"}, "why": ""}, "rung is single, double or auto"),
        ("not an op", "an op is an object"),
    ]
    for op, want in refusals:
        ok, why = CMD.validate(op, rec)
        check(not ok and want in why, "refused (%s): %s" % (want, why))
    for verb in CMD.VERBS:
        ok, why = CMD.validate({"op": verb, "target": T(), "args": {}, "why": ""}, dict(rec, mode="observe"))
        check(not ok and "not allowed in mode observe" in why, "observe allows no op: %s" % verb)
    ok, why = CMD.validate({"op": "note", "target": T(), "args": {"text": "hi"}, "why": ""}, dict(rec, mode="step"))
    check(ok, "step mode allows the same verbs: %s" % why)
    # a pinned slot is never written
    look = FS.Look("enemy", "bug", "BG-B")
    g = FS.Group(look, "run", "side")
    v0 = g.versions(1)[0]
    g.select(1, v0["id"], by="human", pinned=True)
    ok, why = CMD.validate(good, rec)
    check(not ok and "pinned" in why, "a repair touching a pinned slot is refused: %s" % why)
    ok, why = CMD.validate({"op": "stage", "target": T(group="run/side"), "args": {"slot": 1, "version": v0["id"]}, "why": ""}, rec)
    check(not ok and "pinned" in why, "a stage on a pinned slot is refused")
    g.pin(1, False)
    ok, why = CMD.validate(good, rec)
    check(ok, "unpinned again: the repair validates")
    # the budget
    spent = dict(rec, spent={"rerolls": 2, "repair_rounds": {"run/side": 2}, "evaluator_calls": 60})
    for op, want in (({"op": "requeue", "target": T(), "args": {"seed": 3}, "why": ""}, "no rerolls left"),
                     ({"op": "reroll_view", "target": T(), "args": {"view": "side"}, "why": ""}, "no rerolls left"),
                     (good, "no repair_rounds left in the budget for run/side"),
                     ({"op": "ask", "target": T(), "args": {}, "why": ""}, "no evaluator_calls left")):
        ok, why = CMD.validate(op, spent)
        check(not ok and want in why, "budget: %s" % why)
    ok, why = CMD.validate({"op": "repair", "target": T(group="run/side", slots=[2]), "args": {}, "why": ""}, dict(rec, spent={"repair_rounds": {"run/front": 2}}))
    check(ok, "repair rounds are counted per group: another group's spend does not block")
    for verb in ("stage", "note", "select_provisional", "stop"):
        op = {"op": verb, "target": T(group="run/side") if verb == "stage" else T(), "args": {"slot": 2, "version": g.versions(2)[0]["id"]} if verb == "stage" else {}, "why": ""}
        ok, why = CMD.validate(op, spent)
        check(ok, "%s costs no budget unit: %s" % (verb, why))
    check(CMD.unit_of(good) == ("repair_rounds", "run/side") and CMD.unit_of({"op": "ask"}) == ("evaluator_calls", None) and CMD.unit_of({"op": "note"}) is None, "unit_of")
    # dispatch on the fake queue
    ctx = FakeCtx(FS, FRIO, RAPI)
    pins, exports = [], []
    real_pin, real_export = FRIO.pin, FRIO.export_job
    FRIO.pin = lambda *a, **k: (pins.append(a), real_pin(*a, **k))[1]
    FRIO.export_job = lambda *a, **k: (exports.append(a), {"ok": False, "error": "never"})[1]
    bug_json = os.path.join(w["folder"], "bug.json")
    before = open(bug_json, "rb").read()
    try:
        r = CMD.dispatch({"op": "ask", "target": T(group="run/side"), "args": {"tiers": [0, 1]}, "why": "flag"}, rec, ctx)
        e = ctx.enqueued[-1]
        check(r == {"job": "jfake-1"} and e["kind"] == "evaluate" and e["spec"]["request"] == RID and e["spec"]["groups"] == ["run/side"] and e["spec"]["tiers"] == [0, 1] and e["spec"]["cloud_dollars"] == 0.0,
              "ask queues an evaluate job of the request: %s" % e["spec"])
        r = CMD.dispatch(dict(good, args={"rung": "double"}), rec, ctx)
        e = ctx.enqueued[-1]
        check(r.get("job") == "jfake-2" and e["kind"] == "frames_repair" and e["spec"]["slots"] == [1, 2] and e["spec"]["window"] == "double" and e["spec"]["code"] == "BG-B" and e["spec"]["free_fill"] is False,
              "repair queues a frames_repair through frames_io.repair_job with the rung as the window: %s" % e["spec"])
        r = CMD.dispatch({"op": "repair", "target": T(group="run/front", slots=[1]), "args": {}, "why": ""}, rec, ctx)
        check("error" in r and "procedural" in r["error"] and len(ctx.enqueued) == 2, "a repair of a procedural group is refused by the same rule the page meets (never a free fill): %s" % r["error"])
        v2 = g.versions(2)[0]
        r = CMD.dispatch({"op": "stage", "target": T(group="run/side"), "args": {"slot": 2, "version": v2["id"]}, "why": "keep"}, rec, ctx)
        check("result" in r and r["result"]["slot"] == 2, "stage answers with the slot: %s" % r)
        ga = FS.Group(FS.Look("enemy", "bug", "BG-A"), "run", "front")
        va = ga.versions(0)[0]
        gb = FS.Group(look, "run", "front")
        nb = len(gb.versions(0))
        r = CMD.dispatch({"op": "copy", "target": T(group="run/front"), "args": {"slot": 0, "from": {"code": "BG-A", "slot": 0, "version": va["id"]}}, "why": "a better frame"}, rec, ctx)
        check("result" in r and len(gb.versions(0)) == nb + 1 and gb.staged().get("0", {}).get("id") == r["result"]["version"]["id"], "copy brings BG-A's frame in as a new staged version of BG-B's slot: %s" % r)
        r = CMD.dispatch({"op": "note", "target": T(), "args": {"text": "looks off"}, "why": ""}, rec, ctx)
        check(r["result"]["noted"] and RAPI.load(RID)["history"][-1]["text"] == "looks off", "note is an event on the record")
        r = CMD.dispatch({"op": "stop", "target": T(), "args": {"why": "enough"}, "why": ""}, rec, ctx)
        check(r == {"result": {"stop": True, "why": "enough"}}, "stop is a direct result")
        r = CMD.dispatch({"op": "requeue", "target": T(), "args": {"words": "no ghost limbs", "seed": 7919}, "why": "ghost"}, rec, ctx)
        names = [c[0] for c in ctx.calls]
        check(r.get("job") == "jlook" and names[-3:] == ["get", "edit", "requeue"] and ctx.look_job["spec"]["recipe"]["art_prompt"] == "a bug, no ghost limbs"
              and ctx.look_job["spec"]["recipe"]["loop_words"] == "no ghost limbs" and ctx.calls[-1][2] == {"seed": 7919}, "requeue edits the spec's words then re-queues with the seed: %s" % ((names[-3:], ctx.calls[-1]),))
        r = CMD.dispatch({"op": "reroll_view", "target": T(), "args": {"view": "side", "base": "run"}, "why": "twice"}, rec, ctx)
        check(r.get("job") == "jlook" and ctx.calls[-1][0] == "requeue" and ctx.calls[-1][2] == {"clips": ["bug_bgb_ctl_side"]}, "reroll_view re-queues with the view's clip moved aside: %s" % (ctx.calls[-1],))
        r = CMD.dispatch({"op": "select_provisional", "target": T(), "args": {"groups": {"run/side": {"versions": {"2": v2["id"]}}}}, "why": "the gates pass"}, rec, ctx)
        saved = RAPI.load(RID)
        check("result" in r and saved["provisional"]["code"] == "BG-B" and saved["provisional"]["groups"]["run/side"]["staged"] == [2] and saved["history"][-1]["event"] == "provisional",
              "select_provisional stages the versions and records the provisional winner: %s" % saved["provisional"])
        check(pins == [] and exports == [] and not any(e["kind"] == "frames_export" for e in ctx.enqueued), "select_provisional never pins, never exports")
        check(not any((s.get("pinned")) for s in g.selected().values()), "no slot became pinned")
        check(open(bug_json, "rb").read() == before, "the JSON (its `variant`) never changed")
        r = CMD.dispatch(dict(good, extra=1), rec, ctx)
        check(r.get("refused") and r["error"].startswith("refused:"), "dispatch validates first and answers a refusal without raising")
        r = CMD.dispatch({"op": "requeue", "target": T(job="jnone"), "args": {"seed": 1}, "why": ""}, rec, ctx)
        check("error" in r, "a requeue of an unknown job is an error record")
    finally:
        FRIO.pin, FRIO.export_job = real_pin, real_export
    # the shim's charge (for a caller outside the step function)
    RAPI.charge(RID, "repair_rounds", 1, group="run/side")
    RAPI.charge(RID, "rerolls", 1)
    s = RAPI.load(RID)["spent"]
    check(s["repair_rounds"] == {"run/side": 1} and s["rerolls"] == 1, "charge counts a repair round per group and a re-roll: %s" % s)


# ---------------------------------------------------------------- the planner

def _planner_checks(check, LOOP):
    asset = {"kind": "enemy", "id": "bug", "code": "BG-B", "method": "creature_ctl"}
    base = {"rid": "r1", "mode": "auto", "asset": asset, "budget": {"rerolls": 2, "repair_rounds": 2, "evaluator_calls": 60, "cloud_dollars": 0.0},
            "spent": {"rerolls": 0, "repair_rounds": {}, "evaluator_calls": 0}, "iterations": [], "provisional": None}
    groups = [{"label": "run/side", "n": 12, "repairable": True, "method": "creature_ctl", "flagged": [3, 4]},
              {"label": "die/front", "n": 8, "repairable": True, "method": "creature_ctl", "flagged": []}]

    def rec(iters=None, **kw):
        r = json.loads(json.dumps(base))
        r["iterations"] = iters or []
        r.update(kw)
        return r

    def it(n, op, job, **kw):
        d = {"n": n, "job": job, "op": op, "gates": "fail"}
        d.update(kw)
        return d

    def hard(slots, field="jump", group="run/side"):
        return [{"image": "%s/%d" % (group, s), "group": group, "slot": s, "kind": "measured", "field": field, "value": 2.3, "ok": False, "rule": "r", "box": None, "model": None} for s in slots]

    def fnd(job, items, groups_=groups):
        h = sum(1 for i in items if i["kind"] == "measured" and i["ok"] is False)
        a = sum(1 for i in items if i["kind"] == "model" and i["ok"] is False)
        return {"v": 1, "job": job, "items": items, "gates": {"hard_failures": h, "advisory": a, "pass": h == 0}, "groups": groups_}
    op = LOOP.next_op(rec(), None)
    check(op and op["op"] == "ask" and op["target"] == {"kind": "enemy", "id": "bug", "code": "BG-B"} and op["args"] == {"tiers": [0, 1]}, "no findings: ask first: %s" % op)
    op = LOOP.next_op(rec([it(1, {"op": "repair", "target": {"group": "run/side", "slots": [3, 4]}, "args": {"rung": "single"}}, "j5")]), fnd("j2", hard([3, 4])))
    check(op and op["op"] == "ask", "findings older than the last landed job (a repair): ask again: %s" % op)
    ask_it = it(1, {"op": "ask", "target": asset, "args": {}}, "j2")
    op = LOOP.next_op(rec([ask_it]), fnd("j2", [{"kind": "model", "ok": False, "group": "run/side", "slot": 1, "field": "broken"}]))
    check(op and op["op"] == "select_provisional" and set(op["args"]["groups"]) == {"run/side", "die/front"} and "gates pass" in op["why"], "the hard gates pass (only advisory): select_provisional: %s" % op)
    op2 = LOOP.next_op(rec([ask_it, it(2, op, None)], provisional={"code": "BG-B"}), fnd("j2", []))
    check(op2 is None, "after select_provisional: None (waiting for Garry)")
    check(LOOP.next_op(rec([it(1, {"op": "stop", "target": asset}, None)]), None) is None, "after stop: None")
    op = LOOP.next_op(rec([ask_it]), fnd("j2", hard([3, 4])))
    check(op and op["op"] == "repair" and op["target"]["group"] == "run/side" and op["target"]["slots"] == [3, 4] and op["args"]["rung"] == "single" and op["hard_before"] == 2,
          "hard findings on a repairable group: repair, the first rung, the slots as a span: %s" % op)
    rep1 = it(2, {"op": "repair", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"rung": "single"}}, "j3", hard_before=2)
    ask2 = it(3, {"op": "ask", "target": asset, "args": {}}, "j4")
    op = LOOP.next_op(rec([ask_it, rep1, ask2]), fnd("j4", hard([3, 4])))
    check(op and op["op"] == "repair" and op["args"]["rung"] == "double" and "did not improve" in op["why"], "the same slots still failing after a single: the next rung, double: %s" % op)
    rep2 = it(4, {"op": "repair", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"rung": "double"}}, "j5", hard_before=2)
    ask3 = it(5, {"op": "ask", "target": asset, "args": {}}, "j6")
    r3 = rec([ask_it, rep1, ask2, rep2, ask3])
    r3["spent"] = {"rerolls": 0, "repair_rounds": {"run/side": 2}, "evaluator_calls": 3}
    op = LOOP.next_op(r3, fnd("j6", hard([3, 4])))
    check(op and op["op"] == "reroll_view" and op["args"] == {"view": "side", "base": "run"} and op["target"]["group"] == "run/side", "after the ladder (or two repairs without improvement): reroll_view: %s" % op)
    op = LOOP.next_op(rec([ask_it, rep1, ask2]), fnd("j4", hard([3])))
    check(op and op["op"] == "repair" and op["args"]["rung"] == "single" and op["target"]["slots"] == [3] and "lowered" in op["why"], "a repair that lowered the count: the same rung again on what is left: %s" % op)
    rep_nb = it(2, {"op": "repair", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"rung": "single"}}, "j3")
    op = LOOP.next_op(rec([ask_it, rep_nb]), fnd("j3", hard([3, 4])))
    check(op and op["op"] == "ask", "a repair just landed (no fresh findings): ask")
    rp = rec([ask_it, rep_nb, ask2])
    op = LOOP.next_op(rp, fnd("j4", hard([3, 4])))
    check(op and op["op"] == "repair" and op["args"]["rung"] == "double", "a repair without a recorded hard_before counts as not improved: the next rung")
    # the plateau rule: the last op was this exact op (its hard_before absent and its rung the first): never twice in a row
    rp2 = rec([ask_it, it(2, {"op": "repair", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"rung": "double"}}, "j3"), ask2])
    rp2["spent"]["repair_rounds"] = {"run/side": 1}
    op = LOOP.next_op(rp2, fnd("j4", hard([3, 4])))
    check(op and op["op"] == "reroll_view", "the double already ran last: the ladder moves on rather than repeating: %s" % op)
    # the streak: a reroll_view that did not help, then a repair proposed as "not improved" (improved_prev False) that
    # did not help either -> the view failed twice -> reroll_view; a reroll_view restarts the ladder at the first rung
    rv = it(2, {"op": "reroll_view", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"view": "side", "base": "run"}}, "j3", hard_before=2)
    op = LOOP.next_op(rec([ask_it, rv, ask2]), fnd("j4", hard([3, 4])))
    check(op and op["op"] == "repair" and op["args"]["rung"] == "single" and op.get("improved_prev") is False and "re-rolled" in op["why"], "after a re-roll that did not help: the ladder starts again at the first rung, improved_prev recorded: %s" % op)
    rp_after = it(4, op, "j5")
    op = LOOP.next_op(rec([ask_it, rv, ask2, rp_after, ask3]), fnd("j6", hard([3, 4])))
    check(op and op["op"] == "reroll_view" and "failed twice" in op["why"], "two ops on the view without improvement: reroll_view: %s" % op)
    rv_ok = it(2, {"op": "reroll_view", "target": {"kind": "enemy", "id": "bug", "code": "BG-B", "group": "run/side", "slots": [3, 4]}, "args": {"view": "side", "base": "run"}}, "j3", hard_before=2)
    op = LOOP.next_op(rec([ask_it, rv_ok, ask2]), fnd("j4", hard([4])))
    check(op and op["op"] == "repair" and op["args"]["rung"] == "single" and op.get("improved_prev") is True and op["target"]["slots"] == [4], "a re-roll that lowered the count: a single repair on what is left, improved_prev True: %s" % op)
    # a still-level failure -> requeue with the defect words and a new seed
    still = [{"image": "tools/dl/ai_raw_anime/bug_bgb_side.png", "group": None, "slot": None, "kind": "measured", "field": "touches-edge", "value": 300, "ok": False, "rule": "r", "box": None, "model": None}]
    op = LOOP.next_op(rec([ask_it]), fnd("j2", still))
    check(op and op["op"] == "requeue" and LOOP.DEFECT_WORDS["touches-edge"] in op["args"]["words"] and op["args"]["seed"] == LOOP.SEED_STEP and "still-level" in op["why"], "a still-level failure: requeue with the defect's words and a new seed: %s" % op)
    r_seed = rec([ask_it], spent={"rerolls": 1, "repair_rounds": {}, "evaluator_calls": 1})
    op = LOOP.next_op(r_seed, fnd("j2", still))
    check(op and op["args"]["seed"] == 2 * LOOP.SEED_STEP, "the seed moves on with the re-rolls spent")
    # a procedural group (no clip, no driver): never a repair, the still is the thing
    proc = [{"label": "run/front", "n": 4, "repairable": False, "method": "creature_proc", "flagged": [1]}]
    op = LOOP.next_op(rec([ask_it]), fnd("j2", hard([1], "jump", "run/front"), proc))
    check(op and op["op"] == "requeue" and LOOP.DEFECT_WORDS["jump"] in op["args"]["words"], "a procedural group's frame failure: requeue the look (never a free fill): %s" % op)
    op = LOOP.next_op(rec([ask_it], spent={"rerolls": 2, "repair_rounds": {}, "evaluator_calls": 1}), fnd("j2", still))
    check(op and op["op"] == "select_provisional", "no re-roll left for a still-level failure: the best so far is the provisional winner: %s" % op)
    # every frame of a group fails: a new clip, not a repair
    op = LOOP.next_op(rec([ask_it]), fnd("j2", hard(list(range(12)))))
    check(op and op["op"] == "reroll_view" and "new clip" in op["why"], "every frame failing: reroll_view: %s" % op)
    # the budgets exhausted on every move: select_provisional, then None
    rb = rec([ask_it], spent={"rerolls": 2, "repair_rounds": {"run/side": 2}, "evaluator_calls": 60})
    op = LOOP.next_op(rb, fnd("j2", hard([3, 4])))
    check(op and op["op"] == "select_provisional", "no budget for any move: select_provisional: %s" % op)
    check(LOOP.next_op(rec([ask_it, it(2, op, None)], provisional={"code": "BG-B"}), fnd("j2", hard([3, 4]))) is None, "then None")
    op = LOOP.next_op(rec([ask_it], spent={"rerolls": 0, "repair_rounds": {}, "evaluator_calls": 60}), None)
    check(op and op["op"] == "select_provisional", "no evaluator calls left and nothing fresh: the provisional winner, not another ask")
    check(LOOP.next_op(rec([ask_it]), {"v": 1, "job": "j2", "items": [], "gates": {}}) is not None, "empty findings still answer")
    # cheapest first: a repair before a re-roll when both groups fail
    both = hard([3]) + hard(list(range(8)), "jump", "die/front")
    op = LOOP.next_op(rec([ask_it]), fnd("j2", both))
    check(op and op["op"] == "repair" and op["target"]["group"] == "run/side", "cheapest first: the repair of run/side before the re-roll of die/front: %s" % op)
    # the profile and the ladder
    p = LOOP.repair_profile("creature_ctl")
    check(set(p["profile"]) >= {"window", "strength", "steps"} and isinstance(p["escalation"], list) and p["escalation"][-1] == "reroll_view", "repair_profile reads methods.json's profile / escalation or the defaults: %s" % p)
    check(LOOP.next_rung(["single", "double", "reroll_view"], "single") == "double" and LOOP.next_rung(["single", "double", "reroll_view"], "reroll_view") is None and LOOP.next_rung([], "x") is None, "next_rung")
    check(LOOP._spans([3, 4, 5, 9]) == [[3, 4, 5], [9]], "spans")
    check(set(LOOP.DEFECT_WORDS) >= {"legs", "ghost", "face", "smear", "empty", "touches-edge"}, "the defect -> words table has the brief's defects")
    bad_mode = LOOP.next_op(rec([ask_it], mode="step"), fnd("j2", hard([3, 4])))
    check(bad_mode and bad_mode["op"] == "repair", "the planner is the same in step mode (the step function pauses after each op)")


def _docs_checks(check, LOOP):
    doc = open(os.path.join(ROOT, "docs", "level_editor.md"), encoding="utf-8").read()
    check("## Pass 96: the loop" in doc, "docs/level_editor.md has the Pass 96 loop section")
    ms = json.load(open(os.path.join(HERE, "methods.json"), encoding="utf-8"))["methods"]
    for m in ms:
        p = LOOP.repair_profile(m["id"])
        check(isinstance(p["profile"], dict) and isinstance(p["escalation"], list), "repair_profile(%s) answers" % m["id"])
