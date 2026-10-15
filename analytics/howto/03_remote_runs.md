# See any player's runs second by second, one by one or averaged

**Question:** "I want to see the equivalent of this local dashboard ... for one player in particular or as an average
for several players ... save raw data in some kind of JSON ... make it so that I'm able to download it."

**Status:** works since v0.64 (pass 78). Every run played on v0.64 or later, by anyone who said yes on the play-data
card, sends its whole run file to PostHog when it ends (the event `run_record`). Runs from older builds sent only the
per-minute summary, so they cannot be downloaded this way.

## Steps

1. **Download the runs.** Open a terminal in the repo folder (`D:\_projects\88fits`) and run:

       python tools/posthog_runs.py

   It fetches every run of the last 30 days that is not on your PC yet and says what it wrote, one line a run:
   `Lanky_Tinker_24/2026-10-15T03-08-00_01a13ce3.json  2026-10-15 00:10  Astro quit, 0:31, dev`.
   It uses your personal key in `tools/posthog_personal_key.txt` (the same one the boards script uses).
2. **Open the dashboard:** double-click `analytics/dashboard.html`, then press **Remote runs** at the top.
3. **Pick the players.** Every player is a chip with their name, how many runs they sent and when they last played. Tick
   one or several. (Your own label from PostHog shows beside the name when you gave them one.)
4. **One run:** press **Open** on its row. You get the whole dashboard for that run, every card, exactly as if you had
   played it here, plus the Sim's charts for it.
5. **One player's average:** tick only that player, then press **Average every run of the ticked player**. You get the
   Sim tab's charts (DPS, HP, deaths, danger, keeping up, the crowd, coins, damage, kills, level, XP, the build), each
   second averaged over that player's runs. Under each chart the readout says how many runs are still playing at that
   second.
6. **Several players' average:** tick those players, then press **Average every run of the ticked players**.
7. **Hand-picked runs:** tick runs in the list, then press **Average the ticked runs**.
8. **Back to one run:** press **Open** in the list of runs under the average, or **One run** at the top.

## Good to know

- **Only new runs are fetched.** Run the command again whenever you like; it skips what is already on your PC.
  `--force` fetches everything again.
- **Choose what to fetch:**
  - one player: `python tools/posthog_runs.py --player "Hungry Outlaw 94"` (repeat `--player` for several; your label
    or the install id work too),
  - from a day on: `--since 2026-10-01`, or everything ever sent: `--all`,
  - just look first: `--list` shows each player's runs in PostHog without downloading anything.
- **Developer runs** (yours from the editor binary, debug builds, or a phone with debug mode on) are marked **dev** in
  the list. Tick **leave out developer runs** to average real players only.
- **"A part is missing"**: a long run comes in a few pieces; PostHog sometimes shows the last one a minute later. The
  command says so and fetches it next time.
- **"Killed" runs**: when a phone closes the game in the background mid-run, the run is sent at the next launch, as far
  as it got (its result says *Killed*).
- **Where the files are:** `analytics/remote/<player>/`, one `.json` per run (the same file the game writes on the PC,
  plus who sent it). Git ignores the folder. You can open any of them with **Open run files** too, or a whole player's
  folder with **Open a folder**.
- **Your own report:** the `.json` files are plain data: every second of every run (`samples`), every event, the build,
  the gold. Any tool (Excel through the dashboard's CSV buttons, Python, another HTML page) can read them.
- **Compare with a sim:** press **Compare with a sim** and pick a sim's `result.json` (in
  `tools/dl/sim/runs/<sim>/`): its lines go dashed grey on the same charts, real players against the bot.
- **PostHog's limit:** a personal key may read only so much an hour. If the command says the budget is used up, it keeps
  what it fetched; run it again later.
