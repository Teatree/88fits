"""Goofy voice barks through the local Kokoro TTS (Pinokio app on http://127.0.0.1:7860).

Writes game/content/sounds/voice/<id>.wav for every line below and points the sound map at them.
Lines follow the tone in design bible section 16: cartoon western, comedic, short.
Run: python tools/gen_voice.py          (then: godot --import and tools/import_json.gd)
"""
import json, os, re, shutil, sys, urllib.request

BASE = "http://127.0.0.1:7860/gradio_api"
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "content", "sounds")
OUT = os.path.join(ROOT, "voice")

# id, text, voice keyword, speed
LINES = [
    ("pl_hurt", "Oof!", "Puck", 1.25),
    ("pl_death", "Noooooo!", "Puck", 0.85),
    ("pl_revive", "I'm back, baby!", "Puck", 1.1),
    ("pl_jump", "Hup!", "Puck", 1.35),
    ("ui_levelup", "Level up!", "Bella", 1.2),
    ("ui_unlock", "Unlocked!", "Bella", 1.1),
    ("wd_extract", "Extracted! Cha-ching.", "Bella", 1.05),
    ("en_elite_spawn", "Uh oh.", "Puck", 1.0),
    ("en_boss_roar", "Bow before the Tumbleweed King!", "Fenrir", 0.9),
    ("en_boss_die", "My crown! My beautiful crown!", "Fenrir", 0.95),
]


def api_info():
    return json.load(urllib.request.urlopen(f"{BASE}/info", timeout=10))["named_endpoints"]["/generate_first"]


def generate(ep, text, voice_kw, speed):
    params = [p.get("parameter_default") for p in ep["parameters"]]
    params[0] = text
    voices = ep["parameters"][1]["type"]["enum"]
    params[1] = next((v for v in voices if voice_kw in v), voices[0])
    params[2] = speed
    params[3] = "WAV"
    req = urllib.request.Request(f"{BASE}/call/generate_first", data=json.dumps({"data": params}).encode(), headers={"Content-Type": "application/json"})
    eid = json.load(urllib.request.urlopen(req, timeout=30))["event_id"]
    out = urllib.request.urlopen(f"{BASE}/call/generate_first/{eid}", timeout=240).read().decode("utf-8", "ignore")
    m = re.search(r'"url":\s*"([^"]+)"', out)
    if not m:
        raise RuntimeError("no audio in response: " + out[:200])
    return urllib.request.urlopen(m.group(1), timeout=60).read()


def main():
    os.makedirs(OUT, exist_ok=True)
    ep = api_info()
    smap_path = os.path.join(ROOT, "soundmap.json")
    smap = json.load(open(smap_path, encoding="utf-8"))
    done = 0
    for sid, text, voice, speed in LINES:
        path = os.path.join(OUT, sid + ".wav")
        try:
            data = generate(ep, text, voice, speed)
        except Exception as e:
            print("FAILED", sid, e)
            continue
        open(path, "wb").write(data)
        row = smap["sounds"].setdefault(sid, {"category": "voice", "voices": 1, "pitch_spread": 0.04, "volume_db": 0})
        row["file"] = "voice/%s.wav" % sid
        row["pitch_spread"] = max(float(row.get("pitch_spread", 0.04)), 0.04)
        done += 1
        print("voice", sid, "<-", repr(text), len(data), "bytes")
    json.dump(smap, open(smap_path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    print("gen_voice: %d lines written, sound map updated" % done)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
