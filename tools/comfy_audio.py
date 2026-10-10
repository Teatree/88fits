"""Stable Audio 3 on the AI server's ComfyUI (pass 64): sound effects, jingles and music for 88fits.

The server (192.168.137.54:8188) holds two Stable Audio 3 checkpoints and their shared text encoder:
  stable_audio_3_small_sfx.safetensors   effects, up to 120 s
  stable_audio_3_medium.safetensors      music and jingles, up to 380 s
  t5gemma_b_b_ul2.safetensors            the text encoder (CLIPLoader type "stable_audio")
and a small custom node `GameAudioSaveWAV` (custom_nodes/game_audio_wav.py) that writes 44.1 kHz stereo PCM16 WAVs.
The graph is the official Comfy-Org template (user/default/workflows/Stable_Audio_3/*.json on the server):

  CheckpointLoaderSimple -> CLIPLoader -> CLIPTextEncode (prompt, empty negative) -> ConditioningStableAudio
  (seconds_start 0, seconds_total) -> EmptyLatentAudio (seconds + 0.2 margin, batch) -> KSampler (8 steps, cfg 1.0,
  lcm, simple, denoise 1: the distilled weights' own sampling; the negative prompt is inert at cfg 1, so exclusions go
  in the prompt) -> VAEDecodeAudio -> TrimAudioDuration -> GameAudioSaveWAV.

  python tools/comfy_audio.py --test "a bright casino slot win jingle" --model sfx --seconds 2 --out x.wav
  python tools/comfy_audio.py --export      # tools/comfy_workflows/06_stable_audio_3_{sfx,music}.json for the browser UI
"""
import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import comfy  # noqa: E402

MODELS = {"sfx": "stable_audio_3_small_sfx.safetensors", "medium": "stable_audio_3_medium.safetensors"}
MAX_SECONDS = {"sfx": 120.0, "medium": 380.0}
TEXT_ENCODER = "t5gemma_b_b_ul2.safetensors"
# Pass 64: the small sfx model loads in fp16 on the server and about half its runs overflow to NaN (the WAV saver refuses
# them: "Audio contains NaN or infinity"), depending on length and seed, on a fresh server too; computed in bf16 or fp32
# through ModelComputeDtype it returns flat broadband noise. So the game's sounds come from the medium model (clean at
# any length, short pops included); this switch stays for the day the small model behaves.
COMPUTE_DTYPE = {"sfx": "default", "medium": "default"}
STEPS = 8
CFG = 1.0
SAMPLER = "lcm"
SCHEDULER = "simple"
MARGIN = 0.2
RATE = 44100


def graph(prompt, seconds, seed, model="sfx", batch=1, prefix="88fits/sa3", steps=STEPS, cfg=CFG):
    """The Stable Audio 3 graph as a comfy.Graph (API form)."""
    if model not in MODELS:
        raise ValueError("model must be one of %s" % list(MODELS))
    seconds = float(min(max(seconds, 0.3), MAX_SECONDS[model]))
    g = comfy.Graph()
    ck = g.add("CheckpointLoaderSimple", "Model + autoencoder", ckpt_name=MODELS[model])
    mdl = (ck, 0)
    if COMPUTE_DTYPE.get(model, "default") != "default":
        mdl = (g.add("ModelComputeDtype", "Compute dtype (fp16 overflowed)", model=(ck, 0), dtype=COMPUTE_DTYPE[model]), 0)
    cl = g.add("CLIPLoader", "Text encoder", clip_name=TEXT_ENCODER, type="stable_audio", device="default")
    pos = g.add("CLIPTextEncode", "Describe the sound", text=prompt, clip=(cl, 0))
    neg = g.add("CLIPTextEncode", "Negative (inert at cfg 1)", text="", clip=(cl, 0))
    cond = g.add("ConditioningStableAudio", "Duration conditioning", positive=(pos, 0), negative=(neg, 0),
                 seconds_start=0.0, seconds_total=seconds)
    # the latent's floor is 1 s (EmptyLatentAudio's min); the conditioning still says the short length, the trim cuts it
    lat = g.add("EmptyLatentAudio", "Padded latent", seconds=round(max(seconds + MARGIN, 1.0), 2), batch_size=int(batch))
    ks = g.add("KSampler", "8 distilled steps", seed=int(seed), steps=int(steps), cfg=float(cfg), sampler_name=SAMPLER,
               scheduler=SCHEDULER, denoise=1.0, model=mdl, positive=(cond, 0), negative=(cond, 1),
               latent_image=(lat, 0))
    dec = g.add("VAEDecodeAudio", "Decode stereo audio", samples=(ks, 0), vae=(ck, 2))
    trim = g.add("TrimAudioDuration", "Trim to the duration", audio=(dec, 0), start_index=0.0, duration=seconds)
    g.add("GameAudioSaveWAV", "WAV export", audio=(trim, 0), filename_prefix=prefix)
    return g


def run(g, timeout=900):
    """Queue an audio graph; returns (list of wav bytes, seconds)."""
    r = comfy.post("/prompt", {"prompt": g.api(), "client_id": "88fits-audio-" + uuid.uuid4().hex[:8]})
    if r.get("error") or r.get("node_errors"):
        raise RuntimeError("ComfyUI rejected the graph: " + json.dumps({"error": r.get("error"), "node_errors": r.get("node_errors")})[:1500])
    pid = r["prompt_id"]
    t0 = time.time()
    while True:
        time.sleep(0.7)
        h = comfy.get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError("ComfyUI error: " + json.dumps(st.get("messages"))[:1500])
            out = []
            for o in h[pid].get("outputs", {}).values():
                for a in o.get("audio", []):
                    if a.get("type") != "output":
                        continue
                    url = comfy.SERVER + "/view?filename=%s&subfolder=%s&type=%s" % (
                        urllib.parse.quote(a["filename"]), urllib.parse.quote(a.get("subfolder", "")), a["type"])
                    out.append(urllib.request.urlopen(url, timeout=120).read())
            if not out:
                raise RuntimeError("ComfyUI produced no audio")
            return out, time.time() - t0
        if time.time() - t0 > timeout:
            raise RuntimeError("ComfyUI timeout after %ds" % timeout)


def generate(prompt, seconds, seed, model="sfx", batch=1, prefix="88fits/sa3", timeout=900):
    """One queue of `batch` clips; returns (list of wav bytes, seconds taken)."""
    return run(graph(prompt, seconds, seed, model, batch, prefix), timeout=timeout)


def release():
    """Free the server after a session (comfy.release_models: unload, restart when the RAM stays high)."""
    return comfy.release_models()


def export(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for name, model, secs, text in [
            ("06_stable_audio_3_jingle", "medium", 2.0, "A bright casino slot machine win jingle with a twangy western guitar lick, punchy, clean, isolated game sound effect, no speech."),
            ("06_stable_audio_3_music", "medium", 60.0, "Instrumental upbeat western video game music, driving drums, twangy electric guitar, honky-tonk piano, 128 BPM, no vocals.")]:
        g = graph(text, secs, 88, model, 1, "88fits/sa3_" + model)
        with open(os.path.join(out_dir, name + ".json"), "w", newline="") as f:
            json.dump(g.ui_workflow(), f, indent=1)
        print("wrote", name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", default="")
    ap.add_argument("--model", default="sfx", choices=list(MODELS))
    ap.add_argument("--seconds", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=88)
    ap.add_argument("--batch", type=int, default=1)
    ap.add_argument("--out", default="sa3_test.wav")
    ap.add_argument("--export", action="store_true")
    ap.add_argument("--release", action="store_true")
    a = ap.parse_args()
    if a.export:
        export(os.path.join(comfy.REPO, "tools", "comfy_workflows"))
    if a.test:
        wavs, secs = generate(a.test, a.seconds, a.seed, a.model, a.batch)
        base, ext = os.path.splitext(a.out)
        for i, w in enumerate(wavs):
            p = a.out if len(wavs) == 1 else "%s_%d%s" % (base, i, ext)
            with open(p, "wb") as f:
                f.write(w)
            print("wrote", p)
        print("%.1f s" % secs)
    if a.release:
        print(release())


if __name__ == "__main__":
    main()
