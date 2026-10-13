"""Lane B's checks (pass 66): the method catalogue (methods.json), the example pictures, the driver folders' meta.json and
the pure helpers of tools/blender_ref.py and tools/pose_driver.py. selftest.py discovers this file and calls
`checks(check, run_node, server)`; nothing here writes under game/ or runs Blender."""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TOOLS = os.path.join(ROOT, "tools")

METHOD_IDS = ["hero_pose5", "hero_fit", "creature_free2", "creature_pose2", "creature_free8", "creature_ctl", "creature_proc",
              "front_from_picture", "recolour", "item_icon", "icon_cands", "hero_badge", "hero_title", "driver_pose", "driver_depth",
              "ref_probe", "ref_render", "driver_tweak", "hero_puppet"]   # pass 70: driver_tweak (lane LE); pass 71: hero_puppet (lane PLE)
KNOWN_TOOLS = {"gen_art", "gen_ctl", "gen_edit_stills", "gen_icon_cands", "gen_badge_cands", "gen_title_heroes", "recolour_strip",
               "pose_driver", "blender_depth_drivers", "blender_ref", "pose_fit", "pose_spread", "pose_scale", "pose_occlude", "pose_shoulders",
               "puppet"}   # pass 71: tools/puppet.py (hero_puppet)
FIELD_TYPES = {"number", "int", "text", "textarea", "select", "driver", "file", "bool", "json", "view_words", "view_numbers"}   # pass 70: view_numbers (run_scale)
REQUIRED = ["id", "name", "kind", "summary", "needs", "produces", "time", "weaknesses", "example", "recipe_fields", "refs", "runner"]
KINDS = {"enemy", "hero", "item", "driver", "ref"}
REF_USES = {"icon", "look", "animation"}
MAX_EXAMPLE = 150 * 1024


def checks(check, run_node, server):
    path = os.path.join(HERE, "methods.json")
    check(os.path.exists(path), "methods.json exists")
    m = json.load(open(path, encoding="utf-8"))
    methods = m.get("methods", [])
    ids = [x.get("id") for x in methods]
    check(sorted(ids) == sorted(METHOD_IDS), "methods.json holds every method of the synthesis, once: %s" % sorted(set(METHOD_IDS) ^ set(ids)))
    used_images = set()
    for meth in methods:
        mid = meth.get("id")
        for k in REQUIRED:
            check(k in meth, "%s has %s" % (mid, k))
        check(meth.get("kind") in KINDS, "%s kind %r" % (mid, meth.get("kind")))
        t = meth.get("time") or {}
        check(isinstance(t.get("median_s"), (int, float)) and isinstance(t.get("worst_s"), (int, float)) and t["worst_s"] >= t["median_s"] > 0,
              "%s time median/worst: %s" % (mid, t))
        check(isinstance(meth.get("weaknesses"), list) and meth["weaknesses"] and all(isinstance(w, str) and w for w in meth["weaknesses"]),
              "%s names its weaknesses" % mid)
        check(isinstance(meth.get("needs"), list) and isinstance(meth.get("produces"), str) and meth["produces"], "%s needs/produces" % mid)
        check(isinstance(meth.get("summary"), str) and len(meth["summary"]) >= 120, "%s has a real summary paragraph" % mid)
        ex = meth.get("example") or {}
        img = ex.get("image", "")
        check(img.startswith("examples/") and img.endswith(".png"), "%s example image path %r" % (mid, img))
        used_images.add(img.split("/", 1)[-1])
        ip = os.path.join(HERE, img)
        check(os.path.exists(ip), "%s example picture exists: %s" % (mid, img))
        if os.path.exists(ip):
            check(os.path.getsize(ip) <= MAX_EXAMPLE, "%s example <= 150 KB (%d)" % (mid, os.path.getsize(ip)))
        strip = ex.get("strip")
        check(strip is None or (isinstance(strip, dict) and strip.get("kind") in ("enemy", "hero", "item") and strip.get("id")),
              "%s example strip %r" % (mid, strip))
        runner = meth.get("runner") or {}
        check(runner.get("tool") in KNOWN_TOOLS, "%s runner.tool %r is a known tool" % (mid, runner.get("tool")))
        check(isinstance(runner.get("call"), str) and runner["call"], "%s runner.call" % mid)
        check(isinstance(runner.get("argv"), list), "%s runner.argv is a list" % mid)
        for f in list(meth.get("recipe_fields", [])) + list(meth.get("job_fields", [])):
            check(f.get("type") in FIELD_TYPES, "%s field %r type %r" % (mid, f.get("key"), f.get("type")))
            check(isinstance(f.get("key"), str) and f["key"] and isinstance(f.get("help"), str) and f["help"], "%s field %r has key and help" % (mid, f.get("key")))
            if f.get("type") == "select":
                check(isinstance(f.get("options"), list) and f["options"], "%s select %r has options" % (mid, f.get("key")))
        refs = meth.get("refs") or {}
        check(isinstance(refs.get("2d"), bool) and isinstance(refs.get("3d"), list) and set(refs["3d"]) <= REF_USES, "%s refs %r" % (mid, refs))
    # the recipe keys gen_art and gen_ctl read must be offered somewhere
    keys = {f["key"] for meth in methods for f in meth.get("recipe_fields", [])}
    for k in ("art_prompt", "stills", "motion", "pose", "pose_front", "stand", "death", "dead_hint", "walk", "hop_height", "directions",
              "view_hints", "drivers", "look_ref", "death_drivers", "death_keep", "remap_hues", "still_keys", "pose_motion", "anim_seed", "screen"):
        check(k in keys, "recipe key %s is offered by some method" % k)
    check(any(f["key"].startswith("pose_drivers") for meth in methods for f in meth.get("recipe_fields", [])), "hero pose_drivers per view are offered")
    # every example picture on disk is referenced by a method, and none is over the cap
    for p in glob.glob(os.path.join(HERE, "examples", "*.png")):
        check(os.path.basename(p) in used_images, "example %s is referenced by a method" % os.path.basename(p))
        check(os.path.getsize(p) <= MAX_EXAMPLE, "example %s <= 150 KB" % os.path.basename(p))
    # the wordings table and the texts for the form
    rows = m.get("ref_wordings", [])
    check(len(rows) >= 8, "ref_wordings has the synthesis's rows (%d)" % len(rows))
    for r in rows:
        check(all(k in r for k in ("role", "level", "text", "source")), "ref_wordings row has role/level/text/source: %s" % r.get("role"))
    roles = {(r["role"], r["level"]) for r in rows}
    for want in (("style", "fixed"), ("identity", "loosely"), ("identity", "closely"), ("identity", "copy exactly"), ("pose", "closely"),
                 ("view", "fixed"), ("held object", "copy exactly"), ("mark", "copy exactly")):
        check(want in roles, "ref_wordings has %s / %s" % want)
    check("no strength" in m.get("ref_note", ""), "ref_note says there is no strength number")
    ins = m.get("insert_3d_text", "")
    for w in ("FBX Binary", "30 fps", "In Place", "keyframe reduction", "GLB", "without an animation", "icon"):
        check(w in ins, "insert_3d_text mentions %r" % w)
    check(len(m.get("timings_note", "")) > 100, "timings_note is written")
    # driver folders: every meta.json parses and says its kind (lane S's /api/drivers reads it); skipped where the
    # (gitignored) library is absent
    drivers = os.path.join(ROOT, "tools", "dl", "drivers")
    metas = glob.glob(os.path.join(drivers, "*", "meta.json"))
    if metas:
        bad = []
        for p in metas:
            try:
                d = json.load(open(p, encoding="utf-8"))
            except Exception as e:
                bad.append("%s: %s" % (p, e))
                continue
            if d.get("kind") not in ("pose", "depth"):
                bad.append("%s: kind %r" % (os.path.basename(os.path.dirname(p)), d.get("kind")))
            elif d["kind"] == "pose" and not (d.get("fbx") or d.get("src")):
                bad.append("%s: a pose driver without fbx/src" % os.path.basename(os.path.dirname(p)))
            elif not isinstance(d.get("views"), list) or not d["views"]:
                bad.append("%s: no views" % os.path.basename(os.path.dirname(p)))
        check(not bad, "every driver meta.json parses with kind pose|depth and views: %s" % bad[:5])
        print("drivers: %d meta.json files checked" % len(metas))
    # the pure helpers of the Blender scripts (importable without bpy)
    sys.path.insert(0, TOOLS)
    try:
        import blender_ref as br
        import pose_driver as pd
    finally:
        sys.path.remove(TOOLS)
    mix = ["mixamorig:" + n for n in ("Hips", "Spine", "Neck", "Head", "LeftUpLeg", "RightUpLeg", "LeftArm", "RightArm", "LeftFoot", "RightFoot")]
    check(br.rig_guess(mix) == "mixamo", "rig_guess: the Mixamo core after the prefix strip")
    check(br.rig_guess(["Bone_SM_Pelvis", "Bone_SM_Head"]) == "sm", "rig_guess: Bone_SM_*")
    check(br.rig_guess(["Bone", "Bone.003_L"]) == "other" and br.rig_guess([]) == "none", "rig_guess: other / none")
    ue = ["root", "pelvis", "spine_01", "spine_02", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l",
          "foot_l", "ball_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r", "thigh_twist_01_l", "ik_hand_r"]
    g = br.rigmap_guess(ue)
    want = {"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Neck": "neck_01", "Head": "head", "LeftShoulder": "clavicle_l",
            "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l", "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l",
            "LeftFoot": "foot_l", "LeftToeBase": "ball_l", "RightHand": "hand_r", "RightUpLeg": "thigh_r", "RightToeBase": "ball_r"}
    check(all(g.get(k) == v for k, v in want.items()), "rigmap_guess maps a UE-style rig: %s" % {k: g.get(k) for k in want if g.get(k) != want[k]})
    hik = ["Character1_Hips", "Character1_Spine", "Character1_Neck", "Character1_Head", "Character1_LeftUpLeg", "Character1_LeftLeg",
           "Character1_LeftFoot", "Character1_LeftToeBase", "Character1_LeftShoulder", "Character1_LeftArm", "Character1_LeftForeArm",
           "Character1_LeftHand", "Character1_RightUpLeg", "Character1_RightLeg", "Character1_RightFoot", "Character1_RightArm",
           "Character1_RightForeArm", "Character1_RightHand"]
    g2 = br.rigmap_guess(hik)
    check(g2.get("LeftForeArm") == "Character1_LeftForeArm" and g2.get("RightUpLeg") == "Character1_RightUpLeg" and g2.get("LeftHand") == "Character1_LeftHand"
          and g2.get("Hips") == "Character1_Hips", "rigmap_guess reads CamelCase HumanIK names")
    check(all(g2.get(c) for c in br.MIXAMO_CORE), "a HumanIK rig counts as a humanoid through the guess")
    check(br.strip_prefix("mixamorig:Hips") == "Hips" and br.parse_rgb("blue") == (0.0, 0.0, 1.0) and br.parse_rgb("0,1,0") == (0.0, 1.0, 0.0), "strip_prefix / parse_rgb")
    check(br.args(["blender", "--python", "x.py", "--", "src=a b.fbx", "mode=probe"]) == {"src": "a b.fbx", "mode": "probe"}, "args after --")
    # pose_driver's rigmap reader takes both orientations
    import tempfile
    tmp = tempfile.mkdtemp(prefix="le_b_")
    p1 = os.path.join(tmp, "a.json")
    json.dump({"Hips": "pelvis", "LeftArm": "upperarm_l", "HeadTop_End": None}, open(p1, "w"))
    p2 = os.path.join(tmp, "b.json")
    json.dump({"pelvis": "Hips", "upperarm_l": "LeftArm"}, open(p2, "w"))
    check(pd._load_rigmap(p1) == {"pelvis": "Hips", "upperarm_l": "LeftArm"}, "pose_driver rigmap: the probe's {Mixamo: model} is turned round, empty rows dropped")
    check(pd._load_rigmap(p2) == {"pelvis": "Hips", "upperarm_l": "LeftArm"}, "pose_driver rigmap: {model: Mixamo} as it is")
    src = open(os.path.join(TOOLS, "pose_driver.py"), encoding="utf-8").read()
    check('"kind": "pose"' in src and "rigmap" in src and "probe" in src, "pose_driver writes kind pose and takes rigmap= / probe=1")
    dd = open(os.path.join(TOOLS, "blender_depth_drivers.py"), encoding="utf-8").read()
    check('"kind": "depth"' in dd and "amp_bones" in dd and "oneshot" in dd, "blender_depth_drivers writes kind depth and takes amp_bones / mode=oneshot")
    print("lane B: methods.json %d methods, %d wordings; %d example pictures" % (len(methods), len(rows), len(used_images)))
