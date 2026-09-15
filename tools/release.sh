#!/bin/bash
# Publish the latest signed build as a GitHub release, so the phone can download it from anywhere.
# Uses the GitHub CLI (one-time login: `gh auth login --web`). The builds live in their own private repo so no game
# source is pushed; each run creates the next numbered release with the APK attached and prints its page.
#
#   bash tools/release.sh                 # build first with tools/ship.sh --no-install, then release it
#   bash tools/release.sh "what changed"  # optional note shown on the release page
set -u
cd "$(dirname "$0")/.." || exit 1
GH="$(command -v gh 2>/dev/null)"; [ -z "$GH" ] && GH="/c/Program Files/GitHub CLI/gh.exe"; [ -x "$GH" ] || GH="$(pwd)/tools/dl/gh/bin/gh.exe"
REPO="${BUILDS_REPO:-88fits-builds}"
APK="game/export/88fits.apk"
[ -f "$APK" ] || APK="game/export/88fits-debug.apk"
[ -f "$APK" ] || { echo "no APK in game/export; run tools/ship.sh first"; exit 1; }
NOTE="${1:-build}"
"$GH" auth status > /dev/null 2>&1 || { echo "not logged in: run  gh auth login --web  (device code) first"; exit 1; }
OWNER="$("$GH" api user -q .login)"
if ! "$GH" repo view "$OWNER/$REPO" > /dev/null 2>&1; then
  "$GH" repo create "$REPO" --private --description "88fits phone builds (APK releases only, no source)" > /dev/null && echo "created private repo $OWNER/$REPO"
fi
# the builds repo needs one commit for tags to hang on; make it once
if ! "$GH" api "repos/$OWNER/$REPO/commits?per_page=1" > /dev/null 2>&1; then
  TMP="$(mktemp -d)"; ( cd "$TMP" && git init -q && printf '# 88fits builds\n\nEach release carries the signed APK. Open the latest release on the phone, download the .apk, tap to install.\n' > README.md && git add README.md && git -c user.name=88fits -c user.email=builds@88fits.local commit -q -m "builds repo" && git branch -M main && git remote add origin "https://github.com/$OWNER/$REPO.git" && "$GH" auth setup-git > /dev/null 2>&1; git push -q -u origin main ) && echo "initialised $REPO"
  rm -rf "$TMP"
fi
LAST="$("$GH" release list --repo "$OWNER/$REPO" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null)"
N=1; [[ "$LAST" =~ ^build-([0-9]+)$ ]] && N=$(( ${BASH_REMATCH[1]} + 1 ))
TAG="build-$N"
SIZE="$(ls -la "$APK" | awk '{printf "%.1f MiB", $5/1048576}')"
"$GH" release create "$TAG" "$APK#88fits.apk" --repo "$OWNER/$REPO" --title "88fits $TAG" --notes "$(date '+%Y-%m-%d %H:%M') · $SIZE · $NOTE" --latest > /dev/null && echo "released $TAG ($SIZE)"
echo "download page: https://github.com/$OWNER/$REPO/releases/latest"
