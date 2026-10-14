"""The two locks every tool of this repo shares (pass 66): one ComfyUI job at a time, one Godot process at a time.

Both are mkdir locks (atomic on NTFS as on POSIX) under tools/dl/locks/:

    tools/dl/locks/comfy.lock/owner.json    who talks to the AI server at 192.168.137.54:8188 right now
    tools/dl/locks/godot.lock/owner.json    who runs a Godot process right now (headless tools, imports, tests)

owner.json: {"pid", "who", "job", "note", "since", "beat", "host"}. A lock whose owner.json names a pid that is no
longer alive is stale and is reclaimed with a printed line; a lock folder WITHOUT owner.json (a lane's bare `mkdir`
loop) is never reclaimed by code: the Level Editor shows it as "held by an unknown process" and only Garry's explicit
Force release removes it. A pid that is alive keeps its lock however old its beat is.

    python tools/locks.py status                       # both locks
    python tools/locks.py acquire comfy "gen_art werewolf" --pid $(cat /proc/$$/winpid)   # from Git Bash: the shell
                                                       # itself is the owner, until that shell's `release` (or it dies)
    python tools/locks.py release comfy --pid $(cat /proc/$$/winpid) [--force]
    python tools/locks.py keep | restore               # the PC save aside / back (what `godot` does round a run)
    python tools/locks.py godot -- --headless --path D:/_projects/88fits/game --script res://tools/check_scripts.gd
        # takes the Godot lock, keeps the PC save aside, runs the Godot binary with those arguments, restores the save,
        # releases; the exit code is Godot's. `tools/godot.sh` is the bash wrapper over this.

    from locks import acquire, held, run_godot
    with held("comfy", who="gen_art.py"): ...         # every comfy.run / run_dev / release_models inside
    rc, out = run_godot(["--headless", "--path", GAME, "--script", "res://tools/import_json.gd", "--", "only=enemies/goblin"],
                        timeout=120, who="level_editor save")

A child process of a holder must not wait on its parent's lock: the parent sets LOCK_HELD_COMFY=1 (or the older
COMFY_LOCK_HELD=1) / LOCK_HELD_GODOT=1 in the child's environment and `acquire`/`held` pass straight through. A second
acquire of the same lock by the same process is reentrant (a depth counter); only the outermost release lets go.
Standard library only: the Level Editor server imports this.
"""
import contextlib
import json
import os
import shutil
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK_DIR = os.path.join(ROOT, "tools", "dl", "locks")
GODOT = os.path.join(ROOT, "Godot_v4.7.2-stable_win64", "Godot_v4.7.2-stable_win64.exe")
NAMES = ("comfy", "godot", "jobs", "sim")   # jobs: the one Level Editor that runs the job queue (jobs.claim_queue);
# sim (pass 77): one run-sim batch at a time (tools/sim_batch.py, on its own snapshot of game/, never the godot lock)
POLL_SECONDS = 2.0
# the PC's save (smoke_run and a windowed test play on the real one): kept aside round every Godot run
SAVE_DIR = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "88fits")
SAVE_FILES = ("save.json", "save.json.bak")
KEEP_DIR = os.path.join(LOCK_DIR, "save_keep")
RESTORE_PENDING = os.path.join(KEEP_DIR, "restore_pending.json")

_depth = {}  # lock name -> nesting depth in this process
_depth_guard = threading.Lock()


def lock_path(name):
    if name not in NAMES:
        raise ValueError("unknown lock %r (one of %s)" % (name, ", ".join(NAMES)))
    return os.path.join(LOCK_DIR, name + ".lock")


def _owner_file(name):
    return os.path.join(lock_path(name), "owner.json")


def _env_held(name):
    if os.environ.get("LOCK_HELD_" + name.upper()):
        return True
    return name == "comfy" and bool(os.environ.get("COMFY_LOCK_HELD"))


def pid_alive(pid):
    """Whether a process with this pid is running (Windows: OpenProcess + GetExitCodeProcess; else kill 0)."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            import ctypes
            from ctypes import wintypes
            k32 = ctypes.windll.kernel32
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            STILL_ACTIVE = 259
            h = k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
            if not h:
                return False
            try:
                code = wintypes.DWORD()
                if not k32.GetExitCodeProcess(h, ctypes.byref(code)):
                    return False
                return code.value == STILL_ACTIVE
            finally:
                k32.CloseHandle(h)
        except Exception:  # no ctypes: assume alive (never reclaim on a guess)
            return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def status(name):
    """None when free; else {owner_file: bool, pid, who, job, note, since, beat, host, age_s, alive}."""
    p = lock_path(name)
    if not os.path.isdir(p):
        return None
    d = {"owner_file": False, "pid": 0, "who": "unknown process", "job": "", "note": "", "host": ""}
    try:
        with open(_owner_file(name), "r", encoding="utf-8") as f:
            o = json.load(f)
        if isinstance(o, dict):
            d.update(o)
            d["owner_file"] = True
    except (OSError, ValueError):
        pass
    try:
        since = float(d.get("since") or os.path.getmtime(p))
    except (OSError, TypeError, ValueError):
        since = time.time()
    d["since"] = since
    d["beat"] = float(d.get("beat") or since)
    d["age_s"] = max(0.0, time.time() - since)
    d["alive"] = pid_alive(d.get("pid")) if d["owner_file"] else None
    return d


def status_all():
    return {n: status(n) for n in NAMES}


def _write_owner(name, who, job, note, pid=None):
    with open(_owner_file(name), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"pid": int(pid or os.getpid()), "who": str(who), "job": str(job), "note": str(note), "since": time.time(),
                   "beat": time.time(), "host": os.environ.get("COMPUTERNAME", "")}, f)


def _mine(pid, extra=None):
    """Whether an owner pid is this process, the process that ran this script, or `extra` (the shell's own Windows pid
    the CLI is told with --pid: under Git Bash the parent a Python sees is a transient fork, so a shell names itself
    through `cat /proc/$$/winpid`)."""
    try:
        return int(pid or 0) in (os.getpid(), os.getppid(), int(extra or 0))
    except (TypeError, ValueError):
        return False


def _cli_pid(argv):
    """`--pid N` from the CLI's arguments, else the parent process."""
    for i, a in enumerate(argv):
        if a == "--pid" and i + 1 < len(argv):
            try:
                return int(argv[i + 1])
            except ValueError:
                break
        if a.startswith("--pid="):
            try:
                return int(a.split("=", 1)[1])
            except ValueError:
                break
    return os.getppid()


def _reclaim_if_stale(name, log):
    """A lock whose owner.json names a dead pid is removed (and said so). One without owner.json is left alone."""
    s = status(name)
    if s is None or not s["owner_file"] or s["alive"]:
        return False
    log("locks: %s.lock held by dead pid %s (%s) since %ds ago: reclaimed" % (name, s.get("pid"), s.get("who"), int(s["age_s"])))
    return force_release(name)


class Lock:
    """What `acquire` returns: `beat()` to refresh owner.json's beat, `release()` once done. A context manager."""

    def __init__(self, name, who, passthrough=False, nested=False):
        self.name, self.who, self.passthrough, self.nested = name, who, passthrough, nested
        self.released = False

    def beat(self):
        if self.passthrough or self.nested:
            return
        try:
            with open(_owner_file(self.name), "r+", encoding="utf-8") as f:
                o = json.load(f)
                o["beat"] = time.time()
                f.seek(0)
                f.truncate()
                json.dump(o, f)
        except (OSError, ValueError):
            pass

    def release(self):
        if self.released:
            return False
        self.released = True
        if self.passthrough:
            return True
        with _depth_guard:
            d = _depth.get(self.name, 0)
            if d > 1:
                _depth[self.name] = d - 1
                return True
            _depth.pop(self.name, None)
        s = status(self.name)
        if s is None:
            return True
        if s["owner_file"] and int(s.get("pid") or 0) != os.getpid():
            return False  # not ours any more (someone force-released and re-took it)
        return force_release(self.name)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.release()
        return False


def acquire(name, who, job="", note="", wait=True, poll=POLL_SECONDS, timeout=None, log=None, pid=None):
    """Take `name` for `who`. Waits (poll seconds between tries, for ever or `timeout` seconds) unless `wait` is False;
    returns a Lock, or None when it could not be taken without waiting / before the timeout. Reentrant per process;
    a child told LOCK_HELD_<NAME>=1 passes through. `pid` names another owner than this process (the CLI's shell)."""
    log = log or (lambda m: print(m, flush=True))
    if _env_held(name):
        return Lock(name, who, passthrough=True)
    with _depth_guard:
        if _depth.get(name, 0) > 0:
            _depth[name] += 1
            return Lock(name, who, nested=True)
    os.makedirs(LOCK_DIR, exist_ok=True)
    t0 = time.time()
    said = False
    while True:
        try:
            os.mkdir(lock_path(name))
        except FileExistsError:
            s0 = status(name)
            if s0 is not None and s0["owner_file"] and _mine(s0.get("pid")) and pid is None and os.getppid() == int(s0.get("pid") or 0):
                # the shell that runs this script holds it already (a lane's `acquire` then its Godot runs): pass through
                return Lock(name, who, passthrough=True)
            if _reclaim_if_stale(name, log):
                continue
            if not wait or (timeout is not None and time.time() - t0 >= timeout):
                return None
            if not said:
                s = status(name) or {}
                log("locks: waiting for %s.lock (held by %s%s for %d s)" % (
                    name, s.get("who", "?"), (" / " + s["job"]) if s.get("job") else "", int(s.get("age_s", 0))))
                said = True
            time.sleep(poll)
            continue
        _write_owner(name, who, job, note, pid=pid)
        with _depth_guard:
            _depth[name] = 1
        return Lock(name, who)


def force_release(name):
    """Remove the lock folder whoever holds it (Garry's "Force release", and the stale reclaim). True when gone."""
    p = lock_path(name)
    try:
        if os.path.exists(_owner_file(name)):
            os.remove(_owner_file(name))
        os.rmdir(p)
    except OSError:
        pass
    with _depth_guard:
        _depth.pop(name, None)
    return not os.path.isdir(p)


def release(name, force=False, pid=None):
    """CLI-style release of a lock this process, its parent or the shell `pid` holds (or any, with force)."""
    s = status(name)
    if s is None:
        return True
    if not force and s["owner_file"] and not _mine(s.get("pid"), pid):
        return False
    return force_release(name)


@contextlib.contextmanager
def held(name, who, job="", note="", log=None):
    lk = acquire(name, who, job=job, note=note, log=log)
    try:
        yield lk
    finally:
        lk.release()


# ---------------------------------------------------------------- the PC save round a Godot run

def keep_save():
    """Copy the PC's save.json and .bak under tools/dl/locks/save_keep/ and note that a restore is pending."""
    if not os.path.isdir(SAVE_DIR):
        return False
    os.makedirs(KEEP_DIR, exist_ok=True)
    kept = []
    for n in SAVE_FILES:
        src = os.path.join(SAVE_DIR, n)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(KEEP_DIR, n + ".keep"))
            kept.append(n)
    with open(RESTORE_PENDING, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"kept": kept, "since": time.time(), "pid": os.getpid()}, f)
    return True


def restore_save():
    """Put the kept save back (if a keep is pending). Returns the list of files restored."""
    if not os.path.isfile(RESTORE_PENDING):
        return []
    try:
        with open(RESTORE_PENDING, "r", encoding="utf-8") as f:
            kept = json.load(f).get("kept", [])
    except (OSError, ValueError):
        kept = list(SAVE_FILES)
    done = []
    for n in kept:
        k = os.path.join(KEEP_DIR, n + ".keep")
        if os.path.isfile(k) and os.path.isdir(SAVE_DIR):
            shutil.copy2(k, os.path.join(SAVE_DIR, n))
            done.append(n)
    try:
        os.remove(RESTORE_PENDING)
    except OSError:
        pass
    return done


def run_godot(args, timeout=None, who="tool", job="", keep=True, godot=None, log=None, stream=False):
    """Run the Godot binary with `args` under the godot lock, the PC save kept aside and put back after.
    Returns (returncode, output) with stdout+stderr as text (or ("", rc) streamed to this process's stdout when
    `stream`). A timeout kills Godot and returns -1."""
    godot = godot or GODOT
    with held("godot", who, job=job, log=log):
        if keep:
            keep_save()
        try:
            if stream:
                p = subprocess.run([godot] + list(args), cwd=ROOT, timeout=timeout)
                return p.returncode, ""
            p = subprocess.run([godot] + list(args), cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                               errors="replace", timeout=timeout)
            return p.returncode, (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b"")
            if isinstance(out, bytes):
                out = out.decode("utf-8", "replace")
            return -1, out + "\nlocks.run_godot: killed after %s s" % timeout
        finally:
            if keep:
                restore_save()


# ---------------------------------------------------------------- CLI

def _main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "status":
        for n in NAMES:
            s = status(n)
            if s is None:
                print("%s: free" % n)
            else:
                print("%s: held by %s%s (pid %s, %s) for %d s" % (
                    n, s["who"], (" / " + s["job"]) if s.get("job") else "", s.get("pid"),
                    "alive" if s["alive"] else ("dead" if s["alive"] is False else "no owner file"), int(s["age_s"])))
        return 0
    # the positional words of the command: the lock name and the owner, with --force and --pid N taken out
    rest = argv[2:]
    words = [a for i, a in enumerate(rest) if not (a.startswith("--pid") or a == "--force" or (i > 0 and rest[i - 1] == "--pid"))]
    if cmd == "acquire":
        name = words[0] if words else "comfy"
        who = words[1] if len(words) > 1 else "cli"
        owner_pid = _cli_pid(argv)
        try:
            # the shell that ran this command is the owner (this process ends at once): the lock lives while the shell
            # does and that shell's `release` gives it back; a dead shell's lock is reclaimed like any other. Under Git
            # Bash pass the shell's own Windows pid: `--pid $(cat /proc/$$/winpid)` (the parent a Python sees there is a
            # transient fork that is gone at once)
            lk = acquire(name, who, pid=owner_pid)
        except KeyboardInterrupt:
            print("gave up")
            return 1
        print("held: %s by %s (owner pid %d)" % (name, who, owner_pid))
        return 0
    if cmd == "keep":
        print("kept" if keep_save() else "no save folder")
        return 0
    if cmd == "restore":
        print("restored %s" % ", ".join(restore_save() or ["nothing pending"]))
        return 0
    if cmd == "release":
        name = words[0] if words else "comfy"
        ok = release(name, force="--force" in argv, pid=_cli_pid(argv))
        if ok:
            print("released %s" % name)
            return 0
        s = status(name)
        print("not yours: %s held by %s (pid %s); use --force" % (name, s and s.get("who"), s and s.get("pid")))
        return 1
    if cmd == "godot":
        args = argv[argv.index("--") + 1:] if "--" in argv else argv[2:]
        rc, _ = run_godot(args, who="cli godot", stream=True)
        return rc
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
