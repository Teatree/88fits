"""Pass 65: sounds synthesised in numpy (no model): the gem dings, the hero's hurt and the slot machine's sequence.

Garry: VS-style "ding" for the XP gems (stronger for bigger gems), a noticeable chiptune "negative" hit for the hero,
and a slot machine's whole sequence (lever, spin, stop) round the chest and mutation reels. Made after analysing his
references in _REFERENCES/audio/AudioClip (ripped from Vampire Survivors: analysed only, never copied or shipped).
Writes game/content/sounds/real/<id>.wav, 22.05 kHz 16-bit mono, levelled like tools/ai_sfx.py (content RMS -14 dBFS,
peaks held at -2 dBFS, at most 6 dB of limiting). The pass-64 gems are in tools/dl/backup/sfx_pass64/.

    python tools/synth_sfx.py [--only pk_gem_s,ui_slot_spin]
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
rng = np.random.default_rng(65)


def t_of(sec):
    return np.arange(int(SR * sec)) / SR


def env_ad(t, attack, tau):
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / tau)


def partial(t, f, amp, tau, attack=0.002, start=0.0):
    tt = t - start
    on = tt >= 0
    y = np.zeros_like(t)
    y[on] = amp * np.sin(2 * np.pi * f * tt[on]) * env_ad(tt[on], attack, tau)
    return y


def square(phase):
    return np.sign(np.sin(phase))


def fade_out(y, ms=20):
    n = min(len(y), int(SR * ms / 1000))
    y[-n:] *= np.linspace(1, 0, n)
    return y


def level(y):
    y = y - y.mean()
    fr = int(SR * 0.02)
    frames = [y[i:i + fr] for i in range(0, max(len(y) - fr, 1), fr)]
    r = np.array([np.sqrt(np.mean(f ** 2) + 1e-12) for f in frames])
    keep = r > r.max() * 10 ** (-45 / 20)
    rms = np.sqrt(np.mean(np.concatenate([f for f, k in zip(frames, keep) if k]) ** 2))
    g = 10 ** (TARGET_RMS_DB / 20) / rms
    ceil = 10 ** (CEILING_DB / 20)
    lim = np.abs(y).max() * g / ceil
    if lim > 10 ** (MAX_LIMIT_DB / 20):
        g /= lim / 10 ** (MAX_LIMIT_DB / 20)   # a spikier sound stops short of the target
        lim = 10 ** (MAX_LIMIT_DB / 20)
    y = y * g
    if lim > 1.0:
        # soft knee: everything over half the ceiling bends under it
        k = ceil * 0.5
        a = np.abs(y)
        over = a > k
        y[over] = np.sign(y[over]) * (k + (ceil - k) * np.tanh((a[over] - k) / (ceil - k)))
    return y


# ------------------------------------------------------------------ the gem dings
# Reference (VS sfx_gem): partials near 1.34 and 2.01 kHz (a fifth) with a 4.47 kHz glint, peak at 50 ms, -20 dB by
# 355 ms, -40 dB by 795 ms. Ours: other notes (G6 / E6 + B6 / C6 with a second strike), the small one short and soft,
# the large brighter and ringing longer.
def gem(size):
    if size == "s":
        sec, f0, tau = 0.22, 1568.0, 0.055
        t = t_of(sec)
        y = partial(t, f0, 1.0, tau) + partial(t, f0 * 2.0, 0.25, tau * 0.5) + partial(t, f0 * 3.0, 0.08, 0.012)
    elif size == "m":
        sec, f0, tau = 0.42, 1319.0, 0.11
        t = t_of(sec)
        y = (partial(t, f0, 1.0, tau) + partial(t, f0 * 1.5, 0.55, tau * 0.8) + partial(t, f0 * 3.0, 0.18, 0.03)
             + partial(t, f0 * 4.0, 0.06, 0.02))
    else:
        sec, f0, tau = 0.8, 1047.0, 0.22
        t = t_of(sec)
        y = (partial(t, f0, 1.0, tau) + partial(t, f0 * 1.5, 0.5, tau * 0.8) + partial(t, f0 * 2.0, 0.35, tau * 0.6)
             + partial(t, f0 * 4.0, 0.12, 0.04)
             # the second strike, a fifth over the octave 70 ms on: the "ding-ding" of a big one
             + partial(t, f0 * 3.0, 0.6, tau * 0.9, start=0.07) + partial(t, f0 * 6.0, 0.12, 0.05, start=0.07))
    n = int(SR * 0.003)
    y[:n] += rng.normal(0, 0.15, n) * np.linspace(1, 0, n)   # a 3 ms glassy tick on the attack
    return fade_out(y, 25)


# ------------------------------------------------------------------ the hero's hurt
# Reference (VS sfx_enemyHit, loosely): 125 ms, the first 40 ms bright (centroid 4.4 kHz) over 330-520 Hz, gone by
# 50 ms. Ours: a chiptune "negative" blip, a square falling 620 -> 150 Hz over 160 ms with a second voice a tritone
# under, stepped like an old sound chip, and a 25 ms crunch of crushed noise on the hit.
def hurt():
    t = t_of(0.2)
    f = 620.0 * (150.0 / 620.0) ** np.clip(t / 0.16, 0, 1)
    f = np.round(f / 20.0) * 20.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = env_ad(t, 0.002, 0.07)
    y = 0.7 * square(ph) * e + 0.35 * square(ph / 1.414) * e
    noise = np.round(rng.uniform(-1, 1, len(t)) * 3) / 3
    held = np.repeat(noise[::6], 6)[:len(t)]
    y += 0.8 * held * env_ad(t, 0.001, 0.012)
    return fade_out(y, 20)


# ------------------------------------------------------------------ the slot machine
def click(t, at, amp=1.0, f=2600.0, tau=0.004):
    return partial(t, f, amp, tau, 0.0005, at) + partial(t, f * 1.7, amp * 0.5, tau * 0.7, 0.0005, at)


def slot_start():
    # the lever: a ratchet of clicks speeding up as it is pulled, the clunk at the bottom, a western twang as it catches
    t = t_of(0.6)
    y = np.zeros_like(t)
    at, gap = 0.0, 0.045
    while at < 0.3:
        y += click(t, at, 0.5, 2300.0 + 500 * at)
        at += gap
        gap = max(gap * 0.85, 0.018)
    y += partial(t, 140.0, 1.2, 0.06, 0.003, 0.32) + partial(t, 420.0, 0.5, 0.03, 0.002, 0.32)
    n0 = int(0.32 * SR)
    y[n0:n0 + 200] += rng.normal(0, 0.5, 200) * np.linspace(1, 0, 200)
    for f, a in [(392.0, 0.35), (588.0, 0.25)]:
        tt = np.maximum(t - 0.36, 0)
        y += (t >= 0.36) * a * (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(4 * np.pi * f * tt)) * np.exp(-tt / 0.12)
    return fade_out(y, 30)


def slot_spin():
    # the loop: reels whirring past their stops, 24 clicks a second over a soft motor; 0.5 s, the motor whole cycles
    # long and every click's tail folded round to the start, so the loop has no seam
    sec = 0.5
    n = int(SR * sec)
    t = t_of(sec * 2)
    y = np.zeros_like(t)
    for k in range(12):
        at = k / 24.0
        y += click(t, at, 0.9 if k % 3 == 0 else 0.6, 2000.0 if k % 2 else 2400.0, 0.006)
        y += click(t, at + 1 / 48.0, 0.45, 1700.0, 0.005)
    y = y[:n] + y[n:2 * n]
    t = t[:n]
    y += 0.08 * np.sin(2 * np.pi * 110 * t) + 0.05 * np.sin(2 * np.pi * 220 * t + 0.4)
    return y


def slot_stop():
    # the reel catching its stop: a heavy clunk, a metallic clack, a short ring
    t = t_of(0.35)
    y = partial(t, 120.0, 1.3, 0.05, 0.002) + partial(t, 260.0, 0.6, 0.03, 0.002)
    y += click(t, 0.0, 0.9, 3100.0, 0.008) + click(t, 0.018, 0.6, 2500.0, 0.006)
    y += partial(t, 880.0, 0.25, 0.09, 0.002, 0.01) + partial(t, 1320.0, 0.12, 0.06, 0.002, 0.01)
    y[:150] += rng.normal(0, 0.6, 150) * np.linspace(1, 0, 150)
    return fade_out(y, 25)


# ------------------------------------------------------------------ May's inflatable double (pass 69, lane HERO)
def decoy_land():
    # a vinyl doll hitting the sand: a soft low thud and a rubbery "boing" whose pitch wobbles and settles
    t = t_of(0.42)
    wob = 1.0 + 0.18 * np.sin(2 * np.pi * 9.0 * t) * np.exp(-t / 0.12)
    f = (230.0 + 120.0 * np.exp(-t / 0.05)) * wob
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = 0.8 * np.sin(ph) * env_ad(t, 0.004, 0.13) + 0.25 * np.sin(2 * ph) * env_ad(t, 0.004, 0.06)
    y += partial(t, 85.0, 1.0, 0.05, 0.002) + partial(t, 140.0, 0.4, 0.03, 0.002)
    n = int(SR * 0.012)
    y[:n] += rng.normal(0, 0.25, n) * np.linspace(1, 0, n)
    return fade_out(y, 30)


def decoy_pop():
    # the balloon bursting: a sharp crack of bright noise, then the rubber's squeal falling away as the air goes
    t = t_of(0.45)
    y = np.zeros_like(t)
    n = int(SR * 0.018)
    crack = rng.normal(0, 1.0, n)
    crack = np.diff(np.concatenate([[0.0], crack]))   # brighter: a first difference
    y[:n] += 1.4 * crack * np.linspace(1, 0, n) ** 2
    y += partial(t, 180.0, 0.6, 0.025, 0.001)
    f = 1500.0 * (620.0 / 1500.0) ** np.clip((t - 0.03) / 0.3, 0, 1) * (1.0 + 0.05 * np.sin(2 * np.pi * 38.0 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.where(t >= 0.03, env_ad(np.maximum(t - 0.03, 0), 0.02, 0.12), 0.0)
    y += 0.35 * (np.sin(ph) + 0.3 * np.sin(2 * ph)) * e
    return fade_out(y, 30)


# ------------------------------------------------------------------ the pass-69 passive items (lane PAS)
def thump(t, at, f=58.0, amp=1.0):
    # one heartbeat: a low sine whose pitch drops a little as it lands, with a soft knock on top
    tt = t - at
    on = tt >= 0
    y = np.zeros_like(t)
    fr = f * (1.0 + 0.6 * np.exp(-np.maximum(tt, 0) / 0.02))
    ph = 2 * np.pi * np.cumsum(np.where(on, fr, 0.0)) / SR
    y[on] = amp * np.sin(ph[on]) * env_ad(tt[on], 0.004, 0.09)
    y += partial(t, f * 2.1, amp * 0.25, 0.03, 0.002, at)
    return y


def last_stand():
    # Last Stand: time sinks (a low whoom falling an octave and a half) under two heartbeats, lub-dub, lub-dub
    t = t_of(1.5)
    f = 210.0 * (70.0 / 210.0) ** np.clip(t / 0.9, 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = 0.22 * (np.sin(ph) + 0.35 * np.sin(2 * ph)) * env_ad(t, 0.06, 0.55)
    for at in (0.0, 0.62):
        y += thump(t, at, 56.0, 1.0) + thump(t, at + 0.17, 52.0, 0.65)
    return fade_out(y, 60)


def heal_pulse():
    # Hot Springs: a soft warm chime with a breath of steam as the ring goes out
    t = t_of(0.55)
    y = partial(t, 784.0, 0.7, 0.16, 0.02) + partial(t, 1175.0, 0.4, 0.12, 0.02) + partial(t, 1568.0, 0.18, 0.08, 0.02)
    hiss = rng.normal(0, 1.0, len(t))
    hiss = np.convolve(hiss, np.ones(6) / 6, mode="same")
    y += 0.12 * hiss * env_ad(t, 0.05, 0.12)
    return fade_out(y, 40)


def xp_pull():
    # the Magnet's pull: a quick rising magnetic "zwoop" with a shimmer
    t = t_of(0.42)
    f = 260.0 * (980.0 / 260.0) ** np.clip(t / 0.3, 0, 1) * (1.0 + 0.04 * np.sin(2 * np.pi * 28.0 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = env_ad(t, 0.03, 0.14)
    y = 0.6 * np.sin(ph) * e + 0.18 * square(ph * 0.5) * e + 0.12 * np.sin(3 * ph) * e
    return fade_out(y, 30)


def counterpunch():
    # Counterpunch armed: a short whoosh of air and a leather snap
    t = t_of(0.26)
    n = rng.normal(0, 1.0, len(t))
    n = np.convolve(n, np.ones(3) / 3, mode="same")
    sweep = env_ad(t, 0.05, 0.05)
    y = 0.5 * n * sweep
    y += click(t, 0.075, 1.0, 1900.0, 0.01) + partial(t, 120.0, 0.8, 0.04, 0.002, 0.075)
    return fade_out(y, 25)


# ------------------------------------------------------------------ the Salt's shaker (pass 69, lane SALT)
def salt_shake():
    # a glass shaker shaken three times over the sand: each shake a glassy tap and a rattle of grains on the chrome cap
    # (a spray of tiny high clicks), then a soft hiss of salt falling
    t = t_of(0.5)
    y = np.zeros_like(t)
    for k, at in enumerate((0.0, 0.11, 0.22)):
        y += partial(t, 2350.0 + 120 * k, 0.35, 0.012, 0.0008, at) + partial(t, 3900.0, 0.15, 0.008, 0.0008, at)
        for g in range(26):
            ga = at + rng.uniform(0.0, 0.05)
            y += click(t, ga, rng.uniform(0.08, 0.22), rng.uniform(3800.0, 7200.0), 0.0015)
    n = rng.normal(0, 1.0, len(t))
    n = n - np.convolve(n, np.ones(6) / 6, mode="same")
    y += 0.12 * n * env_ad(np.maximum(t - 0.25, 0), 0.03, 0.08) * (t >= 0.25)
    return fade_out(y, 25)


SOUNDS = {
    "w_salt_shake": salt_shake,
    "pk_decoy_land": decoy_land,
    "pk_decoy_pop": decoy_pop,
    "pk_gem_s": lambda: gem("s"),
    "pk_gem_m": lambda: gem("m"),
    "pk_gem_l": lambda: gem("l"),
    "pl_hurt": hurt,
    "ui_slot_start": slot_start,
    "ui_slot_spin": slot_spin,
    "ui_slot_stop": slot_stop,
    "it_last_stand": last_stand,
    "it_heal_pulse": heal_pulse,
    "it_xp_pull": xp_pull,
    "it_counterpunch": counterpunch,
}


def write(path, y):
    pcm = (np.clip(y, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def stats(y):
    r = 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)
    pk = 20 * np.log10(np.abs(y).max() + 1e-12)
    S = np.abs(np.fft.rfft(y))
    f = np.fft.rfftfreq(len(y), 1 / SR)
    return f"{len(y) / SR * 1000:.0f} ms, rms {r:.1f} dB, peak {pk:.1f} dB, centroid {(S * f).sum() / S.sum():.0f} Hz"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    for sid, fn in SOUNDS.items():
        if only and sid not in only:
            continue
        y = level(fn())
        write(os.path.join(OUT, sid + ".wav"), y)
        print(sid, stats(y))


if __name__ == "__main__":
    main()
