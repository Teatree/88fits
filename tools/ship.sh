#!/bin/bash
# One command from "I changed something" to "there is a playable build": checks, signed debug APK, and install on any
# phone that adb can see (USB or Wi-Fi). Prints the APK path at the end so it can be sent to the phone directly.
#
#   bash tools/ship.sh            # full: parse check, tests, smoke run, export, verify, install if a phone is connected
#   bash tools/ship.sh --quick    # skip tests and the smoke run (export + verify + install only)
#   bash tools/ship.sh --no-install
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"
GODOT="$ROOT/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
P="--headless --path $ROOT/game"
export JAVA_HOME="$ROOT/tools/jdk17/jdk-17.0.20.1+1"
ADB="${LOCALAPPDATA:-}/Android/Sdk/platform-tools/adb.exe"
APKSIGNER="${LOCALAPPDATA:-}/Android/Sdk/build-tools/34.0.0/apksigner.bat"
APK="$ROOT/game/export/88fits-debug.apk"
PKG="$(grep -m1 'package/unique_name' "$ROOT/game/export_presets.cfg" | sed 's/.*="\(.*\)"/\1/')"
QUICK=0; INSTALL=1
for a in "$@"; do
  [ "$a" = "--quick" ] && QUICK=1
  [ "$a" = "--no-install" ] && INSTALL=0
done

step() { printf '\n== %s\n' "$1"; }
step "import"; "$GODOT" $P --import > /dev/null 2>&1
step "json -> tres"; "$GODOT" $P --script res://tools/import_json.gd 2>&1 | tail -n 1
step "parse check"; "$GODOT" $P --script res://tools/check_scripts.gd 2>&1 | grep -E "checked|SCRIPT ERROR" | head -n 5
if grep -q "SCRIPT ERROR" <("$GODOT" $P --script res://tools/check_scripts.gd 2>&1); then echo "STOP: script errors"; exit 1; fi
if [ "$QUICK" = "0" ]; then
  step "tests"; "$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests 2>&1 | grep -E "Executed test cases|FAILED" | head -n 3
  step "smoke run"; "$GODOT" $P --script res://tools/smoke_run.gd -- seconds=90 2>&1 | grep -E "smoke_run: (OK|FAIL)|SCRIPT ERROR" | head -n 3
fi
step "export"
if [ -f "$ROOT/tools/keys/keystore.env" ]; then
  # release build: smaller and faster, signed with the project keystore (same signature every time, so it updates in place)
  set -a; . "$ROOT/tools/keys/keystore.env"; set +a
  APK="$ROOT/game/export/88fits.apk"
  "$GODOT" $P --export-release "Android" export/88fits.apk > /dev/null 2>&1
else
  "$GODOT" $P --export-debug "Android" export/88fits-debug.apk > /dev/null 2>&1
fi
python -c "import os,sys;print('%.1f MiB' % (os.path.getsize(sys.argv[1])/1048576))" "$APK"
step "signature"; "$APKSIGNER" verify "$APK" && echo "signature OK" || { echo "STOP: signature failed"; exit 1; }
if [ "$INSTALL" = "1" ] && [ -x "$ADB" ]; then
  step "phone"
  DEV="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [ -n "$DEV" ]; then
    "$ADB" -s "$DEV" install -r "$APK" && "$ADB" -s "$DEV" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 && echo "installed and launched on $DEV"
  else
    echo "no phone on adb (USB or Wi-Fi): send $APK to the phone instead"
  fi
fi
# Google Drive for Desktop: overwrite the build in the synced folder so the phone's Drive app always has the latest
for D in /e/"My Drive" /g/"My Drive" /h/"My Drive" /i/"My Drive" "$USERPROFILE/My Drive" "$USERPROFILE/Google Drive"; do
  if [ -d "$D" ]; then
    mkdir -p "$D/88fits builds" && cp -f "$APK" "$D/88fits builds/88fits.apk" && echo "copied to Google Drive: $D/88fits builds/88fits.apk (Drive app on the phone -> My Drive -> 88fits builds)"
    break
  fi
done
step "done"; echo "APK: $APK"
