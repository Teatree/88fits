---
name: sound-pipeline
description: Generate placeholder sound effects and later real ones for 88fits, and bind them by id in the sound map. Use when adding a sound id, a weapon, an enemy, or when doing the audio pass.
---

# Sound pipeline

Every sound has an id from design-bible section 16 (`ui_tap`, `w_boom_fire`, `en_goblin_die`, `mu_run_1`, ...). Content files reference ids, never file paths. The binding lives in `game/content/sounds/soundmap.json` → `soundmap.tres`.

## Placeholders (now)

```
python tools/gen_sfx.py            # writes game/content/sounds/placeholder/<id>.wav for every id in soundmap.json
"$GODOT" --headless --path D:/_projects/88fits/game --import
```

The script synthesises by category: UI = short sine blips, hits = filtered noise bursts, jumps and pickups = pitch sweeps, deaths = descending sweeps, music = looped chord pads. Pure Python (`wave` + `math`), no dependencies. Volumes are pre-normalised so mixing already sounds right.

## Voice barks (available now)

`python tools/gen_voice.py` generates comedic lines through the Kokoro TTS Gradio app (Pinokio, `http://127.0.0.1:7860`, endpoint `/generate_first`: text, voice, speed, format) into `game/content/sounds/voice/<id>.wav` and rewrites the `file` of those ids in `soundmap.json`. Add a line to `LINES` in the script to voice another id. Then `--import` and `import_json.gd`.

## Real sounds (M4)

Feed the "Prompt for a sound AI" column from section 16 to a sound-effects generator (ElevenLabs SFX, Stable Audio, or a local model). Save as 44.1 kHz mono OGG into `game/content/sounds/real/<id>.ogg`, then run `python tools/normalise_sfx.py` (trim silence, peak-normalise to −3 dB) and change the one row in the sound map. Music loops go in as OGG with loop enabled in the import dock, and stage layers are separate stems (`mu_run_1`, `mu_run_2`, `mu_run_3`).

## Adding a sound id

1. Add the row to `soundmap.json` with `category`, `voices` (max simultaneous), `pitch_spread`.
2. Run `gen_sfx.py` so a placeholder exists.
3. Reference it from content (`"sfx": {"fire": "w_new_fire"}`) or code (`Audio.play("id", pos)`).
