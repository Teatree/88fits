#!/bin/bash
# usage: bash tools/godot.sh <godot args...>      (from any working directory)
# Runs the Godot binary under the repo-wide Godot lock (tools/dl/locks/godot.lock, owner.json written) with the PC save
# kept aside and put back after, whatever the exit code (pass 66; replaces tools/dl/p6X/godot.sh). One Godot process at
# a time across lanes and the Level Editor's server. The exit code is Godot's.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT" || exit 1
exec python "$ROOT/tools/locks.py" godot -- "$@"
