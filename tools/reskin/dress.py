"""A reskin (tools/reskin/README.md), steps 3 and 5 in Blender: a rigged model's GLB, its mesh, rig and animations
untouched, dressed in the material Hunyuan3D-2.1 Paint made on its shape (the hell hound wolf, 2026-11-15). Two steps
around maps.py (Blender has no PIL):
  step=bake    the wolf's own mesh gets a second UV map "HellUV" (Smart UV Project: its own UVs are mirrored, left and
               right share texels, so they could not carry an asymmetric painting); the paint's base colour, roughness and
               metallic are baked onto it from the painted shape (Cycles, selected to active: the same surface), the
               wolf's own alpha (its fur fringes' cut-outs, on its own UVs) too -> maps/*_baked.png, wolf_bake.blend
  step=finish  the normal map (the wolf's own fur normal on its own UVs with the lava cracks pressed in, baked onto
               HellUV), the hell hound material (base colour + alpha cut like the source, metallic-roughness, normal,
               emission), the GLB with the rig and the walk, four previews
  blender -b --python tools/reskin/dress.py -- step=bake src=<wolf.glb> stage=<dir> paint=<dir> maps=<dir>
  blender -b <maps>/wolf_bake.blend --python tools/reskin/dress.py -- step=finish maps=<dir> out=<.glb> prev=<dir> [emit=3] [bump=0.6]
"""
import bpy, sys, os, json, math
from mathutils import Matrix, Vector

args = dict(a.split("=", 1) for a in sys.argv[sys.argv.index("--") + 1:])
STEP = args["step"]
MAPS = os.path.abspath(args["maps"])
os.makedirs(MAPS, exist_ok=True)
RES = int(args.get("res", 2048))


def wolf():
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH" and o.vertex_groups)
    return arm, body


def cycles():
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 4
    scn.cycles.device = "CPU"
    return scn


def target(name, colour):
    im = bpy.data.images.new(name, RES, RES, alpha=True, float_buffer=False)
    im.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    im.generated_color = (0, 0, 0, 1)
    return im


def save(im, fname):
    im.filepath_raw = os.path.join(MAPS, fname)
    im.file_format = "PNG"
    im.save()


def only_active(obj, *sel):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in sel:
        o.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


if STEP == "bake":
    SRC, STAGE, PAINT = (os.path.abspath(args[k]) for k in ("src", "stage", "paint"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm, body = wolf()
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not body:
            print("left out:", o.name)
            bpy.data.objects.remove(o, do_unlink=True)
    arm.data.pose_position = "REST"
    st = json.load(open(os.path.join(STAGE, "stage.json")))
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=os.path.join(PAINT, "textured.obj"))
    painted = next(o for o in bpy.data.objects if o not in before)
    painted.matrix_world = Matrix(st["T"]).inverted() @ painted.matrix_world
    bpy.context.view_layer.update()
    # HellUV: Smart UV Project on the wolf's own mesh (its own UVMap kept)
    me = body.data
    orig_uv = me.uv_layers.active.name
    hell = me.uv_layers.new(name="HellUV")
    me.uv_layers.active = hell
    only_active(body)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("HellUV made; the wolf's own UV map:", orig_uv)
    scn = cycles()
    bk = scn.render.bake
    # the painted shape's maps as emission (unlit), one at a time
    pmat = painted.data.materials[0]
    pnt = pmat.node_tree
    pout = next(n for n in pnt.nodes if n.type == "OUTPUT_MATERIAL")
    pem = pnt.nodes.new("ShaderNodeEmission")
    pnt.links.new(pem.outputs[0], pout.inputs["Surface"])
    puv = pnt.nodes.new("ShaderNodeUVMap"); puv.uv_map = painted.data.uv_layers.active.name
    # the wolf's bake material: a target image node, active
    bm = bpy.data.materials.new("bake_target")
    bm.use_nodes = True
    bnt = bm.node_tree
    old = me.materials[0]
    me.materials.clear()
    me.materials.append(bm)
    tnode = bnt.nodes.new("ShaderNodeTexImage")
    bnt.nodes.active = tnode
    for name, fname, colour in (("albedo", "textured.jpg", True), ("rough", "textured_roughness.jpg", False), ("metal", "textured_metallic.jpg", False)):
        pim = pnt.nodes.new("ShaderNodeTexImage")
        pim.image = bpy.data.images.load(os.path.join(PAINT, fname))
        pim.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        pnt.links.new(puv.outputs["UV"], pim.inputs["Vector"])
        pnt.links.new(pim.outputs["Color"], pem.inputs["Color"])
        im = target("hell_%s_baked" % name, colour)
        tnode.image = im
        only_active(body, painted)
        bk.use_selected_to_active = True
        bk.cage_extrusion = 0.004
        bk.max_ray_distance = 0.02
        bk.margin = 16
        bk.margin_type = "EXTEND"
        bpy.ops.object.bake(type="EMIT", use_selected_to_active=True, cage_extrusion=0.004, max_ray_distance=0.02, margin=16, margin_type="EXTEND", uv_layer="HellUV")
        save(im, "hell_%s_baked.png" % name)
        print("baked", name)
    # the wolf's own alpha (its fur fringes), from its own texture on its own UVs, onto HellUV
    dimg = next(n.image for n in old.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and "_d" in n.image.name)
    nimg = next((n.image for n in old.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and n.image.name.endswith("_n.tga")), None)
    cutoff = 0.5
    for n in old.node_tree.nodes:
        if n.type == "MATH" and n.operation in ("LESS_THAN", "GREATER_THAN"):
            cutoff = float(n.inputs[1].default_value)
    bout = next(n for n in bnt.nodes if n.type == "OUTPUT_MATERIAL")
    bem = bnt.nodes.new("ShaderNodeEmission")
    buv = bnt.nodes.new("ShaderNodeUVMap"); buv.uv_map = orig_uv
    bd = bnt.nodes.new("ShaderNodeTexImage"); bd.image = dimg
    bnt.links.new(buv.outputs["UV"], bd.inputs["Vector"])
    bnt.links.new(bd.outputs["Alpha"], bem.inputs["Color"])
    bnt.links.new(bem.outputs[0], bout.inputs["Surface"])
    im = target("hell_alpha_baked", False)
    tnode.image = im
    bnt.nodes.active = tnode
    only_active(body)
    bpy.ops.object.bake(type="EMIT", use_selected_to_active=False, margin=16, margin_type="EXTEND", uv_layer="HellUV")
    save(im, "hell_alpha_baked.png")
    print("baked alpha; the source's alpha cut-off %.3f" % cutoff)
    # keep the scene for step finish: the wolf's own maps on it, the painted shape gone
    me.materials.clear()
    me.materials.append(old)
    bpy.data.objects.remove(painted, do_unlink=True)
    json.dump({"cutoff": cutoff, "orig_uv": orig_uv, "normal": nimg.name if nimg else ""}, open(os.path.join(MAPS, "bake.json"), "w"))
    for im in bpy.data.images:
        if im.source == "FILE" or im.packed_file is None:
            try:
                im.pack()
            except Exception:
                pass
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(MAPS, "wolf_bake.blend"))
    print("saved", os.path.join(MAPS, "wolf_bake.blend"))

else:
    OUT, PREV = os.path.abspath(args["out"]), os.path.abspath(args["prev"])
    os.makedirs(PREV, exist_ok=True)
    EMIT = float(args.get("emit", 3.0))
    BUMP = float(args.get("bump", 0.6))
    info = json.load(open(os.path.join(MAPS, "bake.json")))
    arm, body = wolf()
    arm.data.pose_position = "REST"
    me = body.data
    old = me.materials[0]
    nimg = bpy.data.images.get(info["normal"]) if info["normal"] else None
    scn = cycles()
    # the normal map: the fur normal (own UVs) with the cracks pressed in (height on HellUV), baked onto HellUV
    bkm = bpy.data.materials.new("bake_normal")
    bkm.use_nodes = True
    nt = bkm.node_tree
    ns, ln = nt.nodes, nt.links
    bsdf = ns["Principled BSDF"]
    uv0 = ns.new("ShaderNodeUVMap"); uv0.uv_map = info["orig_uv"]
    uv1 = ns.new("ShaderNodeUVMap"); uv1.uv_map = "HellUV"
    nm = None
    if nimg:
        on = ns.new("ShaderNodeTexImage"); on.image = nimg; nimg.colorspace_settings.name = "Non-Color"
        ln.new(uv0.outputs["UV"], on.inputs["Vector"])
        nm = ns.new("ShaderNodeNormalMap"); nm.uv_map = info["orig_uv"]
        ln.new(on.outputs["Color"], nm.inputs["Color"])
    hi = ns.new("ShaderNodeTexImage"); hi.image = bpy.data.images.load(os.path.join(MAPS, "hell_height.png")); hi.image.colorspace_settings.name = "Non-Color"
    ln.new(uv1.outputs["UV"], hi.inputs["Vector"])
    bump = ns.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = BUMP; bump.inputs["Distance"].default_value = 0.004
    ln.new(hi.outputs["Color"], bump.inputs["Height"])
    if nm:
        ln.new(nm.outputs["Normal"], bump.inputs["Normal"])
    ln.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    tn = ns.new("ShaderNodeTexImage"); tn.image = target("hell_normal", False)
    tn.image.generated_color = (0.5, 0.5, 1.0, 1.0)
    ns.active = tn
    me.materials.clear()
    me.materials.append(bkm)
    me.uv_layers.active = me.uv_layers["HellUV"]
    only_active(body)
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", use_selected_to_active=False, margin=16, margin_type="EXTEND", uv_layer="HellUV")
    save(tn.image, "hell_normal.png")
    print("normal baked")
    # the hell hound material
    mat = bpy.data.materials.new("hellhound")
    mat.use_nodes = True
    nt = mat.node_tree
    ns, ln = nt.nodes, nt.links
    bsdf = ns["Principled BSDF"]
    uv = ns.new("ShaderNodeUVMap"); uv.uv_map = "HellUV"

    def tex(name, colour):
        n = ns.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(os.path.join(MAPS, name))
        n.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        ln.new(uv.outputs["UV"], n.inputs["Vector"])
        return n

    ta = tex("hell_albedo.png", True)
    ln.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
    # the alpha cut as the glTF importer builds it (1 - (alpha < cutoff)), so the exporter writes alphaMode MASK
    m1 = ns.new("ShaderNodeMath"); m1.operation = "LESS_THAN"; m1.inputs[1].default_value = info["cutoff"]
    m2 = ns.new("ShaderNodeMath"); m2.operation = "SUBTRACT"; m2.inputs[0].default_value = 1.0
    ln.new(ta.outputs["Alpha"], m1.inputs[0])
    ln.new(m1.outputs[0], m2.inputs[1])
    ln.new(m2.outputs[0], bsdf.inputs["Alpha"])
    tm = tex("hell_metal_rough.jpg", False)
    sep = ns.new("ShaderNodeSeparateColor")
    ln.new(tm.outputs["Color"], sep.inputs["Color"])
    ln.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    ln.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    tnm = tex("hell_normal.png", False)
    nmap = ns.new("ShaderNodeNormalMap"); nmap.uv_map = "HellUV"
    ln.new(tnm.outputs["Color"], nmap.inputs["Color"])
    ln.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    te = tex("hell_emission.jpg", True)
    ln.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = EMIT
    mat.surface_render_method = "DITHERED"
    me.materials.clear()
    me.materials.append(mat)
    # the model's own UV map served only its own maps (the normal bake above): gone, so HellUV is the GLB's TEXCOORD_0
    # (an engine that reads only the first UV set shows the new material)
    if info["orig_uv"] in me.uv_layers:
        me.uv_layers.remove(me.uv_layers[info["orig_uv"]])
    arm.data.pose_position = "POSE"
    me.uv_layers.active = me.uv_layers["HellUV"]
    me.uv_layers["HellUV"].active_render = True
    for o in bpy.data.objects:
        o.select_set(o.type in ("MESH", "ARMATURE", "EMPTY"))
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_skins=True,
                              export_image_format="AUTO", export_materials="EXPORT", use_selection=True)
    print("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))
    # previews
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scn.render.resolution_x, scn.render.resolution_y = 1024, 768
    scn.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("w"); scn.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.06, 0.055, 0.06, 1)
    for rot, en in (((math.radians(55), 0, math.radians(-35)), 2.5), ((math.radians(65), 0, math.radians(150)), 0.8)):
        ld = bpy.data.lights.new("sun", "SUN"); ld.energy = en
        lo = bpy.data.objects.new("sun", ld); lo.rotation_euler = rot; scn.collection.objects.link(lo)
    act = arm.animation_data.action if arm.animation_data else None
    if act:
        scn.frame_set(int(act.frame_range[0] + (act.frame_range[1] - act.frame_range[0]) * 0.3))
    bpy.context.view_layer.update()
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    pts = [body.matrix_world @ v.co for v in ev.data.vertices]
    lo_ = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi_ = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (lo_ + hi_) / 2
    R = (hi_ - lo_).length * 0.75
    cd = bpy.data.cameras.new("cam"); cd.lens = 50
    cam = bpy.data.objects.new("cam", cd); scn.collection.objects.link(cam); scn.camera = cam
    for name, az, el in (("left", 90, 8), ("right", 270, 8), ("front34", 35, 18), ("back34", 215, 22), ("top", 120, 55), ("face", 0, 12)):
        a, e = math.radians(az), math.radians(el)
        cam.location = c + Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))) * R * 2.2
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = os.path.join(PREV, "hell_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    print("previews in", PREV)
