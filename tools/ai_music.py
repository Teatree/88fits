"""The six music tracks of 88fits on Stable Audio 3 medium (pass 64), cut into seamless loops.

Garry (2026-10-10): "For Music I want the same, as close to MegaBonk as possible, but slightly more Western style."
So: upbeat, punchy arcade/roguelite action music (driving drums, synth bass, catchy hooks) dressed in spaghetti-western
colours (twangy guitar, whistle, honky-tonk piano, harmonica, mariachi trumpets). The title and the results are
calmer, the three run tracks climb in energy by stage (stage 3 is hell), the boss track is the most intense.

Per track: CANDS clips of `gen` seconds on the server's medium model (tools/comfy_audio.py, 8 steps, cfg 1), each
  1. resampled to RATE (32 kHz stereo, before any cut, so the loop's seam never meets a resampler's edge),
  2. its tempo found from the onset envelope's autocorrelation near the prompt's BPM (librosa's beat tracker needs numba
     loops this PC's numpy lacks),
  3. a loop of a whole number of bars within [loop_min, loop_max] chosen where the music around the loop's end best
     matches the music around its start (band-energy frames, two bars either side), the end then nudged to the sample
     by waveform cross-correlation, and the tail crossfaded into the music just before the start (equal power, XFADE),
     so the sample after the last one is exactly the first one,
  4. levelled: the loud frames' RMS to TARGET_RMS_DB, peaks held at CEILING_DB by a limiter run on the wrapped signal
     (the seam is limited like any other moment),
  5. scored (lower wins): the seam's distance, the seam's click (the wrap's spectral flux against the track's median),
     loudness drops, silence, tempo off the prompt, clipping.
The pick (or `--pick id=k`) is written to game/content/sounds/music/<id>.wav and bound in the soundmap (`file`).

  python tools/ai_music.py                  # generate what is missing, process, pick, write, bind
  python tools/ai_music.py --only mu_boss --cands 8
  python tools/ai_music.py --pick mu_title=3
  python tools/ai_music.py --report
Then under the Godot lock: --import, import_json -- only=sounds.
"""
import argparse
import json
import math
import os
import re
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DL = os.path.join(ROOT, "tools", "dl", "music64")
OUT = os.path.join(ROOT, "game", "content", "sounds", "music")
SOUNDMAP = os.path.join(ROOT, "game", "content", "sounds", "soundmap.json")
RATE = 32000
TARGET_RMS_DB = -17.0
CEILING_DB = -1.0
MAX_LIMIT_DB = 3.5
XFADE = 0.35
CANDS = 6
HOP = 512

_W = (" Instrumental only, no vocals, no singing, no speech. Polished, well mixed, steady tempo, seamless loopable"
      " video game soundtrack.")
TRACKS = {
    "mu_title": {"bpm": 100, "gen": 120, "loop": [48, 90], "role": "title screen (calm, inviting)",
                 "prompt": "Main menu theme for a cartoon western arcade roguelite: a laid-back but catchy swinging groove"
                           " at 100 BPM, twangy clean electric guitar melody with tremolo, honky-tonk piano, brushed"
                           " drums with a shuffle, warm upright bass and a whistled hook, playful casino-lounge"
                           " swagger." + _W},
    "mu_run_1": {"bpm": 128, "gen": 150, "loop": [70, 120], "role": "stage 1 (upbeat, driving)",
                 "prompt": "Upbeat high-energy arcade roguelite action music in the style of Megabonk with a western"
                           " twist: punchy electronic drums with a galloping beat at 128 BPM, driving synth bass, a"
                           " catchy twangy spaghetti-western electric guitar riff, honky-tonk piano stabs and a"
                           " whistle lead, fun and bouncy." + _W},
    "mu_run_2": {"bpm": 136, "gen": 150, "loop": [70, 120], "role": "stage 2 (more intense)",
                 "prompt": "Intense, energetic action roguelite battle music with a western flavour at 136 BPM:"
                           " four-on-the-floor kick and snappy snares, driving distorted surf-rock guitar riff, bold"
                           " mariachi trumpets, harmonica fills and a pulsing synth bass, rising excitement, Megabonk"
                           " style arcade energy." + _W},
    "mu_run_3": {"bpm": 145, "gen": 150, "loop": [70, 120], "role": "stage 3, hell (relentless)",
                 "prompt": "Relentless hellish western action music at 145 BPM in a minor key: heavy distorted baritone"
                           " guitar riffs, dark mariachi trumpets, pounding rock drums, aggressive synth bass and"
                           " fiery tension, a demonic desert showdown, high-energy arcade roguelite soundtrack." + _W},
    "mu_boss": {"bpm": 150, "gen": 120, "loop": [48, 90], "role": "boss fight (most intense)",
                "prompt": "Epic boss battle music, a spaghetti-western showdown fused with hard electronic rock at"
                          " 150 BPM: thunderous drums, a heavy twangy guitar riff, dramatic trumpet fanfares, frantic"
                          " strings and a driving synth bass, intense and heroic, arcade roguelite boss theme." + _W},
    "mu_results": {"bpm": 110, "gen": 90, "loop": [36, 64], "role": "results screen (relaxed win)",
                   "prompt": "Relaxed, upbeat victory groove for a results screen at 110 BPM: twangy guitar, honky-tonk"
                             " piano, light shuffled percussion and slot-machine bell sparkles, a satisfied and"
                             " cheerful casino-lounge western mood." + _W},
}
ORDER = ["mu_run_1", "mu_title", "mu_boss", "mu_run_2", "mu_run_3", "mu_results"]


# ---------------------------------------------------------------- files

def raw_path(sid, k, ext="wav"):
    return os.path.join(DL, "raw", "%s_c%d.%s" % (sid, k, ext))


def loop_path(sid, k):
    return os.path.join(DL, "loop", "%s_c%d.wav" % (sid, k))


def read_json(p, d):
    if not os.path.exists(p):
        return d
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def write_json(p, o):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(o, f, indent=1)
        f.write("\n")


def seed_for(sid, k):
    return zlib.crc32(("music64:%s:%d" % (sid, k)).encode()) & 0x7FFFFFFF


def ks_of(sid):
    d = os.path.join(DL, "raw")
    if not os.path.isdir(d):
        return []
    return sorted(int(m.group(1)) for m in (re.match(r"^%s_c(\d+)\.json$" % sid, f) for f in os.listdir(d)) if m)


# ---------------------------------------------------------------- generation

def generate(only=None, cands=CANDS, force=False):
    import comfy_audio as ca
    for sid in ORDER:
        if only and sid not in only:
            continue
        t = TRACKS[sid]
        for k in range(cands):
            meta = read_json(raw_path(sid, k, "json"), {})
            if not force and os.path.exists(raw_path(sid, k)) and meta.get("prompt") == t["prompt"] and meta.get("gen") == t["gen"]:
                continue
            wavs, secs = ca.generate(t["prompt"], t["gen"], seed_for(sid, k), "medium", 1, "88fits/music64/%s_c%d" % (sid, k))
            os.makedirs(os.path.dirname(raw_path(sid, k)), exist_ok=True)
            with open(raw_path(sid, k), "wb") as f:
                f.write(wavs[0])
            write_json(raw_path(sid, k, "json"), {"id": sid, "k": k, "prompt": t["prompt"], "gen": t["gen"],
                                                  "seed": seed_for(sid, k), "model": ca.MODELS["medium"],
                                                  "steps": ca.STEPS, "cfg": ca.CFG, "elapsed": round(secs, 1)})
            print("%s_c%d %ds in %.1fs" % (sid, k, t["gen"], secs), flush=True)


# ---------------------------------------------------------------- analysis

def load_stereo(p):
    import soundfile as sf
    from scipy.signal import resample_poly
    y, sr = sf.read(p, dtype="float32", always_2d=True)
    if y.shape[1] == 1:
        y = np.repeat(y, 2, axis=1)
    y = y[:, :2]
    if sr != RATE:
        g = math.gcd(int(sr), RATE)
        y = resample_poly(y, RATE // g, int(sr) // g, axis=0).astype(np.float32)
    return y - y.mean(axis=0, keepdims=True)


def stft_mag(m, n_fft=2048, hop=HOP):
    pad = n_fft // 2
    x = np.pad(m, (pad, pad))
    n = 1 + (len(x) - n_fft) // hop
    idx = np.arange(n_fft)[None, :] + hop * np.arange(n)[:, None]
    win = np.hanning(n_fft).astype(np.float32)
    return np.abs(np.fft.rfft(x[idx] * win, axis=1)).astype(np.float32)   # frames x bins


def band_features(S, n_bands=24):
    """Log energy in log-spaced bands (frames x bands), per-frame normalised."""
    freqs = np.fft.rfftfreq((S.shape[1] - 1) * 2, 1.0 / RATE)
    edges = np.geomspace(60.0, RATE / 2.0 * 0.95, n_bands + 1)
    F = np.stack([S[:, (freqs >= edges[b]) & (freqs < edges[b + 1])].sum(axis=1) for b in range(n_bands)], axis=1)
    F = np.log1p(F * 10.0)
    return F


def onset_env(S):
    L = np.log1p(S * 10.0)
    d = np.maximum(np.diff(L, axis=0), 0.0).sum(axis=1)
    d = np.concatenate([[0.0], d])
    d = d - np.convolve(d, np.ones(16) / 16.0, mode="same")
    return np.maximum(d, 0.0)


def tempo_of(env, bpm_hint):
    """Beat period in frames from the onset envelope's autocorrelation: the strongest lag between 70 and 190 BPM,
    weighted towards the hint (and its half/double)."""
    fps = RATE / HOP
    e = env - env.mean()
    ac = np.correlate(e, e, mode="full")[len(e) - 1:]
    ac = ac / max(ac[0], 1e-9)
    best, best_v = None, -1e9
    for lag in range(int(fps * 60 / 190), int(fps * 60 / 70) + 1):
        bpm = 60.0 * fps / lag
        w = max(math.exp(-0.5 * (math.log(bpm / h) / 0.06) ** 2) for h in (bpm_hint, bpm_hint / 2.0, bpm_hint * 2.0))
        v = ac[lag] * (0.6 + 0.4 * w)
        if v > best_v:
            best, best_v = lag, v
    # refine the lag to a fraction by a parabola through the neighbours
    l = best
    if 1 <= l < len(ac) - 1:
        a, b, c = ac[l - 1], ac[l], ac[l + 1]
        den = a - 2 * b + c
        frac = 0.5 * (a - c) / den if abs(den) > 1e-9 else 0.0
        l = l + float(np.clip(frac, -0.5, 0.5))
    return float(l), float(ac[best]), 60.0 * fps / l


def find_loop(y, t):
    m = y.mean(axis=1)
    S = stft_mag(m)
    F = band_features(S)
    env = onset_env(S)
    lag, clarity, bpm = tempo_of(env, t["bpm"])
    bar = 4.0 * lag                       # frames per bar
    fps = RATE / HOP
    n_frames = F.shape[0]
    w = int(round(2 * bar))               # two bars either side of the seam
    lo, hi = t["loop"]
    head = int(3.0 * fps) + w             # skip the intro
    tail = n_frames - int(4.0 * fps) - w  # and the ending (the model winds down to its length)
    best = None
    Fn = F / (np.linalg.norm(F, axis=1, keepdims=True) + 1e-9)
    for nb in range(max(1, int(math.ceil(lo * fps / bar))), int(hi * fps / bar) + 1):
        L = nb * bar
        Li = int(round(L))
        for s in range(head, tail - Li, max(1, int(round(lag / 2)))):
            a = Fn[s - w:s + w]
            b = Fn[s + Li - w:s + Li + w]
            if b.shape[0] != a.shape[0]:
                continue
            d = 1.0 - float(np.mean(np.sum(a * b, axis=1)))
            # prefer longer loops a little (less repetition)
            d_adj = d - 0.0004 * (L / fps)
            if best is None or d_adj < best[0]:
                best = (d_adj, d, s, L)
    if best is None:
        raise RuntimeError("no loop window fits (track too short)")
    _, dist, s_f, L_f = best
    s = int(round(s_f * HOP))
    e = int(round((s_f + L_f) * HOP))
    # sample-level: nudge the end within an eighth of a beat so the waveform around it matches the start's
    x = int(0.03 * RATE)
    rng = int(lag * HOP / 8)
    ref = m[s - x:s + x]
    best_c, best_e = -1e9, e
    for de in range(-rng, rng + 1, 4):
        seg = m[e + de - x:e + de + x]
        if len(seg) != len(ref):
            continue
        c = float(np.dot(seg, ref) / (np.linalg.norm(seg) * np.linalg.norm(ref) + 1e-9))
        if c > best_c:
            best_c, best_e = c, e + de
    for de in range(max(-4, -best_e), 5):   # the last few samples one by one
        ee = best_e + de
        seg = m[ee - x:ee + x]
        if len(seg) == len(ref):
            c = float(np.dot(seg, ref) / (np.linalg.norm(seg) * np.linalg.norm(ref) + 1e-9))
            if c > best_c:
                best_c, best_e = c, ee
    return {"start": s, "end": best_e, "bpm": round(bpm, 2), "clarity": round(clarity, 3), "dist": round(dist, 4),
            "xcorr": round(best_c, 3), "bars": int(round(L_f / bar))}


def build_loop(y, lp):
    s, e = lp["start"], lp["end"]
    xn = min(int(XFADE * RATE), s)
    out = y[s:e].copy()
    if xn > 0:
        th = np.linspace(0.0, math.pi / 2, xn, dtype=np.float32)[:, None]
        out[-xn:] = y[e - xn:e] * np.cos(th) + y[s - xn:s] * np.sin(th)
    return out


def loud_rms(y, win=0.4):
    m = np.sqrt(np.mean(y ** 2, axis=1))
    n = int(win * RATE)
    fr = np.array([np.sqrt(np.mean(m[i:i + n] ** 2)) for i in range(0, len(m) - n, n)])
    if not len(fr):
        return 1e-9, fr
    top = fr.max()
    sel = fr[fr > top * 10 ** (-20 / 20.0)]
    return float(np.sqrt(np.mean(sel ** 2))), fr


def limit_wrapped(y, ceiling_db=CEILING_DB, attack=0.003, release=0.12):
    """A look-ahead peak limiter run over the loop as a circle (padded with its own other end)."""
    c = 10 ** (ceiling_db / 20.0)
    pad = int(0.5 * RATE)
    z = np.concatenate([y[-pad:], y, y[:pad]], axis=0)
    a = np.abs(z).max(axis=1)
    need = np.minimum(1.0, c / np.maximum(a, 1e-9))
    la = int(attack * RATE)
    # look-ahead: the gain reaches its value `la` samples before the peak
    from scipy.ndimage import minimum_filter1d
    g = minimum_filter1d(need, size=2 * la + 1)
    rel = math.exp(-1.0 / (release * RATE))
    out = np.empty_like(g)
    cur = 1.0
    for i in range(len(g)):        # release smoothing (attack is instant thanks to the look-ahead window)
        cur = g[i] if g[i] < cur else g[i] + (cur - g[i]) * rel
        out[i] = cur
    z = z * out[:, None]
    return z[pad:pad + len(y)], float(1.0 - out.min())


def level(y):
    """Loud frames to TARGET_RMS_DB, peaks limited at CEILING_DB; a track that would need more than MAX_LIMIT_DB of
    limiting is turned down instead of squashed (it stops short of the target)."""
    r, _ = loud_rms(y)
    g = 10 ** (TARGET_RMS_DB / 20.0) / max(r, 1e-9)
    z, red = limit_wrapped(y * g)
    over = -20 * math.log10(max(1.0 - red, 1e-6)) - MAX_LIMIT_DB
    if over > 0.0:
        z, red = limit_wrapped(y * g * 10 ** (-over / 20.0))
    return z, red


def seam_click(out):
    """Spectral flux across the wrap against the track's median flux (1.0 = an ordinary moment)."""
    m = out.mean(axis=1)
    n = int(0.5 * RATE)
    ring = np.concatenate([m[-n:], m[:n]])
    S = stft_mag(ring, 1024, 256)
    L = np.log1p(S * 10.0)
    fl = np.maximum(np.diff(L, axis=0), 0).sum(axis=1)
    Sa = stft_mag(m[: min(len(m), 20 * RATE)], 1024, 256)
    La = np.log1p(Sa * 10.0)
    fa = np.maximum(np.diff(La, axis=0), 0).sum(axis=1)
    mid = len(fl) // 2
    peak = fl[max(0, mid - 3):mid + 4].max()
    return float(peak / max(np.median(fa), 1e-9)), float(np.percentile(fa, 95) / max(np.median(fa), 1e-9))


def centroid(y):
    m = y.mean(axis=1)[: 30 * RATE]
    S = stft_mag(m)
    f = np.fft.rfftfreq(2048, 1.0 / RATE)
    e = S.sum(axis=1)
    c = (S * f).sum(axis=1) / np.maximum(e, 1e-9)
    return float(np.sum(c * e) / max(e.sum(), 1e-9))


def score(info, t):
    s = 4.0 * info["dist"]
    s += 0.5 * max(0.0, info["seam_click"] - info["click_p95"]) / max(info["click_p95"], 1e-9)
    s += 0.6 * info["drop_db"] / 10.0
    s += 2.0 * info["silence"]
    off = min(abs(math.log(info["bpm"] / h)) for h in (t["bpm"], t["bpm"] / 2.0, t["bpm"] * 2.0))
    s += 2.0 * max(0.0, off - 0.05)
    s += 0.5 * (1.0 - min(1.0, info["clarity"] / 0.3))
    s += 1.5 * max(0.0, info["limit"] - 0.5)
    if info["raw_clip"] > 0.002:
        s += 0.5
    return round(s, 4)


def process(sid, k):
    import soundfile as sf
    t = TRACKS[sid]
    y = load_stereo(raw_path(sid, k))
    raw_clip = float(np.mean(np.abs(y) > 0.99))
    lp = find_loop(y, t)
    out = build_loop(y, lp)
    out, red = level(out)
    click, p95 = seam_click(out)
    _, fr = loud_rms(out, 1.0)
    frd = 20 * np.log10(np.maximum(fr, 1e-6))
    info = dict(lp)
    info.update({"k": k, "seconds": round(len(out) / RATE, 2), "seam_click": round(click, 3), "click_p95": round(p95, 3),
                 "drop_db": round(float(np.median(frd) - frd.min()), 2) if len(frd) else 0.0,
                 "silence": round(float(np.mean(frd < -40)), 3) if len(frd) else 1.0,
                 "limit": round(red, 3), "raw_clip": round(raw_clip, 4), "centroid": round(centroid(out), 0),
                 "rms_db": round(20 * math.log10(max(loud_rms(out)[0], 1e-9)), 2),
                 "peak_db": round(20 * math.log10(max(float(np.abs(out).max()), 1e-9)), 2)})
    info["score"] = score(info, t)
    os.makedirs(os.path.dirname(loop_path(sid, k)), exist_ok=True)
    sf.write(loop_path(sid, k), np.clip(out, -1, 1), RATE, subtype="PCM_16")
    return info


def analyse(only=None):
    sc = read_json(os.path.join(DL, "scores.json"), {})
    for sid in ORDER:
        if only and sid not in only:
            continue
        cands = []
        for k in ks_of(sid):
            try:
                cands.append(process(sid, k))
            except Exception as e:
                print("%s_c%d failed: %s" % (sid, k, e))
        sc[sid] = {"cands": cands, "role": TRACKS[sid]["role"], "prompt": TRACKS[sid]["prompt"]}
        for c in cands:
            print("%s c%d score %.3f bpm %.1f bars %d %.1fs dist %.3f xcorr %.2f click %.2f/p95 %.2f drop %.1f lim %.2f cen %d"
                  % (sid, c["k"], c["score"], c["bpm"], c["bars"], c["seconds"], c["dist"], c["xcorr"], c["seam_click"],
                     c["click_p95"], c["drop_db"], c["limit"], c["centroid"]), flush=True)
    write_json(os.path.join(DL, "scores.json"), sc)
    return sc


# ---------------------------------------------------------------- picking and binding

def edit_soundmap_file(files, volumes=None):
    """Line-preserving: set the `file` (added last when missing) and `volume_db` of the music rows given."""
    volumes = volumes or {}
    with open(SOUNDMAP, encoding="utf-8", newline="") as f:
        text = f.read()
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(nl)
    changed = 0
    i = 0
    while i < len(lines):
        mm = re.match(r'^(\s{4})"([a-z0-9_]+)": \{\s*$', lines[i])
        if not mm:
            i += 1
            continue
        sid = mm.group(2)
        j = i + 1
        while j < len(lines) and not re.match(r'^\s{4}\}', lines[j]):
            j += 1
        if sid in files or sid in volumes:
            body = lines[i + 1:j]
            found = False
            for b, ln in enumerate(body):
                fm = re.match(r'^(\s+"file": )"([^"]*)"(,?)\s*$', ln)
                if fm and sid in files:
                    found = True
                    if fm.group(2) != files[sid]:
                        body[b] = '%s"%s"%s' % (fm.group(1), files[sid], fm.group(3))
                        changed += 1
                vm = re.match(r'^(\s+"volume_db": )(-?[0-9.]+)(,?)\s*$', ln)
                if vm and sid in volumes and float(vm.group(2)) != float(volumes[sid]):
                    v = volumes[sid]
                    body[b] = "%s%s%s" % (vm.group(1), str(int(v)) if float(v) == int(v) else "%.1f" % v, vm.group(3))
                    changed += 1
            if sid in files and not found:
                indent = re.match(r'^(\s*)', body[-1]).group(1)
                body[-1] = body[-1].rstrip() + ("" if body[-1].rstrip().endswith(",") else ",")
                body.append('%s"file": "%s"' % (indent, files[sid]))
                changed += 1
            lines[i + 1:j] = body
            j = i + 1 + len(body)
        i = j + 1
    if changed:
        with open(SOUNDMAP, "w", encoding="utf-8", newline="") as f:
            f.write(nl.join(lines))
    return changed


def bind(picks, only=None):
    import shutil
    os.makedirs(OUT, exist_ok=True)
    files = {}
    for sid, p in picks.items():
        if only and sid not in only:
            continue
        src = loop_path(sid, p["k"])
        if not os.path.exists(src):
            print("missing", src)
            continue
        shutil.copyfile(src, os.path.join(OUT, sid + ".wav"))
        files[sid] = "music/%s.wav" % sid
    n = edit_soundmap_file(files)
    print("bound %d tracks, %d soundmap lines changed" % (len(files), n))


def auto_pick(sc, picks, only=None, force=False):
    for sid, s in sc.items():
        if only and sid not in only:
            continue
        if picks.get(sid, {}).get("manual") and not force:
            continue
        if not s["cands"]:
            continue
        b = min(s["cands"], key=lambda c: c["score"])
        picks[sid] = {"k": b["k"], "score": b["score"], "manual": False}
    return picks


def report(sc, picks):
    for sid in ORDER:
        s = sc.get(sid)
        if not s:
            continue
        p = picks.get(sid, {})
        c = next((c for c in s["cands"] if c["k"] == p.get("k")), None)
        if c:
            print("%-10s c%d %s %5.1fs %3d bars %6.1f BPM  seam %.3f click %.2f  rms %.1f peak %.1f  cen %d  (%s)" % (
                sid, c["k"], "ear " if p.get("manual") else "auto", c["seconds"], c["bars"], c["bpm"], c["dist"],
                c["seam_click"], c["rms_db"], c["peak_db"], c["centroid"], s["role"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--cands", type=int, default=CANDS)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--gen-only", action="store_true")
    ap.add_argument("--analyse-only", action="store_true")
    ap.add_argument("--pick", action="append", default=[])
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    only = set(x for x in a.only.split(",") if x) or None
    picks_p = os.path.join(DL, "picks.json")
    picks = read_json(picks_p, {})
    if a.report:
        report(read_json(os.path.join(DL, "scores.json"), {}), picks)
        return
    if a.pick:
        sc = read_json(os.path.join(DL, "scores.json"), {})
        for p in a.pick:
            sid, k = p.split("=")
            c = next((c for c in sc.get(sid, {}).get("cands", []) if c["k"] == int(k)), None)
            if c is None:
                raise SystemExit("no candidate %s" % p)
            picks[sid] = {"k": int(k), "score": c["score"], "manual": True}
        write_json(picks_p, picks)
        bind(picks, only=set(p.split("=")[0] for p in a.pick))
        return
    if not a.analyse_only:
        generate(only, a.cands, a.force)
        if a.gen_only:
            return
    sc = analyse(only)
    auto_pick(sc, picks, only)
    write_json(picks_p, picks)
    bind(picks, only)
    report(sc, picks)


if __name__ == "__main__":
    main()
