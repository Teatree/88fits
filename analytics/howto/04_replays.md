# Watch a player's run again, like a video (replays)

**Question:** "Is there a way to save video, or something like a video from each Player's run? ... with the ability to
speed up ... a video with taps highlighted would be the best." and "make it so the Watch feature has both a slow down
functionality and a progress reel ... also tell me how to test it. If I play the game on mobile" and "the ability to
navigate the timeline of that play, so I can get to any point of the game as I wish and slow it down as well."

**Status:** works since v0.97 (pass 114). Every run records what the player did (not a video: the stick, every tap and
every choice, a few hundred KB). On the PC the real game plays the run again from that recording, with the real art, at
any speed, with the taps drawn as rings. Runs from older builds have no recording.

## Try it from your phone, step by step

1. **Play a run on the phone** with the build in Drive (0.97 or later). Play data must be on (the card at the first
   start, or Settings). Play as you like; end the run any way (die, extract, or quit from the pause screen).
2. **Double-click `tools
eplay.cmd`** on the PC. A small menu asks what to do:
   - **1) Download new runs from the phone, then list them** (fetches the replays from PostHog; wait a minute after
     the run, or open the game on the phone again for a few seconds if it does not show),
   - **2) List the runs on this PC** (newest first, numbered),
   - **3) Watch a run** (type its number, Enter = the newest): it opens on the build that recorded it. A window opens:
     the phone's screen on the left, the panel on the right, the reel at the bottom.
   - **4) Quit.**
   (`python tools/replay.py --latest | --list | <file>` and `python tools/posthog_runs.py` still work on their own.)

A run you play on the PC exe (88fits.exe) is recorded too (in `%APPDATA%\Godot\app_userdata\88fits\analytics\replays\`)
and `tools\replay.cmd` finds it without any download. A run from the editor binary goes to `analytics\runs\replays\`.

## What you see

- **The header** (top): whose run it is and when (`Replaying Lanky Tinker 24's run of 2026-10-29 14:02`), the hero, the
  stage, how it ended, and **which build plays it**: `Recorded on build 0.97 (2026-10-29 14:02 UTC, abc1234) · played on
  the same build ✓`. If that build is not on this PC the line is **red** and says the replay may go out of step.
- **The drift light** (top of the panel): **green** while the replay matches the recording (every 5 seconds of play the
  game checks the hero's place, HP, level, XP, kills, gold, the creatures' places and the dice; it shows how many checks
  were equal). **Red** from the second they part, with what differs (recorded / replay). The hero always walks
  exactly where the player walked (his place is recorded at every step), and every choice is made by name; after a red
  light the **safety net** also sets his HP to the recorded HP every half second (the light says so and how often), and
  a card the replay does not offer is swapped for the like one (the log says which, in amber). What you see then stays
  close to what the player did, but the creatures are no longer exactly his. `A` turns the safety net off and on.
- **The rings**: every finger touch shows as a yellow ring where it touched, fading over half a second. The stick shows
  as a ghost under the thumb (the base and the knob).
- **The screens** (cards, chests, the shop, the Stranger, totems, the portal, Down!) appear as they did, and the choice
  is made by name, never by screen position: the log on the right says what was picked (`2:41  Picked Mule Kick`).
- **The Upgrade board** (pass 115, under the numbers): the board the player had when the run began, every talent with a
  dot a rank (blue its first form, amber its second, hollow not bought) and the forms by name, its ranks of the board's
  most and the gold they cost. `B` (or a click on its title) folds it to one line. The header names the hero's look.
  Only a build from 0.98 on shows it in its window; for **any** recording, `python tools/replay.py` prints the board in
  the terminal before the window opens, and `python tools/replay.py --board <file>` (or `--board --latest`) prints only
  the board.
- **The chart**: the recorded HP (red) and level (gold) over the whole run, with a white line where the replay is.
- **The reel** (bottom): the whole run, left to right. Gold marks: level-ups and picks; red: bosses and big hits; white:
  going down; blue: revives, power-ups, the portal. Hover a mark to read it, **click anywhere to jump there**.

## The controls

| Key | Button | What it does |
|---|---|---|
| Space | Pause / Play | pause or go on |
| `.` | Step | one frame forward while paused |
| 1 2 3 4 5 6 7 | 0.1x ... 8x | 0.1x, 0.25x, 0.5x, 1x, 2x, 4x, 8x |
| + / - | | faster / slower |
| → / ← | | 5 seconds forward / back (Shift: 30 seconds) |
| Home | | back to the start |
| click the reel | | jump to that moment |
| A | | the safety net on / off |
| B | | the Upgrade board open / folded (pass 115) |
| M | | sound on / off (off at the start) |
| Esc | | close |

Slow motion shows every frame the phone drew, held longer (0.1x is a frame every few tenths of a second: it looks like a
slide show on purpose, nothing is invented between frames).

**Jumping:** forward, the game runs the frames without drawing them ("Jumping to 5:00 ... 63%"); back, it starts the run
again from the beginning and runs to the point. How long it takes depends on the PC and how busy the run is: see
*Numbers* below.

## Numbers (measured on this PC, pass 114)

- **Exact:** a 12-minute run replayed with every one of its 720 checks equal, in the replay window and in the PC exe;
  runs recorded at 30, 47 and 60 frames a second and at a PC's own uneven frame rate replay exactly too.
- **Jumping:** to 2:30 about 30 seconds, to 5:00 about 70 seconds, to 12:00 about 2 minutes 50 seconds (the game runs
  undrawn at 4 to 5 times its speed). Back = from the start again.
- **Size:** about 0.5 MB for a 15-minute run (sent in 5 pieces with the play data).
- **Builds:** about 220 MB each in `builds\`; the newest 6 plus every one a recording on this PC names stay.

## Where the builds live (and how to tidy them)

A recording plays exactly only on the build that recorded it, so every PC build `ship.sh` makes is kept in
`D:\_projects\88fits\builds\<build id>\` (the exe and its `build.json`; git ignores the folder). The build id is
`<version>-<date>-<time UTC>-<git>` (plus `-dirty` when the build had uncommitted changes), e.g.
`0.97-20261029-1402-abc1234`. `tools\replay.cmd` reads the recording's build id and starts that exe by itself.

- `python tools/builds.py list` — every kept build, its size, and how many recordings name it (and which recordings
  name a build that is gone).
- `python tools/builds.py prune` — removes old builds, **keeping every build a recording on this PC names** and the
  newest 6 (`--keep 10` for more, `--dry-run` to see first). `ship.sh` prunes the same way after each build.
- When the right build is gone, `replay.cmd` says so in plain words and offers the nearest build; the header then says
  in red that the builds differ.

## Good to know

- **What is recorded** (the rules: BALANCING.md 57.REPLAY; the file: analytics/SCHEMA.md *The replay file*): the run's
  seed, the build, the hero, look, stage and map, the save as the run began (the Upgrade board, what is owned and
  unlocked, quests), the settings, the stick a frame, every tap's place, every choice by name, the frame timing, and the
  checks. Nothing from outside the game; no screen pictures.
- **When it is sent:** at the run's end, with the run record, only when play data is on, never from the arena, a tool, a
  test, the sim or a replay. On the phone the newest 50 recordings stay in the game's folder too.
- **Phone runs on the PC:** the phone (ARM) and the PC (x86) can round some sums in the last digit differently, and a
  big crowd can grow that into a different run after a while. The light shows when it happens; the choices and the stick
  are still the player's to the end, and the safety net keeps the hero on the player's path.
- **Your own runs on the PC exe** replay exactly (tested: every check equal over long runs).
