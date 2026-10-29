#!/bin/bash
# One command from "I changed something" to "there is a playable build": checks, signed debug APK, and install on any
# phone that adb can see (USB or Wi-Fi). Prints the APK path at the end so it can be sent to the phone directly.
#
#   bash tools/ship.sh            # full: parse check, tests, smoke run, export, verify, install if a phone is connected
#   bash tools/ship.sh --quick    # skip tests and the smoke run (export + verify + install only)
#   bash tools/ship.sh --no-install
#   bash tools/ship.sh --no-pc      # skip the PC build (88fits.exe), which otherwise follows the APK into the Drive folder
#   bash tools/ship.sh --debug-key  # allow a debug-keystore build when tools/keys/keystore.env is missing (on purpose only)
#
# The PC build (pass 73): its icon is game/icon.ico (tools/make_win_icon.py, made again when game/icon.png changes), its
# version info follows application/config/version, and it is signed only when tools/keys/codesign.env exists (git-
# ignored; what it holds: tools/sign_exe.ps1; why Windows warns and what signing changes: docs/pc_build_trust.md).
#
# Never uninstall the app on the phone to fix an install: it deletes the save. A build signed with the same keystore
# always updates in place (adb install -r); a build signed differently is refused by Android, and that is the right
# outcome, so this script stops rather than export a debug-signed APK by accident (pass 45).
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
QUICK=0; INSTALL=1; DEBUG_KEY=0; NO_PC=0
for a in "$@"; do
  [ "$a" = "--quick" ] && QUICK=1
  [ "$a" = "--no-install" ] && INSTALL=0
  [ "$a" = "--debug-key" ] && DEBUG_KEY=1
  [ "$a" = "--no-pc" ] && NO_PC=1
done

# pass 114 (lane EDITOR): every step is written on the Godot lock (locks.py note), so the Level Editor's Save can say what
# the build is doing and whether a JSON saved now is in this build (before its "json -> tres" step) or the next one
IMPORTED=0
step() { printf '\n== %s\n' "$1"; python tools/locks.py note godot "$1" --pid "${SHELL_PID:-0}" --set "imported=$IMPORTED" > /dev/null 2>&1; }
# pass 66: the whole ship holds the repo-wide Godot lock (one Godot process at a time with the lanes and the Level
# Editor's job runner) and keeps the PC save aside (smoke_run plays on the real one), both given back at exit
SHELL_PID="$(cat /proc/$$/winpid 2>/dev/null || echo 0)"   # this bash's own Windows pid: the lock's owner while it runs
python tools/locks.py acquire godot "the build (ship.sh $*)" --pid "$SHELL_PID" || exit 1
python tools/locks.py keep > /dev/null
trap 'python tools/locks.py restore > /dev/null; python tools/locks.py release godot --pid "$SHELL_PID" > /dev/null' EXIT
step "import"; python tools/lossy_imports.py; "$GODOT" $P --import > /dev/null 2>&1
step "json -> tres"; "$GODOT" $P --script res://tools/import_json.gd 2>&1 | tail -n 1; IMPORTED=1
step "parse check"; "$GODOT" $P --script res://tools/check_scripts.gd 2>&1 | grep -E "checked|SCRIPT ERROR" | head -n 5
if grep -q "SCRIPT ERROR" <("$GODOT" $P --script res://tools/check_scripts.gd 2>&1); then echo "STOP: script errors"; exit 1; fi
if [ "$QUICK" = "0" ]; then
  # any failing test, smoke run or arena check stops the ship: nothing broken goes to the phone
  step "tests"; OUT=$("$GODOT" $P -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  echo "$OUT" | grep -E "Executed test cases|FAILED" | head -n 5
  if echo "$OUT" | grep -q "FAILED"; then echo "STOP: failing tests"; exit 1; fi
  step "smoke run"; OUT=$("$GODOT" $P --script res://tools/smoke_run.gd -- seconds=90 2>&1)
  echo "$OUT" | grep -E "smoke_run: (OK|FAIL)|SCRIPT ERROR" | head -n 3
  if ! echo "$OUT" | grep -q "smoke_run: OK"; then echo "STOP: smoke run failed"; exit 1; fi
  step "arena check"; OUT=$("$GODOT" $P --script res://tools/arena_check.gd 2>&1)
  echo "$OUT" | grep -E "arena_check: (ARENA OK|FAIL)|SCRIPT ERROR" | head -n 3
  if ! echo "$OUT" | grep -q "ARENA OK"; then echo "STOP: arena check failed"; exit 1; fi
  # every button, card, slider and list on every screen, driven by a simulated finger (pass 37: the sliders were dead on
  # the phone and a swipe down a list pressed its buttons)
  step "touch audit"; OUT=$("$GODOT" $P --script res://tools/touch_audit.gd 2>&1)
  echo "$OUT" | grep -E "controls answered|FAIL|SCRIPT ERROR" | head -n 8
  if ! echo "$OUT" | grep -q " 0 failures"; then echo "STOP: touch audit failed"; exit 1; fi
fi
# pass 114 (lane REPLAY): the build id (version, UTC time, git hash, dirty) stamped into the game before both exports
# (game/config/build.json, git-ignored; every run's recording names it), so a replay can find the build that recorded it
step "build stamp"; python tools/builds.py stamp
step "export"
if [ -f "$ROOT/tools/keys/keystore.env" ]; then
  # release build: smaller and faster, signed with the project keystore (same signature every time, so it updates in place)
  set -a; . "$ROOT/tools/keys/keystore.env"; set +a
  APK="$ROOT/game/export/88fits.apk"
  "$GODOT" $P --export-release "Android" export/88fits.apk > /dev/null 2>&1
else
  if [ "$DEBUG_KEY" != "1" ]; then
    echo "STOP: tools/keys/keystore.env is missing. A debug-signed APK cannot update the release build on the phone (signature mismatch -> 'App not installed' -> an uninstall wipes the save). Pass --debug-key to build one on purpose."
    exit 1
  fi
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
# the PC build (2026-10-10, Garry: "create an Android build and then a PC build"): one 88fits.exe with the game packed
# inside (the "Windows Desktop" preset, embed_pck), next to the APK in the same Drive folder; --no-pc skips it
EXE="$ROOT/game/export/88fits.exe"
if [ "$NO_PC" = "0" ]; then
  step "pc build"
  # pass 73: the Windows icon made again when the app icon changed; the old exe removed first, so a failed export
  # cannot send the last build to Drive again
  python tools/make_win_icon.py --if-stale
  rm -f "$EXE"
  ( cd "$ROOT/game" && "$GODOT" --headless --path "$ROOT/game" --export-release "Windows Desktop" export/88fits.exe > /dev/null 2>&1 )
  PC_OK=0
  if [ -s "$EXE" ]; then
    PC_OK=1
    echo "$(du -m "$EXE" | cut -f1) MiB"
    # what Windows will show: the icon's sizes, the version (the game's, from project.godot), the signature
    python tools/exe_info.py "$EXE" --expect-version "$(grep -m1 '^config/version=' "$ROOT/game/project.godot" | sed 's/.*="\(.*\)"/\1/')" || echo "WARNING: the exe's version info is not the game's version"
    # pass 73: Windows code signing, off until tools/keys/codesign.env exists; a build that should be signed and is
    # not stays out of Drive
    if [ -f "$ROOT/tools/keys/codesign.env" ]; then
      step "pc signature"
      if ( set -a; . "$ROOT/tools/keys/codesign.env"; set +a; powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/tools/sign_exe.ps1" -Exe "$EXE" ); then
        :
      else
        echo "STOP (PC build): signing failed, the exe is not copied to Drive"; PC_OK=0
      fi
    fi
  else
    echo "PC export failed: no $EXE"
  fi
  # pass 114 (lane REPLAY): the PC build kept for replays (builds/<build id>/88fits.exe + build.json; tools/builds.py
  # prunes to the newest 6 and every build a recording on this PC names)
  if [ "$PC_OK" = "1" ]; then
    step "keep build"; python tools/builds.py keep "$EXE" || echo "WARNING: the build was not kept for replays"
  fi
  if [ "$PC_OK" = "1" ]; then
    for D in /e/"My Drive" /g/"My Drive" /h/"My Drive" /i/"My Drive" "$USERPROFILE/My Drive" "$USERPROFILE/Google Drive"; do
      if [ -d "$D" ]; then
        # the Drive drive marks every file as downloaded from the Internet (SmartScreen asks about each new build):
        # a copy on a local disk carries no mark and starts without the warning (docs/pc_build_trust.md)
        cp -f "$EXE" "$D/88fits builds/88fits.exe" && echo "copied to Google Drive: $D/88fits builds/88fits.exe (copy it to a local folder, e.g. the Desktop, and run it there)"
        break
      fi
    done
  fi
fi
step "done"; echo "APK: $APK"; [ "$NO_PC" = "0" ] && echo "EXE: $EXE"
