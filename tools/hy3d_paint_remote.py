# runs on the AI server in ~/ai/hy3dpaint/.venv: Hunyuan3D-2 paint (turbo) on a Hunyuan3D shape
import sys, time, trimesh
sys.path.insert(0, "/home/teatree/ai/hy3dpaint/Hunyuan3D-2")
from PIL import Image
from hy3dgen.texgen import Hunyuan3DPaintPipeline
import pymeshlab
src, img, out = sys.argv[1:4]
t0 = time.time()
mesh = trimesh.load(src, force="mesh")
ms = pymeshlab.MeshSet(); ms.add_mesh(pymeshlab.Mesh(mesh.vertices, mesh.faces))
ms.meshing_decimation_quadric_edge_collapse(targetfacenum=40000)
m = ms.current_mesh(); mesh = trimesh.Trimesh(m.vertex_matrix(), m.face_matrix())
print("faces", len(mesh.faces), flush=True)
pipe = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2")
print("loaded %.0fs" % (time.time() - t0), flush=True)
mesh = pipe(mesh, image=Image.open(img))
mesh.export(out)
print("done %.0fs" % (time.time() - t0), flush=True)
