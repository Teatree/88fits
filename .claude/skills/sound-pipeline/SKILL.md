---
name: sound-pipeline
description: Generate the real sound effects of 88fits with Stable Audio (Garry's app on the main PC; AudioGen as the alternate), pick them, and bind them by id in the sound map; the placeholder synthesiser for a brand-new id. Use when adding a sound id, a weapon, an enemy, or when doing an audio pass.
---

# Sound pipeline

Every sound has an id from design-bible section 16 (`ui_tap`, `w_boom_fire`, `en_goblin_die`, `mu_run_1`, ...). Content files reference ids, never file paths. The binding lives in `game/content/sounds/soundmap.json` → `soundmap.tres` (`import_json.gd -- only=sounds`). A row: `{category, voices, pitch_spread, volume_db, loop?, file?}`; `file` defaults to `placeholder/<id>.wav`.

## Real sounds (pass 60: Stable Audio first, AudioGen as the alternate)

Since pass 60 every non-music id plays `game/content/sounds/real/<id>.wav`: 22.05 kHz 16-bit mono, content RMS −14 dBFS with the peaks limited at −2 dBFS, made by **`tools/ai_sfx.py`** from the Stable Audio app Garry runs on the main PC (`http://127.0.0.1:7861/`, Gradio 6.3.0, endpoint `/generate` through `gradio_client` 2.x). The tool holds the one prompt table (`PROMPTS`: id → group, trigger, kind, seconds, pitch, prompt), appends "Sound effect, no music, no voice." for Stable Audio (stings: "Sound effect, no voice, no words."), asks for ceil(seconds)+1 s (loops +2) at the model's own 44.1 kHz stereo and folds to mono. `--engine audiogen` is the alternate: audiocraft_plus at `http://127.0.0.1:7860/` (Gradio 3.50.2, AudioGen medium = dependency 14, spoken over the queue websocket because gradio_client 2.x refuses it; 16 kHz, mono at "16000", bare prompts). Its 345 first-run candidates live in `tools/dl/sfx60/audiogen/` and show on the listening page as alternates.

Server facts that bit (Stable Audio): `seconds_total` and `steps` must be ints (a float makes the app raise); any cfg above 1.0 returns pure silence (the distilled model samples at 8 steps, cfg 1.0, ping-pong: keep the defaults, the negative prompt is ignored there); the client must not download files (`download_files=False`: the verbose file name carries the prompt and breaks Windows' path limit, the short "output.wav" lands in the app's own folder and is refused with 403), so the tool fetches the served `/gradio_api/file=` URL itself, quoted.

```
python tools/ai_sfx.py --dry-run                 # the table and what is missing (per engine)
python tools/ai_sfx.py --gen-only                # 3 candidates per id, one clip at a time (~1.2 s each), resume-safe
python tools/ai_sfx.py                           # generate what is missing, process, score, pick, write real/, bind the map
python tools/ai_sfx.py --only w_new_fire --force # one id again (a changed prompt, length, steps or cfg regenerates by itself: "stale")
python tools/ai_sfx.py --only w_new_fire --cands 6   # three more candidates (c3..c5) for a hard id; the analysis and the pick read every candidate on disk
python tools/ai_sfx.py --rescore && python tools/ai_sfx.py --auto    # after a change to the scoring rules (no re-processing)
python tools/ai_sfx.py --pick w_new_fire=1       # a Stable candidate by ear (kept over --auto), written and bound at once
python tools/ai_sfx.py --pick w_new_fire=audiogen:2          # keep the AudioGen alternate instead
python tools/ai_sfx.py --volume wd_ambient=-20   # a volume_db re-level in the map (line-preserving edit)
python tools/ai_sfx.py --report                  # old vs new centroid and level per id, the engines' share
python tools/ai_sfx.py --docs                    # docs/design/src/sounds.json for the bible's section 16
python tools/make_sfx_review.py                  # docs/sfx_review.html (+ tools/dl/sfx60/sfx_review.zip for Drive)
python tools/ai_sfx.py --engine audiogen --gen-only          # the alternate engine, same flags
```

Then under the Godot lock: `"$GODOT" $P --import` (new wavs) and `"$GODOT" $P --script res://tools/import_json.gd -- only=sounds`.

Processing per candidate (`process`): fold to mono, resample to 22.05 kHz, DC removal, the kind's high-pass (`KINDS[kind].hp`, 40–80 Hz), the optional pitch shift (`pitch` semitones, by varispeed for every kind: longer and lower, transients intact; librosa's phase vocoder has no numba loop on this PC's numpy 1.22 and a machine-dependent method would make the picks irreproducible), onset trim at −40 dB of the peak and a cut at `seconds` with a 20–60 ms fade (loops: the steadiest window, its tail crossfaded into its head over 0.25 s), then the level: content RMS (the 20 ms frames within 45 dB of the loudest) to −14 dBFS with a look-ahead limiter holding the peaks at −2 dBFS, at most 6 dB of limiting (a spikier clip stops short of the target instead; `TARGET_RMS_DB`, `CEILING_DB`, `MAX_LIMIT_DB`). The score (`score_candidate`) is the spectral centroid against the kind's ceiling (`KINDS`), plus penalties for clipping, emptiness, a sound that is mostly sub-bass (`sub_share` under 120 Hz over the kind's `sub_max`, or a centroid under `FLOOR_HZ` 250: a phone speaker plays nothing there, so "low" must mean low-mid; the first Nuke blast and Sun Scepter strike came out at 170-180 Hz), a sound that died long before its length and a loop that swells; the lowest wins. `pick_auto` takes the Stable candidate and falls back to the AudioGen alternate only when every Stable candidate fails hard (`hard_fail`: empty, clipped, a gappy loop). Raw candidates and their `.json` (prompt, seed = crc32 of `id:k`, duration, steps, cfg) live in `tools/dl/sfx60/<engine>/`, the processed ones in `<engine>/proc/`, `<engine>/scores.json` beside them, `picks.json` ({id: {engine, k, score, centroid, manual}}) at the top. The listening page shows old and new centroid per id.

Prompt rules that worked: sound-design language in the register Garry wants ("a dull wooden knock, short, dry, close-miked, low-pitched"); name the texture ("airy hush", "grainy buzz", "hollow clack"); never "deep hum" or "drone" alone, which both models render as a sub-bass drone that a phone cannot play (say "low-mid hum with ..."); for creatures prefer physical sounds and add "an animal, not a person"; for AudioGen positive words only (no negative prompting: "no voice" steers it towards a voice). pl_hurt and pl_jump point at `real/silence.wav` (50 ms) on purpose.

## Placeholders (a brand-new id only)

```
python tools/gen_sfx.py            # writes placeholder/<id>.wav for every id that has none (never --force: it would overwrite the music)
```

The script synthesises by category (sine blips, noise bursts, sweeps, chord pads). Use it so a new id is never silent, then add the id to `PROMPTS` in `tools/ai_sfx.py` and run `--only <id>`.

## Voice barks (gone in pass 60)

The ten Kokoro lines (`tools/gen_voice.py`, now `tools/dl/backup/gen_voice_pass59.py`) and `game/content/sounds/voice/` were removed on Garry's word ("remove all the voice effects"). Their ids keep their rows: eight play non-voice sounds from `real/`, pl_hurt and pl_jump the silent file. The old wavs are kept in `tools/dl/sfx60/old_voice/` for the listening page. The Nuke power-up has its own blast now, `pk_nuke` (it used to play `en_boss_die`, the King's "My crown!").

## Adding a sound id

1. Add the row to `soundmap.json` with `category`, `voices` (max simultaneous within 400 ms), `pitch_spread`, `volume_db`.
2. Add the id to `PROMPTS` in `tools/ai_sfx.py` (group, trigger, kind, seconds, pitch, prompt) and run `python tools/ai_sfx.py --only <id>` with the app running; without it, `gen_sfx.py` for a placeholder.
3. Reference it from content (`"sfx": {"fire": "w_new_fire"}`) or code (`Audio.play("id", pos)`), then `--import` and `import_json.gd -- only=sounds`.
4. `python tools/ai_sfx.py --docs` so the bible's table lists it; `python tools/make_sfx_review.py` for the listening page.
