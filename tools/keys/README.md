# tools/keys: the secrets, on this PC only

Everything in this folder is git-ignored (`.gitignore`: `tools/keys/*`) except this README. Nothing here is ever
committed, shipped in a build, sent to PostHog or printed by a tool; `python tools/doctor.py` lists which of these files
exist (names only, it never opens them).

| File | What it holds | Who reads it |
|---|---|---|
| `keystore.env` + `88fits.keystore` | the Android release keystore, and its path, user and password as environment lines Godot's Android export reads | `tools/ship.sh`, `tools/ship_prod.sh` (a missing file stops a release build: a debug-signed APK cannot update the phone's install) |
| `codesign.env` | Windows code signing (a .pfx, a store certificate or a signing service; docs/pc_build_trust.md) | `tools/sign_exe.ps1` through ship.sh / ship_prod.sh; absent = the exe ships unsigned |
| `anthropic.env` | `ANTHROPIC_API_KEY=...` (or the bare key) for the evaluator's cloud tier | `tools/vision_eval.py` (`read_key`) and `tools/qa_bench.py`; never the environment's key (the harness's own key must not pay for the loop) |
| `gemini.env` | `GEMINI_API_KEY=...` (an AI Studio key with billing) for the planned Gemini backend | `tools/vision_eval.py`, `tools/qa_bench.py` (G3) |

Kept elsewhere, also git-ignored: the PostHog personal key `tools/posthog_personal_key.txt` (`tools/posthog_boards.py`,
`tools/posthog_runs.py`), and the AI server's ssh key `~/.ssh/id_ed25519_ai_server` (its path is `ssh_key` in
`tools/ai_hosts.json`).

On a new PC: copy these files over by hand (a USB stick, never a cloud folder that syncs them in clear), then run
`python tools/doctor.py`.
