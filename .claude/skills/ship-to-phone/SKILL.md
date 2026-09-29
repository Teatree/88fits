---
name: ship-to-phone
description: Turn the current state of 88fits into a playable build on Garry's phone: run the checks, export the signed release APK, overwrite it in Google Drive (the route he uses while away), confirm it synced, and tell him where it is. Use at the end of every user-facing change, or when asked for a build.
---

# Ship to the phone

Garry plays and steers this project from his phone, usually away from the PC. A change is not done until a build he
can tap exists. The route in use is Google Drive: Drive for Desktop is signed in on this PC and mounted as `E:`.

## Do

1. `bash tools/ship.sh` from the repo root. It runs the parse check, the unit tests, the smoke run, the arena check and
   the touch audit (every control on every screen driven by a simulated finger), exports the
   signed **release** APK (`game/export/88fits.apk`, keystore in `tools/keys/`, git-ignored), verifies the signature,
   installs and launches on any phone adb can see, and overwrites `E:/My Drive/88fits builds/88fits.apk`.
   `--quick` skips tests and smoke run when only art changed; `--no-install` skips adb.
2. Confirm the sync with the Google Drive connector: search `title contains '88fits.apk'` and check `modifiedTime`
   is within the last few minutes and `fileSize` matches the local file. If the modified time is stale, Drive for
   Desktop is not running: start `C:\Program Files\Google\Drive File Stream\<version>\GoogleDriveFS.exe` and wait a
   minute; if `E:` never appears, the app is signed out and Garry must sign in at the PC (do not automate the sign-in).
3. Tell Garry: "Build is in Drive → My Drive → 88fits builds → 88fits.apk" with what changed, and the folder link
   https://drive.google.com/drive/folders/1DitOJiGvXaY3PXKUegknJJBtPPb-7_SM.

## Do not

- Do not try to push the APK through the Drive connector (`create_file` carries content as text in the request; a
  30 MB binary cannot travel that way) or the chat file card (30 MiB cap; the build is 32 to 34 MiB).
- Do not switch to the debug export: it is signed differently and Android would demand an uninstall.

## Backup route

`bash tools/release.sh "note"` publishes the same APK as the next `build-N` release in a private GitHub repo through the
portable CLI in `tools/dl/gh/`; it needs `tools/dl/gh/bin/gh.exe auth login --web` once (device code typed on the phone).
