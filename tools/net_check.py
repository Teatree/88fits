#!/usr/bin/env python3
"""What on this PC listens beyond itself? (pass 97, lane SAFE; WF-08) Read-only: it lists, explains and stops there.

    python tools/net_check.py            # the TCP listeners on a non-loopback address, with their process names
    python tools/net_check.py --json     # the same as JSON

The Level Editor binds 127.0.0.1 only (its ports 8787-8800: 8787 and the next free ones); ComfyUI, Ollama and the AI
server's other services live on 192.168.137.54 behind this PC. A listener on 0.0.0.0, on the home LAN address or on the
AI subnet's 192.168.137.1 can be reached from other machines: the ones in the editor's port range (8787-8800) and every
ssh forward (`ssh -L <address>:<port>:...`) are flagged, with the one command that would keep a forward on this PC only.
This tool changes nothing: re-binding or dropping a forward, or stopping any process, is Garry's call.
It reads `netstat -ano -p TCP` and `netstat -ano -p TCPv6`, `tasklist /FO CSV /NH`, and for an ssh or python listener its
command line (PowerShell Get-CimInstance Win32_Process), all read-only.
"""
import argparse
import csv
import io
import json
import re
import subprocess
import sys

EDITOR_PORTS = range(8787, 8801)
WATCH_PORTS = (8788,)
LOOPBACK = ("127.", "[::1]", "::1")
CMDLINE_FOR = ("ssh.exe", "python.exe", "pythonw.exe", "py.exe", "node.exe")


def _run(argv, timeout=20):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout,
                           stdin=subprocess.DEVNULL)
        return p.stdout or ""
    except (OSError, subprocess.TimeoutExpired) as e:
        sys.stderr.write("net_check: %s could not run (%s)\n" % (argv[0], e))
        return ""


def parse_netstat(text):
    """[{proto, address, port, pid}] for the LISTENING lines of `netstat -ano` (IPv4 and IPv6, [scope] kept)."""
    out = []
    for line in (text or "").splitlines():
        bits = line.split()
        if len(bits) < 5 or bits[0].upper() not in ("TCP", "TCPV6") or bits[3].upper() != "LISTENING":
            continue
        local = bits[1]
        m = re.match(r"^(.*):(\d+)$", local)
        if not m:
            continue
        try:
            pid = int(bits[4])
        except ValueError:
            continue
        out.append({"proto": bits[0].upper(), "address": m.group(1), "port": int(m.group(2)), "pid": pid})
    return out


def parse_tasklist(text):
    """{pid: image name} from `tasklist /FO CSV /NH`."""
    names = {}
    for row in csv.reader(io.StringIO(text or "")):
        if len(row) >= 2:
            try:
                names[int(row[1])] = row[0]
            except ValueError:
                continue
    return names


def is_loopback(address):
    return address.startswith(LOOPBACK)


def forward_of(cmdline, port):
    """An `ssh -L [bind:]port:host:hostport` spec in a command line for this local port: (bind, host, hostport) or None."""
    for m in re.finditer(r"-L\s*(\S+)", cmdline or ""):
        spec = m.group(1).strip('"')
        bits = spec.split(":")
        if len(bits) == 4 and bits[1] == str(port):
            return bits[0], bits[2], bits[3]
        if len(bits) == 3 and bits[0] == str(port):
            return "", bits[1], bits[2]
    return None


def verdicts(listeners, names, cmdlines=None):
    """The non-loopback listeners with a verdict each: {address, port, pid, process, flag: editor|forward|watch|"",
    note, advice}. Loopback ones are left out (nothing else can reach them)."""
    cmdlines = cmdlines or {}
    seen, out = set(), []
    for l in listeners:
        if is_loopback(l["address"]):
            continue
        key = (l["address"], l["port"], l["pid"])
        if key in seen:
            continue
        seen.add(key)
        proc = names.get(l["pid"], "?")
        rec = dict(l, process=proc, flag="", note="", advice="")
        cmd = cmdlines.get(l["pid"], "")
        fwd = forward_of(cmd, l["port"]) if proc.lower() == "ssh.exe" else None
        where = "every address of this PC" if l["address"] in ("0.0.0.0", "[::]") else l["address"]
        if fwd:
            bind, host, hport = fwd
            rec["flag"] = "forward"
            rec["note"] = ("an ssh forward: whoever reaches port %s on %s (the network that address is on) reaches %s:%s, "
                           "the AI server's side, through this PC" % (l["port"], where, host, hport))
            rec["advice"] = ("to keep it on this PC only, start that ssh again with -L 127.0.0.1:%s:%s:%s; to drop it, end "
                             "ssh.exe pid %d (Task Manager > Details). Your call: nothing here changes it." % (l["port"], host, hport, l["pid"]))
        if l["port"] in EDITOR_PORTS:
            rec["flag"] = rec["flag"] or "editor"
            rec["note"] = rec["note"] or ("a listener in the Level Editor's port range (8787-8800) on %s: the editor itself only "
                                          "ever binds 127.0.0.1, so this is something else" % where)
            if not rec["advice"]:
                rec["advice"] = ("find what %s (pid %d) is; if it is not meant for other machines, bind it to 127.0.0.1"
                                 % (proc, l["pid"]))
        if l["port"] in WATCH_PORTS and rec["flag"] != "forward":
            rec["flag"] = "watch"
        out.append(rec)
    out.sort(key=lambda r: (r["flag"] == "", r["port"], r["address"]))
    return out


def gather():
    text = _run(["netstat", "-ano", "-p", "TCP"]) + "\n" + _run(["netstat", "-ano", "-p", "TCPv6"])
    listeners = parse_netstat(text)
    names = parse_tasklist(_run(["tasklist", "/FO", "CSV", "/NH"]))
    cmdlines = {}
    for l in listeners:
        if is_loopback(l["address"]) or l["pid"] in cmdlines:
            continue
        if names.get(l["pid"], "").lower() in CMDLINE_FOR:
            cmdlines[l["pid"]] = _run(["powershell", "-NoProfile", "-Command",
                                       "(Get-CimInstance Win32_Process -Filter 'ProcessId=%d').CommandLine" % l["pid"]]).strip()
    return listeners, names, cmdlines


def as_text(rows, cmdlines):
    flagged = [r for r in rows if r["flag"]]
    rest = [r for r in rows if not r["flag"]]
    lines = ["net_check: %d TCP listeners on a non-loopback address (loopback ones left out: nothing else reaches them)" % len(rows)]
    if flagged:
        lines.append("")
        lines.append("FLAGGED (the editor's port range 8787-8800, ssh forwards):")
        for r in flagged:
            lines.append("  %s:%d  %s (pid %d)" % (r["address"], r["port"], r["process"], r["pid"]))
            if r["note"]:
                lines.append("      %s" % r["note"])
            if r["pid"] in cmdlines and cmdlines[r["pid"]]:
                lines.append("      command: %s" % cmdlines[r["pid"]][:300])
            if r["advice"]:
                lines.append("      what to do: %s" % r["advice"])
    else:
        lines.append("nothing in the editor's port range and no ssh forward listens beyond this PC")
    if rest:
        lines.append("")
        lines.append("other listeners (not this project's; listed so nothing is hidden):")
        for r in rest:
            lines.append("  %-28s %-26s pid %d" % ("%s:%d" % (r["address"], r["port"]), r["process"], r["pid"]))
    lines.append("")
    lines.append("The Level Editor binds 127.0.0.1 only. This tool changed nothing.")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="88fits net_check: what listens beyond this PC (read-only)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    listeners, names, cmdlines = gather()
    rows = verdicts(listeners, names, cmdlines)
    if a.json:
        print(json.dumps({"listeners": rows, "flagged": [r for r in rows if r["flag"]]}, indent=1))
    else:
        print(as_text(rows, cmdlines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
