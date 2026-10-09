# Choose when a survey appears, add a 5th-run survey, and test it on the phone

**Question:** "I'd like to have control over the count of runs at which the first Survey appears. And on top of that
I'd like a new survey that appears only on the 5th run." Also: "I'd like an option to reset the Survey. Basically some
way to test it for sure."

**Status:** works from v0.48 (pass 62). Before that, every survey followed one rule: the first run of a minute or more
on a new install, then every third such run until answered. Your phone did show the NPS survey on 2026-10-07 and
2026-10-08. You closed it both times with "Not now", so it waited three more counted runs, and most of your runs since
were shorter than a minute. A reinstall and a progress wipe both keep the survey record, which is why neither brought
it back.

## How the game decides (one table)

You set when a survey appears by putting a **tag in the survey's name** in PostHog. Players never see the name; the
card only says "A quick word". No new build is needed: the game reads the name each time the app starts.

| Name contains | When it is asked | Example name |
|---|---|---|
| `[after N]` | At the end of the N-th counted run. If it is not answered, again every 3 counted runs, until answered. | `Net promoter score [after 3]` |
| `[run N]` | At the end of the N-th counted run only. Never again, whether it was answered or not. | `Fifth run check-in [run 5]` |
| no tag | As before v0.48: at the end of the first counted run on a new install, then again once 3 counted runs have passed since the last survey (any survey), until answered. | `Net promoter score (NPS) (2026-10-07 23:26)` |

- A **counted run** is a run that lasted **60 seconds or more** (the time on the Results screen). The game keeps the
  count for life, and a progress wipe keeps it. Runs in the debug arena don't count. A run counts even when "Questions
  after a run" is off. An install from before v0.48 starts its count at the number of runs it had already finished,
  short ones included, because nothing older tells them apart. So a long-time player is not asked a "5th run" survey
  at his fiftieth run.
- **At most one survey after a run.** If a `[run N]` survey and another one are both due, the `[run N]` one goes first,
  and the other waits for a later run.
- **At most one survey per app session** (until the app is closed and opened again). `[run N]` surveys are the exception:
  their run comes only once, so they are never held back.
- **Answered = never again.** "Not now" puts it off: an `[after N]` survey comes back 3 counted runs later. "Don't ask
  me again" turns all questions off (Settings → "Questions after a run" turns them back on).
- The tag can go anywhere in the name, in any letter case: `[After 3]` and `[ run 5 ]` both work. N must be 1 or more.
  Anything else in brackets is not a tag, for example `[after three]` or `[runs 5]`.
- Nothing is asked until the player has said yes on the play-data card.

## Steps: set when the NPS survey first appears

1. Open **Surveys** in PostHog (https://eu.posthog.com/project/290195/surveys) and click
   **Net promoter score (NPS) (2026-10-07 23:26)**.
2. Click **Edit**.
3. Change the **name** at the top to set its first counted run, e.g. `Net promoter score [after 3]`. Leave everything
   else as it is (questions, presentation, display conditions).
4. Click **Save**. The survey stays launched. Its answers so far stay with it, since the game identifies a survey by its
   id, not its name.
5. The phones pick up the new name the next time the app starts. On your phone, use **Surveys · fetch now** in the
   developer menu instead (see "Test it on the phone" below).

To change the run later, edit the number in the name the same way.

## Steps: create the 5th-run survey

1. In **Surveys**, click **New survey**. Start from a blank survey, not a template.
2. **Name** it exactly `Fifth run check-in [run 5]`. The part before the tag is up to you.
3. **Presentation:** choose **API**. Popover also works; the game draws its own card either way. Don't choose Hosted
   (a link) or Feedback button: the game leaves those out.
4. **Questions.** The game can draw these four types:
   - **Rating** (number scale). The game shows buttons 1 to N (5 is best on a phone; 10 makes two rows). The low and high
     labels show under the buttons.
   - **Single choice select**
   - **Multiple choice select**
   - **Freeform text** (an open question; mark it **optional** so players can skip it)

   The game skips a **Link** question, an "Other: type your own" choice (it shows only as a plain choice) and question
   branching (it always asks the questions in order).

   Suggested questions for a 5th run:

   | # | Type | Question | Choices / labels |
   |---|---|---|---|
   | 1 | Rating, 5, numbers | How fun have your runs been so far? | low "Not fun", high "Loved it" |
   | 2 | Single choice | What usually ends a run for you? | A boss · The crowd got too thick · I ran out of time to play · I got bored · Something else |
   | 3 | Multiple choice | What would you like next? | More heroes · More weapons · A new map · Harder challenges · More upgrades between runs |
   | 4 | Freeform text, optional | Anything you'd change? | |

5. **Display conditions:** leave them at all users. The game decides when to ask, so PostHog's own conditions (pages,
   wait periods, percentages) do nothing here.
6. Click **Save**, then **Launch**. A survey that is not launched (a draft) or that you **Stop** is never asked; the
   phones drop it the next time they fetch.

## See the answers

- On the survey's own page in PostHog: its results, question by question.
- On the **88fits · Surveys** board: every answer next to the player's name, and how often each survey was shown,
  answered and dismissed.
- Every survey event also carries `counted_runs`: the player's counted run when the survey was shown, answered or
  dismissed. To filter one player, follow `01_one_players_data.md`.

## Test it on the phone

The developer menu has a **Surveys** block that works in the normal build. Open it with Settings → hold the version
line at the bottom for 2 seconds → scroll down past "Analytics · PostHog".

The **readout** at the top of the block lists:
- the surveys the phone has and each one's rule in words;
- your counted runs and the runs since the last survey;
- whether a survey was shown this session, and whether the next run is armed to ask;
- which surveys you answered or dismissed.

It also says why nothing would be asked (questions switched off, the play-data card not answered).

| Row | What it does |
|---|---|
| **Surveys · reset** | Asks first, then wipes the survey record: counted runs back to 0, nothing answered, dismissed or shown, and this session counts as fresh. Your play-data answer and the "Questions after a run" switch stay as they are; if the switch is off, the confirmation says so. |
| **Surveys · fetch now** | Asks PostHog for the running surveys straight away (after a rename, or a new survey). The readout shows the result. |
| **Surveys · show one now** | Opens a survey card over the menu, exactly as after a run. Each tap shows the next unanswered survey. Its answers go to PostHog like a real player's (tagged `dev: true` while your debug mode is on). Showing it here changes no timing. |
| **Surveys · next run asks** | ON: your next counted run ends with a survey: the one that is due, or else the first one you haven't answered. This ignores the run rules and the one-per-session rule. It switches itself off once used. |
| **Surveys · counted runs** | Each tap adds one counted run, so you don't have to play four runs to reach the 5th. |

To test the 5th-run survey for real:
1. **Fetch now**, and check the readout lists "Fifth run check-in [run 5]".
2. **Reset** (counted runs: 0).
3. Tap **counted runs** four times (it shows 4; the readout says the 5th-run survey comes "after counted run 5 (the next
   run)").
4. Play one run of at least a minute. The 5th-run survey appears on the Results screen.

To test the NPS after a rename: **Fetch now**, **Reset**, tap **counted runs** twice, then play one run of a minute or
more. It appears after counted run 3.

## Good to know

- The game names a survey in PostHog's events by its full name, tag included. Renaming a survey therefore splits the
  "by name" counts on the Surveys board at the rename. The survey's own page counts by id and is unaffected.
- A player who is offline at the end of a run still gets the survey from the copy the phone keeps from the last fetch.
  The answers wait in the queue and go out later.
- Players from before v0.48 start their counted runs at their finished-runs total, so `[run N]` surveys with small N
  are effectively for new players. To ask everyone something once, use `[after N]` with a small N.
