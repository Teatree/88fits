"""The AI hosts in one file (pass 97, lane SAFE; OPS-03): tools/ai_hosts.json, read by comfy.py, jobs.py, server.py,
gen_art.py and vision_eval.py. Standard library only (the Level Editor server imports it).

    {"comfy": "http://192.168.137.54:8188",            ComfyUI on the AI server (comfy.SERVER, jobs.COMFY_SERVER)
     "ssh": "teatree@192.168.137.54",                   the AI server's ssh login (comfy.SERVER_SSH: restarts, RAM, scp)
     "ssh_key": "~/.ssh/id_ed25519_ai_server",          the key that login uses (~ is the user's home)
     "lmstudio": "http://127.0.0.1:1234",               LM Studio on this PC (the vision QA: /v1/models, /v1/chat/completions)
     "ollama": "http://192.168.137.54:11434"}           Ollama on the AI server (doctor.py asks /api/tags)

The rules: an environment variable that overrides a host today still wins (COMFY_SERVER); a key the file lacks, an empty
value, a missing file or a file that is not JSON = the value the reader always had (each reader passes its own old
literal as the default, so with no file everything is as before, and with today's values in the file it is byte for
byte the same). AI_HOSTS_FILE=<path> reads another file (the selftest, doctor.py --root).

    import ai_hosts
    SERVER = os.environ.get("COMFY_SERVER", ai_hosts.get("comfy", "http://192.168.137.54:8188"))
    python tools/ai_hosts.py            # what every reader gets, and where each value came from
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FILE = os.path.join(HERE, "ai_hosts.json")
# today's values (what every reader had hard-coded before pass 97); a reader still passes its own literal as `default`
DEFAULTS = {
    "comfy": "http://192.168.137.54:8188",
    "ssh": "teatree@192.168.137.54",
    "ssh_key": "~/.ssh/id_ed25519_ai_server",
    "lmstudio": "http://127.0.0.1:1234",
    "ollama": "http://192.168.137.54:11434",
}
_cache = {}      # path -> (mtime, size, dict)
_warned = set()


def path():
    """The hosts file this process reads: AI_HOSTS_FILE, else tools/ai_hosts.json."""
    return os.environ.get("AI_HOSTS_FILE") or FILE


def load(p=None):
    """The file as a dict ({} when it is missing or not a JSON object); cached by mtime and size."""
    p = p or path()
    try:
        st = os.stat(p)
    except OSError:
        return {}
    sig = (st.st_mtime, st.st_size)
    hit = _cache.get(p)
    if hit and hit[0] == sig:
        return hit[1]
    try:
        with open(p, "r", encoding="utf-8") as f:
            d = json.load(f)
        if not isinstance(d, dict):
            raise ValueError("not an object")
    except (OSError, ValueError) as e:
        if p not in _warned:
            _warned.add(p)
            sys.stderr.write("ai_hosts: %s could not be read (%s); the built-in hosts are used\n" % (p, str(e)[:120]))
        d = {}
    _cache[p] = (sig, d)
    return d


def get(name, default=None):
    """The host `name` from the file; `default` (the reader's old literal) when the file has no non-empty string for
    it; DEFAULTS[name] when no default is given."""
    v = load().get(name)
    if isinstance(v, str) and v.strip():
        return v.strip()
    return default if default is not None else DEFAULTS.get(name)


def source(name):
    """Where `name` comes from: "file" or "default"."""
    v = load().get(name)
    return "file" if isinstance(v, str) and v.strip() else "default"


def lmstudio(suffix="", default="http://127.0.0.1:1234"):
    """LM Studio's base URL (no trailing slash) + `suffix` ("/v1/models", "/v1/chat/completions")."""
    return get("lmstudio", default).rstrip("/") + suffix


def ssh_argv(timeout=10):
    """comfy.SERVER_SSH's shape: ssh -i <key> -o ConnectTimeout=<timeout> <login>."""
    return ["ssh", "-i", os.path.expanduser(get("ssh_key", DEFAULTS["ssh_key"])), "-o", "ConnectTimeout=%d" % timeout,
            get("ssh", DEFAULTS["ssh"])]


def table():
    """{name: {value, source}} for every known host (doctor.py, `python tools/ai_hosts.py`)."""
    return {k: {"value": get(k), "source": source(k)} for k in DEFAULTS}


if __name__ == "__main__":
    print("hosts file: %s (%s)" % (path(), "present" if os.path.isfile(path()) else "absent: the built-in values"))
    for k, v in table().items():
        print("  %-9s %-34s %s" % (k, v["value"], v["source"]))
    if os.environ.get("COMFY_SERVER"):
        print("  COMFY_SERVER is set (%s): comfy.py and jobs.py use it over the file" % os.environ["COMFY_SERVER"])
