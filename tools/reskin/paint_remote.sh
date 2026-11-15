#!/bin/bash
# Hunyuan3D-2.1 Paint on the AI server for a reskin (tools/reskin/README.md): under the ComfyUI lock, ComfyUI stopped
# around it and started again after. Writes textured.obj + its albedo, metallic and roughness into <local out dir>.
#   bash tools/reskin/paint_remote.sh <shape.glb> <rgba.png> <local out dir> [views=12] [res=768]
set -e
cd /d/_projects/88fits
SHAPE=$1; RGBA=$2; OUT=$3; VIEWS=${4:-12}; RES=${5:-768}
NAME=reskin_$(basename "$OUT")
SSH="ssh -i $HOME/.ssh/id_ed25519_ai_server -o ConnectTimeout=10 teatree@192.168.137.54"
SCP="scp -i $HOME/.ssh/id_ed25519_ai_server"
WP=$(cat /proc/$$/winpid)
python tools/locks.py acquire comfy "reskin paint" --pid $WP
trap 'python tools/locks.py release comfy --pid '$WP'' EXIT
Q=$(curl -s --max-time 10 http://192.168.137.54:8188/queue | python -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('queue_running',[]))+len(d.get('queue_pending',[])))")
if [ "$Q" != "0" ]; then echo "ComfyUI is busy ($Q in its queue): not stopping it"; exit 2; fi
$SSH "mkdir -p ~/ai/hy3dpaint/$NAME && rm -rf ~/ai/hy3dpaint/$NAME/out"
$SCP "$SHAPE" teatree@192.168.137.54:ai/hy3dpaint/$NAME/shape.glb
$SCP "$RGBA" teatree@192.168.137.54:ai/hy3dpaint/$NAME/ref.png
$SCP tools/hy3d21_paint_remote.py teatree@192.168.137.54:ai/hy3dpaint/hy3d21_paint_remote.py
$SSH "systemctl --user stop ai-comfyui.service"
set +e
$SSH "cd ~/ai/hy3dpaint && export LD_LIBRARY_PATH=~/ai/ComfyUI/.venv-rocm/lib/python3.12/site-packages/_rocm_sdk_core/lib && .venv21/bin/python hy3d21_paint_remote.py ~/ai/hy3dpaint/$NAME/shape.glb ~/ai/hy3dpaint/$NAME/ref.png ~/ai/hy3dpaint/$NAME/out $VIEWS $RES 2>&1 | tail -6"
RC=$?
set -e
$SSH "systemctl --user start ai-comfyui.service"
mkdir -p "$OUT"
$SCP -r "teatree@192.168.137.54:ai/hy3dpaint/$NAME/out/*" "$OUT/"
ls -la "$OUT"
echo "paint exit $RC"
