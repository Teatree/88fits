#!/bin/bash
# Serve the latest build to the phone over Wi-Fi: prints the address to open in the phone's browser.
# The phone must be on the same network as this PC (its own Wi-Fi hotspot counts). Ctrl+C stops the server.
#   bash tools/serve_apk.sh            # serves game/export/ on port 8088
cd "$(dirname "$0")/../game/export" || exit 1
PORT="${1:-8088}"
APK="$(ls -t *.apk 2>/dev/null | head -n 1)"
[ -z "$APK" ] && { echo "no APK in game/export; run tools/ship.sh first"; exit 1; }
echo "Serving $APK"
for ip in $(ipconfig 2>/dev/null | grep -E "IPv4" | sed 's/.*: //'); do
  echo "  http://$ip:$PORT/$APK"
done
echo "On the phone: open one of those addresses in the browser, download, tap the file, allow installs from the browser once."
python -m http.server "$PORT" --bind 0.0.0.0
