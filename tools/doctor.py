#!/usr/bin/env python3
"""Is this PC ready for the 88fits tools? (pass 97, lane SAFE; OPS-03) Read-only: it changes nothing anywhere.

    python tools/doctor.py                 # one line per check; exit 0 when the essentials pass, else 1 naming what is missing
    python tools/doctor.py --json          # the same as JSON (Claude; the Level Editor shows the summary in /api/status.doctor)
    python tools/doctor.py --quick         # no ssh login and no walk of tools/dl (what the editor runs, every 10 minutes at most)
    python tools/doctor.py --home D --root R   # look at another home folder / checkout (an empty one names every missing piece)

What it looks at:
    essentials  Python 3.8+, the packages tools/requirements.txt marks essential (numpy, Pillow, scipy), Node.js (the Level
                Editor's selftest), the Godot binary in the checkout, the checkout itself (game/project.godot)
    the rest    the optional packages, Blender, the JDK (Android export), git, the three AI services (ComfyUI /system_stats,
                LM Studio /v1/models, Ollama /api/tags; hosts from tools/ai_hosts.json), the ssh key and a BatchMode login
                (`true` on the AI server: no prompt, nothing changed), the four locks with a verdict on each holder, the
                free disk space and what tools/dl holds, which key files exist in tools/keys/ (names only, never read)
It never runs Godot (the repo-wide lock rule), never writes a file, never releases a lock, and never prints a key.
Standard library only (it must run on a PC where nothing is installed yet).
"""
import argparse
import glob
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

LOCK_NAMES = ("comfy", "godot", "jobs", "sim")
# tools/requirements.txt's names -> the module a tool imports; essential ones stop the art tools when missing
IMPORT_NAMES = {"numpy": "numpy", "pillow": "PIL", "scipy": "scipy", "pefile": "pefile", "soundfile": "soundfile",
                "librosa": "librosa", "gradio-client": "gradio_client", "gradio_client": "gradio_client",
                "websocket-client": "websocket"}
ESSENTIAL_PACKAGES = ("numpy", "pillow", "scipy")
BUILTIN_REQUIREMENTS = [("numpy", "1.22.0"), ("pillow", "10.0.0"), ("scipy", "1.11.2")]
HOST_DEFAULTS = {"comfy": "http://192.168.137.54:8188", "ssh": "teatree@192.168.137.54",
                 "ssh_key": "~/.ssh/id_ed25519_ai_server", "lmstudio": "http://127.0.0.1:1234",
                 "ollama": "http://192.168.137.54:11434"}
KEY_FILES = ("keystore.env", "88fits.keystore", "anthropic.env", "gemini.env", "codesign.env")
DISK_WARN_GB = 10.0
WALK_SECONDS = 20.0


class Probe:
    """Everything doctor asks the outside world, in one place (the selftest hands a fake one in)."""

    def which(self, name):
        return shutil.which(name)

    def run(self, argv, timeout=15):
        """(returncode, stdout+stderr text); (None, error text) when it could not run."""
        try:
            p = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout,
                               stdin=subprocess.DEVNULL)
            return p.returncode, (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired:
            return None, "no answer in %d s" % timeout
        except OSError as e:
            return None, str(e)

    def http_json(self, url, timeout=3.0):
        """(True, parsed JSON or text) or (False, why)."""
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                raw = r.read(2_000_000)
            try:
                return True, json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                return True, raw[:200].decode("utf-8", "replace")
        except Exception as e:   # noqa: BLE001
            return False, "%s: %s" % (type(e).__name__, str(e)[:160])

    def exists(self, path):
        return os.path.exists(path)

    def isdir(self, path):
        return os.path.isdir(path)

    def glob(self, pattern):
        return sorted(glob.glob(pattern))

    def disk_free(self, path):
        try:
            return shutil.disk_usage(path).free
        except OSError:
            return None

    def module(self, name):
        """(found, version or "") without importing it."""
        try:
            spec = importlib.util.find_spec(name)
        except (ImportError, ValueError):
            spec = None
        if spec is None:
            return False, ""
        return True, _dist_version(name)

    def read_json(self, path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def read_text(self, path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except OSError:
            return None

    def pid_alive(self, pid):
        try:
            import locks
            return locks.pid_alive(pid)
        except Exception:   # noqa: BLE001
            return None

    def listdir(self, path):
        try:
            return sorted(os.listdir(path))
        except OSError:
            return []

    def now(self):
        return time.time()


def _dist_version(module):
    try:
        import importlib.metadata as md
    except ImportError:
        return ""
    for dist in [k for k, v in IMPORT_NAMES.items() if v == module] + [module]:
        for name in (dist, dist.replace("-", "_"), dist.capitalize()):
            try:
                return md.version(name)
            except Exception:   # noqa: BLE001
                continue
    return ""


def _vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", str(v))[:3]) or (0,)


class Report:
    def __init__(self, root, home):
        self.root, self.home, self.checks = root, home, []

    def add(self, name, status, value="", detail="", fix="", essential=False):
        """status: ok | missing | warn | info. A missing essential fails the run; a missing optional piece is a warning."""
        self.checks.append({"name": name, "status": status, "essential": bool(essential), "value": value,
                            "detail": detail, "fix": fix})

    @property
    def missing(self):
        """The essentials that are missing (they fail the run)."""
        return [c["name"] for c in self.checks if c["status"] == "missing" and c["essential"]]

    @property
    def absent(self):
        """The optional pieces that are missing (named, never failing)."""
        return [c["name"] for c in self.checks if c["status"] == "missing" and not c["essential"]]

    @property
    def warnings(self):
        return [c["name"] for c in self.checks if c["status"] == "warn"]


def requirements(root, probe):
    """[(name, minimum)] from <root>/tools/requirements.txt (None when the file is missing)."""
    text = probe.read_text(os.path.join(root, "tools", "requirements.txt"))
    if text is None:
        return None
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        m = re.match(r"^([A-Za-z0-9_.\-]+)\s*(?:>=\s*([0-9][0-9A-Za-z.]*))?", line)
        if m:
            out.append((m.group(1).lower(), m.group(2) or ""))
    return out


def hosts(root, probe):
    d = probe.read_json(os.path.join(root, "tools", "ai_hosts.json"))
    d = d if isinstance(d, dict) else {}
    h = {k: (d[k].strip() if isinstance(d.get(k), str) and d[k].strip() else v) for k, v in HOST_DEFAULTS.items()}
    if os.environ.get("COMFY_SERVER"):   # what comfy.py and jobs.py use over the file
        h["comfy"] = os.environ["COMFY_SERVER"]
    return h, bool(d)


def _expand(path, home):
    return os.path.normpath(os.path.join(home, path[2:]) if path.startswith("~/") or path.startswith("~\\") else os.path.expanduser(path))


def check_python(rep, probe):
    v = sys.version_info
    ok = v >= (3, 8)
    rep.add("python", "ok" if ok else "missing", "%d.%d.%d" % v[:3], sys.executable,
            "" if ok else "install Python 3.10 from https://www.python.org/downloads/ (tick \"Add python.exe to PATH\")", True)


def check_packages(rep, probe):
    reqs = requirements(rep.root, probe)
    if reqs is None:
        rep.add("requirements.txt", "warn", "", "no tools/requirements.txt in the checkout: the built-in list is checked",
                "git pull (the file is in the repo since pass 97)")
        reqs = BUILTIN_REQUIREMENTS
    for name, minimum in reqs:
        mod = IMPORT_NAMES.get(name, name.replace("-", "_"))
        found, ver = probe.module(mod)
        essential = name in ESSENTIAL_PACKAGES
        fix = "python -m pip install -r tools/requirements.txt"
        if not found:
            rep.add(name, "missing", "", "import %s fails" % mod, fix, essential)
        elif minimum and ver and _vtuple(ver) < _vtuple(minimum):
            rep.add(name, "warn", ver, "older than %s (tools/requirements.txt)" % minimum, fix, essential)
        else:
            rep.add(name, "ok", ver or "found", "", "", essential)


def _version_of(probe, argv, timeout=15):
    rc, out = probe.run(argv, timeout)
    if rc is None:
        return None, out
    line = next((l.strip() for l in (out or "").splitlines() if l.strip()), "")
    return (line if rc == 0 else None), line


def check_programs(rep, probe):
    node = probe.which("node")
    ver, why = _version_of(probe, [node, "--version"]) if node else (None, "not on PATH")
    rep.add("node", "ok" if ver else "missing", ver or "", node or why,
            "" if ver else "install Node.js LTS from https://nodejs.org (the Level Editor's selftest runs its page maths in it)", True)
    git = probe.which("git")
    ver, why = _version_of(probe, [git, "--version"]) if git else (None, "not on PATH")
    rep.add("git", "ok" if ver else "missing", ver or "", git or why, "" if ver else "install Git for Windows (git-scm.com)")
    godot = os.path.join(rep.root, "Godot_v4.7.2-stable_win64", "Godot_v4.7.2-stable_win64.exe")
    ok = probe.exists(godot)
    rep.add("godot", "ok" if ok else "missing", "4.7.2" if ok else "", godot,
            "" if ok else "unzip Godot 4.7.2 (win64) into Godot_v4.7.2-stable_win64/ at the repo root (git-ignored)", True)
    blender = os.environ.get("BLENDER") if rep.home == os.path.expanduser("~") else None
    if not (blender and probe.exists(blender)):
        local = os.path.join(rep.home, "AppData", "Local") if rep.home != os.path.expanduser("~") else os.environ.get("LOCALAPPDATA", "")
        hits = probe.glob(os.path.join(local, "Programs", "blender-*", "blender.exe")) if local else []
        if rep.home == os.path.expanduser("~"):
            hits = hits or probe.glob("C:/Program Files/Blender Foundation/Blender */blender.exe")
        blender = hits[-1] if hits else None
    if blender:
        m = re.search(r"blender[- ](\d+\.\d+(?:\.\d+)?)", blender.replace("\\", "/"), re.I)
        rep.add("blender", "ok", m.group(1) if m else "found", blender)
    else:
        rep.add("blender", "missing", "", "not under %LOCALAPPDATA%/Programs/blender-*/ nor BLENDER",
                "unzip Blender 5.2 into %LOCALAPPDATA%/Programs/ (or set BLENDER=<path to blender.exe>): the driver and 3D tools")
    javas = probe.glob(os.path.join(rep.root, "tools", "jdk17", "jdk-17*", "bin", "java.exe"))
    if javas:
        ver, why = _version_of(probe, [javas[-1], "-version"])
        rep.add("jdk", "ok" if ver else "warn", ver or "", javas[-1] if ver else why)
    else:
        rep.add("jdk", "missing", "", "no tools/jdk17/jdk-17*/", "unzip a JDK 17 into tools/jdk17/ (the Android export; see docs/RUNNING.md)")


def check_checkout(rep, probe):
    ok = probe.exists(os.path.join(rep.root, "game", "project.godot"))
    rep.add("checkout", "ok" if ok else "missing", rep.root, "game/project.godot" + ("" if ok else " is not there"),
            "" if ok else "run doctor from the 88fits checkout (or pass --root)", True)


def check_services(rep, probe):
    h, from_file = hosts(rep.root, probe)
    rep.add("ai_hosts", "info", "tools/ai_hosts.json" if from_file else "built-in", ", ".join("%s %s" % (k, h[k]) for k in ("comfy", "lmstudio", "ollama")))
    for name, url, what, fix in (
            ("comfyui", h["comfy"].rstrip("/") + "/system_stats", "the AI server's ComfyUI",
             "start the AI server (its ComfyUI is the user service ai-comfyui) or check the network to it"),
            ("lmstudio", h["lmstudio"].rstrip("/") + "/v1/models", "LM Studio (the vision QA)",
             "start LM Studio's server on this PC, or run the art jobs with Skip QA"),
            ("ollama", h["ollama"].rstrip("/") + "/api/tags", "Ollama on the AI server", "optional: only the evaluator's server-side eye uses it")):
        ok, data = probe.http_json(url, 3.0)
        if ok:
            detail = ""
            if name == "comfyui" and isinstance(data, dict):
                sysd = data.get("system") or {}
                devs = data.get("devices") or []
                detail = "ComfyUI %s%s" % (sysd.get("comfyui_version", "?"), (", " + str(devs[0].get("name", ""))[:60]) if devs else "")
            elif name == "lmstudio" and isinstance(data, dict):
                detail = "%d models" % len(data.get("data") or [])
            elif name == "ollama" and isinstance(data, dict):
                detail = "%d models" % len(data.get("models") or [])
            rep.add(name, "ok", url, detail)
        else:
            rep.add(name, "warn", url, "%s does not answer (%s)" % (what, data), fix)


def check_ssh(rep, probe, quick):
    h, _ = hosts(rep.root, probe)
    key = _expand(h["ssh_key"], rep.home)
    if not probe.exists(key):
        rep.add("ssh_key", "missing", "", "%s is not there" % key,
                "copy the AI server's key to %s (restarting ComfyUI and the RAM check need it)" % h["ssh_key"])
        return
    rep.add("ssh_key", "ok", key)
    if quick:
        return
    ssh = probe.which("ssh")
    if not ssh:
        rep.add("ssh_login", "warn", "", "no ssh on PATH", "Windows: Settings > Optional features > OpenSSH Client")
        return
    rc, out = probe.run([ssh, "-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", h["ssh"], "true"], timeout=20)
    if rc == 0:
        rep.add("ssh_login", "ok", h["ssh"], "a BatchMode login answers")
    else:
        tail = (out or "").strip().splitlines()[-1:] or [""]
        rep.add("ssh_login", "warn", h["ssh"], "the BatchMode login failed (%s)" % (tail[0][:160] or "exit %s" % rc),
                "the AI server is off, or its authorized_keys lacks this key")


def check_locks(rep, probe):
    d = os.path.join(rep.root, "tools", "dl", "locks")
    for name in LOCK_NAMES:
        p = os.path.join(d, name + ".lock")
        if not probe.isdir(p):
            rep.add("lock " + name, "ok", "free")
            continue
        o = probe.read_json(os.path.join(p, "owner.json"))
        if not isinstance(o, dict):
            rep.add("lock " + name, "warn", "held by an unknown process", "a lock folder without owner.json is never reclaimed by code",
                    "the Level Editor's Jobs tab: Force release (only when nothing runs)")
            continue
        pid, who = o.get("pid"), o.get("who") or "?"
        age = max(0, int(probe.now() - float(o.get("since") or probe.now())))
        alive = probe.pid_alive(pid)
        held = "held by %s (pid %s) for %s" % (who, pid, _dur(age))
        if alive is False:
            rep.add("lock " + name, "warn", held, "its holder is dead: the next tool that wants it reclaims it on its own")
            continue
        if name == "jobs":
            m = re.search(r"port (\d+)", str(o.get("note") or ""))
            if m:
                ok, data = probe.http_json("http://127.0.0.1:%s/api/status" % m.group(1), 1.5)
                if ok and isinstance(data, dict) and data.get("ok") and "jobs_available" in data:
                    rep.add("lock jobs", "ok", held, "a Level Editor answers on port %s" % m.group(1))
                else:
                    rep.add("lock jobs", "warn", held, "nothing answers as a Level Editor on port %s: the next editor takes the queue over" % m.group(1))
                continue
        rep.add("lock " + name, "ok" if alive else "info", held, "its holder is alive" if alive else "liveness unknown")


def _dur(s):
    s = int(s)
    return "%d s" % s if s < 120 else ("%d min" % (s // 60) if s < 7200 else "%.1f h" % (s / 3600.0))


def _folder_size(path, deadline):
    total, files, done = 0, 0, True
    for d, _dirs, fs in os.walk(path):
        for f in fs:
            try:
                total += os.path.getsize(os.path.join(d, f))
                files += 1
            except OSError:
                pass
        if time.time() > deadline:
            done = False
            break
    return total, files, done


def check_disk(rep, probe, quick):
    free = probe.disk_free(rep.root if probe.exists(rep.root) else os.path.dirname(rep.root) or rep.root)
    if free is None:
        rep.add("disk", "warn", "", "the free space could not be read")
    else:
        gb = free / 1e9
        rep.add("disk", "ok" if gb >= DISK_WARN_GB else "warn", "%.0f GB free" % gb, "",
                "" if gb >= DISK_WARN_GB else "free some space: the art jobs write GBs under tools/dl")
    if quick:
        return
    dl = os.path.join(rep.root, "tools", "dl")
    if not probe.isdir(dl):
        rep.add("tools/dl", "info", "absent", "made by the first tool that writes there")
        return
    deadline = time.time() + WALK_SECONDS
    sizes, complete = [], True
    for name in probe.listdir(dl):
        full = os.path.join(dl, name)
        if not os.path.isdir(full):
            continue
        b, n, done = _folder_size(full, deadline)
        complete = complete and done
        sizes.append((b, name, n))
        if not done:
            break
    sizes.sort(reverse=True)
    total = sum(b for b, _, _ in sizes)
    top = ", ".join("%s %.1f GB" % (n, b / 1e9) for b, n, _ in sizes[:5])
    rep.add("tools/dl", "info", "%s%.1f GB" % ("" if complete else "at least ", total / 1e9), top)


def check_keys(rep, probe):
    d = os.path.join(rep.root, "tools", "keys")
    have = [k for k in KEY_FILES if probe.exists(os.path.join(d, k))]
    rep.add("tools/keys", "info", ", ".join(have) or "none", "names only; the files are never read here (tools/keys/README.md)")


def run(root=None, home=None, quick=False, probe=None):
    """Every check -> a Report (nothing is written anywhere)."""
    probe = probe or Probe()
    rep = Report(os.path.abspath(root or REPO), os.path.abspath(home) if home else os.path.expanduser("~"))
    for fn in (check_python, check_packages, check_programs, check_checkout):
        fn(rep, probe)
    check_services(rep, probe)
    check_ssh(rep, probe, quick)
    check_locks(rep, probe)
    check_disk(rep, probe, quick)
    check_keys(rep, probe)
    rep.at = time.strftime("%Y-%m-%dT%H:%M:%S")
    return rep


def summary(rep):
    """The short form /api/status.doctor carries."""
    return {"ok": not rep.missing, "at": getattr(rep, "at", ""), "missing": rep.missing, "absent": rep.absent, "warnings": rep.warnings,
            "checks": [{k: c[k] for k in ("name", "status", "value", "detail", "fix")} for c in rep.checks]}


def as_text(rep):
    lines = ["88fits doctor: %s (home %s), %s" % (rep.root, rep.home, getattr(rep, "at", ""))]
    for c in rep.checks:
        tag = {"ok": "ok", "missing": "MISSING" if c["essential"] else "missing", "warn": "warn", "info": "info"}[c["status"]]
        bits = [str(c["value"])] if c["value"] else []
        if c["detail"]:
            bits.append(str(c["detail"]))
        line = "  %-8s %-18s %s" % (tag, c["name"], "  ".join(bits))
        if c["fix"] and c["status"] in ("missing", "warn"):
            line += "\n  %-8s %-18s -> %s" % ("", "", c["fix"])
        lines.append(line)
    if rep.missing:
        lines.append("essentials MISSING: %s" % ", ".join(rep.missing))
    else:
        lines.append("essentials ok")
    if rep.absent:
        lines.append("optional, missing: %s" % ", ".join(rep.absent))
    if rep.warnings:
        lines.append("warnings: %s" % ", ".join(rep.warnings))
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="88fits doctor: is this PC ready for the tools? (read-only)")
    ap.add_argument("--json", action="store_true", help="the report as JSON")
    ap.add_argument("--quick", action="store_true", help="no ssh login probe and no walk of tools/dl")
    ap.add_argument("--home", default=None, help="the home folder to look in (ssh key, %%LOCALAPPDATA%%) instead of yours")
    ap.add_argument("--root", default=None, help="the checkout to look at instead of this one")
    a = ap.parse_args(argv)
    rep = run(a.root, a.home, a.quick)
    if a.json:
        print(json.dumps(dict(summary(rep), root=rep.root, home=rep.home), indent=1))
    else:
        print(as_text(rep))
    return 1 if rep.missing else 0


if __name__ == "__main__":
    sys.exit(main())
