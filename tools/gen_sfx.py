"""Synthesises a placeholder WAV for every sound id in game/content/sounds/soundmap.json.

Pure Python (wave + math). Categories decide the recipe:
  ui      short sine blips
  player  thuds and sweeps
  weapon  clicks, noise bursts, zaps
  pickup  rising chimes
  enemy   squeaks, growls, pops
  world   loops of filtered noise
  music   looped chord pads (stems differ by register)
Run: python tools/gen_sfx.py [--force]
"""
import json, math, os, random, struct, sys, wave

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "content", "sounds")
RATE = 22050
FORCE = "--force" in sys.argv


def env(t, dur, a=0.005, r=0.08):
    if t < a:
        return t / a
    if t > dur - r:
        return max((dur - t) / r, 0.0)
    return 1.0


def write(path, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = 0.7 / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))


def sine(freq_fn, dur, shape="sine"):
    out = []
    phase = 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        f = freq_fn(t)
        phase += 2 * math.pi * f / RATE
        if shape == "square":
            v = 1.0 if math.sin(phase) > 0 else -1.0
        elif shape == "saw":
            v = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        else:
            v = math.sin(phase)
        out.append(v * env(t, dur))
    return out


def noise(dur, lowpass=0.2, decay=6.0):
    out = []
    y = 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        y += (random.uniform(-1, 1) - y) * lowpass
        out.append(y * math.exp(-decay * t) * env(t, dur, 0.002, 0.02))
    return out


def clack(r, freq, dur=0.05):
    """One woody knock: a short ringing tone and its overtone, with a tick of noise at the front."""
    out = []
    for i in range(int(dur * RATE)):
        t = i / RATE
        e = math.exp(-t * 90.0)
        tick = r.uniform(-1, 1) * 0.5 * math.exp(-t * 400.0)
        out.append((math.sin(2 * math.pi * freq * t) * 0.8 + math.sin(2 * math.pi * freq * 2.3 * t) * 0.35 + tick) * e)
    return out


def clatter(r, n, span, band):
    """Bones knocking together (the skeletons, pass 33.3): n clacks over `span` seconds, thinning out and softening
    towards the end like a heap settling."""
    out = [0.0] * int((span + 0.08) * RATE)
    for k in range(n):
        at = span * (k / max(n - 1, 1)) ** 1.6 * r.uniform(0.85, 1.0) if n > 1 else 0.0
        c = clack(r, r.uniform(*band), r.uniform(0.03, 0.06))
        g = r.uniform(0.5, 1.0) * (1.0 - 0.5 * k / max(n, 1))
        s = int(at * RATE)
        for i, v in enumerate(c):
            if s + i < len(out):
                out[s + i] += v * g
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] if i < len(p) else 0.0 for p in parts) for i in range(n)]


def chord(freqs, dur, shape="saw", wobble=0.0):
    out = [0.0] * int(dur * RATE)
    for f in freqs:
        s = sine(lambda t, f=f: f * (1.0 + wobble * math.sin(t * 5.0)), dur, shape)
        for i, v in enumerate(s):
            out[i] += v / len(freqs)
    # loop-friendly: no release
    return [v * (min(1.0, i / (0.01 * RATE))) for i, v in enumerate(out)]


def recipe(sid, cat, loop):
    r = random.Random(sid)
    if cat == "music":
        base = {"mu_title": 110.0, "mu_run_1": 130.8, "mu_run_2": 261.6, "mu_run_3": 523.2, "mu_boss": 98.0, "mu_results": 146.8}.get(sid, 130.8)
        pattern = [1.0, 1.25, 1.5, 1.25, 1.0, 1.2, 1.5, 1.8]
        dur = 4.0
        out = []
        for k, m in enumerate(pattern):
            out += chord([base * m, base * m * 1.5, base * m * 2.0], dur / len(pattern), "saw" if "run" in sid or "boss" in sid else "sine", 0.01)
        return out
    if cat == "world":
        if "gust" in sid:
            # a gust of wind (pass 44): low hiss that swells and dies away
            raw = noise(2.4, 0.045, 0.0)
            n = len(raw)
            return [v * 0.7 * math.sin(math.pi * i / n) ** 1.5 for i, v in enumerate(raw)]
        return [v * 0.6 for v in noise(3.0, 0.03 if "ambient" in sid else 0.1, 0.0)]
    if cat == "ui":
        if "fanfare" in sid:
            # the level-up reveal (pass 44): a three-stab brass fanfare, then a held major chord with a little vibrato
            out = []
            for f in (392.0, 523.3, 659.3):
                out += chord([f, f * 1.25, f * 1.5], 0.13, "saw", 0.0)
            out += chord([523.3, 659.3, 784.0, 1046.5], 0.55, "saw", 0.012)
            return mix(out, [v * 0.25 for v in noise(0.12, 0.6, 30)])
        if "jackpot" in sid:
            # the chest landing (pass 44): a rising run of bells and a shimmer on top
            out = []
            for k, f in enumerate((784.0, 987.8, 1174.7, 1568.0, 1975.5, 2349.3)):
                out += sine(lambda t, f=f: f, 0.07)
            out += [v * 0.8 for v in sine(lambda t: 2093.0, 0.5)]
            return mix(out, [v * 0.3 for v in noise(0.9, 0.7, 6)])
        if "levelup" in sid or "unlock" in sid:
            return mix(sine(lambda t: 523 if t < 0.12 else (659 if t < 0.24 else 784), 0.45), noise(0.1, 0.5, 30))
        if "buy" in sid:
            return mix(sine(lambda t: 1200 + 400 * math.sin(t * 60), 0.3), noise(0.3, 0.6, 12))
        if "locked" in sid:
            return sine(lambda t: 140, 0.15, "square")
        if "pause" in sid:
            return sine(lambda t: 800 - 600 * t / 0.3, 0.3)
        if "resume" in sid:
            return sine(lambda t: 200 + 600 * t / 0.3, 0.3)
        if "card" in sid:
            return mix(noise(0.05, 0.9, 40), sine(lambda t: 880, 0.12))
        return sine(lambda t: 900, 0.05)
    if cat == "player":
        if "step" in sid:
            return noise(0.08, 0.15, 40)
        if "jump" in sid:
            return sine(lambda t: 300 + 500 * t / 0.25, 0.25, "square")
        if "land" in sid:
            return mix(noise(0.15, 0.1, 25), sine(lambda t: 90, 0.12))
        if "hurt" in sid:
            return sine(lambda t: 260 - 100 * t / 0.2, 0.2, "saw")
        if "death" in sid:
            return mix(sine(lambda t: 900 - 800 * t / 0.8, 0.8), noise(0.3, 0.1, 10))
        if "revive" in sid:
            return sine(lambda t: 300 + 900 * t / 0.7, 0.7)
    if cat == "weapon":
        if "pea_fire" in sid:
            return mix(sine(lambda t: 600 - 300 * t / 0.08, 0.08), noise(0.04, 0.8, 60))
        if "boom_fire" in sid:
            return mix(noise(0.25, 0.08, 14), sine(lambda t: 120, 0.15, "square"))
        if "saw_loop" in sid:
            return sine(lambda t: 180 + 20 * math.sin(t * 30), 1.0, "saw")
        if "saw_hit" in sid:
            return mix(sine(lambda t: 2400 - 1800 * t / 0.1, 0.1), noise(0.06, 0.9, 40))
        if "lob_throw" in sid:
            return sine(lambda t: 1200 - 900 * t / 0.5, 0.5)
        if "lob_boom" in sid:
            return mix(noise(0.6, 0.04, 6), sine(lambda t: 60, 0.4))
        if "zap" in sid:
            return [v * (1 if r.random() > 0.3 else 0.2) for v in noise(0.2, 0.9, 12)]
        if "turret_place" in sid:
            return mix(sine(lambda t: 200, 0.1, "square"), sine(lambda t: 400 + 200 * t, 0.2))
        if "turret_fire" in sid:
            return sine(lambda t: 1400 - 800 * t / 0.06, 0.06, "square")
        if "evo" in sid:
            return mix(sine(lambda t: 220 * (2 ** (t * 2)), 1.6), noise(0.5, 0.2, 4))
        # pass 35: the Hammer, the Revolver, the Gravity Gun and the Singularity
        if "hammer_swing" in sid:
            return [v * min(1.0, i / 3000.0) for i, v in enumerate(noise(0.3, 0.12, 5))]
        if "hammer_hit" in sid:
            return mix(noise(0.55, 0.05, 7), sine(lambda t: 70 - 35 * t / 0.4, 0.4), [v * 0.6 for v in noise(0.08, 0.9, 40)])
        if "guitarra" in sid:
            # a strummed chord (pass 43): three plucked strings a few ms apart, each a bright decaying tone with a pick tick
            out = [0.0] * int(0.5 * RATE)
            for k, f in enumerate((196.0, 246.9, 293.7)):
                at = int(k * 0.018 * RATE)
                for i in range(int(0.45 * RATE)):
                    tt = i / RATE
                    v = (math.sin(2 * math.pi * f * tt) * 0.7 + math.sin(2 * math.pi * f * 2.0 * tt) * 0.25 + math.sin(2 * math.pi * f * 3.0 * tt) * 0.1) * math.exp(-tt * 7.0)
                    if at + i < len(out):
                        out[at + i] += v / 3.0
            return mix(out, [v * 0.35 for v in noise(0.03, 0.9, 80)])
        if "revolver" in sid:
            return mix(noise(0.22, 0.6, 18), sine(lambda t: 900 - 700 * t / 0.1, 0.1, "square"), sine(lambda t: 110, 0.12))
        if "grav_grab" in sid:
            return mix(sine(lambda t: 180 + 700 * t / 0.4 + 40 * math.sin(t * 90), 0.4, "saw"), [v * 0.3 for v in noise(0.4, 0.3, 3)])
        if "grav_throw" in sid:
            return mix(sine(lambda t: 900 - 700 * t / 0.3, 0.3), noise(0.25, 0.2, 9))
        if "grav_land" in sid:
            return mix(noise(0.45, 0.07, 8), sine(lambda t: 90 - 40 * t / 0.3, 0.3))
        if "blackhole" in sid:
            return mix(sine(lambda t: 140 - 90 * t / 1.2 + 6 * math.sin(t * 40), 1.2, "saw"), [v * 0.4 for v in noise(1.2, 0.04, 1.5)])
        return noise(0.1, 0.5, 30)
    if cat == "pickup":
        f = {"pk_gem_s": 1046, "pk_gem_m": 1568, "pk_gem_l": 2093, "pk_coin": 1760}.get(sid, 1200)
        if "barrel" in sid:
            # a barrel bursting (pass 44): a sharp wooden crack, a low thump and planks clattering down
            return mix(noise(0.14, 0.35, 28), sine(lambda t: 110 - 60 * t / 0.25, 0.25), clatter(r, 7, 0.45, (380, 1100)))
        if "chest" in sid:
            return mix(noise(0.4, 0.3, 6), sine(lambda t: 500 + 700 * t, 0.5))
        if "vacuum" in sid:
            return sine(lambda t: 200 + 1400 * t / 1.5, 1.5, "saw")
        if "teleport" in sid:
            # the Teleport (pass 35): a sweep up with a shimmer on top
            return mix(sine(lambda t: 300 + 1500 * t / 0.7 + 60 * math.sin(t * 70), 0.7), [v * 0.35 for v in noise(0.7, 0.6, 3)])
        return sine(lambda t: f, 0.09)
    if cat == "enemy":
        if "slime_hit" in sid:
            # the Blue Slime (pass 44): a wet squelch
            return mix(noise(0.09, 0.12, 30), sine(lambda t: 320 - 190 * t / 0.09, 0.09))
        if "slime_die" in sid:
            # a bubbly pop as it bursts into a puddle
            return mix(sine(lambda t: 520 - 420 * t / 0.3, 0.3), noise(0.22, 0.09, 14), [v * 0.5 for v in noise(0.06, 0.8, 50)])
        if "boss_roar" in sid:
            return mix(sine(lambda t: 80 + 30 * math.sin(t * 8), 1.2, "saw"), noise(1.0, 0.05, 3))
        if "boss_die" in sid:
            return mix(noise(1.6, 0.05, 2), sine(lambda t: 150 - 100 * t / 1.6, 1.6, "saw"))
        if "boss_attack" in sid:
            return noise(0.4, 0.15, 8)
        if "elite" in sid:
            return mix(sine(lambda t: 110, 0.6, "saw"), sine(lambda t: 1300, 0.08))
        if "ant" in sid:
            return sine(lambda t: 2500 - 1500 * t / 0.05, 0.05, "square")
        if "cactus_spit" in sid:
            return mix(noise(0.12, 0.3, 20), sine(lambda t: 400 - 200 * t / 0.12, 0.12))
        if "cactus_die" in sid:
            return sine(lambda t: 1200 - 1000 * t / 0.4, 0.4, "square")
        if "beetle_charge" in sid:
            return mix(noise(0.3, 0.1, 10), sine(lambda t: 100, 0.3, "saw"))
        if "bone_hit" in sid:
            return clatter(r, 3, 0.09, (900, 1700))
        if "bone_die" in sid:
            return clatter(r, 14, 0.55, (500, 1500))
        if "rocket_boom" in sid:
            # a deep boom that rolls on: low rumble, a falling thump and a crackle on top
            return mix(noise(1.4, 0.03, 3.0), sine(lambda t: 70 - 40 * t / 1.2, 1.2), [v * 0.5 for v in noise(0.5, 0.35, 9.0)])
        if "beetle_die" in sid:
            return mix(noise(0.4, 0.08, 8), sine(lambda t: 200 - 150 * t / 0.4, 0.4, "saw"))
        if "die" in sid:
            return sine(lambda t: 700 - 500 * t / 0.35, 0.35, "saw")
        return sine(lambda t: 500 + 300 * math.sin(t * 40), 0.08)
    return sine(lambda t: 440, 0.1)


def main():
    smap = json.load(open(os.path.join(ROOT, "soundmap.json"), encoding="utf-8"))
    out_dir = os.path.join(ROOT, "placeholder")
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for sid, row in smap["sounds"].items():
        path = os.path.join(out_dir, sid + ".wav")
        if os.path.exists(path) and not FORCE:
            continue
        samples = recipe(sid, row.get("category", "sfx"), row.get("loop", False))
        write(path, samples)
        written += 1
    print("gen_sfx: wrote %d wavs into %s" % (written, out_dir))


if __name__ == "__main__":
    main()
