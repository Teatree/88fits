"""Sprite animation through video generation (the proven route: one still -> a short clip of the character moving in
place -> the loop cut into frames). Uses Wan 2.2 14B image-to-video on the ComfyUI server with the lightx2v 4-step
LoRAs, exactly like the official ComfyUI "Wan2.2 14B i2v" template (two-stage high/low noise sampling, shift 5).

    frames = animate.cycle(still_rgb, key, "running in place, side view", seed)   -> list of 8 RGBA frames

Every frame is chroma-keyed, the run period is found by comparing silhouettes, and eight evenly spaced frames of one
period are returned cropped to the union box, so the bounce of the run survives. Clips are cached in
tools/dl/ai_anim/<key>/ with a contact sheet for review. Debug: python tools/animate.py <still.png> "<motion>" [seed]
"""
import io, json, os, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy, artkit
import numpy as np
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANIM = os.path.join(REPO, "tools", "dl", "ai_anim")

WAN_HIGH = "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
WAN_LOW = "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
WAN_LORA_HIGH = "wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
WAN_LORA_LOW = "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
WAN_CLIP = "umt5_xxl_fp8_e4m3fn_scaled.safetensors"
WAN_VAE = "wan_2.1_vae.safetensors"

NEGATIVE = ("camera movement, camera pan, zoom, dolly, the character walks across the frame, background scenery, ground, floor, "
            "shadow, blurry, low quality, deformed, extra limbs, missing limbs, text, watermark, static image, frozen")


def wan_i2v(prompt, image_name, seed, width=640, height=640, length=49, negative=NEGATIVE, prefix="88fits/anim"):
    """Wan 2.2 14B image-to-video, lightx2v 4 steps (2 high-noise + 2 low-noise), frames saved as PNGs."""
    g = comfy.Graph()
    hi = g.add("UNETLoader", "Wan 2.2 high noise", unet_name=WAN_HIGH, weight_dtype="default")
    lo = g.add("UNETLoader", "Wan 2.2 low noise", unet_name=WAN_LOW, weight_dtype="default")
    hi = g.add("LoraLoaderModelOnly", "lightx2v high", model=(hi, 0), lora_name=WAN_LORA_HIGH, strength_model=1.0)
    lo = g.add("LoraLoaderModelOnly", "lightx2v low", model=(lo, 0), lora_name=WAN_LORA_LOW, strength_model=1.0)
    hi = g.add("ModelSamplingSD3", model=(hi, 0), shift=5.0)
    lo = g.add("ModelSamplingSD3", model=(lo, 0), shift=5.0)
    clip = g.add("CLIPLoader", "umt5 text encoder", clip_name=WAN_CLIP, type="wan", device="default")
    vae = g.add("VAELoader", vae_name=WAN_VAE)
    pos = g.add("CLIPTextEncode", "motion prompt", clip=(clip, 0), text=prompt)
    neg = g.add("CLIPTextEncode", "negative", clip=(clip, 0), text=negative)
    img = g.add("LoadImage", "still", image=image_name)
    i2v = g.add("WanImageToVideo", positive=(pos, 0), negative=(neg, 0), vae=(vae, 0), width=width, height=height, length=length, batch_size=1, start_image=(img, 0))
    s1 = g.add("KSamplerAdvanced", "high noise 0-2", model=(hi, 0), add_noise="enable", noise_seed=seed, steps=4, cfg=1.0, sampler_name="euler", scheduler="simple",
               positive=(i2v, 0), negative=(i2v, 1), latent_image=(i2v, 2), start_at_step=0, end_at_step=2, return_with_leftover_noise="enable")
    s2 = g.add("KSamplerAdvanced", "low noise 2-4", model=(lo, 0), add_noise="disable", noise_seed=0, steps=4, cfg=1.0, sampler_name="euler", scheduler="simple",
               positive=(i2v, 0), negative=(i2v, 1), latent_image=(s1, 0), start_at_step=2, end_at_step=10000, return_with_leftover_noise="disable")
    dec = g.add("VAEDecode", samples=(s2, 0), vae=(vae, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


WAN_ANIMATE = "wan2.2_animate_14B_fp8_e4m3fn_scaled_KJ.safetensors"
WAN_ANIMATE_LORA = "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
WAN_CLIP_VISION = "clip_vision_h.safetensors"


def wan_animate(prompt, ref_name, pose_names, seed, width=640, height=640, negative=NEGATIVE, prefix="88fits/pose", steps=4):
    """Wan 2.2 Animate 14B: the still as the character reference, our OpenPose drivers as the motion. The distilled
    LoRA makes it a 4-step cfg-1 job. Output frames (len(pose_names)) are saved as PNGs."""
    g = comfy.Graph()
    m = g.add("UNETLoader", "Wan 2.2 Animate", unet_name=WAN_ANIMATE, weight_dtype="default")
    m = g.add("LoraLoaderModelOnly", "lightx2v distill", model=(m, 0), lora_name=WAN_ANIMATE_LORA, strength_model=1.0)
    m = g.add("ModelSamplingSD3", model=(m, 0), shift=8.0)
    clip = g.add("CLIPLoader", "umt5 text encoder", clip_name=WAN_CLIP, type="wan", device="default")
    vae = g.add("VAELoader", vae_name=WAN_VAE)
    cv = g.add("CLIPVisionLoader", clip_name=WAN_CLIP_VISION)
    pos = g.add("CLIPTextEncode", "prompt", clip=(clip, 0), text=prompt)
    neg = g.add("CLIPTextEncode", "negative", clip=(clip, 0), text=negative)
    ref = g.add("LoadImage", "character still", image=ref_name)
    cve = g.add("CLIPVisionEncode", clip_vision=(cv, 0), image=(ref, 0), crop="none")
    batch = None
    for k, name in enumerate(pose_names):
        li = g.add("LoadImage", "pose %02d" % k, image=name)
        batch = li if batch is None else g.add("ImageBatch", image1=(batch, 0), image2=(li, 0))
    anim = g.add("WanAnimateToVideo", positive=(pos, 0), negative=(neg, 0), vae=(vae, 0), width=width, height=height, length=len(pose_names),
                 batch_size=1, continue_motion_max_frames=5, video_frame_offset=0, clip_vision_output=(cve, 0), reference_image=(ref, 0), pose_video=(batch, 0))
    ks = g.add("KSampler", model=(m, 0), seed=seed, steps=steps, cfg=1.0, sampler_name="euler", scheduler="simple", denoise=1.0,
               positive=(anim, 0), negative=(anim, 1), latent_image=(anim, 2))
    trim = g.add("TrimVideoLatent", samples=(ks, 0), trim_amount=(anim, 3))
    dec = g.add("VAEDecode", samples=(trim, 0), vae=(vae, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


def cycle_pose(still_rgb, key, driver_dir, seed=0, size=640, prompt_hint="", tries=2, negative_extra="", loop=True, motion="running in place on the spot like on a treadmill"):
    """One run/walk cycle driven by OpenPose frames in `driver_dir` (driver_NN.png, the last repeating the first).
    Returns (frames, meta): n RGBA keyed frames of the loop (the repeated frame dropped), cropped to a common box.
    Cached in ANIM/<key>/ like cycle(); no period detection, every driver frame is a sprite frame."""
    os.makedirs(os.path.join(ANIM, key), exist_ok=True)
    meta_p = os.path.join(ANIM, key, "cycle.json")
    drivers = sorted(f for f in os.listdir(driver_dir) if f.startswith("driver_") and f.endswith(".png"))
    n_out = len(drivers) - 1 if loop else len(drivers)   # a loop's last driver repeats the first and is dropped
    if os.path.exists(meta_p):
        meta = json.load(open(meta_p, encoding="utf-8"))
        if meta.get("pose") and meta.get("n_out") == n_out:
            frames = [Image.open(os.path.join(ANIM, key, "out_%02d.png" % k)).convert("RGBA") for k in range(n_out)]
            if len(frames) == n_out:
                return frames, meta
    still, bg = _prep_still(still_rgb, size)
    ref_name = comfy.upload_pil(still, key + "_still.png")
    pose_names = [comfy.upload(open(os.path.join(driver_dir, f), "rb").read(), key + "_" + f) for f in drivers]
    colour = "blue" if bg[2] > bg[1] else "green"
    prompt = ("A 2D anime game character sprite" + (", " + prompt_hint if prompt_hint else "") + ", following the motion exactly, " + motion +
              ", the same character, outfit and colours as the reference in every frame, crisp clean line art, cel shading. The camera is "
              "completely locked off and static. The background is a flat solid " + colour + " color with nothing in it, no ground plane, no shadow.")
    last_err = None
    for attempt in range(tries):
        s = seed + attempt * 7919
        neg = NEGATIVE + (", " + negative_extra if negative_extra else "")
        pngs, secs = comfy.run(wan_animate(prompt, ref_name, pose_names, s, size, size, negative=neg, prefix="88fits/pose_" + key), timeout=3600)
        raw = [Image.open(io.BytesIO(b)).convert("RGB") for b in pngs]
        if len(raw) < n_out:
            last_err = "got %d frames for %d drivers" % (len(raw), n_out)
            print("  pose %-24s seed %-7d %5.0fs  retry: %s" % (key, s, secs, last_err), flush=True)
            continue
        keyed = [artkit.key_background(im, 0.16, 0.7) for im in raw[:n_out]]
        boxes = []
        bad = 0
        for f in keyed:
            a = np.asarray(f)[..., 3] > 127
            ys, xs = np.nonzero(a)
            if len(xs) < 50:
                bad += 1
                continue
            boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
            if xs.min() < 4 or ys.min() < 4 or xs.max() > size - 5 or ys.max() > size - 5:
                bad += 1
        if bad > n_out * 0.1 or len(boxes) < n_out * 0.8:
            last_err = "figure left the frame in %d of %d frames" % (bad, n_out)
            print("  pose %-24s seed %-7d %5.0fs  retry: %s" % (key, s, secs, last_err), flush=True)
            continue
        x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes); x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
        pad = 6
        box = (max(0, x0 - pad), max(0, y0 - pad), min(size, x1 + pad + 1), min(size, y1 + pad + 1))
        out = [f.crop(box) for f in keyed]
        for k, f in enumerate(out):
            f.save(os.path.join(ANIM, key, "out_%02d.png" % k))
        for k, f in enumerate(keyed):
            f.save(os.path.join(ANIM, key, "full_%02d.png" % k))
        artkit.contact_sheet(out, n_out, 200).save(os.path.join(ANIM, key, "cycle_sheet.png"))
        meta = {"key": key, "seed": s, "pose": True, "driver_dir": os.path.abspath(driver_dir), "n_out": n_out, "frames": len(raw),
                "box": [int(v) for v in box], "seconds": round(secs, 1), "prompt": prompt}
        json.dump(meta, open(meta_p, "w", encoding="utf-8", newline=chr(10)), indent=1)
        print("  pose %-24s seed %-7d %5.0fs  %d frames, box %s" % (key, s, secs, n_out, box), flush=True)
        return out, meta
    raise RuntimeError("no usable pose clip for %s: %s" % (key, last_err))


def _prep_still(still_rgb, size=640, fill=0.72):
    """The still goes in centred on its own screen colour with room around it, so the character can move without clipping."""
    keyed = artkit.crop_alpha(artkit.key_background(still_rgb))
    arr = np.asarray(still_rgb.convert("RGB")).astype(np.float32) / 255.0
    edge = np.concatenate([arr[:16, :, :].reshape(-1, 3), arr[:, :16, :].reshape(-1, 3)])
    bg = tuple(int(v * 255) for v in np.median(edge, axis=0))
    canvas = Image.new("RGB", (size, size), bg)
    scale = min(size * fill / keyed.width, size * fill / keyed.height)
    w, h = max(1, int(keyed.width * scale)), max(1, int(keyed.height * scale))
    small = keyed.resize((w, h), Image.LANCZOS)
    canvas.paste(small, ((size - w) // 2, int(size * 0.86) - h), small)
    return canvas, bg


def _silhouettes(frames_rgba, n=24):
    feats = []
    for f in frames_rgba:
        a = f.getchannel("A").resize((n, n), Image.BILINEAR)
        feats.append(np.asarray(a).astype(np.float32).ravel() / 255.0)
    return feats


def find_cycle(frames_rgba, skip=8, pmin=10, pmax=48):
    """Period and start of the most repeatable loop: minimise the silhouette distance between t and t + period."""
    feats = _silhouettes(frames_rgba)
    n = len(feats)
    best = (1e9, 12, skip)
    scores = {}
    for p in range(pmin, min(pmax, n - skip - 1) + 1):
        for s in range(skip, n - p):
            d = np.mean(np.abs(feats[s] - feats[s + p]))
            # prefer the earliest good start so a long clip does not drift; tiny bias towards longer periods (smoother)
            score = d + 0.0004 * (s - skip) - 0.0006 * p
            scores[(p, s)] = score
            if score < best[0]:
                best = (score, p, s)
    # a side or front view looks the same every half stride (left leg forward vs right leg forward), so the best
    # match is often the half cycle; when the double period matches nearly as well, that is the full stride
    _, p0, s0 = best
    for p2 in (2 * p0 - 1, 2 * p0, 2 * p0 + 1):
        cand = [(scores[(p2, s)], s) for s in range(skip, n - p2) if (p2, s) in scores]
        if cand:
            sc, s2 = min(cand)
            if sc <= best[0] * 1.4 + 0.012:
                return p2, s2, sc
    return best[1], best[2], best[0]


def cycle(still_rgb, key, motion, seed=0, n_out=12, tries=2, length=81, size=640):
    """Returns n_out RGBA frames of one loop of `motion`, cropped to a common box (feet may leave the ground), plus info."""
    os.makedirs(os.path.join(ANIM, key), exist_ok=True)
    meta_p = os.path.join(ANIM, key, "cycle.json")
    if os.path.exists(meta_p):
        meta = json.load(open(meta_p, encoding="utf-8"))
        if meta.get("n_out") == n_out and meta.get("frames", 0) >= length - 1:
            frames = [Image.open(os.path.join(ANIM, key, "out_%02d.png" % k)).convert("RGBA") for k in range(meta["n_out"])]
            if len(frames) == meta["n_out"]:
                return frames, meta
        # an older cut (fewer frames or a shorter clip): re-cut from the kept frames when we have them, else re-render
        fulls = sorted(f for f in os.listdir(os.path.join(ANIM, key)) if f.startswith("full_"))
        if len(fulls) >= length - 1:
            keyed = [Image.open(os.path.join(ANIM, key, f)).convert("RGBA") for f in fulls]
            return _cut(keyed, key, n_out, size, meta.get("seed", seed), meta.get("prompt", ""), meta.get("seconds", 0)), json.load(open(meta_p, encoding="utf-8"))
    still, bg = _prep_still(still_rgb, size)
    name = comfy.upload_pil(still, key + "_still.png")
    prompt = ("A 2D anime game character sprite, " + motion + ". The character stays exactly in the centre of the frame and does not travel, "
              "like running on a treadmill: a smooth, energetic, seamlessly looping animation cycle at a steady pace. The camera is completely "
              "locked off and static. The background stays a flat solid " + ("blue" if bg[2] > bg[1] else "green") + " color with nothing in it, "
              "no ground plane, no shadow.")
    last_err = None
    for attempt in range(tries):
        s = seed + attempt * 7919
        t0 = time.time()
        pngs, secs = comfy.run(wan_i2v(prompt, name, s, size, size, length, prefix="88fits/anim_" + key), timeout=3600)
        raw = [Image.open(io.BytesIO(b)).convert("RGB") for b in pngs]
        # motion blur smears the screen colour into edges: key with a wider, stronger despill than a still needs
        keyed = [artkit.key_background(im, 0.16, 0.7) for im in raw]
        # a clip where the figure leaves the frame or vanishes is a bad roll
        bad = 0
        boxes = []
        for f in keyed:
            a = np.asarray(f)[..., 3] > 127
            ys, xs = np.nonzero(a)
            if len(xs) < 50:
                bad += 1
                continue
            boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
            if xs.min() < 4 or ys.min() < 4 or xs.max() > size - 5 or ys.max() > size - 5:
                bad += 1
        if bad > len(keyed) * 0.1 or len(boxes) < 20:
            last_err = "figure left the frame in %d of %d frames" % (bad, len(keyed))
            print("  clip %-24s seed %-7d %5.0fs  retry: %s" % (key, s, secs, last_err), flush=True)
            continue
        return _cut(keyed, key, n_out, size, s, prompt, secs, boxes), json.load(open(meta_p, encoding="utf-8"))
    raise RuntimeError("no usable clip for %s: %s" % (key, last_err))


def _cut(keyed, key, n_out, size, seed, prompt, secs, boxes=None):
    """Pick n_out frames of one full stride from keyed frames, crop to the union box, save and describe."""
    os.makedirs(os.path.join(ANIM, key), exist_ok=True)
    if boxes is None:
        boxes = []
        for f in keyed:
            a = np.asarray(f)[..., 3] > 127
            ys, xs = np.nonzero(a)
            if len(xs) >= 50:
                boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
    if True:
        period, start, dist = find_cycle(keyed)
        idx = [start + int(round(k * period / n_out)) for k in range(n_out)]
        idx = [min(i, len(keyed) - 1) for i in idx]
        chosen = [keyed[i] for i in idx]
        x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes); x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
        pad = 6
        box = (max(0, x0 - pad), max(0, y0 - pad), min(size, x1 + pad + 1), min(size, y1 + pad + 1))
        out = [f.crop(box) for f in chosen]
        for k, f in enumerate(out):
            f.save(os.path.join(ANIM, key, "out_%02d.png" % k))
        for k, f in enumerate(keyed):
            f.save(os.path.join(ANIM, key, "full_%02d.png" % k))   # kept so a cycle can be re-cut without re-rendering
        for k, f in enumerate(keyed):
            thumb = Image.new("RGB", (160, 160), (30, 30, 36))
            small = f.resize((160, 160))
            thumb.paste(small, mask=small.getchannel("A"))
            thumb.save(os.path.join(ANIM, key, "raw_%02d.jpg" % k), quality=80)
        sheet = artkit.contact_sheet(out, n_out, 200)
        sheet.save(os.path.join(ANIM, key, "cycle_sheet.png"))
        meta = {"key": key, "seed": seed, "period": int(period), "start": int(start), "distance": float(dist), "n_out": n_out, "frames": len(keyed),
                "box": [int(v) for v in box], "seconds": round(secs, 1), "prompt": prompt}
        json.dump(meta, open(os.path.join(ANIM, key, "cycle.json"), "w", encoding="utf-8", newline="\n"), indent=1)
        print("  clip %-24s seed %-7d %5.0fs  period %d start %d dist %.3f  %d frames" % (key, seed, secs, period, start, dist, n_out), flush=True)
        return out


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    still = Image.open(sys.argv[1]).convert("RGB")
    motion = sys.argv[2] if len(sys.argv) > 2 else "running in place, seen from the side"
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    key = "test_" + os.path.splitext(os.path.basename(sys.argv[1]))[0]
    frames, meta = cycle(still, key, motion, seed)
    print(json.dumps(meta, indent=1))
