"""Pass 97 (lead): every page script parses.

Pass 96 shipped tools/level_editor/frames.js with an apostrophe inside a single-quoted string (line 462, a review fix):
the browser refused the whole file, so the Frames view never loaded, and no check noticed because the selftest only
loads the page-free *_model.js modules. This group runs `node --check` over every *.js the page loads (index.html's
script tags) and every other *.js beside it, so a syntax error anywhere in the page fails the suite.

Run by selftest.py's extra_checks (every selftest_<name>.py beside it exports `checks(check, run_node, server)`).
"""
import glob
import os
import re
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))


def _node():
    return shutil.which("node")


def checks(check, run_node=None, server=None):
    node = _node()
    if not node:
        print("JSSYNTAX97: node is not here: the page scripts' syntax is not checked")
        return
    with open(os.path.join(HERE, "index.html"), encoding="utf-8") as f:
        html = f.read()
    loaded = re.findall(r'<script[^>]+src="([^"]+\.js)"', html)
    local = [p for p in loaded if not p.startswith(("http:", "https:", "//"))]
    check(len(local) > 10, "JSSYNTAX97: index.html names the page's scripts (%d found)" % len(local))
    for rel in local:
        check(os.path.isfile(os.path.join(HERE, rel)), "JSSYNTAX97: index.html's script %s exists" % rel)
    files = sorted(set(glob.glob(os.path.join(HERE, "*.js")) + [os.path.join(HERE, r) for r in local if os.path.isfile(os.path.join(HERE, r))]))
    files = [p for p in files if os.sep + "vendor" + os.sep not in p]
    bad = []
    for p in files:
        r = subprocess.run([node, "--check", p], capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            first = (r.stderr or r.stdout).strip().splitlines()
            bad.append("%s: %s" % (os.path.basename(p), " | ".join(first[:3])))
    check(not bad, "JSSYNTAX97: every page script parses (%d files)%s" % (len(files), ("; broken: " + "; ".join(bad)) if bad else ""))
