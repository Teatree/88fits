#!/bin/bash
# lane UIREVIEW: every capture docs/ui_review uses, into tools/dl/p116/UIREVIEW/<set>/
cd D:/_projects/88fits
D=D:/_projects/88fits/tools/dl/p116/UIREVIEW
run() { name=$1; shift; mkdir -p $D/$name; echo "== $name $(date +%T)"; GODOT_TIMEOUT=900 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --log-file $D/$name.log "$@"; echo "exit $? $(ls $D/$name | wc -l) files"; }
run wanted --script res://tools/wanted_shots.gd -- out=$D/wanted
run uidoc --script res://tools/uidoc_shots.gd -- out=$D/uidoc
run bible --script res://tools/screenshot_run.gd -- out=$D/bible
run bounty --script res://tools/_p112_wanted_shots.gd -- out=$D/bounty
run skins --script res://tools/_p111_skins_shot.gd -- out=$D/skins
run results --script res://tools/_p116_RESULTS_shots.gd -- out=$D/results only=results
run meta --script res://tools/_p115_META_shots.gd -- out=$D/meta
echo ALLDONE
