"""Writes docs/design/pose-animation.html: how the pose-driven sprite animation works, with the Drifter's still, the
driver skeleton, and before/after looping GIFs embedded as data URIs (nothing external).

    python tools/make_pose_page.py
"""
import base64
import io
import json
import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANIM = os.path.join(REPO, "tools", "dl", "ai_anim")
DRIVERS = os.path.join(REPO, "tools", "dl", "drivers")
RAW = os.path.join(REPO, "tools", "dl", "ai_raw_anime")
OUT = os.path.join(REPO, "docs", "design", "pose-animation.html")
BG = (26, 24, 34)


def frames_of(folder, prefix="out_"):
    fs = sorted(f for f in os.listdir(folder) if f.startswith(prefix) and f.endswith(".png"))
    return [Image.open(os.path.join(folder, f)).convert("RGBA") for f in fs]


def gif_uri(frames, fps, height=260, loop=True):
    """Frames composited on the page's dark ground, one shared box, saved as a looping GIF."""
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    out = []
    for f in frames:
        canvas = Image.new("RGBA", (w, h), BG + (255,))
        canvas.alpha_composite(f, ((w - f.width) // 2, h - f.height))
        s = height / h
        canvas = canvas.resize((max(1, int(w * s)), height), Image.LANCZOS).convert("RGB")
        out.append(canvas.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    buf = io.BytesIO()
    out[0].save(buf, "GIF", save_all=True, append_images=out[1:], duration=int(round(1000.0 / fps)), loop=0 if loop else 1, disposal=1, optimize=False)
    return "data:image/gif;base64," + base64.b64encode(buf.getvalue()).decode("ascii"), len(buf.getvalue()) // 1024


def png_uri(img, height=260):
    s = height / img.height
    img = img.resize((max(1, int(img.width * s)), height), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "WEBP", quality=85, method=6)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def main():
    sizes = {}
    # the still (side view, keyed) and the driver skeleton
    import sys
    sys.path.insert(0, os.path.join(REPO, "tools"))
    import artkit
    still = artkit.crop_alpha(artkit.key_background(Image.open(os.path.join(RAW, "drifter_side.png")).convert("RGB")))
    still_canvas = Image.new("RGBA", still.size, BG + (255,))
    still_canvas.alpha_composite(still)
    still_uri = png_uri(still_canvas.convert("RGB"))
    drv = frames_of(os.path.join(DRIVERS, "run", "side"), "driver_")
    driver_uri, sizes["driver"] = gif_uri(drv[:-1], 24, 260)
    driver_frame_uri = png_uri(drv[0].convert("RGB"))
    before_s, sizes["before_s"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_run_s")), 28, 260)
    after_s, sizes["after_s"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_pose_run_side")), 36, 260)
    before_f, sizes["before_f"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_run_f")), 28, 260)
    after_f, sizes["after_f"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_pose_run_front")), 36, 260)
    before_b, sizes["before_b"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_run_b")), 28, 260)
    after_b, sizes["after_b"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_pose_run_back")), 36, 260)
    hit_uri, sizes["hit"] = gif_uri(frames_of(os.path.join(ANIM, "drifter_pose_hit_front")) + [frames_of(os.path.join(ANIM, "drifter_pose_hit_front"))[0]] * 6, 12, 260)
    meta_s = json.load(open(os.path.join(ANIM, "drifter_pose_run_side", "cycle.json")))
    meta_old = json.load(open(os.path.join(ANIM, "drifter_run_s", "cycle.json")))
    html = f'''<title>Pose-Driven Sprites</title>
<style>
:root{{--bg:#1a1822;--bg2:#241f31;--line:#433b5c;--ink:#f0ecf8;--ink2:#b5aec8;--ink3:#877f9e;--accent:#ffb13b;--good:#46d39a;--bad:#ee4a5c}}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 "Segoe UI",system-ui,sans-serif;padding-block:32px 96px;padding-inline:20px}}
.page{{max-width:1080px;margin:0 auto}}
h1{{font-size:clamp(30px,5vw,44px);line-height:1.1;margin:0 0 8px}}
h2{{font-size:24px;margin:44px 0 10px}}
p{{max-width:72ch;margin:0 0 14px;color:var(--ink2)}} p b{{color:var(--ink)}}
.lede{{font-size:18px;color:var(--ink)}}
code{{font-family:ui-monospace,Consolas,monospace;font-size:.92em;background:var(--bg2);padding:1px 6px;border-radius:5px;color:var(--ink)}}
.row{{display:flex;flex-wrap:wrap;gap:18px;margin:16px 0 22px;align-items:flex-end}}
figure{{margin:0;background:var(--bg2);border:1px solid var(--line);border-radius:14px;padding:12px;flex:1 1 220px;max-width:100%}}
figure img{{display:block;height:260px;width:auto;max-width:100%;margin:0 auto;image-rendering:auto}}
figcaption{{font-size:13.5px;color:var(--ink3);margin-top:8px;line-height:1.45}} figcaption b{{color:var(--ink2)}}
.tag{{display:inline-block;font:600 11px/1 ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;padding:5px 9px;border-radius:999px;border:1px solid var(--line);color:var(--ink2);margin-bottom:8px}}
.tag.bad{{border-color:var(--bad);color:var(--bad)}} .tag.good{{border-color:var(--good);color:var(--good)}}
table{{border-collapse:collapse;width:100%;font-size:14px;margin:8px 0 18px}} th,td{{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}}
th{{font:500 11px/1 ui-monospace,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--ink3)}}
.callout{{border-left:4px solid var(--accent);background:var(--bg2);border-radius:10px;padding:12px 16px;margin:18px 0;max-width:76ch}} .callout p{{margin:0}}
ol{{max-width:76ch;color:var(--ink2);padding-left:22px}} li{{margin-bottom:8px}} li b{{color:var(--ink)}}
</style>
<div class="page">
<h1>Pose-driven sprites</h1>
<p class="lede">How the Drifter's run cycles went from "the model guesses the stride" to "we hand it the stride": a Mixamo skeleton drives Wan 2.2 Animate, the painted still supplies the look, and every driver frame becomes exactly one sprite frame.</p>

<h2>The problem</h2>
<p>Until now a run cycle was a free image-to-video clip of the still ("running in place, treadmill, static camera") from which a cutter picked one stride by comparing silhouettes. Seen from the <b>front, back or side</b> a left step and a right step have the same silhouette, so the period was ambiguous by a factor of two and the cutter often picked the wrong one: six frames holding two steps, or half a stride stretched over a full cycle. Only the diagonals, where the two legs look different, came out right every time.</p>
<div class="row">
<figure><span class="tag bad">before · free clip, side</span><img src="{before_s}" alt="old side run cycle"><figcaption>Silhouette-cut cycle from the free Wan i2v clip. {meta_old.get('n_out')} frames cut from a period the detector chose.</figcaption></figure>
<figure><span class="tag good">after · pose-driven, side</span><img src="{after_s}" alt="new side run cycle"><figcaption>Driven by the Mixamo stride: 24 frames, one left step and one right step, closed loop. Rendered in {int(meta_s.get('seconds', 0))} s.</figcaption></figure>
</div>
<div class="row">
<figure><span class="tag bad">before · front</span><img src="{before_f}" alt="old front run cycle"><figcaption>The symmetric view where the old cutter guessed most.</figcaption></figure>
<figure><span class="tag good">after · front</span><img src="{after_f}" alt="new front run cycle"><figcaption>Legs alternate correctly because the driver says so.</figcaption></figure>
<figure><span class="tag bad">before · back</span><img src="{before_b}" alt="old back run cycle"><figcaption></figcaption></figure>
<figure><span class="tag good">after · back</span><img src="{after_b}" alt="new back run cycle"><figcaption></figcaption></figure>
</div>

<h2>The method</h2>
<ol>
<li><b>A real stride.</b> Garry downloaded Mixamo's <i>Running</i> (and <i>Walking</i>, <i>Pain Gesture</i>) as FBX, 30 fps, "In Place". One file is exactly one stride, 21 frames, and its last frame lands on its first.</li>
<li><b>Drivers per view.</b> <code>tools/pose_driver.py</code> runs inside Blender: it reads the skeleton, works out which way the figure faces from its feet, turns it to each of the game's five views (back, back-diagonal, side, front-diagonal, front; the side and diagonals facing screen-right like the painted stills), looks at it from a camera 25° above (the game camera is high), resamples the stride to 24 frames and adds a 25th that repeats the first. A second, plain-Python pass draws the joints as <b>OpenPose skeletons</b>, the format Wan Animate is trained on. Face and ear points are only drawn when that side of the head faces the camera.</li>
<li><b>Wan 2.2 Animate.</b> The character still goes in as the reference image (through CLIP-Vision and as a latent), the skeleton frames as the pose video. The model repaints the still following the motion. The 4-step distillation LoRA makes a 640×640×25 clip take about a minute on the R9700.</li>
<li><b>No detection.</b> Every output frame is keyed (chroma key with despill), cropped to one shared box so the bounce survives, outlined, scaled to the standing still, and packed straight into the strip. There is nothing left to guess: 24 in, 24 out, same cadence in all five views.</li>
<li><b>One-shots the same way.</b> The hit reaction is the Mixamo pain gesture sliced from 0.2 s to 1.0 s into 9 frames, rendered per view and played through once when the hero is hit. The drivers carry <b>both hands with every finger</b> in the DWPose style (the Mixamo rig has the finger bones), which is what stopped the model from guessing where the hands go.</li>
</ol>
<div class="row">
<figure><span class="tag">the still</span><img src="{still_uri}" alt="Drifter side still"><figcaption>Flux.2 Klein painting, side view, keyed. This is the only art input.</figcaption></figure>
<figure><span class="tag">the driver</span><img src="{driver_uri}" alt="OpenPose driver, side view"><figcaption>24 OpenPose frames of the Mixamo run, side view, 25° camera pitch.</figcaption></figure>
<figure><span class="tag">hit reaction</span><img src="{hit_uri}" alt="Drifter hit reaction, front"><figcaption>Pain gesture, 9 frames at 20 fps, front view, shown here with a pause between plays.</figcaption></figure>
</div>

<h2>What runs where</h2>
<table>
<tr><th>piece</th><th>what</th><th>where it came from</th></tr>
<tr><td>Wan 2.2 Animate 14B, fp8</td><td>the video model that repaints the still along the skeleton</td><td>downloaded to the AI server over SSH: <code>Kijai/WanVideo_comfy_fp8_scaled</code>, 18.4 GB</td></tr>
<tr><td>lightx2v I2V distill LoRA</td><td>4 steps instead of 20, cfg 1</td><td><code>Kijai/WanVideo_comfy/Lightx2v</code>, 0.7 GB</td></tr>
<tr><td>clip_vision_h</td><td>encodes the reference still for the Animate model</td><td><code>Comfy-Org/Wan_2.1_ComfyUI_repackaged</code>, 1.3 GB</td></tr>
<tr><td>umt5 text encoder, Wan 2.1 VAE</td><td>shared with the old i2v clips</td><td>already on the server</td></tr>
<tr><td>WanAnimateToVideo, TrimVideoLatent</td><td>the native ComfyUI nodes (0.33)</td><td>already on the server, no custom nodes</td></tr>
<tr><td>Mixamo FBX</td><td>the motion</td><td>Garry, <code>tools/dl/mixamo/</code> with a README</td></tr>
<tr><td>Blender 5.2</td><td>reads the FBX skeleton</td><td>already on the PC</td></tr>
<tr><td><code>tools/pose_driver.py</code>, <code>animate.cycle_pose</code>, <code>animate.wan_animate</code>, <code>gen_art.pose_cycle</code></td><td>our code</td><td>written for this pass</td></tr>
</table>

<h2>Things that had to be dealt with</h2>
<div class="callout"><p><b>Which way is forward.</b> Mixamo rigs do not agree on a facing axis, so the driver works it out from the feet (toe minus ankle, averaged over the stride) rather than assuming one.</p></div>
<div class="callout"><p><b>Which way is right.</b> The first drivers turned the figure the wrong way about the vertical axis, so every side and diagonal cycle came out facing screen-left; in the game, which mirrors the right-facing views when the hero runs left, that inverted left and right. Fixed by flipping the sign of the turn; the three affected views were re-rendered.</p></div>
<div class="callout"><p><b>Invented faces.</b> Wan Animate painted a face and hair behind Astro's opaque visor in the front view. The character JSON now carries <code>anim_hint</code> (what the animation must keep) and <code>anim_negative</code> (what it must not invent), passed as the prompt hint and negative prompt of every clip.</p></div>
<div class="callout"><p><b>Speed.</b> 24 frames covered the stride in 0.86 s at 28 fps, slower than the Mixamo run; playback is 36 fps now (0.67 s, the clip's own tempo), frames unchanged.</p></div>
<div class="callout"><p><b>Effects out of nowhere.</b> Describing the hit as "flinching from a hit" made the model paint impact rings and a white blade around the Drifter. Hit clips now describe the body only ("staggering and recoiling backwards, then straightening up") and ban effects in the negative prompt.</p></div>
<div class="callout"><p><b>Loop length.</b> Wan wants 4k+1 frames. Loops render 25 with the last a repeat of the first and drop it; one-shots render 9.</p></div>

<h2>What stays on the old path</h2>
<p>Creatures without a human skeleton (ants, hornets, mushrooms, the tumbleweed) still use the free clip and the silhouette cutter. The goblin family, the bramble imp and the toadstool could move to the <i>Orc Walk</i> and <i>Walking</i> drivers; the boar and beetle to <i>Big Guy Walking</i>.</p>
</div>
'''
    open(OUT, "w", encoding="utf-8", newline="\n").write(html)
    print("wrote", OUT, "%d KB" % (len(html.encode("utf-8")) // 1024), "gif KB:", sizes)


if __name__ == "__main__":
    main()
