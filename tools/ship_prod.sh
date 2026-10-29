#!/bin/bash
# The production build (pass 81; Garry, 2026-10-15: "It's time to make a production build version ... no debug options,
# no extra art (unless it's used in the Level timeline) ... extra optimization for the art and stuff, to make the build
# smaller and faster ... from this point onwards you will only make a prod build if I ask for it"). Made from a pruned,
# optimised STAGING copy of game/ (tools/dl/prod/stage/game); the source tree is never changed. The skill
# .claude/skills/ship-prod/SKILL.md says when and how.
#
#   bash tools/ship_prod.sh                # the source's checks and tests, then the prod APK and exe, copied to Drive
#   bash tools/ship_prod.sh --no-drive     # the same, nothing copied to Drive (a test, a dry run)
#   bash tools/ship_prod.sh --quick        # skip the gdUnit tests on the source (ship.sh just ran them); the staging
#                                          # copy's checks, smoke run and run check always run
#   bash tools/ship_prod.sh --no-pc        # the APK only            --no-android   # the exe only
#   bash tools/ship_prod.sh --out DIR      # the builds, logs and reports (default tools/dl/prod/out)
#
# Steps: the source (lossy imports, import, json -> tres, the parse check, the tests unless --quick, the Windows icon)
# -> the staging copy (tools/prod_stage.py: its own user folder, the Android Prod version code) -> the plan
# (game/tools/prod_plan.gd: what the game can show) -> the prune (tools/prod_prune.py) -> the optimiser
# (tools/prod_optimise.py) -> import + json -> tres in the staging copy -> its checks (check_scripts, prod_check,
# smoke_run, prod_run_check with prod forced) -> the "Android Prod" export (signed with the project keystore, verified)
# and the "Windows Desktop Prod" export (version info, signing when tools/keys/codesign.env exists) -> the exe's cold
# start (tools/prod_probe.py) -> the numbers (tools/prod_report.py, report.md) -> Drive: 88fits-prod.apk / .exe.
# Any failed check stops it: nothing broken goes to Drive. Holds the repo-wide Godot lock for the whole run (one Godot
# process at a time with the lanes and the Level Editor) and keeps the PC save aside, like ship.sh.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd -W 2>/dev/null || pwd)"
GODOT="$ROOT/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64.exe"
export JAVA_HOME="$ROOT/tools/jdk17/jdk-17.0.20.1+1"
APKSIGNER="${LOCALAPPDATA:-}/Android/Sdk/build-tools/34.0.0/apksigner.bat"
STAGE="$ROOT/tools/dl/prod/stage"
SG="$STAGE/game"
OUT="$ROOT/tools/dl/prod/out"
QUICK=0; DRIVE=1; PC=1; ANDROID=1
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --no-drive) DRIVE=0 ;;
    --no-pc) PC=0 ;;
    --no-android) ANDROID=0 ;;
    --out) shift; OUT="$1" ;;
    *) echo "ship_prod: unknown option $1"; exit 2 ;;
  esac
  shift
done
mkdir -p "$OUT/logs"
OUT="$(cd "$OUT" && (pwd -W 2>/dev/null || pwd))"
LOGS="$OUT/logs"
T0=$(date +%s)
TIMES=""
# pass 114 (lane EDITOR): every step is written on the Godot lock (locks.py note): a JSON saved after the staging copy is
# not in this build (the Level Editor's Save says so)
IMPORTED=0
step() { printf '\n== %s\n' "$1"; TS=$(date +%s); python tools/locks.py note godot "$1" --pid "${SHELL_PID:-0}" --set "imported=$IMPORTED" > /dev/null 2>&1; }
took() { TIMES="$TIMES$(printf '%-28s %4d s' "$1" $(( $(date +%s) - TS )))\n"; }
die() { echo "STOP: $1"; exit 1; }
# one Godot run, its output in $LOGS/<name>.log (Godot prints nothing to a redirected console on Windows)
# (in a subshell, so a headless run's known crash at teardown, after its result is written, is not reported here)
gd() { local name="$1"; shift; ( "$GODOT" --log-file "$LOGS/$name.log" "$@"; exit $? ) > /dev/null 2>&1; }
logline() { grep -E "$2" "$LOGS/$1.log" | head -n "${3:-5}"; }

SHELL_PID="$(cat /proc/$$/winpid 2>/dev/null || echo 0)"
python tools/locks.py acquire godot "the production build (ship_prod.sh)" --pid "$SHELL_PID" || exit 1
python tools/locks.py keep > /dev/null
trap 'python tools/locks.py restore > /dev/null; python tools/locks.py release godot --pid "$SHELL_PID" > /dev/null' EXIT
export LOCK_HELD_GODOT=1   # the Python helpers that run Godot (prod_probe.py) pass through this shell's lock

step "source: import, json -> tres, parse check"
python tools/lossy_imports.py
gd src_import --headless --path "$ROOT/game" --import
# json -> tres for every content JSON newer than its .tres (sim_batch.stale_json), so the staging copy plays the saved JSON
STALE="$(python -c "import sys; sys.path.insert(0, 'tools'); import sim_batch; print(','.join(sim_batch.stale_json('game')))")"
if [ -n "$STALE" ]; then gd src_import_json --headless --path "$ROOT/game" --script res://tools/import_json.gd -- "only=$STALE"; echo "json -> tres: $STALE"; fi
gd src_check --headless --path "$ROOT/game" --script res://tools/check_scripts.gd
logline src_check "check_scripts:"
grep -q "check_scripts: .*, 0 errors" "$LOGS/src_check.log" || { logline src_check "SCRIPT ERROR" 8; die "script errors in the source"; }
if [ "$QUICK" = "0" ]; then
  gd src_tests --headless --path "$ROOT/game" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -rd "$LOGS/gdunit" -c
  RES="$(ls -d "$LOGS"/gdunit/report_* 2>/dev/null | sort -V | tail -n 1)/results.xml"
  grep -o '<testsuites[^>]*>' "$RES" 2>/dev/null | head -n 1
  if [ ! -f "$RES" ] || grep -q '<failure' "$RES" || ! grep -q '<testsuites[^>]* failures="0"' "$RES"; then die "failing tests (see $RES)"; fi
fi
[ "$PC" = "1" ] && python tools/make_win_icon.py --if-stale
took "source checks"

step "staging copy"
python tools/prod_stage.py --stage "$STAGE" || die "the staging copy"
IMPORTED=1
took "staging copy"

step "plan (what the game can show)"
gd plan --headless --path "$SG" --script res://tools/prod_plan.gd -- out="$OUT/plan.json"
logline plan "prod_plan:"
grep -q "prod_plan: OK" "$LOGS/plan.log" || die "the plan ($LOGS/plan.log)"
grep -q "registry problems 0" "$LOGS/plan.log" || die "the Registry has problems in the staging copy ($LOGS/plan.log)"
took "plan"

step "prune"
PRUNE_OUT="$(python tools/prod_prune.py --plan "$OUT/plan.json" --stage "$STAGE" --report "$OUT/prune.json")" || die "the prune"
echo "$PRUNE_OUT" | grep -v "only="
ONLY="$(echo "$PRUNE_OUT" | grep "only=" | sed 's/.*only=//')"
took "prune"

step "optimise"
python tools/prod_optimise.py --stage "$STAGE" --report "$OUT/optimise.json" || die "the optimiser"
took "optimise"

step "import and json -> tres in the staging copy"
gd stage_import --headless --path "$SG" --import
gd stage_import_json --headless --path "$SG" --script res://tools/import_json.gd -- "only=${ONLY:+$ONLY,}sounds"
logline stage_import_json "import_json|wrote|ERROR" 3
took "staging import"

step "checks in the staging copy"
gd stage_check_scripts --headless --path "$SG" --script res://tools/check_scripts.gd
logline stage_check_scripts "check_scripts:"
grep -q "check_scripts: .*, 0 errors" "$LOGS/stage_check_scripts.log" || { logline stage_check_scripts "SCRIPT ERROR|ERROR" 8; die "a script or scene does not load in the staging copy"; }
gd prod_check --headless --path "$SG" --script res://tools/prod_check.gd -- plan="$OUT/plan.json"
logline prod_check "prod_check:" 30
grep -q "prod_check: OK" "$LOGS/prod_check.log" || die "prod_check ($LOGS/prod_check.log)"
gd stage_smoke --headless --path "$SG" --script res://tools/smoke_run.gd -- seconds=90
logline stage_smoke "smoke_run: (OK|FAIL)|SCRIPT ERROR" 3
grep -q "smoke_run: OK" "$LOGS/stage_smoke.log" || die "the smoke run in the staging copy ($LOGS/stage_smoke.log)"
gd prod_run_check --headless --fixed-fps 60 --path "$SG" --script res://tools/prod_run_check.gd -- seconds=12
logline prod_run_check "prod_run_check:" 12
grep -q "prod_run_check: OK" "$LOGS/prod_run_check.log" || die "prod_run_check ($LOGS/prod_run_check.log)"
if grep -hE "Resource file not found|Failed loading resource|Cannot open file|No loader found" "$LOGS"/stage_*.log "$LOGS"/prod_*.log | grep -v "debug_launch" | head -n 5 | grep -q .; then
  grep -hE "Resource file not found|Failed loading resource|Cannot open file|No loader found" "$LOGS"/stage_*.log "$LOGS"/prod_*.log | sort -u | head -n 10
  die "a missing resource in the staging copy"
fi
took "staging checks"

APK="$OUT/88fits-prod.apk"
EXE="$OUT/88fits-prod.exe"
rm -f "$APK" "$EXE"
if [ "$ANDROID" = "1" ]; then
  step "Android Prod"
  [ -f "$ROOT/tools/keys/keystore.env" ] || die "tools/keys/keystore.env is missing: a prod APK is never debug-signed"
  ( set -a; . "$ROOT/tools/keys/keystore.env"; set +a; gd export_android --headless --path "$SG" --export-release "Android Prod" "$APK" )
  [ -s "$APK" ] || die "the Android export failed ($LOGS/export_android.log)"
  python -c "import os,sys;print('%.1f MiB' % (os.path.getsize(sys.argv[1])/1048576))" "$APK"
  "$APKSIGNER" verify "$APK" && echo "signature OK" || die "the APK's signature"
  took "Android export"
fi
if [ "$PC" = "1" ]; then
  step "Windows Desktop Prod"
  gd export_pc --headless --path "$SG" --export-release "Windows Desktop Prod" "$EXE"
  [ -s "$EXE" ] || die "the PC export failed ($LOGS/export_pc.log)"
  python -c "import os,sys;print('%.1f MiB' % (os.path.getsize(sys.argv[1])/1048576))" "$EXE"
  python tools/exe_info.py "$EXE" --expect-version "$(grep -m1 '^config/version=' "$ROOT/game/project.godot" | sed 's/.*="\(.*\)"/\1/')" || echo "WARNING: the exe's version info is not the game's version"
  if [ -f "$ROOT/tools/keys/codesign.env" ]; then
    ( set -a; . "$ROOT/tools/keys/codesign.env"; set +a; powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/tools/sign_exe.ps1" -Exe "$EXE" ) || die "signing the exe"
  fi
  took "PC export"
  step "the exe's cold start"
  python tools/prod_probe.py "$EXE" --expect prod --repeat 3 --work "$OUT/probe" --out "$OUT/probe.json" || die "the prod exe's launch check"
  took "probe"
fi

step "the numbers"
DEVP=""
[ -f "$OUT/probe_dev.json" ] && DEVP="--dev-probe $OUT/probe_dev.json"
python tools/prod_report.py --out "$OUT" $DEVP
took "report"

if [ "$DRIVE" = "1" ]; then
  step "Google Drive"
  for D in /e/"My Drive" /g/"My Drive" /h/"My Drive" /i/"My Drive" "$USERPROFILE/My Drive" "$USERPROFILE/Google Drive"; do
    if [ -d "$D" ]; then
      mkdir -p "$D/88fits builds"
      [ -s "$APK" ] && cp -f "$APK" "$D/88fits builds/88fits-prod.apk" && echo "copied to Google Drive: $D/88fits builds/88fits-prod.apk"
      [ -s "$EXE" ] && cp -f "$EXE" "$D/88fits builds/88fits-prod.exe" && echo "copied to Google Drive: $D/88fits builds/88fits-prod.exe (copy it to a local folder and run it there)"
      break
    fi
  done
fi

step "done in $(( $(date +%s) - T0 )) s"
printf "$TIMES"
[ -s "$APK" ] && echo "APK: $APK"
[ -s "$EXE" ] && echo "EXE: $EXE"
echo "report: $OUT/report.md"
