"""ComfyUI client and workflow builders for the 88fits art pipeline (design bible section 15).

Everything runs on the AI server's ComfyUI (Flux.2 on a 32 GB R9700). Three workflows, all built here as
plain node graphs so they can be queued through the API *and* exported as JSON files that open in the
ComfyUI browser UI (tools/comfy_workflows/*.json, written by `python tools/comfy.py --export`):

  klein(...)      Flux.2 Klein 9B distilled: text (+ up to 4 reference images) -> image. 4 steps, cfg 1, euler,
                  Flux2Scheduler. References go through ImageScaleToTotalPixels -> VAEEncode -> ReferenceLatent on
                  both the positive and the zeroed negative, exactly like the official Klein edit template.
  flux2_dev(...)  Flux.2 dev (32B fp8) with the Turbo LoRA: FluxGuidance 4, BasicGuider, 8 steps. Slower, richer;
                  used when Klein is not enough (style anchor candidates).
  animate.wan_i2v Wan 2.2 14B image-to-video (tools/animate.py): a still becomes a run cycle; exported as 05_run_cycle_wan22.json.

Graph nodes are added with Graph.add(class_type, **inputs); an input value that is a (node_id, slot) tuple is a link.
"""
import atexit, io, json, os, re, sys, threading, time, urllib.parse, urllib.request, uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
try:   # pass 97 (lane SAFE): the hosts from tools/ai_hosts.json; COMFY_SERVER and --server= still win; the old literals when absent
    import ai_hosts as _ai_hosts
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import ai_hosts as _ai_hosts
SERVER = os.environ.get("COMFY_SERVER", _ai_hosts.get("comfy", "http://192.168.137.54:8188"))
for _a in sys.argv:
    if _a.startswith("--server="):
        SERVER = _a.split("=", 1)[1]

# ---------------------------------------------------------------- the one-job-at-a-time lock (pass 66)
# One ComfyUI job at a time across Claude's scripts and the Level Editor's jobs queue: tools/dl/locks/comfy.lock
# (tools/locks.py). The lock is taken for the WHOLE PROCESS, lazily, on the first call that touches /prompt, /free,
# /interrupt, /queue, /upload/image or the ssh restart (so release_models() and run_dev()'s restart can never hit another
# script's render), and released at exit. It is reentrant, and a child told LOCK_HELD_COMFY=1 (or the older
# COMFY_LOCK_HELD=1) by the holder passes straight through. No command line changes: every script that imports this
# module takes it on its own. Scripts from older checkouts do not know the lock.
LOCKED_PATHS = ("/prompt", "/free", "/interrupt", "/queue", "/upload/image")
_LOCK = None
_LOCK_GUARD = threading.Lock()
_LAST_BEAT = 0.0
BEAT_SECONDS = 30.0


def _lock_who():
    base = os.path.basename(sys.argv[0]) if sys.argv and sys.argv[0] else "comfy.py"
    return (base + " " + " ".join(sys.argv[1:])[:60]).strip()


def ensure_lock():
    """Take the comfy lock for this process (waits as long as it takes, saying who holds it); a no-op once held."""
    global _LOCK
    if _LOCK is not None:
        return _LOCK
    with _LOCK_GUARD:
        if _LOCK is not None:
            return _LOCK
        try:
            import locks
        except ImportError:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import locks
        _LOCK = locks.acquire("comfy", who=_lock_who(), job=os.environ.get("ASSET_JOB_ID", ""))
        atexit.register(release_lock)
        return _LOCK


def release_lock():
    """Let the comfy lock go (atexit does this; a script that wants to free the server early may call it)."""
    global _LOCK
    lk, _LOCK = _LOCK, None
    if lk is not None:
        try:
            lk.release()
        except Exception:
            pass


def _beat():
    """Refresh the lock's heartbeat now and then while a long render runs."""
    global _LAST_BEAT
    if _LOCK is None:
        return
    now = time.time()
    if now - _LAST_BEAT >= BEAT_SECONDS:
        _LAST_BEAT = now
        try:
            _LOCK.beat()
        except Exception:
            pass

KLEIN_UNET = "flux-2-klein-9b-fp8.safetensors"
KLEIN_CLIP = "qwen_3_8b_fp8mixed.safetensors"
FLUX2_UNET = "flux2_dev_fp8mixed.safetensors"
FLUX2_CLIP = "mistral_3_small_flux2_fp8.safetensors"
FLUX2_TURBO_LORA = "Flux2TurboComfyv2.safetensors"
VAE = "flux2-vae.safetensors"

_OBJECT_INFO = None


# ---------------------------------------------------------------- http

def get(path, timeout=120):
    return json.load(urllib.request.urlopen(SERVER + path, timeout=timeout))


def post(path, obj, timeout=120):
    if path.split("?", 1)[0] in LOCKED_PATHS:
        ensure_lock()
    req = urllib.request.Request(SERVER + path, data=json.dumps(obj).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


# ---------------------------------------------------------------- the page's own Workflows sidebar (user data)
# pass 66 follow-up (Garry: "I want to be able to click a link and open the ComfyUI page with the workflow and
# everything"): every workflow a job runs is also saved into the server's user data, workflows/88fits/<job folder>/,
# where the ComfyUI page lists it in its Workflows sidebar; the 88fits_open web extension (tools/comfy_ext/88fits_open,
# installed by `python tools/comfy.py --install-ext`) opens one straight from a link: <server>/?open=<that path>.

USER_FOLDER = "workflows/88fits"
EXT_NAME = "88fits_open"


def safe_name(name, default="job"):
    """A user-data file or folder name from any text: letters, digits, - _ . and spaces as _, at most 80 characters."""
    out = "".join(c if (c.isalnum() or c in "-_.") else "_" for c in str(name or "").strip())
    out = re.sub(r"_+", "_", out).strip("._")
    return out[:80] or default


def user_workflow_path(folder, stem):
    """workflows/88fits/<folder>/<stem>.json: where a job's workflow sits in the page's sidebar (`folder` may nest:
    goblin_GOB-E/j20261011-..., one sub-folder per job)."""
    parts = [safe_name(x) for x in str(folder or "").split("/") if x.strip()] or ["job"]
    return "%s/%s/%s.json" % (USER_FOLDER, "/".join(parts), safe_name(stem))


def wait_idle(timeout=1800, poll=5):
    """Wait until the server's own queue is empty (something Garry queued by hand on the page is never cut by a
    restart); True when idle, False after `timeout` seconds."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            q = get("/queue", timeout=10)
            if not q.get("queue_running") and not q.get("queue_pending"):
                return True
        except Exception:
            return True   # no answer: nothing to wait for
        time.sleep(poll)
    return False


def put_user_workflow(path, workflow, timeout=30):
    """Save a UI-format workflow into the page's user data (POST /api/userdata/<path>, the folders made on the way);
    returns the server's record {path, size, modified, created}. No lock: the user-data route never touches the queue."""
    url = SERVER + "/api/userdata/" + urllib.parse.quote(path, safe="") + "?overwrite=true&full_info=true"
    req = urllib.request.Request(url, data=json.dumps(workflow).encode("utf-8"), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def open_url(path, server=None):
    """The link that opens the ComfyUI page on that saved workflow (read by the 88fits_open extension)."""
    return (server or SERVER).rstrip("/") + "/?open=" + urllib.parse.quote(path, safe="")


def extension_installed(timeout=5):
    """True when the page lists the 88fits_open extension (GET /api/extensions), False when it does not, None when the
    server did not answer."""
    try:
        files = json.load(urllib.request.urlopen(SERVER + "/api/extensions", timeout=timeout))
    except Exception:
        return None
    return any(("/" + EXT_NAME + "/") in str(f) for f in files)


def install_extension(restart=True):
    """Copy tools/comfy_ext/88fits_open to the server's custom_nodes (scp over the ssh key) and restart ComfyUI under
    the lock so the page loads it (a web extension is read at start-up). Returns what happened, as text."""
    import subprocess
    src = os.path.join(REPO, "tools", "comfy_ext", EXT_NAME)
    if not os.path.isdir(src):
        raise RuntimeError("no %s" % src)
    key = SERVER_SSH[SERVER_SSH.index("-i") + 1]
    host = SERVER_SSH[-1]
    cmd = ["scp", "-i", key, "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "-r", src, host + ":~/ai/ComfyUI/custom_nodes/"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError("scp failed: %s" % (r.stderr or r.stdout).strip())
    if not restart:
        return "copied (the page loads it after the next restart)"
    ensure_lock()
    if not wait_idle():
        return "copied, but the server's queue stayed busy for 30 min: not restarted (the page loads it after the next restart)"
    state = restart_server()
    return "copied, %s, extension %s" % (state, "listed" if extension_installed() else "NOT listed yet")


def object_info():
    """Node schemas, cached on disk (tools/dl/object_info.json) so UI export works offline."""
    global _OBJECT_INFO
    if _OBJECT_INFO is None:
        cache = os.path.join(REPO, "tools", "dl", "object_info.json")
        try:
            _OBJECT_INFO = get("/object_info", timeout=180)
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            json.dump(_OBJECT_INFO, open(cache, "w", encoding="utf-8"))
        except Exception:
            _OBJECT_INFO = json.load(open(cache, encoding="utf-8"))
    return _OBJECT_INFO


def upload_name(name, default="upload.png"):
    """The file name an upload goes to ComfyUI under (pass 70): one plain name, never a path. The path's separators and
    every character but letters, digits, - _ . become "_", repeats fold, at most 120 characters, ".png" kept or added.
    The Bandit job had built "buckshot_dwarf_tools/dl/uploads/2d/bandit.png_ref.png" (a picture's path typed into a
    look's Stills field) and /upload/image answered 500; such a name now uploads as
    "buckshot_dwarf_tools_dl_uploads_2d_bandit.png_ref.png". A plain name (style_anchor.png) is unchanged."""
    parts = [x for x in str(name or "").strip().replace("\\", "/").split("/") if x.strip(" .")]
    s = "".join(c if (c.isalnum() and c.isascii()) or c in "-_." else "_" for c in "_".join(parts))
    s = re.sub(r"_+", "_", s).strip("._")
    s = re.sub(r"\.{2,}", ".", s)
    if not s:
        return default
    stem, ext = os.path.splitext(s)
    if ext.lower() != ".png":
        stem, ext = s, ".png"
    return stem[:120 - len(ext)].rstrip("._") + ext


def upload(png_bytes, name, subfolder="88fits"):
    """Upload an image into ComfyUI's input folder; returns the value LoadImage expects. The name is upload_name()'s
    (pass 70: a path or an odd character can never reach the server as a 500)."""
    name = upload_name(name)
    ensure_lock()
    boundary = "----88fits" + uuid.uuid4().hex
    parts = []
    parts.append(b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"image\"; filename=\"" + name.encode() +
                 b"\"\r\nContent-Type: image/png\r\n\r\n" + png_bytes + b"\r\n")
    for k, v in (("subfolder", subfolder), ("overwrite", "true")):
        if k == "subfolder" and not v:
            continue
        parts.append(b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"" + k.encode() + b"\"\r\n\r\n" + v.encode() + b"\r\n")
    body = b"".join(parts) + b"--" + boundary.encode() + b"--\r\n"
    req = urllib.request.Request(SERVER + "/upload/image", data=body, headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    r = json.load(urllib.request.urlopen(req, timeout=120))
    value = (r.get("subfolder", "") + "/" if r.get("subfolder") else "") + r["name"]
    if subfolder:
        _UPLOADED[value] = png_bytes   # pass 71: the bytes a saved workflow's top-level copy is made from (portable_ui)
    return value


# ---------------------------------------------------------------- pass 71 (lane PLE): saved workflows that open clean
# A job uploads its pictures into ComfyUI's input/88fits/ and its graphs name them "88fits/<file>". The API runs them,
# but the page's LoadImage picker lists only the input folder's top level, so a saved workflow opened from the job card
# showed every LoadImage red ("4 errors found, resolve them before running"). The workflow a job SAVES (the UI file and
# its copy in the page's Workflows sidebar; never the graph that runs) names a top-level copy instead: the same bytes
# uploaded again as "<subfolder>_<sha1 10>_<file>", named by its contents, so the saved workflow keeps the exact picture
# even after a later job overwrites the subfolder file.
_UPLOADED = {}        # "88fits/<file>" -> the bytes this process uploaded under it (the last ones)
_TOP_COPIES = {}      # the top-level copies this process made: name -> True


def _input_bytes(value):
    """The bytes of an input picture on the server (GET /view, type input): "<subfolder>/<file>"."""
    sub, name = value.rsplit("/", 1)
    q = urllib.parse.urlencode({"filename": name, "subfolder": sub, "type": "input"})
    return urllib.request.urlopen(SERVER + "/view?" + q, timeout=60).read()


def top_level_input(value):
    """A LoadImage value with a subfolder as a file the page's picker lists: the top-level copy's name (uploaded once
    per content in this process); a value without a subfolder is returned as it is."""
    import hashlib
    v = str(value or "")
    if "/" not in v:
        return v
    data = _UPLOADED.get(v)
    if data is None:
        data = _input_bytes(v)
    sub, name = v.rsplit("/", 1)
    top = upload_name("%s_%s_%s" % (sub.replace("/", "_"), hashlib.sha1(data).hexdigest()[:10], name))
    if top not in _TOP_COPIES:
        top = upload(data, top, subfolder="")
        _TOP_COPIES[top] = True
    return top


def portable_ui(ui):
    """A UI workflow's LoadImage widgets rewritten to top-level copies (top_level_input), in place; a picture that cannot
    be copied keeps its value (the workflow still runs through the API). Returns [(old, new)] for what changed."""
    changed = []
    for node in (ui or {}).get("nodes", []) if isinstance(ui, dict) else []:
        if node.get("type") != "LoadImage":
            continue
        wv = node.get("widgets_values")
        if not isinstance(wv, list) or not wv or not isinstance(wv[0], str) or "/" not in wv[0]:
            continue
        try:
            new = top_level_input(wv[0])
        except Exception as e:
            print("comfy: %s stays as it is in the saved workflow (%s)" % (wv[0], e))
            continue
        if new != wv[0]:
            changed.append((wv[0], new))
            wv[0] = new
    return changed


def upload_pil(img, name, subfolder="88fits"):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return upload(buf.getvalue(), name, subfolder)


SERVER_SSH = ["ssh", "-i", os.path.expanduser(_ai_hosts.get("ssh_key", "~/.ssh/id_ed25519_ai_server")), "-o", "ConnectTimeout=10",
              _ai_hosts.get("ssh", "teatree@192.168.137.54")]   # pass 97 (lane SAFE): tools/ai_hosts.json "ssh_key", "ssh"


def server_ram_used_gb():
    """RAM in use on the server (GB), or -1 when ssh fails."""
    import subprocess
    try:
        out = subprocess.run(SERVER_SSH + ["free -g | sed -n 2p"], capture_output=True, text=True, timeout=30).stdout.split()
        return int(out[2])
    except Exception:
        return -1


def release_models():
    """Flux.2 dev (35 GB) and its text encoder (18 GB) do not both fit the server's 47 GB of RAM twice over: after a
    render, ask ComfyUI to unload, and if the RAM does not come back restart the service (about 20 s)."""
    import subprocess
    try:
        post("/free", {"unload_models": True, "free_memory": True})
    except Exception:
        pass
    time.sleep(6)
    if server_ram_used_gb() > 20:
        return restart_server()
    return "freed"


def restart_server():
    """Restart the ComfyUI service and wait until it answers (about 20 s). Uploaded references live in its input folder
    and survive the restart."""
    import subprocess
    ensure_lock()
    try:
        # a server thrashing its swap can take minutes to stop: wait for systemd rather than give up after one
        subprocess.run(SERVER_SSH + ["systemctl --user restart ai-comfyui.service"], capture_output=True, timeout=300)
    except subprocess.TimeoutExpired:
        pass
    for _ in range(80):
        time.sleep(3)
        try:
            get("/system_stats")
            return "restarted"
        except Exception:
            continue
    raise RuntimeError("ComfyUI did not come back after the restart")


def run_dev(graph, timeout=1500, tries=2):
    """A Flux.2 dev render on a freshly started server (pass 46: the third dev render in one process sat for half an hour
    loading the models into a full RAM, then timed out and blocked the queue behind it), retried once after a restart
    when it times out."""
    for attempt in range(tries):
        restart_server()
        try:
            return run(graph, timeout=timeout)
        except RuntimeError as e:
            if "timeout" not in str(e) or attempt == tries - 1:
                raise
            try:
                post("/queue", {"clear": True})
                post("/interrupt", {})
            except Exception:
                pass


def save_job_workflow(graph):
    """Under a Level Editor job (ASSET_JOB_SIDECAR set), every graph that runs is kept beside the job as a ComfyUI
    workflow file (`<job>/workflows/NN_<prefix>_workflow.json`, drag it into the ComfyUI page) and its API form, so
    Garry can open exactly what ran (pass 66 follow-up)."""
    side = os.environ.get("ASSET_JOB_SIDECAR", "")
    if not side:
        return None
    try:
        d = os.path.join(os.path.dirname(side), "workflows")
        os.makedirs(d, exist_ok=True)
        n = len([f for f in os.listdir(d) if f.endswith("_workflow.json")]) + 1
        prefix = "graph"
        for node in graph.api().values():
            if node.get("class_type") in ("SaveImage", "SaveAudio", "SaveGLB"):
                prefix = str(node.get("inputs", {}).get("filename_prefix", "graph")).split("/")[-1]
        stem = "%02d_%s" % (n, "".join(c if c.isalnum() or c in "-_" else "_" for c in prefix)[:60])
        ui = graph.ui_workflow()
        portable_ui(ui)   # pass 71: LoadImage names a top-level copy the page's picker lists (the graph that runs keeps its own)
        with open(os.path.join(d, stem + "_workflow.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(ui, f, indent=1)
        with open(os.path.join(d, stem + "_api.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(graph.api(), f, indent=1)
        # the same workflow into the page's Workflows sidebar (workflows/88fits/<job folder>/<stem>.json), the marker
        # the job card reads (jobs._harvest: "open in ComfyUI"); a server that does not answer leaves no marker and the
        # card offers "Send to ComfyUI" later
        folder = os.environ.get("ASSET_JOB_NAME") or os.environ.get("ASSET_JOB_ID") or "job"
        upath = user_workflow_path(folder, stem)
        try:
            rec = put_user_workflow(upath, ui)
            with open(os.path.join(d, stem + "_userdata.json"), "w", encoding="utf-8", newline="\n") as f:
                json.dump({"path": upath, "open": open_url(upath), "server": rec}, f, indent=1)
        except Exception as e:
            print("comfy: the workflow was not saved into the page's sidebar (%s)" % e)
        return stem
    except Exception:
        return None


# ---------------------------------------------------------------- pass 97 (lane PROGRESS, WF-07): live progress from /ws
# ComfyUI tells the client that queued a prompt what it runs over its WebSocket (ws://<server>/ws?clientId=<id>, the
# same id the POST /prompt carried): `executing` {node, prompt_id} when a node starts (node None = the prompt is done),
# `progress` {node, prompt_id, value, max} for a sampler's steps, `execution_error` {prompt_id, node_id, node_type,
# exception_type, exception_message, ...}, `execution_success`, `execution_cached`, `status`, and binary preview frames
# (ignored). The shapes are ComfyUI's documented protocol (docs: development/comfyui-server/comms_messages); a live
# capture on the AI server (pass 97, idle) recorded the `status` message on connect; the recorded fixture the selftest
# replays is tools/level_editor/testdata/comfy_ws/. This thread only PRINTS lines for the Level Editor's parser:
#     comfy: <prompt_id> <node title> <value>/<max>     at most one line per PROGRESS_SECONDS, and at once on a new node
#     comfy: <prompt_id> error <node_type> #<node>: <exception_type>: <message>      at once on execution_error
# (a node without steps prints 0/0). The node title is Graph.add's `_title`, else the class_type. Nothing waits on it:
# /history stays the completion authority; a socket that fails is tried again at most PROGRESS_RECONNECTS times and then
# the thread goes quiet; it closes when run() returns. On only under a Level Editor job (ASSET_JOB_ID or
# ASSET_JOB_SIDECAR set) or with COMFY_PROGRESS=1; COMFY_PROGRESS=0 turns it off.

PROGRESS_SECONDS = 2.0
PROGRESS_RECONNECTS = 2
_PRINT_LOCK = threading.Lock()


def progress_enabled():
    flag = os.environ.get("COMFY_PROGRESS", "").strip()
    if flag in ("0", "off", "no", "false"):
        return False
    return flag in ("1", "on", "yes", "true") or bool(os.environ.get("ASSET_JOB_ID") or os.environ.get("ASSET_JOB_SIDECAR"))


def _ws_backend():
    """(name, connect) for the first WebSocket client that imports: websocket-client, else websockets' sync client;
    None when neither does (then no thread: /history alone, as before pass 97). connect(url, timeout) returns an object
    with recv(timeout) -> (kind "text"|"binary", payload) or None on a timeout, and close()."""
    try:
        import websocket as _wsc   # websocket-client
        if hasattr(_wsc, "create_connection"):
            def connect_wsc(url, timeout):
                return _WscConn(_wsc, _wsc.create_connection(url, timeout=timeout))
            return "websocket-client", connect_wsc
    except Exception:   # noqa: BLE001
        pass
    try:
        from websockets.sync.client import connect as _wss_connect   # websockets >= 11

        def connect_wss(url, timeout):
            return _WssConn(_wss_connect(url, open_timeout=timeout, close_timeout=1, max_size=None))
        return "websockets", connect_wss
    except Exception:   # noqa: BLE001
        pass
    return None


class _WscConn:
    def __init__(self, mod, ws):
        self.mod, self.ws = mod, ws

    def recv(self, timeout):
        self.ws.settimeout(timeout)
        try:
            op, data = self.ws.recv_data()
        except self.mod.WebSocketTimeoutException:
            return None
        if op == self.mod.ABNF.OPCODE_TEXT:
            return "text", data.decode("utf-8", "replace")
        if op == self.mod.ABNF.OPCODE_CLOSE:
            raise ConnectionError("closed by the server")
        return "binary", data

    def close(self):
        try:
            self.ws.close(timeout=1)
        except Exception:   # noqa: BLE001
            pass


class _WssConn:
    def __init__(self, ws):
        self.ws = ws

    def recv(self, timeout):
        try:
            data = self.ws.recv(timeout=timeout)
        except TimeoutError:
            return None
        return ("text", data) if isinstance(data, str) else ("binary", data)

    def close(self):
        try:
            self.ws.close()
        except Exception:   # noqa: BLE001
            pass


class ProgressWatch:
    """One run()'s listener (a daemon thread). set_prompt(pid) after the POST; close() when run() returns."""

    def __init__(self, client_id, graph=None, server=None, backend=None, out=None, seconds=None, reconnects=None):
        self.client_id = client_id
        self.url = (server or SERVER).replace("https://", "wss://").replace("http://", "ws://").rstrip("/") + "/ws?clientId=" + client_id
        self.titles = {}
        try:
            for nid, node in (graph.api() if graph is not None else {}).items():
                self.titles[str(nid)] = str((graph.titles or {}).get(nid) or node.get("class_type") or nid)
        except Exception:   # noqa: BLE001
            pass
        self.backend = backend if backend is not None else _ws_backend()
        self.out = out   # a callable taking one line (the selftest); default: stdout
        self.seconds = PROGRESS_SECONDS if seconds is None else float(seconds)
        self.reconnects = PROGRESS_RECONNECTS if reconnects is None else int(reconnects)
        self.prompt = None
        self.connects = 0          # successful connections (the selftest reads these)
        self.failures = 0
        self.lines = []            # what it printed
        self.gave_up = False
        self._stop = threading.Event()
        self._released = threading.Event()   # set_prompt ran: the `comfy: prompt` line is out, ours may follow
        self._conn = None
        self._node = None          # (prompt, node id) printed last
        self._node_since = 0.0
        self._last_print = 0.0
        self._pending = None       # the newest state not printed yet (throttled)
        self._printed_state = None
        self._done_prompts = set()
        self.thread = threading.Thread(target=self._main, name="comfy-progress", daemon=True)

    def start(self):
        if self.backend is None:
            return self
        self.thread.start()
        return self

    def set_prompt(self, pid):
        self.prompt = str(pid)
        self._released.set()

    def close(self, wait=0.0):
        """Stop listening; the thread closes its socket itself within a quarter second (run() never waits for the
        closing handshake)."""
        self._stop.set()
        self._released.set()
        if wait and self.thread.is_alive() and threading.current_thread() is not self.thread:
            self.thread.join(wait)

    # -- the thread ----------------------------------------------------------------------------------------------
    def _main(self):
        tries = 0
        while not self._stop.is_set():
            try:
                self._conn = self.backend[1](self.url, 5.0)
            except Exception:   # noqa: BLE001  (refused, no upgrade, no route: /history goes on alone)
                self._conn = None
                self.failures += 1
                tries += 1
                if tries > self.reconnects or self._stop.wait(min(1.0 * tries, 3.0)):
                    self.gave_up = not self._stop.is_set()
                    return
                continue
            self.connects += 1
            try:
                self._listen()
            except Exception:   # noqa: BLE001  (dropped mid-render: try again, at most `reconnects` times in all)
                pass
            finally:
                c, self._conn = self._conn, None
                if c is not None:
                    c.close()
            if self._stop.is_set():
                return
            self.failures += 1
            tries += 1
            if tries > self.reconnects or self._stop.wait(min(1.0 * tries, 3.0)):
                self.gave_up = not self._stop.is_set()
                return

    def _listen(self):
        while not self._stop.is_set():
            got = self._conn.recv(0.25)
            self._flush()
            if got is None:
                continue
            kind, payload = got
            if kind != "text":
                continue   # a preview picture
            try:
                msg = json.loads(payload)
            except ValueError:
                continue
            self._on_message(msg)

    def _on_message(self, msg):
        if not isinstance(msg, dict):
            return
        typ, data = msg.get("type"), msg.get("data") if isinstance(msg.get("data"), dict) else {}
        pid = str(data.get("prompt_id") or "")
        if self.prompt and pid and pid != self.prompt:
            return   # another prompt on this socket (an earlier run's, a reconnect's replay)
        if typ == "execution_error":
            node = str(data.get("node_id") or "")
            text = "%s #%s: %s: %s" % (data.get("node_type") or self.titles.get(node, "?"), node, data.get("exception_type") or "error",
                                       data.get("exception_message") or "")
            text = " ".join(str(text).split())[:300]
            self._pending = None
            self._emit("comfy: %s error %s" % (pid or self.prompt or "?", text), force=True)
            self._done_prompts.add(pid)
        elif typ == "executing":
            node = data.get("node")
            if node is None:
                self._done_prompts.add(pid)
                self._flush(force=True)
                return
            self._state(pid, str(node), 0, 0)
        elif typ == "progress":
            node = data.get("node")
            try:
                v, mx = int(data.get("value") or 0), int(data.get("max") or 0)
            except (TypeError, ValueError):
                return
            self._state(pid, str(node) if node is not None else (self._node[1] if self._node else "?"), v, mx)
        elif typ in ("execution_success", "execution_interrupted"):
            self._done_prompts.add(pid)
            self._flush(force=True)

    def _state(self, pid, node, value, mx):
        key = (pid or self.prompt or "?", node)
        new_node = key != self._node
        if new_node:
            # the node that ran before may have a step not printed yet: let it go (the new node is the news)
            self._node = key
            self._node_since = time.time()
        self._pending = (key[0], node, value, mx)
        if new_node:
            self._flush(force=True)

    def _flush(self, force=False):
        st = self._pending
        if st is None or st == self._printed_state:
            return
        if not force and time.time() - self._last_print < self.seconds:
            return
        if not self._released.is_set():
            return   # the `comfy: prompt <id>` line is not out yet: ours wait (the pending state is kept)
        pid, node, value, mx = st
        self._printed_state = st
        self._pending = None
        self._emit("comfy: %s %s %d/%d" % (pid, self.titles.get(node, node), value, mx))

    def _emit(self, line, force=False):
        if not force and self._stop.is_set():
            return
        if not self._released.is_set() and not force:
            return
        self.lines.append(line)
        self._last_print = time.time()
        try:
            if self.out is not None:
                self.out(line)
            else:
                with _PRINT_LOCK:
                    sys.stdout.write(line + "\n")   # one write: never split by another thread's print
                    sys.stdout.flush()
        except Exception:   # noqa: BLE001
            pass


def progress_watch(client_id, graph=None):
    """The started ProgressWatch for a run, or None (outside a Level Editor job, COMFY_PROGRESS=0, no WebSocket library)."""
    if not progress_enabled():
        return None
    try:
        w = ProgressWatch(client_id, graph)
        if w.backend is None:
            return None
        return w.start()
    except Exception:   # noqa: BLE001  (the watch must never stop a render)
        return None


def run(graph, timeout=1200):
    """Queue a graph and wait for its SaveImage outputs. Returns (list of png bytes, seconds).
    pass 97 (lane PROGRESS, WF-07): under a Level Editor job a daemon thread also listens on ComfyUI's /ws for this
    client id and prints `comfy: <prompt> <node> <value>/<max>` lines (progress_watch); /history below stays the one
    completion authority, and the whole mechanism when the socket fails."""
    save_job_workflow(graph)
    client_id = "88fits-" + uuid.uuid4().hex[:8]
    watch = progress_watch(client_id, graph)   # None outside a Level Editor job (a hand run prints what it always printed)
    try:
        r = post("/prompt", {"prompt": graph.api(), "client_id": client_id})
        if r.get("error") or r.get("node_errors"):
            raise RuntimeError("ComfyUI rejected the graph: " + json.dumps({"error": r.get("error"), "node_errors": r.get("node_errors")})[:1500])
        pid = r["prompt_id"]
        print("comfy: prompt %s" % pid, flush=True)   # pass 96 (WF-06c): the Level Editor keeps it, so a cancel deletes this prompt alone
        if watch is not None:
            watch.set_prompt(pid)
        t0 = time.time()
        while True:
            time.sleep(1.0)
            _beat()
            h = get("/history/" + pid)
            if pid in h:
                st = h[pid].get("status", {})
                if st.get("status_str") == "error":
                    raise RuntimeError("ComfyUI error: " + json.dumps(st.get("messages"))[:1500])
                out = []
                for o in h[pid].get("outputs", {}).values():
                    for im in o.get("images", []):
                        if im.get("type") != "output":
                            continue
                        url = SERVER + "/view?filename=%s&subfolder=%s&type=%s" % (urllib.parse.quote(im["filename"]), urllib.parse.quote(im["subfolder"]), im["type"])
                        out.append(urllib.request.urlopen(url, timeout=120).read())
                if not out:
                    raise RuntimeError("ComfyUI produced no image")
                return out, time.time() - t0
            if time.time() - t0 > timeout:
                raise RuntimeError("ComfyUI timeout after %ds" % timeout)
    finally:
        if watch is not None:
            watch.close()


# ---------------------------------------------------------------- graph

class Graph:
    def __init__(self):
        self.nodes = {}
        self.order = []
        self.titles = {}
        self._n = 0

    def add(self, class_type, _title=None, **inputs):
        self._n += 1
        nid = str(self._n)
        conv = {}
        for k, v in inputs.items():
            conv[k] = [str(v[0]), int(v[1])] if isinstance(v, tuple) else v
        self.nodes[nid] = {"class_type": class_type, "inputs": conv}
        self.order.append(nid)
        if _title:
            self.titles[nid] = _title
        return nid

    def api(self):
        return self.nodes

    # -- UI export ------------------------------------------------------------------
    def ui_workflow(self):
        """Convert to the LiteGraph JSON the ComfyUI frontend loads (File > Open / drag and drop)."""
        info = object_info()
        depth = {}

        def d_of(nid):
            if nid in depth:
                return depth[nid]
            best = 0
            for v in self.nodes[nid]["inputs"].values():
                if isinstance(v, list) and len(v) == 2 and str(v[0]) in self.nodes:
                    best = max(best, d_of(str(v[0])) + 1)
            depth[nid] = best
            return best

        for nid in self.order:
            d_of(nid)
        col_count = {}
        nodes_out, links_out = [], []
        link_id = 0
        pending_links = {}   # (target_nid, input_name) -> link id
        outputs_links = {}   # nid -> {slot: [link ids]}
        for nid in self.order:
            for name, v in self.nodes[nid]["inputs"].items():
                if isinstance(v, list) and len(v) == 2 and str(v[0]) in self.nodes:
                    link_id += 1
                    pending_links[(nid, name)] = link_id
                    outputs_links.setdefault(str(v[0]), {}).setdefault(int(v[1]), []).append(link_id)
        for nid in self.order:
            n = self.nodes[nid]
            spec = info.get(n["class_type"], {})
            spec_in = spec.get("input", {})
            ordered = list(spec_in.get("required", {}).items()) + list(spec_in.get("optional", {}).items())
            inputs, widgets = [], []
            for name, s in ordered:
                typ = s[0]
                opts = s[1] if len(s) > 1 and isinstance(s[1], dict) else {}
                is_widget = isinstance(typ, list) or typ in ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO")
                val = n["inputs"].get(name)
                linked = (nid, name) in pending_links
                if linked:
                    inputs.append({"name": name, "type": typ if isinstance(typ, str) else "COMBO", "link": pending_links[(nid, name)]})
                    if is_widget:
                        widgets.append(val if val is not None else opts.get("default"))
                elif is_widget:
                    if val is None:
                        if isinstance(typ, list):
                            val = typ[0] if typ else ""
                        elif typ == "COMBO":
                            val = (opts.get("options") or [""])[0] if not opts.get("default") else opts.get("default")
                        else:
                            val = opts.get("default")
                    widgets.append(val)
                    if name in ("seed", "noise_seed") or opts.get("control_after_generate"):
                        widgets.append("fixed")
                else:
                    inputs.append({"name": name, "type": typ if isinstance(typ, str) else "COMBO", "link": None})
            if n["class_type"] == "LoadImage":
                widgets = [n["inputs"].get("image", ""), "image"]
            outs = []
            for i, t in enumerate(spec.get("output", [])):
                outs.append({"name": (spec.get("output_name") or spec.get("output"))[i], "type": t, "links": outputs_links.get(nid, {}).get(i, []), "slot_index": i})
            d = depth[nid]
            row = col_count.get(d, 0)
            col_count[d] = row + 1
            node = {"id": int(nid), "type": n["class_type"], "pos": [60 + d * 400, 60 + row * 230],
                    "size": [360, 90 + 26 * len(widgets) + 20 * len(inputs)], "flags": {}, "order": self.order.index(nid), "mode": 0,
                    "inputs": inputs, "outputs": outs, "properties": {"Node name for S&R": n["class_type"]}, "widgets_values": widgets}
            if nid in self.titles:
                node["title"] = self.titles[nid]
            nodes_out.append(node)
        for (tnid, name), lid in pending_links.items():
            src = self.nodes[tnid]["inputs"][name]
            spec = info.get(self.nodes[str(src[0])]["class_type"], {})
            typ = (spec.get("output") or ["*"])[int(src[1])] if spec.get("output") else "*"
            tin = [i for i, x in enumerate([ni for ni in nodes_out if ni["id"] == int(tnid)][0]["inputs"]) if x["name"] == name][0]
            links_out.append([lid, int(src[0]), int(src[1]), int(tnid), tin, typ])
        return {"last_node_id": self._n, "last_link_id": link_id, "nodes": nodes_out, "links": links_out, "groups": [],
                "config": {}, "extra": {"88fits": "generated by tools/comfy.py"}, "version": 0.4}


# ---------------------------------------------------------------- workflows

def _refs(g, refs, vae, pos, neg=None, megapixels=1.0):
    for r in refs:
        li = g.add("LoadImage", "reference", image=r)
        sc = g.add("ImageScaleToTotalPixels", image=(li, 0), upscale_method="lanczos", megapixels=megapixels, resolution_steps=1)
        enc = g.add("VAEEncode", pixels=(sc, 0), vae=(vae, 0))
        pos = g.add("ReferenceLatent", conditioning=(pos, 0), latent=(enc, 0))
        if neg is not None:
            neg = g.add("ReferenceLatent", conditioning=(neg, 0), latent=(enc, 0))
    return pos, neg


def _init_latent(g, vae, init, width, height, sig, denoise):
    """pass 94 (lane REAL): img2img. The sampling starts from `init` (an uploaded picture's name) noised to `denoise` (the
    low part of the schedule) instead of from pure noise: the painting keeps the picture's shapes (a model's clay tinted
    like the look). Returns (latent node, sigmas node)."""
    li = g.add("LoadImage", "start picture", image=init)
    sc = g.add("ImageScale", image=(li, 0), upscale_method="lanczos", width=width, height=height, crop="disabled")
    lat = g.add("VAEEncode", pixels=(sc, 0), vae=(vae, 0))
    sp = g.add("SplitSigmasDenoise", sigmas=(sig, 0), denoise=float(denoise))
    return lat, (sp, 1)


def klein(prompt, seed, width=1024, height=1024, refs=(), steps=4, cfg=1.0, prefix="88fits/klein", negative="", init=None, denoise=1.0):
    """Flux.2 Klein 9B distilled. refs: LoadImage names (see upload()). pass 94: `init` + `denoise` < 1: img2img from that
    picture (_init_latent)."""
    g = Graph()
    m = g.add("UNETLoader", "Flux.2 Klein 9B", unet_name=KLEIN_UNET, weight_dtype="default")
    c = g.add("CLIPLoader", "Qwen3 8B text encoder", clip_name=KLEIN_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    if negative:
        neg = g.add("CLIPTextEncode", "negative", clip=(c, 0), text=negative)
    else:
        neg = g.add("ConditioningZeroOut", conditioning=(pos, 0))
    pos, neg = _refs(g, refs, v, pos, neg)
    guider = g.add("CFGGuider", model=(m, 0), positive=(pos, 0), negative=(neg, 0), cfg=cfg)
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=steps, width=width, height=height)
    if init and float(denoise) < 1.0:
        lat, sigs = _init_latent(g, v, init, width, height, sig, denoise)
    else:
        lat, sigs = g.add("EmptyFlux2LatentImage", width=width, height=height, batch_size=1), (sig, 0)
    noise = g.add("RandomNoise", noise_seed=seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=sigs, latent_image=(lat, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


def flux2_dev(prompt, seed, width=1024, height=1024, refs=(), steps=8, guidance=4.0, turbo=True, prefix="88fits/flux2dev", init=None, denoise=1.0):
    """Flux.2 dev with the Turbo LoRA (8 steps) or plain (20 steps). pass 94: `init` + `denoise` as klein()'s."""
    g = Graph()
    m = g.add("UNETLoader", "Flux.2 dev", unet_name=FLUX2_UNET, weight_dtype="default")
    if turbo:
        m = g.add("LoraLoaderModelOnly", "Turbo LoRA", model=(m, 0), lora_name=FLUX2_TURBO_LORA, strength_model=1.0)
    c = g.add("CLIPLoader", "Mistral text encoder", clip_name=FLUX2_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    pos, _ = _refs(g, refs, v, pos, None)
    pos = g.add("FluxGuidance", conditioning=(pos, 0), guidance=guidance)
    guider = g.add("BasicGuider", model=(m, 0), conditioning=(pos, 0))
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=steps if turbo else max(steps, 20), width=width, height=height)
    if init and float(denoise) < 1.0:
        lat, sigs = _init_latent(g, v, init, width, height, sig, denoise)
    else:
        lat, sigs = g.add("EmptyFlux2LatentImage", width=width, height=height, batch_size=1), (sig, 0)
    noise = g.add("RandomNoise", noise_seed=seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=sigs, latent_image=(lat, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


WAN_VACE_HIGH = "wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors"
WAN_VACE_LOW = "wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors"


def wan_fun_vace(prompt, ref_name, ctl_names, mask_names, seed, width=640, height=640, negative="", prefix="88fits/vace", shift=5.0,
                 steps=4, cfg=1.0, lora=True, strength=1.0, length=None):
    """Wan 2.2 Fun VACE 14B (pass 95, lane VACE): a clip with some frames kept and some painted anew. `ctl_names` is
    one picture per frame: a kept frame as it is, a frame to redo as its guide (the driver's depth or pose frame, or
    mid grey for a free fill); `mask_names` one picture per frame, white where the model paints (a redone frame),
    black where it keeps; `ref_name` the painting (the identity). The core WanVaceToVideo node encodes the kept frames
    as the inactive video and the guides as the reactive one, the reference as a latent frame in front (trimmed after
    sampling), and the same two-stage lightx2v 4-step split as the Fun Control walks (tools/animate.wan_fun_control),
    so a repaired stretch comes out of the model family the clip was walked by."""
    import animate
    g = Graph()
    hi = g.add("UNETLoader", "Wan 2.2 Fun VACE high noise", unet_name=WAN_VACE_HIGH, weight_dtype="default")
    lo = g.add("UNETLoader", "Wan 2.2 Fun VACE low noise", unet_name=WAN_VACE_LOW, weight_dtype="default")
    if lora:
        hi = g.add("LoraLoaderModelOnly", "lightx2v high", model=(hi, 0), lora_name=animate.WAN_T2V_LORA_HIGH, strength_model=1.0)
        lo = g.add("LoraLoaderModelOnly", "lightx2v low", model=(lo, 0), lora_name=animate.WAN_T2V_LORA_LOW, strength_model=1.0)
    hi = g.add("ModelSamplingSD3", model=(hi, 0), shift=shift)
    lo = g.add("ModelSamplingSD3", model=(lo, 0), shift=shift)
    clip = g.add("CLIPLoader", "umt5 text encoder", clip_name=animate.WAN_CLIP, type="wan", device="default")
    vae = g.add("VAELoader", vae_name=animate.WAN_VAE)
    pos = g.add("CLIPTextEncode", "motion prompt", clip=(clip, 0), text=prompt)
    neg = g.add("CLIPTextEncode", "negative", clip=(clip, 0), text=negative or animate.NEGATIVE)
    ref = g.add("LoadImage", "reference painting", image=ref_name)
    batch = None
    for k, name in enumerate(ctl_names):
        li = g.add("LoadImage", "frame %02d" % k, image=name)
        batch = li if batch is None else g.add("ImageBatch", image1=(batch, 0), image2=(li, 0))
    mbatch = None
    for k, name in enumerate(mask_names):
        li = g.add("LoadImage", "mask %02d" % k, image=name)
        mbatch = li if mbatch is None else g.add("ImageBatch", image1=(mbatch, 0), image2=(li, 0))
    masks = g.add("ImageToMask", "masks: white = paint anew", image=(mbatch, 0), channel="red")
    n = int(length or len(ctl_names))
    vace = g.add("WanVaceToVideo", positive=(pos, 0), negative=(neg, 0), vae=(vae, 0), width=width, height=height, length=n, batch_size=1,
                 strength=float(strength), control_video=(batch, 0), control_masks=(masks, 0), reference_image=(ref, 0))
    steps = max(2, int(steps))
    half = steps // 2
    s1 = g.add("KSamplerAdvanced", "high noise 0-%d" % half, model=(hi, 0), add_noise="enable", noise_seed=seed, steps=steps, cfg=float(cfg), sampler_name="euler", scheduler="simple",
               positive=(vace, 0), negative=(vace, 1), latent_image=(vace, 2), start_at_step=0, end_at_step=half, return_with_leftover_noise="enable")
    s2 = g.add("KSamplerAdvanced", "low noise %d-%d" % (half, steps), model=(lo, 0), add_noise="disable", noise_seed=0, steps=steps, cfg=float(cfg), sampler_name="euler", scheduler="simple",
               positive=(vace, 0), negative=(vace, 1), latent_image=(s1, 0), start_at_step=half, end_at_step=10000, return_with_leftover_noise="disable")
    trim = g.add("TrimVideoLatent", samples=(s2, 0), trim_amount=(vace, 3))
    dec = g.add("VAEDecode", samples=(trim, 0), vae=(vae, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


def export_workflows(out_dir):
    """Write the three pipeline workflows as ComfyUI UI files, with the real prompts used by tools/gen_art.py."""
    os.makedirs(out_dir, exist_ok=True)
    try:
        import gen_art
        style, bg = gen_art.STYLE, gen_art.BG_GREEN
        anchor_prompt = gen_art.anchor_prompt()
        ex = "a tan coyote creature with sandy fur, tall pointed ears and a mischievous grin with its tongue out"
    except Exception:
        style, bg, anchor_prompt = "Clash Royale style", "flat green background", "style sheet"
        ex = "a goofy coyote"
    # the UI's LoadImage combo only lists top-level input files, so the exported graphs reference top-level copies
    for src, name in ((os.path.join(REPO, "game", "art", "style", "style_anchor.png"), "style_anchor.png"),
                      (os.path.join(REPO, "tools", "dl", "ai_raw2", "drifter_front.png"), "drifter_front.png")):
        if os.path.exists(src):
            try:
                upload(open(src, "rb").read(), name, "")
            except Exception as e:
                print("  (could not upload %s to the server: %s)" % (name, e))
    wf = {
        "01_style_anchor_klein.json": klein(anchor_prompt, 1234, 1536, 768, prefix="88fits/anchor"),
        "02_item_from_anchor_klein.json": klein("Using exactly the same art style as the reference image, draw " + ex + ". Full body, front view, " + style + ". " + bg,
                                                42, 1024, 1024, refs=["style_anchor.png"], prefix="88fits/item"),
        "03_character_back_view_klein.json": klein("Turn this exact character around to show a full back view seen directly from behind. Same outfit, colors and proportions, standing straight. " + bg,
                                                   42, 1024, 1024, refs=["drifter_front.png"], prefix="88fits/back"),
        "04_style_anchor_flux2_dev.json": flux2_dev(anchor_prompt, 1234, 1536, 768, prefix="88fits/anchor_dev"),
    }
    try:
        import animate
        wf["05_run_cycle_wan22.json"] = animate.wan_i2v("A 2D anime game character sprite, running in place at a steady jog, seen in strict side profile facing right. "
                                                        "The character stays exactly in the centre of the frame like on a treadmill, a seamless looping run cycle, "
                                                        "camera locked off, flat solid blue background, no ground, no shadow.", "drifter_side_still.png", 1)
    except Exception as e:
        print("  (no Wan workflow exported: %s)" % e)
    for name, g in wf.items():
        json.dump(g.ui_workflow(), open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="\n"), indent=1)
        print("wrote", os.path.join(out_dir, name))


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if "--export" in sys.argv:
        export_workflows(os.path.join(REPO, "tools", "comfy_workflows"))
    elif "--install-ext" in sys.argv:
        # the 88fits_open web extension onto the server, then a restart under the lock (waits for a running job)
        print(install_extension(restart="--no-restart" not in sys.argv))
    elif "--check-ext" in sys.argv:
        st = extension_installed()
        print("88fits_open:", "installed" if st else ("not installed" if st is False else "the server did not answer"))
    else:
        s = get("/system_stats")
        print("ComfyUI", s["system"].get("comfyui_version"), "on", s["devices"][0].get("name"), "at", SERVER)
        print("diffusion models:", get("/models/diffusion_models"))
