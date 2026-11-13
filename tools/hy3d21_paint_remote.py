# Runs ON THE AI SERVER in ~/ai/hy3dpaint/.venv21 (2026-11-13): Hunyuan3D-2.1 Paint (PBR: albedo + metallic/roughness)
# on a Hunyuan3D shape. Writes <out>.obj with its textures; the GLB is assembled on the PC by tools/blender_glb_finish.py
# (the repo's own OBJ->GLB step needs bpy 4.0, which has no Python 3.12 build: a stub stands in for it).
#   python hy3d21_paint_remote.py <shape.glb> <rgba.png> <out_dir> [views=9] [res=768]
import os, sys, types, time
REPO = os.path.expanduser("~/ai/hy3dpaint/Hunyuan3D-2.1")
sys.modules.setdefault("bpy", types.ModuleType("bpy"))
os.chdir(REPO)
sys.path.insert(0, os.path.join(REPO, "hy3dpaint"))
sys.path.insert(0, REPO)
from utils.torchvision_fix import apply_fix
apply_fix()
from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig
src, img, out = [os.path.abspath(os.path.expanduser(p)) for p in sys.argv[1:4]]
views = int(sys.argv[4]) if len(sys.argv) > 4 else 9
res = int(sys.argv[5]) if len(sys.argv) > 5 else 768
os.makedirs(out, exist_ok=True)
t0 = time.time()
conf = Hunyuan3DPaintConfig(views, res)
conf.realesrgan_ckpt_path = os.path.join(REPO, "hy3dpaint", "ckpt", "RealESRGAN_x4plus.pth")
pipe = Hunyuan3DPaintPipeline(conf)
print("loaded %.0fs" % (time.time() - t0), flush=True)
# the repo's own remesh needs open3d (no ROCm-friendly build here): decimate with pymeshlab first and skip it
import pymeshlab
ms = pymeshlab.MeshSet()
ms.load_new_mesh(src, load_in_a_single_layer=True)
ms.meshing_decimation_quadric_edge_collapse(targetfacenum=40000, preservenormal=True)
mesh_obj = os.path.join(out, "mesh.obj")
ms.save_current_mesh(mesh_obj, save_textures=False)
p = pipe(mesh_path=mesh_obj, image_path=img, output_mesh_path=os.path.join(out, "textured.obj"), use_remesh=False, save_glb=False)
print("done %.0fs ->" % (time.time() - t0), p, sorted(os.listdir(out)), flush=True)
