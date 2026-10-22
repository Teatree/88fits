"""One adapter for every visual evaluator of 88fits (pass 96, lane LOOP; the assessment's AI-01, AI-03, AI-07).

    findings = vision_eval.evaluate(images, "frame_blind")                     # the local eye (LM Studio) on pictures
    findings = vision_eval.evaluate_look("enemy", "desert_spider", "SP-B")     # a stored look through the tiers
    python tools/vision_eval.py --job <job_dir>/evaluate.json                  # the Level Editor's `evaluate` job
    python tools/vision_eval.py --kind enemy --id desert_spider --code SP-B [--tiers 0,1] [--groups run/side] [--out <dir>]

Three backends, one call shape (`Backend.ask(images_bytes, prompt, max_tokens) -> (text, usage)`):
  openai_chat   the OpenAI chat shape with base64 PNGs: LM Studio on this PC (http://127.0.0.1:1234, free, 0.9 s a picture),
                Ollama on the AI server between renders; temperature 0; what gen_art.vision_json sent since pass 60.
  anthropic     the Messages API with a model id pinned in tools/level_editor/request_defaults.json (tiers["2"].model), the
                key ONLY from the git-ignored tools/keys/anthropic.env (never the environment: a harness key must not pay for
                the loop), image blocks, effort low, a dollars estimate from `usage` x the price table below.
  gemini        the official Generative Language API `generateContent` with inline PNGs, the key from tools/keys/gemini.env.
                Built; untested until a key exists (G3): its prices are not in the table, so a call is refused as unpriced
                until GATES / Garry writes them.
  fake          FakeBackend(answers) for the selftests (canned answers, every call recorded).

Rules the adapter keeps (the pass 95 experiment, part_AI.md):
  - opaque names: every picture is copied to img_<n>.png in a temporary folder before any call and the backend gets bytes
    only; the prompt is a fixed rubric from tools/qa_rubrics.json (no look note, job title, recipe word or file name);
  - a per-model thinking / max_tokens budget (BUDGETS): a thinking model given 220 tokens returns nothing;
  - an empty or unparsable answer is "no verdict" (an item with ok None), never "ok";
  - the ledger tools/dl/qa/ledger.json (every call: backend, model, pictures, ms, tokens, dollars, request id, rubric) with
    ceilings: the request's `cloud_dollars` and the global `cloud_ceiling_dollars_per_day` of request_defaults.json
    (0 = the cloud tier is off); a call that would pass a ceiling is refused and logged as refused;
  - a cache keyed by sha1(pictures) + rubric + model under tools/dl/qa/cache (a cached answer costs nothing).
The legacy callers keep their behaviour: gen_art.vision_json / gen_art.qa and frames_io.ask go through openai_chat_json
(the same request body, the same parse, no cache, the ledger told).

The tiers (evaluate_look): 0 = deterministic on every frame of the look's groups (frames_store.Group.flags: empty, footprint,
jump, seam, silhouette; gen_art's geometry on the stills) = the HARD gates; 1 = the local eye on the flagged frames plus one
sampled clean frame a group (advisory, with the model's name); 2 = the cloud eye on ONE contact sheet per decision point,
only when the request's cloud_dollars > 0 and the tiers disagree or a hard finding needs confirming (advisory too).
The findings record (INTERFACES.md): {v, job, look, model_calls, items[{image, group, slot, kind measured|model|human, field,
value, ok, rule, box, model}], gates{hard_failures, advisory, pass}, sheet}.
"""
import base64
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

DL = os.path.join(REPO, "tools", "dl")
QA_DIR = os.path.join(DL, "qa")
LEDGER = os.path.join(QA_DIR, "ledger.json")
CACHE_DIR = os.path.join(QA_DIR, "cache")
RUBRICS = os.path.join(HERE, "qa_rubrics.json")
DEFAULTS = os.path.join(HERE, "level_editor", "request_defaults.json")
KEYS_DIR = os.path.join(HERE, "keys")
JOBS_DIR = os.path.join(DL, "jobs")

import ai_hosts  # noqa: E402  (pass 97, lane SAFE: tools/ai_hosts.json "lmstudio"; the old literal when the file has none)
LMSTUDIO = ai_hosts.get("lmstudio", "http://127.0.0.1:1234").rstrip("/") + "/v1/chat/completions"
VISION_MODEL = "qwen2.5-vl-7b-instruct-abliterated"
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
ANTHROPIC_DEFAULT_MODEL = "claude-haiku-5-5"
GEMINI_DEFAULT_MODEL = "gemini-2.5-flash"   # unverified: no key exists (G3); the tier table names the real one

# $ per million tokens (input, output), the Anthropic list prices as the claude-api skill's table cached them on
# PRICES_DATE; cache reads are counted at a tenth of the input price and cache writes at 1.25x (an estimate, marked so).
# Gemini has no row: its prices were never verified here (the assessment's AI-06), so its calls are refused as unpriced.
PRICES_DATE = "2026-10-06"
PRICES = {"claude-haiku-5-5": (0.10, 0.50), "claude-haiku-4-5": (1.0, 5.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-sonnet-5": (2.0, 10.0),
          "claude-sonnet-4-6": (3.0, 15.0), "claude-opus-5-5": (4.0, 20.0), "claude-opus-5": (5.0, 25.0), "claude-opus-4-8": (5.0, 25.0),
          "claude-opus-4-7": (5.0, 25.0), "claude-opus-4-6": (5.0, 25.0)}
TOKENS_PER_IMAGE = 1500    # what a 1024 px picture costs in input tokens, roughly (part_AI: ~1,400); the estimate before a call
TOKENS_PER_PROMPT = 400
# the answer budget per model (max_tokens): a thinking model spends its budget on hidden reasoning first (gemma at 220
# returned nothing), so it gets more; the 7B answers in under 200. Matched by substring, the longest match wins.
BUDGETS = {"": 220, "gemma": 1200, "qwen3": 1200, "thinking": 1200, "claude": 2048, "gemini": 2048, "fake": 220}
LEDGER_KEEP = 2000
HARD_FIELDS = ("empty", "footprint", "jump", "seam", "silhouette", "touches-edge")
GREY = (110, 110, 120, 255)

_lock = threading.RLock()
_rubrics = {"mtime": None, "data": {}}


def log(*a):
    print(*a, flush=True)


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _day():
    return time.strftime("%Y-%m-%d")


def _rel(path):
    try:
        return os.path.relpath(path, REPO).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


def _load_json(path, default=None):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


def sha_of(data):
    return hashlib.sha1(data).hexdigest()


def png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


# ---------------------------------------------------------------- the rubrics, the defaults, the keys

def rubrics():
    """tools/qa_rubrics.json's `rubrics`, re-read when the file changes."""
    try:
        mt = os.path.getmtime(RUBRICS)
    except OSError:
        return {}
    if _rubrics["mtime"] != mt:
        d = _load_json(RUBRICS, {}) or {}
        _rubrics.update(mtime=mt, data=d.get("rubrics") or {})
    return _rubrics["data"]


def rubric(rid):
    r = rubrics().get(rid)
    if not isinstance(r, dict):
        raise ValueError("no rubric %r in %s" % (rid, _rel(RUBRICS)))
    return r


def rubric_text(rid, **subs):
    """The fixed question of a rubric, its placeholders filled (`{subject}`, `{noun}`: only the two legacy rubrics have any;
    a placeholder not given takes the rubric's default)."""
    r = rubric(rid)
    text = str(r.get("text") or "")
    for k, dflt in (r.get("placeholders") or {}).items():
        v = subs.get(k)
        text = text.replace("{" + k + "}", str(dflt if v is None else v))
    return text


def defaults():
    """tools/level_editor/request_defaults.json (GATES / REQ write it; absent = the built-ins)."""
    return _load_json(DEFAULTS, {}) or {}


def tier_table():
    """Which tier runs on what: request_defaults.json `tiers`, else the built-in table (tier 2 off: ceiling 0)."""
    t = defaults().get("tiers")
    if isinstance(t, dict) and t:
        return t
    return {"0": "deterministic",
            "1": {"backend": "openai_chat", "model": VISION_MODEL, "on": "flagged+sample"},
            "2": {"backend": "anthropic", "model": ANTHROPIC_DEFAULT_MODEL, "on": "sheets", "ceiling_dollars": 0.0}}


def global_ceiling():
    """The day's cloud ceiling in dollars (request_defaults.json `cloud_ceiling_dollars_per_day`; 0 = the cloud tier is off)."""
    try:
        return float(defaults().get("cloud_ceiling_dollars_per_day") or 0.0)
    except (TypeError, ValueError):
        return 0.0


def read_key(name):
    """The API key of a backend from tools/keys/<name>.env (git-ignored; `X_API_KEY=...` lines or a bare token). Never the
    environment: the harness's ANTHROPIC_API_KEY must not pay for the loop. "" when the file is missing."""
    p = os.path.join(KEYS_DIR, name + ".env")
    try:
        with open(p, "r", encoding="utf-8") as f:
            lines = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")]
    except OSError:
        return ""
    for ln in lines:
        if "=" in ln:
            k, v = ln.split("=", 1)
            if k.strip().upper().endswith("KEY"):
                return v.strip().strip('"').strip("'")
    return lines[0] if lines and "=" not in lines[0] else ""


def keys_status():
    return {"anthropic": bool(read_key("anthropic")), "gemini": bool(read_key("gemini")), "dir": _rel(KEYS_DIR)}


def budget_for(model, default=None):
    """max_tokens for a model: the longest BUDGETS key the model name contains."""
    if default:
        return int(default)
    m = str(model or "").lower()
    best, best_len = BUDGETS[""], -1
    for k, v in BUDGETS.items():
        if k and k in m and len(k) > best_len:
            best, best_len = v, len(k)
    return int(best)


def price_of(model):
    """(input, output) $/MTok of a cloud model, or None when the table has no row (unpriced: refused under a ceiling)."""
    m = str(model or "")
    if m in PRICES:
        return PRICES[m]
    for k, v in PRICES.items():
        if m.startswith(k):
            return v
    return None


def dollars_of(model, usage):
    """The estimated cost of a call from its usage (tokens) and the price table; None when the model is unpriced."""
    p = price_of(model)
    if not p or not isinstance(usage, dict):
        return None if not p else 0.0
    i, o = float(usage.get("input") or 0), float(usage.get("output") or 0)
    cr, cw = float(usage.get("cache_read") or 0), float(usage.get("cache_write") or 0)
    return round((i * p[0] + o * p[1] + cr * p[0] * 0.1 + cw * p[0] * 1.25) / 1e6, 6)


# ---------------------------------------------------------------- parsing an answer

def parse_json_answer(txt):
    """The first {...} of a model's text as a dict (what gen_art.vision_json did since pass 60): {} when there is none."""
    txt = (txt or "").strip().strip("`")
    if txt.startswith("json"):
        txt = txt[4:]
    i, j = txt.find("{"), txt.rfind("}")
    if i < 0 or j <= i:
        return {}
    try:
        v = json.loads(txt[i:j + 1])
    except ValueError:
        return {}
    return v if isinstance(v, dict) else {}


def _http_json(url, body, headers, timeout):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=dict({"Content-Type": "application/json"}, **headers))
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


# ---------------------------------------------------------------- the backends

class Backend:
    name = "base"
    free = True

    def __init__(self, model=""):
        self.model = model

    def ask(self, images, prompt, max_tokens):
        """images: a list of PNG bytes. Returns (text, usage) with usage {input, output, cache_read, cache_write} (0 when
        the server says nothing)."""
        raise NotImplementedError

    def health(self):
        return True, "no check"

    def estimate(self, n_images, prompt, max_tokens):
        """Dollars this call could cost at most (before it is made); 0.0 for a free backend; None when unpriced."""
        if self.free:
            return 0.0
        p = price_of(self.model)
        if not p:
            return None
        return round(((n_images * TOKENS_PER_IMAGE + TOKENS_PER_PROMPT + len(prompt) // 3) * p[0] + max_tokens * p[1]) / 1e6, 6)


def _usage0():
    return {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}


class OpenAIChatBackend(Backend):
    """LM Studio on the PC (the default), Ollama on the server: the OpenAI chat shape, base64 PNG, temperature 0."""
    name = "openai_chat"
    free = True

    def __init__(self, model=VISION_MODEL, url=LMSTUDIO, timeout=300):
        Backend.__init__(self, model)
        self.url, self.timeout = url, timeout

    def body(self, images, prompt, max_tokens):
        content = [{"type": "text", "text": prompt}]
        for data in images:
            content.append({"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(data).decode()}})
        return {"model": self.model, "max_tokens": max_tokens, "temperature": 0, "messages": [{"role": "user", "content": content}]}

    def ask(self, images, prompt, max_tokens):
        res = _http_json(self.url, self.body(images, prompt, max_tokens), {}, self.timeout)
        txt = ((res.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
        u = res.get("usage") or {}
        usage = _usage0()
        usage.update(input=int(u.get("prompt_tokens") or 0), output=int(u.get("completion_tokens") or 0))
        return txt, usage

    def health(self):
        base = self.url.split("/v1/", 1)[0]
        try:
            urllib.request.urlopen(base + "/v1/models", timeout=1.5).read(64)
            return True, "answers"
        except Exception as e:   # noqa: BLE001
            return False, "%s: %s" % (type(e).__name__, e)


class AnthropicBackend(Backend):
    """The Messages API (raw HTTP: the Level Editor's tools are standard library only, and the key must come from the key
    file alone, never from the environment the official client would read). Effort low, no sampling parameters (the
    current models refuse them), the model id pinned by the caller / the tier table."""
    name = "anthropic"
    free = False

    def __init__(self, model=None, key=None, url=None, timeout=120):
        Backend.__init__(self, model or ((tier_table().get("2") or {}).get("model") if isinstance(tier_table().get("2"), dict) else None) or ANTHROPIC_DEFAULT_MODEL)
        self.key = key if key is not None else read_key("anthropic")
        self.url, self.timeout = url or ANTHROPIC_URL, timeout

    def body(self, images, prompt, max_tokens):
        content = [{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": base64.b64encode(d).decode()}} for d in images]
        content.append({"type": "text", "text": prompt})
        return {"model": self.model, "max_tokens": int(max_tokens), "output_config": {"effort": "low"},
                "messages": [{"role": "user", "content": content}]}

    def ask(self, images, prompt, max_tokens):
        if not self.key:
            raise RuntimeError("no Anthropic key: tools/keys/anthropic.env is missing (git-ignored; the environment is never read)")
        res = _http_json(self.url, self.body(images, prompt, max_tokens),
                         {"x-api-key": self.key, "anthropic-version": ANTHROPIC_VERSION}, self.timeout)
        txt = "" if res.get("stop_reason") == "refusal" else "".join(str(b.get("text") or "") for b in (res.get("content") or []) if b.get("type") == "text")
        u = res.get("usage") or {}
        usage = _usage0()
        usage.update(input=int(u.get("input_tokens") or 0), output=int(u.get("output_tokens") or 0),
                     cache_read=int(u.get("cache_read_input_tokens") or 0), cache_write=int(u.get("cache_creation_input_tokens") or 0))
        return txt, usage

    def health(self):
        return (True, "key present (never pinged: a ping costs)") if self.key else (False, "no key file tools/keys/anthropic.env")


class GeminiBackend(Backend):
    """The official Generative Language API, generateContent with inline PNG data. Built without a key (G3): untested."""
    name = "gemini"
    free = False

    def __init__(self, model=None, key=None, url=None, timeout=120):
        Backend.__init__(self, model or GEMINI_DEFAULT_MODEL)
        self.key = key if key is not None else read_key("gemini")
        self.url, self.timeout = url, timeout

    def body(self, images, prompt, max_tokens):
        parts = [{"text": prompt}] + [{"inline_data": {"mime_type": "image/png", "data": base64.b64encode(d).decode()}} for d in images]
        return {"contents": [{"role": "user", "parts": parts}],
                "generationConfig": {"temperature": 0, "maxOutputTokens": int(max_tokens), "responseMimeType": "application/json"}}

    def ask(self, images, prompt, max_tokens):
        if not self.key:
            raise RuntimeError("no Gemini key: tools/keys/gemini.env is missing (git-ignored)")
        url = self.url or (GEMINI_URL % self.model)
        res = _http_json(url, self.body(images, prompt, max_tokens), {"x-goog-api-key": self.key}, self.timeout)
        cands = res.get("candidates") or []
        parts = ((cands[0].get("content") or {}).get("parts") or []) if cands else []
        txt = "".join(str(p.get("text") or "") for p in parts)
        u = res.get("usageMetadata") or {}
        usage = _usage0()
        usage.update(input=int(u.get("promptTokenCount") or 0), output=int(u.get("candidatesTokenCount") or 0))
        return txt, usage

    def health(self):
        return (True, "key present (never pinged)") if self.key else (False, "no key file tools/keys/gemini.env")


class FakeBackend(Backend):
    """For the selftests: canned answers (a list cycled, a dict by the picture's sha1, or a callable(images, prompt) ->
    text); every call recorded in `calls`. `free=False` with a priced model name makes it count dollars like a cloud eye."""
    name = "fake"

    def __init__(self, answers=None, model="fake-eye", free=True, usage=None, fail=None):
        Backend.__init__(self, model)
        self.answers, self.free, self.usage_each, self.fail = answers, free, usage, fail
        self.calls = []
        self.n = 0

    def ask(self, images, prompt, max_tokens):
        self.calls.append({"n": self.n, "images": [sha_of(d) for d in images], "prompt": prompt, "max_tokens": max_tokens})
        self.n += 1
        if self.fail:
            raise RuntimeError(self.fail)
        a = self.answers
        if callable(a):
            txt = a(images, prompt)
        elif isinstance(a, dict):
            txt = a.get(sha_of(images[0]) if images else "", a.get("*", ""))
        elif isinstance(a, (list, tuple)):
            txt = a[(self.n - 1) % len(a)] if a else ""
        else:
            txt = a if isinstance(a, str) else ""
        if isinstance(txt, dict):
            txt = json.dumps(txt)
        usage = _usage0()
        usage.update(self.usage_each or {"input": 1500 * max(1, len(images)), "output": 40})
        return str(txt or ""), usage

    def health(self):
        return True, "fake"


# ---------------------------------------------------------------- pass 98 (lane GEMINI): Garry's Gemini subscription as an eye
# The Antigravity CLI (agy.exe, Garry's Google subscription: no dollars) in print mode, the call tools/dl/qa_bench/agy_run.py
# proved: `agy -p=<prompt> --mode plan --output-format json --model gemini-3.8-flash-medium --print-timeout <s>` run with
# cwd = a folder holding only the pictures under opaque names, the prompt telling it to call view_file once on each named
# file and nothing else; the answer is the JSON's `response`. agy reads files only under Garry's read rules in
# ~/.gemini/antigravity-cli/settings.json: the inbox rule `read_file(<repo>/tools/dl/qa/agy_inbox)` (ensure_agy_rule
# appends it, a backup first). A refused read (`denied_actions`), an empty answer, a timeout = no verdict, never ok.
# Free in dollars, bounded by a daily call cap (request_defaults.json tiers["2"].daily_calls, default 40) counted from the
# ledger, and by a request's evaluator_calls (the budget's `calls_left`).
AGY_EXE = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser(r"~\AppData\Local"), "agy", "bin", "agy.exe")
AGY_MODEL = "gemini-3.8-flash-medium"
AGY_SETTINGS = os.path.join(os.path.expanduser("~"), ".gemini", "antigravity-cli", "settings.json")
AGY_INBOX = os.path.join(QA_DIR, "agy_inbox")
AGY_LOCK = os.path.join(QA_DIR, "agy.lock")
AGY_DAILY_CALLS = 40
AGY_PRINT_TIMEOUT = 420          # seconds agy itself waits for the model (one picture took ~100 s in the blind bench)
AGY_SHEET_MAX = 16               # cells on one contact sheet: one agent turn covers up to 16 frames
AGY_NAME = "Gemini"              # the eye's name on the page's badges
AGY_CLI_LOG = os.path.join(os.path.expanduser("~"), ".gemini", "antigravity-cli", "cli.log")   # agy's own log (the reason of an empty answer)
AGY_STATE = os.path.join(QA_DIR, "agy_state.json")   # {quota_until, reason, seen}: the subscription's quota spent (no call until then)


def agy_rule(inbox=None):
    """The one read rule agy needs for the inbox (forward slashes: a backslash breaks Garry's JSON)."""
    return "read_file(%s)" % os.path.abspath(inbox or AGY_INBOX).replace("\\", "/")


def agy_table():
    """tiers["2"] of request_defaults.json when it names antigravity, else {} (the built-ins apply)."""
    t2 = tier_table().get("2")
    return t2 if isinstance(t2, dict) and t2.get("backend") == "antigravity" else {}


def agy_daily_cap():
    """The day's Gemini call cap: request_defaults.json tiers["2"].daily_calls (default 40; whatever tier 2's backend is,
    so a tier table rewritten by qa_bench keeps the cap)."""
    t2 = tier_table().get("2")
    try:
        v = (t2 or {}).get("daily_calls") if isinstance(t2, dict) else None
        return int(v) if v is not None else AGY_DAILY_CALLS
    except (TypeError, ValueError):
        return AGY_DAILY_CALLS


def backend_calls_today(backend_name, day=None):
    """How many calls of one backend the ledger holds for the day (refused and cached ones not counted)."""
    day = day or _day()
    d = _ledger_load()
    return sum(1 for c in d["calls"] if isinstance(c, dict) and c.get("backend") == backend_name and c.get("day") == day
               and not c.get("refused") and not c.get("cached"))


def agy_error_of(d, since=None, log_path=None):
    """Why agy answered nothing: an error field of its JSON, else the newest "run ended with error" line of its own
    cli.log written since the call began (local HH:MM:SS of today). "" when nothing says."""
    for k in ("error", "error_message", "message", "status_message"):
        v = (d or {}).get(k)
        if isinstance(v, dict):
            v = v.get("message") or json.dumps(v)
        if v and str(v).strip():
            return str(v).strip()[:300]
    p = log_path or AGY_CLI_LOG
    try:
        with open(p, "rb") as f:
            f.seek(0, 2)
            n = f.tell()
            f.seek(max(0, n - 65536))
            tail = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    t0 = time.strftime("%H:%M:%S", time.localtime((since or time.time()) - 2))
    day = time.strftime("%m%d", time.localtime())
    for ln in reversed(tail):
        m = re.match(r"^[EW](\d{4}) (\d\d:\d\d:\d\d)", ln)
        if not m or m.group(1) != day or m.group(2) < t0:
            continue
        for pat in (r"run ended with error and no response: (.*)$", r"(RESOURCE_EXHAUSTED.*)$", r"(UNAUTHENTICATED.*)$", r"(PERMISSION_DENIED.*)$"):
            mm = re.search(pat, ln)
            if mm:
                return mm.group(1).strip()[:300]
    return ""


def _hms_seconds(text):
    """"166h35m16s" -> seconds (0 when absent)."""
    m = re.search(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?", text or "")
    if not m or not any(m.groups()):
        return 0
    h, mi, s = (int(x or 0) for x in m.groups())
    return h * 3600 + mi * 60 + s


def note_agy_failure(why):
    """A spent subscription quota ("Individual quota reached ... Resets in 166h35m16s") is remembered in agy_state.json:
    no Gemini call is made until it resets (the local fallback runs, shown as an error)."""
    w = str(why or "")
    if "quota" not in w.lower() and "resource_exhausted" not in w.lower():
        return None
    m = re.search(r"[Rr]esets in ([0-9hms]+)", w)
    secs = _hms_seconds(m.group(1)) if m else 3600
    st = {"quota_until": time.time() + max(60, secs), "reason": w[:300], "seen": _now()}
    st["until_text"] = time.strftime("%Y-%m-%d %H:%M", time.localtime(st["quota_until"]))
    try:
        _save_json(AGY_STATE, st)
    except OSError:
        pass
    return st


def agy_quota():
    """The remembered spent quota {quota_until, until_text, reason} while it lasts, else None."""
    st = _load_json(AGY_STATE, None)
    if isinstance(st, dict) and float(st.get("quota_until") or 0) > time.time():
        return st
    return None


def agy_today():
    """{calls, cap, left, day, fallbacks, last_fallback} of the Gemini eye for the page's Ops fold (fallbacks: the times
    today the local model checked frames because a Gemini call failed)."""
    n, cap = backend_calls_today("antigravity"), agy_daily_cap()
    day = _day()
    fb, last = set(), None
    for c in _ledger_load()["calls"]:
        if isinstance(c, dict) and c.get("day") == day and c.get("fallback"):
            fb.add(c.get("fallback_id") or c.get("t"))
            last = {"why": c.get("fallback"), "t": c.get("t")}
    q = agy_quota()
    return {"calls": n, "cap": cap, "left": max(0, cap - n), "day": day, "fallbacks": len(fb), "last_fallback": last,
            "quota_until": q.get("until_text") if q else None, "quota_reason": q.get("reason") if q else None}


def _read_settings(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def agy_rule_present(settings_path=None, inbox=None):
    """(present, detail): the inbox's read rule (or one on a folder above it) in agy's allow list."""
    p = settings_path or AGY_SETTINGS
    want = agy_rule(inbox)[len("read_file("):-1].rstrip("/").lower()
    try:
        d = _read_settings(p)
    except FileNotFoundError:
        return False, "no settings file %s" % p
    except (OSError, ValueError) as e:
        return False, "the settings file %s could not be read: %s" % (p, e)
    allow = ((d.get("permissions") or {}).get("allow") or []) if isinstance(d, dict) else []
    for r in allow:
        r = str(r)
        if r.startswith("read_file(") and r.endswith(")"):
            have = r[len("read_file("):-1].replace("\\", "/").rstrip("/").lower()
            if want == have or want.startswith(have + "/"):
                return True, r
    return False, "no %s in %s" % (agy_rule(inbox), p)


def ensure_agy_rule(settings_path=None, inbox=None, backup_dir=None):
    """Append the inbox's read rule to agy's allow list (nothing else changes; Garry's own rules kept, in order), after a
    backup of the file into backup_dir. Returns {ok, added, rule, backup, file}. Never writes when the rule is there."""
    p = settings_path or AGY_SETTINGS
    rule = agy_rule(inbox)
    ok, why = agy_rule_present(p, inbox)
    if ok:
        return {"ok": True, "added": False, "rule": rule, "file": p, "why": "already there: %s" % why}
    try:
        d = _read_settings(p)
    except FileNotFoundError:
        d = {}
    except (OSError, ValueError) as e:
        return {"ok": False, "added": False, "rule": rule, "file": p, "error": "unreadable: %s (nothing written)" % e}
    if not isinstance(d, dict):
        return {"ok": False, "added": False, "rule": rule, "file": p, "error": "the settings file is not a JSON object (nothing written)"}
    backup = None
    if os.path.isfile(p):
        bd = backup_dir or os.path.join(DL, "qa", "agy_settings_backups")
        os.makedirs(bd, exist_ok=True)
        backup = os.path.join(bd, "settings.%s.json" % time.strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(p, backup)
    perms = d.setdefault("permissions", {})
    if not isinstance(perms, dict):
        return {"ok": False, "added": False, "rule": rule, "file": p, "error": "permissions is not an object (nothing written)"}
    allow = perms.setdefault("allow", [])
    if not isinstance(allow, list):
        return {"ok": False, "added": False, "rule": rule, "file": p, "error": "permissions.allow is not a list (nothing written)"}
    allow.append(rule)
    os.makedirs(os.path.dirname(os.path.abspath(p)), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")
    json.loads(open(tmp, "r", encoding="utf-8").read())   # the file must parse before it replaces Garry's
    os.replace(tmp, p)
    return {"ok": True, "added": True, "rule": rule, "file": p, "backup": backup}


def agy_health(exe=None, settings_path=None, inbox=None):
    """What the page shows about the Gemini eye, without a call: the exe, the read rule, today's calls against the cap."""
    exe = exe or AGY_EXE
    exe_ok = os.path.isfile(exe if isinstance(exe, str) else (exe[-1] if exe else ""))
    rule_ok, rule_why = agy_rule_present(settings_path, inbox)
    t = agy_today()
    why = []
    if not exe_ok:
        why.append("agy.exe is not at %s (the Antigravity CLI)" % exe)
    if not rule_ok:
        why.append(rule_why)
    if t["left"] <= 0:
        why.append("today's cap is spent (%d of %d calls)" % (t["calls"], t["cap"]))
    if t.get("quota_until"):
        why.append("Gemini's subscription quota is spent until %s (agy: %s)" % (t["quota_until"], (t.get("quota_reason") or "")[:120]))
    return {"ok": exe_ok and rule_ok and not t.get("quota_until"), "exe": exe if isinstance(exe, str) else " ".join(exe), "exe_ok": exe_ok, "rule": agy_rule(inbox), "rule_ok": rule_ok,
            "rule_detail": rule_why, "settings": settings_path or AGY_SETTINGS, "model": (agy_table().get("model") or AGY_MODEL), "today": t,
            "why": "; ".join(why) or "ready (no call made to check)"}


def _agy_lock(timeout):
    """One agy call at a time across processes (an evaluate job and the server may both ask): a file made exclusively,
    a stale one (older than the call's own timeout + 2 minutes) taken over."""
    os.makedirs(os.path.dirname(AGY_LOCK), exist_ok=True)
    t0 = time.time()
    while True:
        try:
            fd = os.open(AGY_LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, ("%d %s" % (os.getpid(), _now())).encode())
            os.close(fd)
            return True
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(AGY_LOCK) > timeout + 120:
                    os.remove(AGY_LOCK)
                    continue
            except OSError:
                continue
            if time.time() - t0 > timeout + 180:
                return False
            time.sleep(0.5)


def _agy_unlock():
    try:
        os.remove(AGY_LOCK)
    except OSError:
        pass


class AgyBackend(Backend):
    """Gemini through Garry's Antigravity CLI. ask(images, prompt) writes the pictures as img_<n>.png into
    tools/dl/qa/agy_inbox/<call id>/ (removed after the call), runs agy there in plan mode, parses `response`. `exe` may
    be a path (agy.exe, or a .py stand-in run with this Python: the selftests' fake) or an argv list."""
    name = "antigravity"
    free = True

    def __init__(self, model=None, exe=None, inbox=None, print_timeout=None, timeout=None, settings_path=None):
        t = agy_table()
        Backend.__init__(self, model or t.get("model") or AGY_MODEL)
        self.exe = exe or t.get("exe") or AGY_EXE
        self.inbox = inbox or AGY_INBOX
        self.print_timeout = int(print_timeout or t.get("print_timeout") or AGY_PRINT_TIMEOUT)
        self.timeout = int(timeout or (self.print_timeout + 60))
        self.settings_path = settings_path
        self.daily_calls = agy_daily_cap()
        self.last = {}

    def argv(self, prompt):
        if isinstance(self.exe, (list, tuple)):
            head = list(self.exe)
        elif str(self.exe).lower().endswith(".py"):
            head = [sys.executable, str(self.exe)]
        else:
            head = [str(self.exe)]
        return head + ["-p=" + prompt, "--mode", "plan", "--output-format", "json", "--print-timeout", "%ds" % self.print_timeout, "--model", self.model]

    @staticmethod
    def instruction(names):
        if len(names) == 1:
            how = "Call view_file once on %s in the current folder to see the picture, then answer." % names[0]
        else:
            how = "Call view_file once on each of %s in the current folder to see the pictures, then answer." % ", ".join(names)
        return how + " Do not list folders, do not run commands, do not read any other file, do not write anything."

    def ask(self, images, prompt, max_tokens):
        head = self.argv("")[:-9]
        if head and not os.path.isfile(head[-1]):
            raise RuntimeError("agy is not installed at %s" % head[-1])
        call_id = "c%s_%s" % (time.strftime("%H%M%S"), os.urandom(4).hex())
        folder = os.path.join(self.inbox, call_id)
        os.makedirs(folder, exist_ok=True)
        names = []
        self.last = {"call": call_id}
        self.started = time.time()
        try:
            for k, data in enumerate(images):
                n = "img_%d.png" % k
                with open(os.path.join(folder, n), "wb") as f:
                    f.write(data)
                names.append(n)
            full = self.instruction(names) + "\n\n" + prompt
            if not _agy_lock(self.timeout):
                raise RuntimeError("another Gemini call held the agy lock too long (%s)" % _rel(AGY_LOCK))
            try:
                import subprocess
                try:
                    r = subprocess.run(self.argv(full), cwd=folder, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=self.timeout)
                except subprocess.TimeoutExpired:
                    raise RuntimeError("timeout: agy gave no answer in %d s" % self.timeout)
            finally:
                _agy_unlock()
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        out = (r.stdout or "").strip()
        d = None
        try:
            d = json.loads(out) if out.startswith("{") else None
        except ValueError:
            d = None
        if not isinstance(d, dict):
            lines = [ln for ln in out.splitlines() if ln.strip().startswith("{")]
            for ln in reversed(lines):
                try:
                    d = json.loads(ln)
                    break
                except ValueError:
                    continue
        if not isinstance(d, dict):
            err = (r.stderr or out or "").strip().splitlines()
            raise RuntimeError("agy answered no JSON (exit %s): %s" % (r.returncode, (err[-1] if err else "nothing")[:300]))
        txt = str(d.get("response") or "")
        denied = d.get("denied_actions") or []
        u = d.get("usage") or {}
        usage = _usage0()
        usage.update(input=int(u.get("input_tokens") or 0), output=int(u.get("output_tokens") or 0), cache_read=int(u.get("cache_read_tokens") or 0))
        if u.get("thinking_tokens") is not None:
            usage["thinking"] = int(u.get("thinking_tokens") or 0)
        self.last.update(status=d.get("status"), denied=denied, exit=r.returncode)
        if denied and not txt.strip():
            raise RuntimeError("denied: agy was refused %s (is %s in %s?)" % (json.dumps(denied)[:200], agy_rule(self.inbox), self.settings_path or AGY_SETTINGS))
        if not txt.strip():
            why = agy_error_of(d, self.started)
            self.last["why"] = why
            if why:
                note_agy_failure(why)
                raise RuntimeError("empty: agy gave no answer: %s" % why)
        return txt, usage

    def health(self):
        h = agy_health(self.exe, self.settings_path, self.inbox)
        return h["ok"], h["why"]


def _font(px):
    from PIL import ImageFont
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf"):
        for base in ("", os.path.join(os.environ.get("WINDIR") or r"C:\Windows", "Fonts")):
            try:
                return ImageFont.truetype(os.path.join(base, name) if base else name, px)
            except (OSError, IOError):
                continue
    return ImageFont.load_default()


def agy_sheets(cells, per=AGY_SHEET_MAX, cell_px=256, cols=4):
    """Gemini's contact sheets: cells [(ref, group, slot, cell[, version])] on grey, each numbered big (1..k on every
    sheet) in a black box at its top left; at most `per` cells a sheet. Returns [(image, {n: {ref, group, slot, version}})]."""
    Image, ImageDraw = _pil()
    font = _font(max(18, cell_px // 6))
    out = []
    for i in range(0, len(cells), max(1, per)):
        chunk = cells[i:i + per]
        n = len(chunk)
        c = max(1, min(cols, n))
        rows = (n + c - 1) // c
        gap = 10
        W, H = c * (cell_px + gap) + gap, rows * (cell_px + gap) + gap
        sheet = Image.new("RGBA", (W, H), (60, 60, 68, 255))
        dr = ImageDraw.Draw(sheet)
        where = {}
        for k, cl in enumerate(chunk):
            ref, group, slot, cell = cl[0], cl[1], cl[2], cl[3]
            ver = cl[4] if len(cl) > 4 else None
            x, y = gap + (k % c) * (cell_px + gap), gap + (k // c) * (cell_px + gap)
            tile = Image.new("RGBA", (cell_px, cell_px), GREY)
            tile.alpha_composite(cell.convert("RGBA").resize((cell_px, cell_px), Image.LANCZOS))
            sheet.alpha_composite(tile, (x, y))
            label = str(k + 1)
            try:
                bb = dr.textbbox((0, 0), label, font=font)
                tw, th = bb[2] - bb[0], bb[3] - bb[1]
            except AttributeError:
                bb = (0, 0, 10 * len(label), 14)
                tw, th = bb[2], bb[3]
            pad = max(4, cell_px // 40)
            dr.rectangle((x, y, x + tw + 2 * pad + 2, y + th + 2 * pad + 4), fill=(0, 0, 0, 255))
            dr.text((x + pad + 1, y + pad - bb[1] + 2), label, fill=(255, 235, 60, 255), font=font)
            where[k + 1] = {"ref": ref, "group": group, "slot": slot, "version": ver}
        out.append((sheet.convert("RGB"), where))
    return out


TRUSTED_DEFECTS = ("ghost", "smear", "face")   # pass 98: what the blind bench says Gemini sees (legs 2/11: never alone)


def defect_kinds(cell):
    """The kinds of defect a flagged Gemini cell names: ghost / smear / face (trusted by the bench: they may drive a
    repair), legs (a count: a badge only, unless tier 0's silhouette or footprint flag agrees), other (a cut or broken
    part, a foreign colour: advisory)."""
    c = cell if isinstance(cell, dict) else {}
    why = str(c.get("why") or "").lower()
    out = []
    if c.get("ghost") is True or "ghost" in why or "see-through" in why or "faint" in why:
        out.append("ghost")
    if c.get("smear") is True or "smear" in why or "blur" in why or "streak" in why:
        out.append("smear")
    face = str(c.get("face") or "").lower()
    if face in ("missing", "wrong") or ("face" in why and ("missing" in why or "wrong" in why or "no face" in why or "double" in why)):
        out.append("face")
    if "leg" in why or "limb" in why:
        out.append("legs")
    if not out:
        out.append("other")
    return out


def agy_label(cell):
    """The badge's short words for one cell answer: "9 legs, extra leg" / "ghost leg" / "fine"."""
    if not isinstance(cell, dict):
        return "no verdict"
    why = str(cell.get("why") or "").strip()
    bits = []
    legs = cell.get("legs")
    if isinstance(legs, (int, float)) and not isinstance(legs, bool) and cell.get("ok") is False and "leg" not in why.lower():
        bits.append("%d legs" % int(legs))
    if why and why.lower() not in ("fine", "ok", "none"):
        bits.append(why)
    if not bits:
        return "fine" if cell.get("ok") is not False else "flagged"
    return ", ".join(bits)[:48]


def _agy_items(answer, where, model, rid="sheet_agy", tier=2):
    """A Gemini sheet answer {cells: [{n, ok, legs?, ghost?, face?, why}]} as one item per cell (kind model, field sheet,
    `eye` gemini, `backend` antigravity, `version` of the frame shown, `label` the badge's words, `note` the full answer)."""
    if not isinstance(answer, dict) or not isinstance(answer.get("cells"), list):
        return [dict(_item(w.get("ref"), w.get("group"), w.get("slot"), "model", "verdict", None, None, "no verdict: Gemini's sheet answer was empty or unparsable", None, model, tier),
                     eye="gemini", backend="antigravity", version=w.get("version"), cell=n) for n, w in sorted(where.items())]
    by_n = {}
    for c in answer["cells"]:
        if isinstance(c, dict) and c.get("n") is not None:
            try:
                by_n[int(c["n"])] = c
            except (TypeError, ValueError):
                pass
    out = []
    for n, w in sorted(where.items()):
        c = by_n.get(int(n))
        if c is None:
            out.append(dict(_item(w.get("ref"), w.get("group"), w.get("slot"), "model", "sheet", None, None, "no verdict: Gemini skipped cell %d" % int(n), None, model, tier),
                            eye="gemini", backend="antigravity", version=w.get("version"), cell=int(n)))
            continue
        ok = c.get("ok")
        ok = None if ok is None else bool(ok)
        lab = agy_label(c)
        it = _item(w.get("ref"), w.get("group"), w.get("slot"), "model", "sheet", c.get("why"), ok, "Gemini on a contact sheet: %s (a hint, not a verdict)" % lab, None, model, tier)
        it.update(eye="gemini", backend="antigravity", version=w.get("version"), cell=int(n), label=lab,
                  note=json.dumps({k: v for k, v in c.items() if k != "n"}, ensure_ascii=False)[:600])
        for k in ("legs", "ghost", "face", "smear"):
            if k in c:
                it[k] = c[k]
        if ok is False:
            it["defects"] = defect_kinds(c)
        out.append(it)
    return out


def tier2_free(be2, gdata, items, scope="flagged", slots=None, request=None, budget=None, job=None, use_cache=True, out_dir=None, rubric_id="sheet_agy"):
    """Tier 2 on a free eye (Gemini through agy): which frames, the sheets, one call a sheet, the cells mapped back.
    scope: "flagged" (the decision point: frames tier 0 or tier 1 flagged + one sampled clean frame a group, packed into
    sheets across groups), "all" (Check with Gemini: every frame, sheets per animation x view), "slots" (Ask Gemini: the
    chosen slots, `slots` = {group label: [slot, ...]}). budget["calls_left"] caps the sheets (a request's evaluator_calls);
    the daily cap is checked per call by ceiling_check. Returns (items, calls, tier2 record)."""
    flagged = {}
    for it in items:
        if it.get("group") and it.get("ok") is False and it.get("slot") is not None:
            flagged.setdefault(it["group"], set()).add(int(it["slot"]))
    batches = []   # [[cells]]
    if scope == "all":
        for gd in gdata:
            cells = [("%s/%d" % (gd["label"], s), gd["label"], s, gd["cells"][s], (gd.get("versions") or [None] * gd["n"])[s]) for s in range(min(gd["n"], len(gd["cells"])))]
            for i in range(0, len(cells), AGY_SHEET_MAX):
                batches.append(cells[i:i + AGY_SHEET_MAX])
    else:
        cells = []
        for gd in gdata:
            if scope == "slots":
                want = sorted({int(s) for s in ((slots or {}).get(gd["label"]) or [])})
            else:
                fl = flagged.get(gd["label"], set())
                want = sorted(fl)
                s = _sample_clean_slot(gd["n"], fl)
                if s is not None:
                    want.append(s)
            for s in want:
                if 0 <= s < len(gd["cells"]):
                    cells.append(("%s/%d" % (gd["label"], s), gd["label"], s, gd["cells"][s], (gd.get("versions") or [None] * gd["n"])[s]))
        for i in range(0, len(cells), AGY_SHEET_MAX):
            batches.append(cells[i:i + AGY_SHEET_MAX])
    rec = {"ran": False, "why": "", "backend": be2.name, "model": be2.model, "eye": AGY_NAME if be2.name == "antigravity" else be2.model, "scope": scope, "sheets": []}
    if not batches:
        rec["why"] = "nothing to show: no frame in scope"
        return [], [], rec
    left = None
    if isinstance(budget, dict) and budget.get("calls_left") is not None:
        try:
            left = int(budget["calls_left"])
        except (TypeError, ValueError):
            left = None
    out_items, calls, skipped = [], [], 0
    text = rubric_text(rubric_id)
    for bi, cells in enumerate(batches):
        if left is not None and left <= 0:
            skipped += len(cells)
            for c in cells:
                out_items.append(dict(_item(c[0], c[1], c[2], "model", "verdict", None, None, "not asked: the request's evaluator_calls are spent", None, be2.model, 2),
                                      eye="gemini" if be2.name == "antigravity" else None, backend=be2.name, version=c[4]))
            continue
        img, where = agy_sheets(cells)[0]
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
            sp = os.path.join(out_dir, "gemini_sheet_%d.png" % (bi + 1))
            img.save(sp)
            rec["sheets"].append({"file": _rel(sp), "cells": len(cells), "groups": sorted({c[1] for c in cells})})
        res = ask(be2, [png_bytes(img)], text, rubric_id=rubric_id, request=request, budget=budget, use_cache=use_cache)
        calls.append({"backend": res["backend"], "model": res["model"], "images": 1, "cells": len(cells), "ms": res["ms"], "dollars": res["dollars"],
                      "cached": res["cached"], "refused": res["refused"], "error": res["error"], "tier": 2})
        if left is not None and not res["cached"] and not res["refused"]:
            left -= 1
        if res["refused"] or res["error"] or res["answer"] is None:
            why = ("refused: " + res["refused"]) if res["refused"] else ("no answer: " + res["error"]) if res["error"] else "no verdict: an empty or unparsable answer"
            for n, w in sorted(where.items()):
                out_items.append(dict(_item(w["ref"], w["group"], w["slot"], "model", "verdict", None, None, why, None, be2.model, 2),
                                      eye="gemini" if be2.name == "antigravity" else None, backend=be2.name, version=w.get("version"), cell=int(n)))
            rec["why"] = why
            rec.setdefault("failed_cells", []).extend(cells)   # pass 98: the local model's fallback takes exactly these
            rec["failed_why"] = _short_reason(res)
            continue
        got = _agy_items(res["answer"], where, be2.model)
        out_items += got
        rec["ran"] = True
        # a cell the answer skipped is a partial failure: the local model's fallback takes those frames too
        missed = {(i.get("group"), i.get("slot")) for i in got if i.get("ok") is None}
        if missed:
            rec.setdefault("failed_cells", []).extend(c for c in cells if (c[1], c[2]) in missed)
            rec["failed_why"] = rec.get("failed_why") or "Gemini gave no verdict on %d frame%s" % (len(missed), "" if len(missed) == 1 else "s")
    rec["cells"] = sum(len(b) for b in batches) - skipped
    if skipped:
        rec["why"] = (rec["why"] + "; " if rec["why"] else "") + "%d frames not asked: the request's evaluator_calls are spent" % skipped
    bad = {}
    for it in out_items:
        if it.get("ok") is False and it.get("group"):
            bad.setdefault(it["group"], []).append(int(it["slot"]))
    rec["flagged"] = {g: sorted(set(v)) for g, v in bad.items()}
    rec["line"] = eyes_line(rec)
    return out_items, calls, rec


def _short_reason(res):
    """Why a Gemini call failed, in Garry's words for the red line (agy missing, not logged in, refused read, timeout,
    empty answer, the day's cap)."""
    if res.get("refused"):
        return str(res["refused"])
    e = str(res.get("error") or "")
    e = re.sub(r"^[A-Za-z]+Error: ", "", e)
    low = e.lower()
    if "not installed" in low or "cannot find the file" in low or "no such file" in low:
        return "agy is not installed (%s)" % e[:120]
    if "quota" in low or "resource_exhausted" in low:
        m = re.search(r"[Rr]esets in ([0-9hms]+)", e)
        return "Gemini's subscription quota is spent%s" % ((" (it resets in %s)" % m.group(1)) if m else "")
    if "log in" in low or "logged in" in low or "login" in low or "sign in" in low:
        return "Antigravity wants a log-in again (%s)" % e[:120]
    if low.startswith("denied"):
        return "agy was refused the read (the inbox rule is missing from its settings.json)"
    if not e:
        return "an empty or unparsable answer"
    return e[:160]


def eyes_line(t2):
    """"Gemini flagged 3 frames in run/side" (the look card's and the job card's line)."""
    eye = (t2 or {}).get("eye") or AGY_NAME
    if not (t2 or {}).get("ran"):
        return "%s did not look: %s" % (eye, (t2 or {}).get("why") or "not asked")
    fl = (t2 or {}).get("flagged") or {}
    n = sum(len(v) for v in fl.values())
    if not n:
        return "%s flagged nothing in %d frame%s" % (eye, int(t2.get("cells") or 0), "" if int(t2.get("cells") or 0) == 1 else "s")
    return "%s flagged %d frame%s in %s" % (eye, n, "" if n == 1 else "s", ", ".join("%s (%s)" % (g, ",".join(str(s) for s in v)) for g, v in sorted(fl.items())))


def agreed_frames(findings):
    """{(group, slot)} both eyes flag: a tier-1 (local) item and a tier-2 (Gemini) item with ok False on the same frame."""
    t1, t2 = set(), set()
    for it in (findings or {}).get("items") or []:
        if it.get("kind") != "model" or it.get("ok") is not False or not it.get("group") or it.get("slot") is None:
            continue
        key = (it["group"], int(it["slot"]))
        (t2 if int(it.get("tier") or 1) == 2 else t1).add(key)
    return t1 & t2


def backend_for(name=None, model=None, url=None):
    """A backend by name (openai_chat | anthropic | gemini | fake), or the instance handed in."""
    if isinstance(name, Backend):
        return name
    n = str(name or "openai_chat")
    if n == "openai_chat":
        return OpenAIChatBackend(model or VISION_MODEL, url or LMSTUDIO)
    if n == "anthropic":
        return AnthropicBackend(model, url=url)
    if n == "gemini":
        return GeminiBackend(model, url=url)
    if n == "fake":
        return FakeBackend([], model=model or "fake-eye")
    if n == "antigravity":   # pass 98 (lane GEMINI): Gemini through Garry's Antigravity CLI (no dollars, a daily cap)
        return AgyBackend(model)
    raise ValueError("unknown evaluator backend %r (openai_chat, anthropic, gemini, antigravity, fake)" % name)


# ---------------------------------------------------------------- the ledger and its ceilings

def _ledger_lockfile():
    return LEDGER + ".lock"


def _with_ledger_lock(fn):
    """A cross-process lock on the ledger (an evaluate job and the server's Ask button may write at once)."""
    with _lock:
        lf = _ledger_lockfile()
        os.makedirs(os.path.dirname(lf), exist_ok=True)
        t0 = time.time()
        fd = None
        while fd is None:
            try:
                fd = os.open(lf, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                if time.time() - t0 > 3.0:
                    try:
                        os.remove(lf)   # a lock older than three seconds is a crashed writer's
                    except OSError:
                        pass
                time.sleep(0.02)
        try:
            return fn()
        finally:
            os.close(fd)
            try:
                os.remove(lf)
            except OSError:
                pass


def _ledger_load():
    d = _load_json(LEDGER, None)
    if not isinstance(d, dict):
        d = {"v": 1, "about": "every evaluator call (pass 96, lane LOOP): backend, model, pictures, ms, tokens, dollars, request, rubric",
             "prices_date": PRICES_DATE, "calls": [], "totals": {"calls": 0, "images": 0, "dollars": 0.0}, "days": {}}
    d.setdefault("calls", [])
    d.setdefault("totals", {"calls": 0, "images": 0, "dollars": 0.0})
    d.setdefault("days", {})
    return d


def ledger_record(entry):
    """Append one call (or one refusal) to the ledger; returns the entry with its number."""
    def go():
        d = _ledger_load()
        e = dict(entry)
        e.setdefault("t", _now())
        e.setdefault("day", _day())
        e["n"] = int(d["totals"].get("n", 0)) + 1
        d["totals"]["n"] = e["n"]
        d["calls"].append(e)
        if len(d["calls"]) > LEDGER_KEEP:
            d["calls"] = d["calls"][-LEDGER_KEEP:]
        if not e.get("refused") and not e.get("cached"):
            d["totals"]["calls"] = int(d["totals"].get("calls", 0)) + 1
            d["totals"]["images"] = int(d["totals"].get("images", 0)) + int(e.get("images") or 0)
            d["totals"]["dollars"] = round(float(d["totals"].get("dollars", 0.0)) + float(e.get("dollars") or 0.0), 6)
            day = d["days"].setdefault(e["day"], {"calls": 0, "images": 0, "dollars": 0.0})
            day["calls"] += 1
            day["images"] += int(e.get("images") or 0)
            day["dollars"] = round(day["dollars"] + float(e.get("dollars") or 0.0), 6)
        _save_json(LEDGER, d)
        return e
    try:
        return _with_ledger_lock(go)
    except Exception as e:   # noqa: BLE001  (the ledger must never fail a check)
        return dict(entry, ledger_error="%s: %s" % (type(e).__name__, e))


def ledger_totals(day=None):
    """{calls, images, dollars, day, day_calls, day_dollars} for the page ("QA: 3 calls, $0.00")."""
    d = _ledger_load()
    day = day or _day()
    dd = d["days"].get(day) or {"calls": 0, "images": 0, "dollars": 0.0}
    return {"calls": int(d["totals"].get("calls", 0)), "images": int(d["totals"].get("images", 0)), "dollars": float(d["totals"].get("dollars", 0.0)),
            "day": day, "day_calls": int(dd.get("calls", 0)), "day_dollars": float(dd.get("dollars", 0.0)), "prices_date": PRICES_DATE,
            "ceiling_per_day": global_ceiling(), "file": _rel(LEDGER)}


def request_dollars(rid):
    """What a request has spent on cloud calls so far, from the ledger."""
    if not rid:
        return 0.0
    d = _ledger_load()
    return round(sum(float(c.get("dollars") or 0.0) for c in d["calls"] if c.get("request") == rid and not c.get("refused") and not c.get("cached")), 6)


def ceiling_check(backend, estimate, budget=None, request=None):
    """(ok, reason) before a call. A free backend always passes. A cloud call needs: a price (else "unpriced"), the global
    daily ceiling above 0 and not passed, and, when a request budget is given, its cloud_dollars above 0 and not passed."""
    if getattr(backend, "daily_calls", None) is not None:
        # pass 98 (lane GEMINI): a free eye with a daily call cap (Gemini through agy) and a request's calls left
        cap = int(backend.daily_calls)
        n = backend_calls_today(backend.name)
        if n >= cap:
            return False, "today's %s cap: %d of %d calls made (request_defaults.json tiers[\"2\"].daily_calls)" % (AGY_NAME if backend.name == "antigravity" else backend.name, n, cap)
        if isinstance(budget, dict) and budget.get("calls_left") is not None and int(budget.get("calls_left") or 0) <= 0:
            return False, "the request's evaluator_calls are spent"
        q = agy_quota() if backend.name == "antigravity" else None
        if q:
            return False, "Gemini's subscription quota is spent until %s (no call made)" % q.get("until_text")
    if getattr(backend, "free", True):
        return True, ""
    if estimate is None:
        return False, "unpriced: %s has no row in the price table (dated %s): a ceiling cannot bound it" % (backend.model, PRICES_DATE)
    g = global_ceiling()
    if g <= 0:
        return False, "the cloud tier is off: cloud_ceiling_dollars_per_day is %s in request_defaults.json" % g
    day = ledger_totals()["day_dollars"]
    if day + estimate > g:
        return False, "the day's cloud ceiling: $%.4f spent + $%.4f estimated > $%.4f" % (day, estimate, g)
    if isinstance(budget, dict):
        cap = float(budget.get("cloud_dollars") or 0.0)
        if cap <= 0:
            return False, "the request's cloud tier is off (cloud_dollars 0)"
        spent = float(budget.get("spent") if budget.get("spent") is not None else request_dollars(request))
        if spent + estimate > cap:
            return False, "the request's cloud_dollars: $%.4f spent + $%.4f estimated > $%.4f" % (spent, estimate, cap)
    return True, ""


# ---------------------------------------------------------------- the cache

def cache_key(images, rubric_id, rubric_text_, model):
    h = hashlib.sha1()
    for d in images:
        h.update(sha_of(d).encode())
    h.update(("|%s|%s|%s" % (rubric_id, sha_of(rubric_text_.encode("utf-8")), model)).encode("utf-8"))
    return h.hexdigest()


def cache_get(key):
    return _load_json(os.path.join(CACHE_DIR, key + ".json"), None)


def cache_put(key, rec):
    try:
        _save_json(os.path.join(CACHE_DIR, key + ".json"), rec)
    except OSError:
        pass


# ---------------------------------------------------------------- one call

def ask(backend, images, prompt, max_tokens=None, rubric_id="", request=None, budget=None, use_cache=True, cache_rubric=None, ledger_extra=None):
    """One evaluator call on PNG bytes: the cache, the ceiling, the call, the parse, the ledger.
    Returns {answer (dict | None = no verdict), text, usage, ms, dollars, cached, refused, error, model, backend}."""
    backend = backend_for(backend)
    images = [d for d in images if d]
    max_tokens = budget_for(backend.model, max_tokens)
    out = {"answer": None, "text": "", "usage": _usage0(), "ms": 0, "dollars": 0.0, "cached": False, "refused": "", "error": "",
           "model": backend.model, "backend": backend.name, "images": len(images)}
    key = cache_key(images, rubric_id or cache_rubric or "", prompt, backend.model) if use_cache else None
    if key:
        c = cache_get(key)
        if isinstance(c, dict) and isinstance(c.get("answer"), dict):
            out.update(answer=c["answer"], text=c.get("text", ""), cached=True)
            ledger_record({"backend": backend.name, "model": backend.model, "images": len(images), "ms": 0, "tokens_in": 0, "tokens_out": 0,
                           "dollars": 0.0, "request": request, "rubric": rubric_id, "cached": True})
            return out
    est = backend.estimate(len(images), prompt, max_tokens)
    ok, why = ceiling_check(backend, est, budget, request)
    if not ok:
        out["refused"] = why
        ledger_record({"backend": backend.name, "model": backend.model, "images": len(images), "ms": 0, "tokens_in": 0, "tokens_out": 0,
                       "dollars": 0.0, "estimate": est, "request": request, "rubric": rubric_id, "refused": why})
        return out
    t0 = time.time()
    try:
        txt, usage = backend.ask(images, prompt, max_tokens)
    except Exception as e:   # noqa: BLE001
        out["error"] = "%s: %s" % (type(e).__name__, e)
        out["ms"] = int((time.time() - t0) * 1000)
        ledger_record(dict({"backend": backend.name, "model": backend.model, "images": len(images), "ms": out["ms"], "tokens_in": 0, "tokens_out": 0,
                            "dollars": 0.0, "request": request, "rubric": rubric_id, "error": out["error"]}, **(ledger_extra or {})))
        return out
    out["ms"] = int((time.time() - t0) * 1000)
    out["text"], out["usage"] = txt or "", usage or _usage0()
    d = dollars_of(backend.model, out["usage"]) if not backend.free else 0.0
    out["dollars"] = d if d is not None else 0.0
    ans = parse_json_answer(txt)
    out["answer"] = ans if ans else None   # empty or unparsable = no verdict, never ok
    extra = dict(ledger_extra or {})   # pass 98 (lane GEMINI): a fallback call's {fallback, fallback_id}
    if backend.name == "antigravity":   # pass 98 (lane GEMINI): seconds and agy's thinking tokens on the row
        extra = dict(extra, **{"seconds": round(out["ms"] / 1000.0, 1), "tokens_thinking": int(out["usage"].get("thinking") or 0), "tokens_cache_read": int(out["usage"].get("cache_read") or 0)})
    ledger_record(dict({"backend": backend.name, "model": backend.model, "images": len(images), "ms": out["ms"], "tokens_in": out["usage"].get("input", 0),
                        "tokens_out": out["usage"].get("output", 0), "dollars": out["dollars"], "unpriced": d is None, "request": request, "rubric": rubric_id,
                        "verdict": bool(ans)}, **extra))
    if key and ans:
        cache_put(key, {"answer": ans, "text": txt, "model": backend.model, "rubric": rubric_id, "t": _now()})
    return out


def openai_chat_json(img, question, max_tokens=220, url=LMSTUDIO, model=VISION_MODEL, timeout=300):
    """What gen_art.vision_json did since pass 60, unchanged: the OpenAI chat shape with one base64 PNG, temperature 0,
    the first {...} of the answer as a dict ({} when there is none), the exception raised to the caller. No cache; the
    ledger is told (a free call; the request id from ASSET_JOB_REQUEST when a request's job runs it)."""
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG")
    be = OpenAIChatBackend(model, url, timeout)
    t0 = time.time()
    txt, usage = be.ask([buf.getvalue()], question, max_tokens)
    ans = parse_json_answer(txt)
    ledger_record({"backend": be.name, "model": model, "images": 1, "ms": int((time.time() - t0) * 1000), "tokens_in": usage.get("input", 0),
                   "tokens_out": usage.get("output", 0), "dollars": 0.0, "request": os.environ.get("ASSET_JOB_REQUEST") or None,
                   "rubric": "legacy", "verdict": bool(ans)})
    return ans


# ---------------------------------------------------------------- findings from answers

def _item(image, group, slot, kind, field, value, ok, rule, box=None, model=None, tier=None):
    it = {"image": image, "group": group, "slot": slot, "kind": kind, "field": field, "value": value, "ok": ok, "rule": rule, "box": box, "model": model}
    if tier is not None:
        it["tier"] = tier
    return it


def items_from_answer(answer, rid, image, group, slot, model, tier=1):
    """A model's parsed answer to a per-image rubric as findings items (kind model). None = one "no verdict" item."""
    r = rubric(rid)
    if not isinstance(answer, dict):
        return [_item(image, group, slot, "model", "verdict", None, None, "no verdict: the model returned an empty or unparsable answer", None, model, tier)]
    out = []
    note = None
    for field, spec in (r.get("fields") or {}).items():
        if spec.get("note"):
            note = answer.get(field)
            continue
        if field not in answer:
            continue
        v = answer.get(field)
        if spec.get("record"):
            out.append(_item(image, group, slot, "model", field, v, None, spec.get("rule", ""), None, model, tier))
            continue
        bad = spec.get("bad_when")
        if isinstance(bad, list):
            ok = str(v).lower() not in [str(b).lower() for b in bad]
        else:
            ok = (bool(v) != bool(bad)) if isinstance(v, (bool, int)) else (str(v).lower() != str(bad).lower())
        out.append(_item(image, group, slot, "model", field, v, ok, spec.get("rule", ""), None, model, tier))
    if note is not None and str(note).strip().lower() not in ("", "fine", "none", "nothing"):
        out.append(_item(image, group, slot, "model", "note", str(note), None, "the model's note (its prose is never a check on its verdict)", None, model, tier))
    return out


def gates_of(items):
    hard = sum(1 for it in items if it.get("kind") == "measured" and it.get("ok") is False)
    adv = sum(1 for it in items if it.get("kind") == "model" and it.get("ok") is False)
    return {"hard_failures": hard, "advisory": adv, "pass": hard == 0}


def _normalise_images(images):
    """[{bytes, ref, group, slot}] from paths, PIL images or {image, group, slot, ref} dicts."""
    out = []
    for k, x in enumerate(images or []):
        group, slot, ref, cells = None, None, None, None
        if isinstance(x, dict):
            group, slot, ref, cells = x.get("group"), x.get("slot"), x.get("ref"), x.get("cells")
            x = x.get("image")
        if isinstance(x, (bytes, bytearray)):
            data = bytes(x)
            ref = ref or "image_%d" % k
        elif isinstance(x, str):
            with open(x, "rb") as f:
                data = f.read()
            ref = ref or _rel(x)
        else:
            data = png_bytes(x.convert("RGBA"))
            ref = ref or "image_%d" % k
        out.append({"bytes": data, "ref": ref, "group": group, "slot": slot, "cells": cells})
    return out


def _opaque_copies(entries):
    """The pictures copied to img_<n>.png in a temporary folder and read back from there: what reaches a backend never
    carries a name. Returns (folder, [bytes])."""
    tmp = tempfile.mkdtemp(prefix="qa_blind_")
    data = []
    for k, e in enumerate(entries):
        p = os.path.join(tmp, "img_%d.png" % k)
        with open(p, "wb") as f:
            f.write(e["bytes"])
        with open(p, "rb") as f:
            data.append(f.read())
    return tmp, data


def evaluate(images, rubric_id, backend=None, model=None, budget=None, request=None, job=None, look=None, tier=1, use_cache=True, ledger_extra=None):
    """The findings of a backend on pictures (INTERFACES shape, items of kind model). images: paths, PIL images or
    {image, group, slot} dicts; rubric_id: a key of tools/qa_rubrics.json; backend: a name or an instance; budget: the
    request's {cloud_dollars, spent} for a cloud backend. Names never reach the model: opaque copies, a fixed rubric."""
    be = backend_for(backend, model)
    r = rubric(rubric_id)
    text = rubric_text(rubric_id)
    entries = _normalise_images(images)
    items, calls = [], []
    tmp, data = _opaque_copies(entries)
    try:
        if r.get("per") == "sheet":
            batches = [(entries, data)]
        else:
            batches = [([e], [d]) for e, d in zip(entries, data)]
        for ents, dat in batches:
            res = ask(be, dat, text, rubric_id=rubric_id, request=request, budget=budget, use_cache=use_cache, ledger_extra=ledger_extra)
            calls.append({"backend": res["backend"], "model": res["model"], "images": len(dat), "ms": res["ms"], "dollars": res["dollars"],
                          "cached": res["cached"], "refused": res["refused"], "error": res["error"], "tier": tier})
            if res["refused"] or res["error"]:
                for e in ents:
                    items.append(_item(e["ref"], e["group"], e["slot"], "model", "verdict", None, None,
                                       ("refused: " + res["refused"]) if res["refused"] else ("no answer: " + res["error"]), None, be.model, tier))
                continue
            if r.get("per") == "sheet":
                items += _sheet_items(res["answer"], rubric_id, ents, be.model, tier)
            else:
                e = ents[0]
                items += items_from_answer(res["answer"], rubric_id, e["ref"], e["group"], e["slot"], be.model, tier)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return {"v": 1, "job": job, "look": look, "model_calls": calls, "items": items, "gates": gates_of(items), "sheet": None, "tier": tier, "time": _now()}


def _sheet_items(answer, rid, ents, model, tier):
    """A contact-sheet answer {cells: [{n, ok, why}]} mapped back to the pictures (`ents[k]["cells"]` = the cell numbers)."""
    if not isinstance(answer, dict) or not isinstance(answer.get("cells"), list):
        return [_item(e["ref"], e["group"], e["slot"], "model", "verdict", None, None, "no verdict: the sheet answer was empty or unparsable", None, model, tier) for e in ents]
    by_n = {}
    for c in answer["cells"]:
        if isinstance(c, dict) and c.get("n") is not None:
            try:
                by_n[int(c["n"])] = c
            except (TypeError, ValueError):
                pass
    out = []
    for e in ents:
        for n, where in (e.get("cells") or {}).items():
            c = by_n.get(int(n))
            if c is None:
                out.append(_item(where.get("ref"), where.get("group"), where.get("slot"), "model", "sheet", None, None, "no verdict: the sheet answer skipped cell %d" % int(n), None, model, tier))
                continue
            ok = c.get("ok")
            ok = (None if ok is None else bool(ok))
            out.append(_item(where.get("ref"), where.get("group"), where.get("slot"), "model", "sheet", c.get("why"), ok,
                             "the cloud eye on the decision sheet: %s" % (c.get("why") or ("fine" if ok else "flagged")), None, model, tier))
    return out


# ---------------------------------------------------------------- pictures: a frame on grey, the sheets, the geometry

def _pil():
    from PIL import Image, ImageDraw
    return Image, ImageDraw


def frame_on_grey(cell, scale=3):
    """A strip cell three times its size on grey (as the Frames view's Ask button shows it: the model reads a 160 px cell badly)."""
    Image, _ = _pil()
    cell = cell.convert("RGBA")
    big = cell.resize((cell.width * scale, cell.height * scale), Image.LANCZOS)
    bg = Image.new("RGBA", big.size, GREY)
    bg.alpha_composite(big)
    return bg.convert("RGB")


def geometry(img):
    """gen_art.geometry's maths (the margins to every edge and the figure's size of a keyed still, in pixels)."""
    import numpy as np
    import artkit
    a = np.asarray(artkit.key_background(img))[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return {"empty": True}
    h, w = a.shape
    return {"left": int(xs.min()), "right": int(w - 1 - xs.max()), "top": int(ys.min()), "bottom": int(h - 1 - ys.max()),
            "height": int(ys.max() - ys.min()), "width": int(xs.max() - xs.min())}


def geometry_problems(geo, expect=None):
    """The problems gen_art.render raises from a still's geometry before any model is asked: empty, touches-edge (portraits
    may run off the bottom edge)."""
    expect = expect or {}
    if geo.get("empty"):
        return ["empty"]
    if expect.get("bust"):
        if min(geo["left"], geo["right"], geo["top"]) < 12:
            return ["touches-edge"]
    elif min(geo["left"], geo["right"], geo["top"]) < 12 or geo["bottom"] < 20:
        return ["touches-edge"]
    return []


def _bbox_xywh(cell):
    import numpy as np
    a = np.asarray(cell.convert("RGBA"))[..., 3] > 127
    ys, xs = np.nonzero(a)
    if len(xs) == 0:
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)]


def findings_sheet(groups, flagged, out_path, cell_px=96):
    """The page's sheet: every frame of every evaluated group in rows, the flagged slots framed red, labels in the margin.
    groups: [(label, [cells])]; flagged: {label: set(slots)}."""
    Image, ImageDraw = _pil()
    if not groups:
        return None
    cols = max(len(cells) for _, cells in groups)
    label_w = 90
    W, H = label_w + cols * (cell_px + 4) + 4, len(groups) * (cell_px + 18) + 4
    sheet = Image.new("RGBA", (W, H), (48, 48, 54, 255))
    dr = ImageDraw.Draw(sheet)
    for r, (label, cells) in enumerate(groups):
        y = 4 + r * (cell_px + 18)
        dr.text((4, y + cell_px // 2 - 6), label, fill=(230, 230, 230, 255))
        for k, c in enumerate(cells):
            x = label_w + k * (cell_px + 4)
            tile = Image.new("RGBA", (cell_px, cell_px), GREY)
            tile.alpha_composite(c.convert("RGBA").resize((cell_px, cell_px), Image.LANCZOS))
            sheet.alpha_composite(tile, (x, y))
            if k in (flagged.get(label) or set()):
                dr.rectangle((x, y, x + cell_px - 1, y + cell_px - 1), outline=(230, 60, 60, 255), width=3)
            dr.text((x + 2, y + cell_px + 2), str(k), fill=(200, 200, 200, 255))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet.convert("RGB").save(out_path)
    return out_path


def decision_sheet(cells, cell_px=160, cols=6):
    """The tier-2 contact sheet: numbered cells on grey, one picture for one call. cells: [(ref, group, slot, cell)].
    Returns (image, {n: {ref, group, slot}}) with n starting at 1."""
    Image, ImageDraw = _pil()
    n = len(cells)
    cols = max(1, min(cols, n))
    rows = (n + cols - 1) // cols
    W, H = cols * (cell_px + 6) + 6, rows * (cell_px + 6) + 6
    sheet = Image.new("RGBA", (W, H), (70, 70, 78, 255))
    dr = ImageDraw.Draw(sheet)
    where = {}
    for k, (ref, group, slot, c) in enumerate(cells):
        x, y = 6 + (k % cols) * (cell_px + 6), 6 + (k // cols) * (cell_px + 6)
        tile = Image.new("RGBA", (cell_px, cell_px), GREY)
        tile.alpha_composite(c.convert("RGBA").resize((cell_px, cell_px), Image.LANCZOS))
        sheet.alpha_composite(tile, (x, y))
        dr.rectangle((x, y, x + 26, y + 14), fill=(0, 0, 0, 255))
        dr.text((x + 3, y + 1), str(k + 1), fill=(255, 255, 255, 255))
        where[k + 1] = {"ref": ref, "group": group, "slot": slot}
    return sheet.convert("RGB"), where


# ---------------------------------------------------------------- a stored look through the tiers

def _group_label(base, view):
    return "%s/%s" % (base, view)


def _measured_value(rec):
    for k in ("score", "area", "iou", "w", "h", "shrunk"):
        if k in rec:
            return rec[k]
    return None


def tier0_look(look, groups_wanted=None):
    """The deterministic tier on a stored look: every group's flags (frames_store) and the stills' geometry.
    Returns (items, groups_data) where groups_data = [{label, base, view, group, cells, n, repairable}]."""
    import frames_store as FS
    items, gdata = [], []
    for base, view, key, n in FS.groups_of(look):
        label = _group_label(base, view)
        if groups_wanted and label not in groups_wanted:
            continue
        g = FS.Group(look, base, view)
        if not g.exists():
            FS.register_look(look.kind, look.cid, look.code)
            g = FS.Group(look, base, view)
        if not g.exists():
            continue
        cells = g.effective_cells()
        flags = g.flags()
        for slot in range(g.n):
            f = flags.get(str(slot)) or {}
            for name, rec in f.items():
                items.append(_item("%s/%d" % (label, slot), label, slot, "measured", name, _measured_value(rec), False, str(rec.get("rule") or name),
                                   _bbox_xywh(cells[slot]) if slot < len(cells) else None, None, 0))
        gdata.append({"label": label, "base": base, "view": view, "group": g, "cells": cells, "n": g.n,
                      "repairable": bool(g.meta.get("clip") or g.meta.get("driver")), "method": g.meta.get("method"),
                      "versions": _effective_ids(g)})   # pass 98 (lane GEMINI): the version each cell shows (per-frame findings)
    # the stills (the paintings the clips were made from): gen_art's geometry, no model
    seen = set()
    for gd in gdata:
        for view in (gd["view"], "front"):
            rel = look.ref_still(view)
            if not rel or rel in seen:
                continue
            seen.add(rel)
            p = os.path.join(FS.REPO, rel)
            try:
                Image, _ = _pil()
                geo = geometry(Image.open(p).convert("RGB"))
            except Exception as e:   # noqa: BLE001
                items.append(_item(rel, None, None, "measured", "unreadable", str(e), False, "the still could not be read", None, None, 0))
                continue
            for prob in geometry_problems(geo):
                items.append(_item(rel, None, None, "measured", prob, geo.get("height"), False,
                                   "the figure is missing" if prob == "empty" else "the figure touches the picture's edge (margins %s/%s/%s/%s)" % (geo["left"], geo["right"], geo["top"], geo["bottom"]),
                                   None, None, 0))
    return items, gdata


def _effective_ids(g):
    """pass 98 (lane GEMINI): the id of the version each slot of a group shows (the cell evaluated), None where unknown."""
    out = []
    for k in range(g.n):
        try:
            v, _ = g.effective(k)
        except Exception:   # noqa: BLE001
            v = None
        out.append(v.get("id") if isinstance(v, dict) else None)
    return out


def _stamp_versions(items, gdata):
    """pass 98 (lane GEMINI): a model item on a frame learns the version it judged (the frames store keeps it per version)."""
    by = {gd["label"]: gd.get("versions") or [] for gd in gdata}
    for it in items:
        if it.get("kind") == "model" and it.get("group") in by and it.get("slot") is not None and not it.get("version"):
            vs = by[it["group"]]
            k = int(it["slot"])
            if 0 <= k < len(vs) and vs[k]:
                it["version"] = vs[k]


def _sample_clean_slot(n, flagged):
    """One clean frame a group, chosen the same way every run: the middle of the unflagged slots."""
    clean = [k for k in range(n) if k not in flagged]
    return clean[len(clean) // 2] if clean else None


def evaluate_look(kind, cid, code, tiers=(0, 1), groups=None, backend=None, model=None, request=None, cloud_dollars=0.0, cloud_backend=None,
                  out_dir=None, job=None, budget=None, use_cache=True, scope="flagged", slots=None, allow_fallback=True):
    """A stored look through the tiers; the findings written to <out_dir>/findings.json and findings_sheet.png when out_dir
    is given. `backend` is tier 1's (default: the tier table's local eye), `cloud_backend` tier 2's (default: the tier
    table's); `cloud_dollars` is the request's ceiling for a PAID tier 2 (0 = off); a free tier 2 (antigravity, pass 98)
    runs at $0, bounded by its daily call cap."""
    import frames_store as FS
    tiers = [int(t) for t in (tiers or (0, 1))]
    look = FS.Look(kind, cid, code)
    items, calls = [], []
    gdata = []
    flagged_by_group = {}
    if 0 in tiers:
        items, gdata = tier0_look(look, set(groups or []) or None)
    else:
        # the frames are still needed for the model tiers
        _, gdata = tier0_look(look, set(groups or []) or None)
    for it in items:
        if it["group"] and it["ok"] is False:
            flagged_by_group.setdefault(it["group"], set()).add(int(it["slot"]))
    tt = tier_table()
    t1 = tt.get("1") if isinstance(tt.get("1"), dict) else {}
    want_slots = slots   # (the tier-1 block below reuses the name `slots`)
    # pass 98 (lane GEMINI; Garry: "just use Gemini first ... the local as backups"): when tier 2's eye is a FREE one (Gemini
    # through agy: the tier table's antigravity, or a backend handed in), Gemini is the primary model eye and the local
    # tier runs only on the frames of a Gemini call that failed (the fallback, surfaced as an error); otherwise pass 96
    t2 = tt.get("2") if isinstance(tt.get("2"), dict) else {}
    be2_free = None
    if 2 in tiers:
        name2 = cloud_backend if cloud_backend is not None else t2.get("backend")
        if isinstance(name2, Backend):
            be2_free = name2 if name2.free else None
        elif name2 == "antigravity":
            be2_free = backend_for("antigravity", t2.get("model") if t2.get("backend") == "antigravity" else None)
    # tier 1: the local eye on the flagged frames plus one sampled clean frame a group
    if 1 in tiers and gdata and be2_free is None:
        be1 = backend_for(backend or t1.get("backend") or "openai_chat", model or t1.get("model") or VISION_MODEL)
        pics = []
        for gd in gdata:
            fl = flagged_by_group.get(gd["label"], set())
            slots = sorted(fl)
            s = _sample_clean_slot(gd["n"], fl)
            if s is not None:
                slots.append(s)
            for slot in slots:
                if slot < len(gd["cells"]):
                    pics.append({"image": frame_on_grey(gd["cells"][slot]), "group": gd["label"], "slot": slot, "ref": "%s/%d" % (gd["label"], slot)})
        if pics:
            f1 = evaluate(pics, "frame_blind", be1, request=request, budget=budget, job=job, tier=1, use_cache=use_cache)
            items += f1["items"]
            calls += f1["model_calls"]
    # tier 2: the cloud eye on one contact sheet when the tiers disagree or a hard finding needs confirming
    tier2 = {"ran": False, "why": ""}
    fallback = None
    if be2_free is not None:
        # pass 98 (lane GEMINI): Gemini on sheets of the flagged frames + a clean one a group (scope flagged), every frame
        # (all) or chosen slots (slots), bounded by the day's cap and the request's calls
        f2_items, f2_calls, tier2 = tier2_free(be2_free, gdata, items, scope=scope or "flagged", slots=want_slots, request=request, budget=budget, job=job,
                                               use_cache=use_cache, out_dir=out_dir)
        failed = tier2.pop("failed_cells", [])
        if failed and allow_fallback:
            # the fallback: the local model on exactly the frames Gemini failed on, its items marked, the error surfaced
            be1 = backend_for(backend or t1.get("backend") or "openai_chat", model or t1.get("model") or VISION_MODEL)
            why = tier2.get("failed_why") or "Gemini gave no answer"
            fid = "fb_%s_%s" % (time.strftime("%H%M%S"), os.urandom(3).hex())
            pics = [{"image": frame_on_grey(c[3]), "group": c[1], "slot": c[2], "ref": c[0]} for c in failed]
            f1 = evaluate(pics, "frame_blind", be1, request=request, budget=budget, job=job, tier=1, use_cache=use_cache,
                          ledger_extra={"fallback": why, "fallback_id": fid})
            ver = {(c[1], c[2]): c[4] for c in failed}
            for it in f1["items"]:
                it.update(eye="local", fallback=True, version=ver.get((it.get("group"), it.get("slot"))))
            items += f1["items"]
            calls += [dict(c, fallback=True) for c in f1["model_calls"]]
            fallback = {"frames": len(failed), "why": why, "model": be1.model, "id": fid,
                        "line": "Gemini failed: %s - checked by the local model instead" % why}
        elif failed:
            fallback = {"frames": 0, "why": tier2.get("failed_why") or "Gemini gave no answer", "model": None, "id": None,
                        "line": "Gemini failed: %s - no fallback was allowed" % (tier2.get("failed_why") or "no answer")}
        items += f2_items
        calls += f2_calls
    elif 2 in tiers:
        hard_slots = {(it["group"], it["slot"]) for it in items if it["kind"] == "measured" and it["ok"] is False and it["group"]}
        model_bad = {(it["group"], it["slot"]) for it in items if it["kind"] == "model" and it["ok"] is False and it["group"]}
        model_seen = {(it["group"], it["slot"]) for it in items if it["kind"] == "model" and it["group"]}
        disagree = (hard_slots & (model_seen - model_bad)) | (model_bad - hard_slots)
        if float(cloud_dollars or 0) <= 0:
            tier2["why"] = "off: the request's cloud_dollars is 0"
        elif not hard_slots and not disagree:
            tier2["why"] = "not needed: no hard finding and the tiers agree"
        else:
            name_paid = cloud_backend or t2.get("backend") or "anthropic"
            if name_paid == t2.get("backend"):
                model_paid = t2.get("model")
            else:   # pass 98 review: a paid eye named by hand takes its own model from tiers["2"].alternates, never the table's Gemini id
                alt = [a for a in (t2.get("alternates") or {}).values() if isinstance(a, dict) and a.get("backend") == name_paid]
                model_paid = alt[0].get("model") if alt else None
            be2 = backend_for(name_paid, model_paid)
            want = sorted(hard_slots | disagree)
            cells = []
            for gd in gdata:
                slots = sorted({s for (grp, s) in want if grp == gd["label"]})
                near = set()
                for s in slots:
                    near.update(k for k in (s - 1, s, s + 1) if 0 <= k < gd["n"])
                for s in sorted(near):
                    cells.append(("%s/%d" % (gd["label"], s), gd["label"], s, gd["cells"][s]))
            if cells:
                sheet_img, where = decision_sheet(cells)
                ent = {"image": sheet_img, "ref": "decision_sheet", "cells": where}
                bud = dict(budget or {})
                bud.setdefault("cloud_dollars", float(cloud_dollars or 0))
                f2 = evaluate([ent], "sheet_blind", be2, request=request, budget=bud, job=job, tier=2, use_cache=use_cache)
                items += f2["items"]
                calls += f2["model_calls"]
                c0 = f2["model_calls"][0] if f2["model_calls"] else {}
                if c0.get("refused") or c0.get("error"):
                    tier2["why"] = ("refused: " + c0["refused"]) if c0.get("refused") else ("no answer: " + c0["error"])
                else:
                    tier2["ran"] = True
                    tier2["cells"] = len(cells)
                if out_dir:
                    sp = os.path.join(out_dir, "decision_sheet.png")
                    os.makedirs(out_dir, exist_ok=True)
                    sheet_img.save(sp)
                    tier2["sheet"] = _rel(sp)
    _stamp_versions(items, gdata)   # pass 98 (lane GEMINI)
    gates = gates_of(items)
    sheet_path = None
    if out_dir and gdata:
        sheet_path = findings_sheet([(gd["label"], gd["cells"]) for gd in gdata], flagged_by_group, os.path.join(out_dir, "findings_sheet.png"))
    findings = {"v": 1, "job": job, "look": {"kind": kind, "id": cid, "code": code}, "model_calls": calls, "items": items, "gates": gates,
                "sheet": _rel(sheet_path) if sheet_path else None, "tiers": tiers, "tier2": tier2, "request": request, "time": _now(),
                "groups": [{"label": gd["label"], "n": gd["n"], "repairable": gd["repairable"], "method": gd["method"],
                            "flagged": sorted(flagged_by_group.get(gd["label"], set()))} for gd in gdata],
                "dollars": round(sum(float(c.get("dollars") or 0) for c in calls), 6)}
    findings["summary"] = summary_line(findings)
    if be2_free is not None:   # pass 98 (lane GEMINI): the eye's line ("Gemini flagged 3 frames in run/side") on the record
        findings["eyes"] = {"gemini" if be2_free.name == "antigravity" else be2_free.name: {"line": tier2.get("line") or eyes_line(tier2), "flagged": tier2.get("flagged") or {},
                                                                                           "model": be2_free.model, "backend": be2_free.name}}
        findings["agreed"] = sorted([list(x) for x in agreed_frames(findings)])
        findings["summary"] += "; " + (tier2.get("line") or eyes_line(tier2))
        findings["eye"] = "gemini"
        if fallback:   # Garry: the fallback is surfaced as an error, everywhere the findings go
            findings["eye"] = "local (fallback)" if fallback.get("frames") else "none"
            findings["gemini_error"] = fallback["why"]
            findings["fallback"] = fallback
            findings["summary"] += "; " + fallback["line"]
    if out_dir:
        _save_json(os.path.join(out_dir, "findings.json"), findings)
        findings["file"] = _rel(os.path.join(out_dir, "findings.json"))
    return findings


def summary_line(findings):
    """One line for the job's notes and the request card."""
    g = findings.get("gates") or {}
    by_group = {}
    for it in findings.get("items") or []:
        if it.get("kind") == "measured" and it.get("ok") is False:
            by_group.setdefault(it.get("group") or "stills", set()).add("%s %s" % (it.get("slot") if it.get("slot") is not None else "", it.get("field")))
    where = "; ".join("%s: %s" % (k, ", ".join(sorted(v))) for k, v in sorted(by_group.items())) or "no hard finding"
    calls = findings.get("model_calls") or []
    models = {}
    for c in calls:
        models.setdefault("%s (tier %s)" % (c.get("model"), c.get("tier", "?")), 0)
        models["%s (tier %s)" % (c.get("model"), c.get("tier", "?"))] += 1
    eyes = ", ".join("%s x%d" % (k, v) for k, v in sorted(models.items())) or "no model asked"
    t2 = findings.get("tier2") or {}
    t2s = ("tier 2 ran on %d cells" % t2.get("cells", 0)) if t2.get("ran") else ("tier 2 %s" % t2["why"] if t2.get("why") else "")
    return "findings: %d hard, %d advisory (%s); %s; %s$%.4f" % (int(g.get("hard_failures", 0)), int(g.get("advisory", 0)), where, eyes,
                                                                (t2s + "; ") if t2s else "", float(findings.get("dollars") or 0.0))


def findings_of_job(job_id, jobs_dir=None):
    """A job's findings.json (the evaluate kind writes it beside its evaluate.json)."""
    p = os.path.join(jobs_dir or JOBS_DIR, str(job_id), "findings.json")
    return _load_json(p, None)


# ---------------------------------------------------------------- the CLI (the evaluate job)

def run_job(path):
    """tools/level_editor/jobs.py's evaluate kind: <job_dir>/evaluate.json -> findings.json + findings_sheet.png beside it,
    the sidecar result.json (ASSET_JOB_SIDECAR) with info.findings / info.gates / info.summary / info.outputs."""
    with open(path, "r", encoding="utf-8") as f:
        j = json.load(f)
    out_dir = j.get("out") or os.path.dirname(os.path.abspath(path))
    tiers = j.get("tiers") or [0, 1]
    if isinstance(tiers, str):
        tiers = [int(x) for x in tiers.split(",") if x.strip()]
    groups = j.get("groups") or None
    if isinstance(groups, str):
        groups = [x.strip() for x in groups.split(",") if x.strip()]
    be = j.get("backend") or None
    if be == "fake":
        be = FakeBackend([json.dumps({"legs": 8, "arms": 0, "broken": False, "ghost": False, "face": "ok", "smear": False, "colour": False, "note": "fine"})])
    # pass 98 (lane GEMINI): the tier-2 eye named by the job (antigravity: Check with Gemini, Ask Gemini), the frames in
    # scope (flagged | all | slots), the request's calls left, a fresh look (no cache); absent = pass 96's job exactly
    kw = {}
    if j.get("scope"):
        kw["scope"] = str(j["scope"])
    if j.get("slots"):
        sl = j["slots"]
        if isinstance(sl, list):
            sl = {(groups or ["?"])[0]: sl}
        kw["slots"] = {str(k): [int(x) for x in v] for k, v in (sl or {}).items()}
    cb = j.get("cloud_backend") or None
    if cb == "fake_agy":   # the selftests' stand-in for agy.exe (never the real one)
        if not os.environ.get("AGY_FAKE_EXE"):
            raise ValueError("cloud_backend fake_agy needs AGY_FAKE_EXE (the stand-in script)")
        cb = AgyBackend(exe=os.environ["AGY_FAKE_EXE"])
    bud = None
    if j.get("calls_left") not in (None, "", -1):
        bud = {"calls_left": int(j["calls_left"])}
    f = evaluate_look(str(j.get("kind")), str(j.get("id")), str(j.get("code")), tiers=tiers, groups=groups, backend=be, model=j.get("model") or None,
                      request=j.get("request") or None, cloud_dollars=float(j.get("cloud_dollars") or 0.0), out_dir=out_dir, job=j.get("job") or os.environ.get("ASSET_JOB_ID"),
                      cloud_backend=cb, budget=bud, use_cache=not j.get("fresh"), allow_fallback=j.get("fallback", True) is not False, **kw)
    log("evaluate: %s %s %s: %s" % (j.get("kind"), j.get("id"), j.get("code"), f["summary"]))
    log("evaluate: wrote %s" % f.get("file"))
    sidecar = os.environ.get("ASSET_JOB_SIDECAR")
    if sidecar:
        outs = []
        if f.get("sheet"):
            outs.append({"file": f["sheet"], "label": "findings sheet", "type": "sheet"})
        if (f.get("tier2") or {}).get("sheet"):
            outs.append({"file": f["tier2"]["sheet"], "label": "decision sheet (tier 2)", "type": "sheet"})
        for sh in (f.get("tier2") or {}).get("sheets") or []:   # pass 98 (lane GEMINI): the sheets Gemini was shown
            outs.append({"file": sh["file"], "label": "Gemini's sheet (%d frames: %s)" % (sh["cells"], ", ".join(sh.get("groups") or [])), "type": "sheet"})
        _save_json(sidecar, {"tool": "vision_eval", "call": "evaluate_look", "info": {"findings": f.get("file"), "sheet": f.get("sheet"), "gates": f["gates"],
                                                                                      "summary": f["summary"], "outputs": outs, "dollars": f.get("dollars", 0.0),
                                                                                      "model_calls": len(f.get("model_calls") or []), "tier2": f.get("tier2"),
                                                                                      "eyes": f.get("eyes"), "agreed": f.get("agreed"), "eye": f.get("eye"),
                                                                                      "gemini_error": f.get("gemini_error"), "fallback": f.get("fallback")}})
    return f


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="the visual evaluator: a look through the tiers, or one job file")
    ap.add_argument("--job", help="a Level Editor evaluate job's evaluate.json")
    ap.add_argument("--kind")
    ap.add_argument("--id")
    ap.add_argument("--code")
    ap.add_argument("--tiers", default="0,1")
    ap.add_argument("--groups", default="", help="run/side,die/front (empty = every group)")
    ap.add_argument("--backend", default="", help="openai_chat | anthropic | gemini | fake (tier 1's; empty = the tier table's)")
    ap.add_argument("--cloud-backend", default="", help="pass 98: tier 2's eye (antigravity = Gemini through agy; empty = the tier table's)")
    ap.add_argument("--scope", default="flagged", help="pass 98: tier 2's frames: flagged (+ a clean one a group) | all")
    ap.add_argument("--model", default="")
    ap.add_argument("--cloud-dollars", type=float, default=0.0)
    ap.add_argument("--request", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--ledger", action="store_true", help="print the ledger's totals and stop")
    ap.add_argument("--keys", action="store_true", help="say which key files exist and stop")
    ap.add_argument("--agy-health", action="store_true", help="pass 98: the Gemini eye (agy.exe, its read rule, today's calls) without a call")
    ap.add_argument("--agy-rule", action="store_true", help="pass 98: append the inbox's read rule to agy's settings.json (a backup first) and stop")
    a = ap.parse_args(argv)
    if a.ledger:
        log(json.dumps(ledger_totals(), indent=1))
        return 0
    if a.keys:
        log(json.dumps(keys_status(), indent=1))
        return 0
    if a.agy_health:
        log(json.dumps(agy_health(), indent=1))
        return 0
    if a.agy_rule:
        log(json.dumps(ensure_agy_rule(), indent=1))
        return 0
    if a.job:
        run_job(a.job)
        return 0
    if not (a.kind and a.id and a.code):
        ap.error("--kind, --id and --code are needed (or --job)")
    f = evaluate_look(a.kind, a.id, a.code, tiers=[int(x) for x in a.tiers.split(",") if x.strip()], groups=[x for x in a.groups.split(",") if x.strip()] or None,
                      backend=a.backend or None, model=a.model or None, request=a.request or None, cloud_dollars=a.cloud_dollars,
                      out_dir=a.out or None, cloud_backend=a.cloud_backend or None, scope=a.scope)
    log(f["summary"])
    if f.get("file"):
        log("wrote " + f["file"])
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:   # noqa: BLE001
        pass
    sys.exit(main())
