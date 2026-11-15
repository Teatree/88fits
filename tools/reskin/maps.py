"""A reskin's maps (tools/reskin/README.md, step 4) from the baked ones (dress.py step=bake), outside Blender (PIL): the base colour with the
wolf's own alpha (its fur fringes), emission (the hot orange-yellow, bright and saturated parts: lava cracks, eyes,
embers), the packed metallic-roughness (glTF: G roughness, B metallic), the crack height for the normal bake.
  python tools/reskin/maps.py <maps dir>   (the glow test fits lava: hot orange-yellow, bright, saturated)"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

MAPS = sys.argv[1]
ld = lambda n, m: np.asarray(Image.open(os.path.join(MAPS, n)).convert(m)).astype(np.float32) / 255
alb = ld("hell_albedo_baked.png", "RGB")
rough = ld("hell_rough_baked.png", "L")
metal = ld("hell_metal_baked.png", "L")
alpha = ld("hell_alpha_baked.png", "L")
mx = alb.max(axis=2)
mn = alb.min(axis=2)
sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
r, b = alb[..., 0], alb[..., 2]
warm = np.clip((r - b) * 2.0, 0, 1)
glow = np.clip((mx - 0.45) / 0.35, 0, 1) * np.clip((sat - 0.35) / 0.3, 0, 1) * warm


def blur(a, rad):
    return np.asarray(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(rad))).astype(np.float32) / 255


glow = blur(glow, 1.0)
# emission and metallic-roughness as JPEG (no alpha; the GLB keeps a JPEG as it is), the base colour (alpha) and the
# normal map stay PNG
Image.fromarray((np.clip(alb * glow[..., None], 0, 1) * 255).astype(np.uint8)).save(os.path.join(MAPS, "hell_emission.jpg"), quality=92)
rough2 = np.clip(rough * (1 - glow) + 0.55 * glow, 0.35, 1.0)
orm = np.stack([np.ones_like(rough2), rough2, metal * (1 - glow) * 0.3], axis=2)
Image.fromarray((orm * 255).astype(np.uint8)).save(os.path.join(MAPS, "hell_metal_rough.jpg"), quality=92)
Image.fromarray(((1.0 - blur(glow, 1.6)) * 255).astype(np.uint8)).save(os.path.join(MAPS, "hell_height.png"))
rgba = np.concatenate([alb, alpha[..., None]], axis=2)
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(MAPS, "hell_albedo.png"))
print("glow covers %.1f%% of the atlas; alpha below 0.5 on %.1f%%" % (100 * float((glow > 0.5).mean()), 100 * float((alpha < 0.5).mean())))
