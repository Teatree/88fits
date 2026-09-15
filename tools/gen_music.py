"""Procedural cartoon-western music loops for 88fits, replacing the chord-pad placeholders.

All run stems share tempo and length so the layers stay in sync (Audio.play_music starts them together):
  mu_run_1   drums + bass (galloping)
  mu_run_2   rhythm stabs + chords
  mu_run_3   whistle lead + double-time hats
  mu_boss    faster, minor, brass stabs
  mu_title   laid-back guitar-ish arpeggio
  mu_results twenty seconds of jaunty harmonica-ish lead
Pure Python. Writes 44.1 kHz mono WAVs into game/content/sounds/placeholder/.
Run: python tools/gen_music.py
"""
import math, os, random, struct, wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "content", "sounds", "placeholder")
os.makedirs(OUT, exist_ok=True)

A = 110.0
MINOR_PENT = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22]  # semitones from root
MAJOR = [0, 2, 4, 5, 7, 9, 11, 12]


def note(semi, root=A):
    return root * (2 ** (semi / 12.0))


def osc(shape, f, t, vib=0.0):
    ph = f * t + vib * math.sin(t * 6.0 * math.tau) * 0.004 * f
    x = (ph % 1.0)
    if shape == "saw":
        return 2.0 * x - 1.0
    if shape == "square":
        return 1.0 if x < 0.5 else -1.0
    if shape == "tri":
        return 4.0 * abs(x - 0.5) - 1.0
    return math.sin(ph * math.tau)


def adsr(t, dur, a=0.005, d=0.06, s=0.7, r=0.08):
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * (t - a) / d
    if t > dur - r:
        return max(0.0, s * (dur - t) / r)
    return s


class Track:
    def __init__(self, seconds):
        self.n = int(seconds * RATE)
        self.buf = [0.0] * self.n

    def tone(self, shape, freq, start, dur, vol=0.3, vib=0.0, env=(0.005, 0.06, 0.7, 0.08), lowpass=0.0):
        i0 = int(start * RATE)
        i1 = min(self.n, int((start + dur) * RATE))
        y = 0.0
        for i in range(i0, i1):
            t = (i - i0) / RATE
            v = osc(shape, freq, t, vib) * adsr(t, dur, *env) * vol
            if lowpass > 0.0:
                y += (v - y) * lowpass
                v = y
            j = i % self.n
            self.buf[j] += v

    def noise(self, start, dur, vol=0.3, decay=30.0, lowpass=0.5):
        i0 = int(start * RATE)
        i1 = min(self.n, int((start + dur) * RATE))
        y = 0.0
        for i in range(i0, i1):
            t = (i - i0) / RATE
            y += (random.uniform(-1, 1) - y) * lowpass
            self.buf[i % self.n] += y * math.exp(-decay * t) * vol

    def kick(self, start, vol=0.8):
        i0 = int(start * RATE)
        for i in range(i0, min(self.n, i0 + int(0.18 * RATE))):
            t = (i - i0) / RATE
            f = 120.0 * math.exp(-t * 18.0) + 40.0
            self.buf[i % self.n] += math.sin(t * f * math.tau) * math.exp(-t * 14.0) * vol

    def write(self, name):
        peak = max(1e-6, max(abs(v) for v in self.buf))
        g = 0.85 / peak
        with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * g)) * 32767)) for v in self.buf))
        print("wrote", name)


def gallop(track, bpm, bars, root, vol_bass=0.35, kick_vol=0.7):
    beat = 60.0 / bpm
    bar = beat * 4
    for b in range(bars):
        t0 = b * bar
        # gallop pattern: da-da-DUM per beat
        for q in range(4):
            tb = t0 + q * beat
            track.kick(tb, kick_vol)
            track.noise(tb + beat * 0.5, 0.05, 0.18, 60, 0.6)
            track.noise(tb + beat * 0.75, 0.05, 0.12, 60, 0.6)
            if q in (1, 3):
                track.noise(tb, 0.12, 0.35, 25, 0.25)  # snare
        # bass: root - fifth - octave walk
        prog = [0, 0, 5, 5, 7, 7, 3, 3][b % 8]
        for q in range(8):
            semi = prog + [0, 0, 7, 0, 12, 0, 7, 5][q]
            track.tone("square", note(semi, root) / 2.0, t0 + q * beat * 0.5, beat * 0.45, vol_bass, 0.0, (0.004, 0.04, 0.6, 0.05), 0.15)


def stabs(track, bpm, bars, root):
    beat = 60.0 / bpm
    bar = beat * 4
    for b in range(bars):
        t0 = b * bar
        prog = [0, 0, 5, 5, 7, 7, 3, 3][b % 8]
        chord = [0, 3, 7] if prog in (0, 3) else [0, 4, 7]
        for q in (1, 3):
            for semi in chord:
                track.tone("saw", note(prog + semi + 12, root), t0 + q * beat, beat * 0.35, 0.09, 0.0, (0.004, 0.08, 0.3, 0.06), 0.35)
        for semi in chord:
            track.tone("tri", note(prog + semi + 12, root), t0, bar, 0.05, 0.0, (0.1, 0.3, 0.8, 0.3), 0.2)


def lead(track, bpm, bars, root, shape="sine", vol=0.22, seed=3):
    r = random.Random(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    idx = 4
    for b in range(bars):
        t0 = b * bar
        q = 0.0
        while q < 4.0:
            dur = r.choice([0.5, 0.5, 1.0, 1.0, 1.5, 2.0])
            if q + dur > 4.0:
                dur = 4.0 - q
            step = r.choice([-2, -1, -1, 0, 1, 1, 2])
            idx = max(2, min(len(MINOR_PENT) - 1, idx + step))
            if r.random() < 0.85:
                track.tone(shape, note(MINOR_PENT[idx] + 12, root), t0 + q * beat, dur * beat * 0.9, vol, 1.0, (0.02, 0.1, 0.8, 0.1))
            q += dur
        if b % 4 == 3:
            track.tone(shape, note(12, root), t0 + 3 * beat, beat * 0.9, vol, 1.0)


def hats(track, bpm, bars):
    beat = 60.0 / bpm
    bar = beat * 4
    for b in range(bars):
        for e in range(8):
            track.noise(b * bar + e * beat * 0.5, 0.03, 0.10 if e % 2 == 0 else 0.06, 90, 0.9)


def main():
    random.seed(88)
    bpm, bars = 132.0, 8
    seconds = bars * 4 * 60.0 / bpm
    t = Track(seconds); gallop(t, bpm, bars, A); t.write("mu_run_1")
    t = Track(seconds); stabs(t, bpm, bars, A); t.write("mu_run_2")
    t = Track(seconds); lead(t, bpm, bars, A, "sine", 0.22, 3); hats(t, bpm, bars); t.write("mu_run_3")
    # boss: faster, lower, with brass-like saw stabs on every beat
    bpm_b = 156.0
    sec_b = bars * 4 * 60.0 / bpm_b
    t = Track(sec_b); gallop(t, bpm_b, bars, A * 0.75, 0.4, 0.9)
    beat = 60.0 / bpm_b
    for b in range(bars):
        for q in range(4):
            for semi in (0, 3, 7):
                t.tone("saw", note(semi + 12, A * 0.75), (b * 4 + q) * beat, beat * 0.5, 0.12, 0.0, (0.003, 0.05, 0.4, 0.05), 0.4)
    lead(t, bpm_b, bars, A * 0.75, "square", 0.12, 5)
    t.write("mu_boss")
    # title: slow arpeggio
    bpm_t = 84.0
    sec_t = 8 * 4 * 60.0 / bpm_t
    t = Track(sec_t)
    beat = 60.0 / bpm_t
    for b in range(8):
        prog = [0, 5, 7, 3][b % 4]
        for e in range(8):
            semi = prog + [0, 7, 12, 7, 15, 12, 7, 12][e]
            t.tone("tri", note(semi, A), (b * 4 + e * 0.5) * beat, beat * 0.9, 0.2, 0.3, (0.01, 0.2, 0.5, 0.2), 0.3)
        t.tone("sine", note(prog, A) / 2, b * 4 * beat, 4 * beat * 0.95, 0.25, 0.0, (0.05, 0.5, 0.8, 0.3))
    lead(t, bpm_t, 8, A, "sine", 0.12, 11)
    t.write("mu_title")
    # results: jaunty major, twenty seconds
    bpm_r = 140.0
    bars_r = 12
    sec_r = bars_r * 4 * 60.0 / bpm_r
    t = Track(sec_r)
    beat = 60.0 / bpm_r
    r = random.Random(21)
    idx = 3
    for b in range(bars_r):
        prog = [0, 5, 7, 0][b % 4]
        for q in range(4):
            t.kick((b * 4 + q) * beat, 0.5)
            t.noise((b * 4 + q + 0.5) * beat, 0.05, 0.15, 60, 0.6)
            t.tone("square", note(prog + (0 if q % 2 == 0 else 7), A) / 2, (b * 4 + q) * beat, beat * 0.4, 0.28, 0.0, (0.004, 0.04, 0.6, 0.05), 0.15)
        q = 0.0
        while q < 4.0:
            dur = r.choice([0.5, 1.0, 1.0, 1.5])
            if q + dur > 4.0:
                dur = 4.0 - q
            idx = max(0, min(len(MAJOR) - 1, idx + r.choice([-2, -1, 0, 1, 2])))
            t.tone("saw", note(MAJOR[idx] + 12 + prog, A), (b * 4 + q) * beat, dur * beat * 0.85, 0.16, 1.0, (0.01, 0.08, 0.7, 0.08), 0.5)
            q += dur
    t.write("mu_results")


if __name__ == "__main__":
    main()
