#!/bin/bash
# The Google Play upload (2026-10-31): the dev game (debug surfaces kept, every look) as an Android App Bundle for Play's
# Internal testing track. Preset "Android Play" in game/export_presets.cfg: package com.outlawsurvivors.game (permanent
# once uploaded), label "Outlaw Survivors", Gradle build (game/android/build, installed from the 4.7.2 template on the
# first run), target SDK 36. Signed with the project keystore (tools/keys/keystore.env), which is the Play *upload* key:
# Play App Signing re-signs it for the testers.
#
#   bash tools/ship_play.sh [--no-drive] [--keep-code]
#
# Every run raises the preset's version/code by one (Play refuses a code it has seen; --keep-code rebuilds the same
# one) and writes game/export/outlaw_survivors.aab, then copies it to E:/My Drive/88fits builds/outlaw_survivors.aab.
# Checks are ship.sh's: run it first when the game changed.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"
DRIVE=1; BUMP=1
for a in "$@"; do
  case "$a" in
    --no-drive) DRIVE=0 ;;
    --keep-code) BUMP=0 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done
export JAVA_HOME="$ROOT/tools/jdk17/jdk-17.0.20.1+1"
[ -f "$ROOT/tools/keys/keystore.env" ] || { echo "STOP: tools/keys/keystore.env is missing (Play needs the upload key)"; exit 1; }
set -a; . "$ROOT/tools/keys/keystore.env"; set +a
step() { echo; echo "== $1"; }

step "version code"
CODE=$(python - "$BUMP" <<'EOF'
import re, sys
p = "game/export_presets.cfg"
s = open(p, encoding="utf-8", newline="").read()
i = s.index('name="Android Play"'); j = s.index("version/code=", i); k = s.index("\n", j)
code = int(s[j + len("version/code="):k]) + (1 if sys.argv[1] == "1" else 0)
open(p, "w", encoding="utf-8", newline="").write(s[:j] + "version/code=%d" % code + s[k:])
print(code)
EOF
) || exit 1
echo "version code $CODE"

step "build stamp"; python tools/builds.py stamp
step "export"
AAB="$ROOT/game/export/outlaw_survivors.aab"
rm -f "$AAB"
TEMPLATE=""
[ -d "$ROOT/game/android/build" ] || TEMPLATE="--install-android-build-template"
GODOT_TIMEOUT=1800 bash tools/godot.sh --headless --path "$ROOT/game" $TEMPLATE --export-release "Android Play" export/outlaw_survivors.aab
[ -f "$AAB" ] || { echo "STOP: no .aab was written"; exit 1; }
python -c "import os,sys;print('%.1f MiB' % (os.path.getsize(sys.argv[1])/1048576))" "$AAB"
step "signature"
"$JAVA_HOME/bin/jarsigner" -verify "$AAB" 2>&1 | grep -q "^jar verified" && echo "signature OK" || { echo "STOP: signature failed"; exit 1; }
if [ "$DRIVE" = "1" ]; then
  step "drive"
  cp "$AAB" "E:/My Drive/88fits builds/outlaw_survivors.aab" && echo "E:/My Drive/88fits builds/outlaw_survivors.aab"
fi
echo; echo "DONE: version code $CODE, $AAB"
