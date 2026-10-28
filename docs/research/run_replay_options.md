# Watching a player's run afterwards: options (pass 111, 2026-10-28)

Garry: "Is there a way to save video, or something like a video from each Player's run? ... I want to be able to view it
after Player is done ... with the ability to speed up ... a video with taps highlighted would be the best. ... How would
you handle large video files, how do permissions for this kind of thing work legally? Don't implement anything."

This is research only; nothing is built.

## What we already have
- Every run (with the player's consent) sends `run_record` to PostHog: per-second curves, events, the build, totems, quests,
  frame timing. That is about 140 KB for 25 minutes, sent as gzip+base64 parts; tools/posthog_runs.py downloads them.
- The Watch (tools/watch.py) plays a run in a PC window at 0.25–8x speed, with charts and a takeover.
- Many of the game's systems already roll their dice from one run seed.

## The options

### 1. Input replay: record what the player did, re-run it on the PC (recommended)
- **What's saved:** the run seed, the build number, and per simulation step the joystick vector and the step's delta. Every
  tap on a card, chest, shop, totem or pause gets a step number.
- **Viewing:** a "Replay" mode of the Watch feeds those inputs to the hero instead of the bot. The same seed and the same
  inputs give the same run, at any speed, with the charts beside it. Taps can be drawn as rings because we know where they
  were.
- **Size:** about 60 numbers a second, so roughly 100–300 KB for 15 minutes after compression. That fits next to run_record
  in PostHog or any cheap storage.
- **Catch:** the game must be fully deterministic. Every random roll must come from the seed, no wall-clock time can steer
  the game, and each step's delta must be recorded so the frame catch-up (Game.CATCH_UP_STEPS) replays the same.
  - Old replays only play on the build that recorded them, so builds have to be kept.
  - Small drifts are possible, so add a checksum every 5 s (hero HP, position, kill count) to show where a replay went out of
    step.
- **Effort:** medium. A determinism audit, a recorder, and the Watch's replay mode.

### 2. Flight recorder: save the state of the world a few times a second
- **What's saved:** 5–10 times a second, the hero's position and HP, plus each creature's type, look, quantised position,
  facing and HP. Also the projectiles' positions, the pickups, and the screens and taps.
- **Viewing:** either the game draws the recorded positions with the real art (a replay scene), or the dashboard draws a
  lighter top-down 2D view.
- **Size:** about 3–8 MB per 15-minute run after delta coding and compression, depending on the crowd. Too big for PostHog,
  fine for object storage.
- **Pros:** doesn't need the game to be deterministic, and old recordings survive new builds.
- **Cons:** the in-between frames are interpolated, so the motion is less exact than a replay. Bigger files.
- **Effort:** medium.

### 3. Real video recorded on the phone
- Android's screen recorder (MediaProjection) shows a system consent dialog before every recording session. It can't be
  suppressed since Android 10. It also records anything on screen, such as notifications.
- Recording only our own picture avoids the dialog: Godot renders the frames and an Android plugin encodes them with
  MediaCodec. But that needs a custom plugin, and encoding while playing costs CPU, battery and heat on phones that already
  struggle late in a run.
- **Size:** 720p at ~2 Mbps is about 15 MB a minute, so ~225 MB for a 15-minute run. Realistic only as "keep the last few
  minutes on the phone, upload on Wi-Fi when asked".
- **Effort:** high.
- **Verdict:** not worth it as the default.

### 4. Video made on the PC from option 1 or 2 (pairs with them)
- Godot's Movie Maker mode (`--write-movie`) renders a replay frame-perfect to a video file on the PC, at any resolution.
- Taps and the joystick are drawn on top as rings and a stick ghost.
- You get a shareable MP4 with taps highlighted, while the phone only ever uploads a few hundred KB.

### 5. Third-party session replay (PostHog, UXCam, Smartlook)
- Their mobile replay records native Android views or screenshots. A Godot game draws everything into one GL surface, so
  they would show a blank or a low-rate screenshot slideshow.
- Costly at volume, and adds a vendor that sees screens.
- **Verdict:** not a fit.

## Handling the files
- **Where:** PostHog for small input replays (option 1), as we already do for run_record. For anything in the MB range, use
  object storage: Cloudflare R2 (no download fees) or Backblaze B2. Uploads go through a tiny signed-URL endpoint, so no
  secret key is ever in the game.
- **How:**
  - Upload on Wi-Fi only.
  - Upload in chunks that resume.
  - Upload after the run, never during it.
  - Delete the local copy once it's confirmed uploaded.
- **How much:**
  - Sample: e.g. every run of testers and debug builds, 10% of other players' runs, and all runs that end in a crash or a
    rage-quit.
  - Delete after 30–90 days.
  - Keep an index (player, build, stage, length) for searching.

## The legal side
This is not legal advice; check with a privacy lawyer before release.
- **GDPR and ePrivacy (EU):**
  - A replay tied to a player id is personal data about how that person plays.
  - Recording isn't needed to run the game, so the safe route is opt-in consent before anything is recorded. Ask with a
    separate "share replays of my runs to help improve the game" choice on our consent card, off by default, changeable in
    Settings.
  - Commentators are split on legitimate interest versus consent for session replay. France's CNIL calls consent "generally
    the most appropriate". A consent-gated feature avoids the argument.
  - Also needed: a privacy-policy entry, a retention period, and a way to delete one player's recordings on request (by
    player id).
  - Recording at scale may need a data protection impact assessment (DPIA).
- **Google Play:**
  - Declare it in the Data safety form ("App activity: in-app actions"; "diagnostics" if crash replays are kept).
  - Describe it in the privacy policy.
  - Show a prominent in-app disclosure before collecting data users wouldn't expect, with an affirmative accept that isn't a
    back tap. Real screen video (option 3) is the case most clearly needing it, and would also face the Android system dialog.
- **Children:** if the game were rated or marketed for kids, Google Play's Families policy and COPPA restrict this kind of
  collection much more.
- **US:** the session-replay wiretap lawsuits under California's CIPA target websites. A disclosed, consented gameplay replay
  is far from that, but the consent text should name it plainly.

## Recommendation
1. Option 1 (input replay with checksums), viewed in the Watch at any speed with taps drawn.
2. Option 4 to export an MP4 of a chosen run on the PC.
3. Option 2 only if determinism proves too costly to guarantee.
4. Consent-gated, opt-in, sampled, with deletion by player id.

Sources: Google Play prominent disclosure (support.google.com/googleplay/android-developer/answer/11150561), Android media
projection (developer.android.com/media/grow/media-projection), CNIL session replay consultation (cliffordchance.com, Mar
2026), session replay and GDPR overviews (complydog.com, flexyconsent.com), seed + input replay pattern (bugnet.io).
