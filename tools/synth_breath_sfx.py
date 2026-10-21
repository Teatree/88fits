"""Pass 95 (lane BREATH): the Dragon's Breath's sounds synthesised in numpy (no model; the ComfyUI Stable Audio route was
busy with the spiders, and a breath of fire is a breath of shaped noise anyway): `w_breath_start`, the lighter's flick
and the first whoomp as the spray catches, and `w_breath_loop`, a seamless 1.6 s roar of fire that Audio.play_loop runs
for the breath (FireBreath._loop_start; the blue flame plays it a little higher, the Fire Eater lower).
Writes game/content/sounds/real/<id>.wav, 22.05 kHz 16-bit mono, levelled like tools/synth_sfx.py (content RMS -14 dBFS,
peaks held at -2 dBFS, at most 6 dB of limiting). Then `--import` and `import_json.gd -- only=sounds`.

    python tools/synth_breath_sfx.py [--only w_breath_loop] [--out <dir>]
"""
import argparse
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "content", "sounds", "real")
TARGET_RMS_DB = -14.0
CEILING_DB = -2.0
MAX_LIMIT_DB = 6.0
rng = np.random.default_rng(95)


def t_of(sec):
    return np.arange(int(SR * sec)) / SR


def band(x, lo, hi, slope=0.35):
    """`x` band-passed between `lo` and `hi` Hz with soft shoulders (FFT: a mask that ramps over `slope` octaves)."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    with np.errstate(divide="ignore"):
        lf = np.log2(np.maximum(f, 1e-6))
    up = np.clip((lf - np.log2(lo) + slope) / slope, 0, 1)
    down = np.clip((np.log2(hi) - lf + slope) / slope, 0, 1)
    mask = up * down
    mask[0] = 0.0
    return np.fft.irfft(np.fft.rfft(x) * mask, n)


def lowpass(x, fc):
    return band(x, 1.0, fc, 0.6)


def level(y):
    y = y - y.mean()
    fr = int(SR * 0.02)
    frames = [y[i:i + fr] for i in range(0, max(len(y) - fr, 1), fr)]
    r = np.array([np.sqrt(np.mean(f ** 2) + 1e-12) for f in frames])
    keep = r > r.max() * 10 ** (-45 / 20)
    rms = np.sqrt(np.mean(np.concatenate([f for f, k in zip(frames, keep) if k]) ** 2))
    g = 10 ** (TARGET_RMS_DB / 20) / rms
    ceil = 10 ** (CEILING_DB / 20)
    y = y * g
    peak = np.abs(y).max()
    if peak > ceil:
        lim = min(peak / ceil, 10 ** (MAX_LIMIT_DB / 20))
        y = np.tanh(y / ceil * 0.9 / lim * lim) * ceil if lim > 1.0 else y
        y = y / max(np.abs(y).max() / ceil, 1.0)
    return y


def write(path, y):
    y = np.clip(y, -1.0, 1.0)
    data = (y * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def roar(seconds, seed_shift=0):
    """The fire's body: pink-ish noise banded 120..3200 Hz, its loudness fluttering 6..14 times a second (low-passed noise
    as the LFO), a low rumble under it and a thin hiss over it."""
    n = int(SR * seconds)
    white = rng.standard_normal(n)
    body = band(white, 120.0, 3200.0)
    body /= np.abs(body).max() + 1e-9
    # the flutter: slow noise, 2..14 Hz, so the roar breathes instead of hissing flat
    lfo = band(rng.standard_normal(n), 2.0, 14.0)
    lfo /= np.abs(lfo).max() + 1e-9
    body *= 1.0 + 0.45 * lfo
    rumble = band(rng.standard_normal(n), 40.0, 140.0)
    rumble /= np.abs(rumble).max() + 1e-9
    hiss = band(rng.standard_normal(n), 3000.0, 7500.0)
    hiss /= np.abs(hiss).max() + 1e-9
    hiss *= 1.0 + 0.6 * lfo
    return body + 0.5 * rumble + 0.12 * hiss


def w_breath_loop():
    """A seamless loop: 1.6 s of roar, its last 0.25 s crossfaded under its first, so the join is silent."""
    seconds = 1.6
    fade = int(SR * 0.25)
    n = int(SR * seconds)
    y = roar(seconds + 0.25)
    out = y[:n].copy()
    ramp = np.linspace(0.0, 1.0, fade)
    out[:fade] = out[:fade] * ramp + y[n:n + fade] * (1.0 - ramp)
    return level(out)


def w_breath_start():
    """The lighter's flick (a 12 ms click of bright noise and a tiny metallic ping) and, a tenth of a second on, the
    whoomp: a low sweep down with the roar swelling up and dying over about half a second."""
    seconds = 0.75
    n = int(SR * seconds)
    t = t_of(seconds)
    y = np.zeros(n)
    # the click
    ck = int(SR * 0.012)
    click = band(rng.standard_normal(ck), 1800.0, 7000.0)
    click *= np.exp(-np.arange(ck) / (SR * 0.004))
    y[:ck] += 0.9 * click / (np.abs(click).max() + 1e-9)
    ping = np.sin(2 * np.pi * 5200.0 * t) * np.exp(-t / 0.012)
    y += 0.25 * ping
    # the whoomp: starts 0.08 s on
    on = int(SR * 0.08)
    tt = t[on:] - t[on]
    sweep_f = 150.0 * np.exp(-tt / 0.09) + 55.0
    phase = 2 * np.pi * np.cumsum(sweep_f) / SR
    thud = np.sin(phase) * np.exp(-tt / 0.18)
    y[on:] += 0.8 * thud
    r = roar(seconds - 0.08)
    env = np.clip(tt / 0.06, 0, 1) * np.exp(-np.maximum(tt - 0.06, 0) / 0.22)
    y[on:] += 0.7 * r / (np.abs(r).max() + 1e-9) * env
    # a short tail of fade so the loop takes over cleanly
    tail = int(SR * 0.05)
    y[-tail:] *= np.linspace(1.0, 0.0, tail)
    return level(y)


SOUNDS = {"w_breath_loop": w_breath_loop, "w_breath_start": w_breath_start}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", default="", help="comma-separated ids")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args(argv)
    want = [s for s in a.only.split(",") if s] or list(SOUNDS)
    os.makedirs(a.out, exist_ok=True)
    for sid in want:
        y = SOUNDS[sid]()
        path = os.path.join(a.out, sid + ".wav")
        write(path, y)
        print("%s: %.2f s, peak %.2f, rms %.1f dBFS -> %s" % (sid, len(y) / SR, np.abs(y).max(), 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-9), os.path.relpath(path)))


if __name__ == "__main__":
    main()
