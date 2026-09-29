"""Every PNG under game/content, and every picture of the menus in game/art/ui/wanted (hero cut-outs, the desert still),
imports lossy (WebP 0.75), like the rest of the game's art: a new strip or icon imports lossless by default, and a few
of those added a megabyte each to the APK (pass 9's lesson, enforced since pass 34).

    python tools/lossy_imports.py          (tools/ship.sh runs it before the import step)

Touches only the .import files that say compress/mode=0; Godot re-imports those on the next --import."""
import glob
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
changed = []
files = glob.glob(os.path.join(REPO, "game", "content", "**", "*.png.import"), recursive=True)
files += glob.glob(os.path.join(REPO, "game", "art", "ui", "wanted", "*.png.import"))
files += glob.glob(os.path.join(REPO, "game", "art", "ui", "wanted", "*.jpg.import"))
for p in files:
    s = open(p, encoding="utf-8").read()
    if "compress/mode=0" not in s:
        continue
    s = s.replace("compress/mode=0", "compress/mode=1")
    s = re.sub(r"compress/lossy_quality=[0-9.]+", "compress/lossy_quality=0.75", s)
    open(p, "w", encoding="utf-8", newline="\n").write(s)
    changed.append(os.path.relpath(p, REPO))
print("lossy_imports: %d set to lossy%s" % (len(changed), (": " + ", ".join(os.path.basename(c) for c in changed)) if changed else ""))
