# See one player's data on any dashboard

**Question:** "I want to open a dashboard and see one player's progress and data in every chart."

**Status:** works since 2026-10-09 (pass 62). Before that, filtering a board by `player_name` changed nothing in most
charts. Those charts are SQL tiles, and PostHog only applies a dashboard filter to a SQL tile whose query contains a
`{filters}` placeholder. `tools/posthog_boards.py` now adds that placeholder to every SQL tile. The other charts (the
Trends tiles, such as "Runs a day") always followed the filter.

## Steps

1. **Find the player's name.** Open the **88fits · Players** board
   (https://eu.posthog.com/project/290195/dashboard/1005833). Every install has a name like *Hungry Outlaw 94*. Your
   own name is at the bottom of the game's Settings screen, after the version ("88fits v0.47 · Hungry Outlaw 94").
2. **Open the board you want**, for example **88fits · Builds & items**
   (https://eu.posthog.com/project/290195/dashboard/1005837).
3. At the top of the board, next to the date range, click **Add filter** (the funnel icon).
4. In the list that opens, choose the **Person properties** group (not Event properties), then **player_name**.
5. Leave the operator on **= equals** and pick or type the name, e.g. `Hungry Outlaw 94`. Close the pop-up.
6. Every chart on the board reloads with only that player's events: their runs, their picks, their deaths, their gold.
   Check that it worked by looking at a count you know. For example, **Heroes** on Builds & items should show only the
   runs that player played.
7. **To keep the filter**, click **Save** on the board. Note that this changes the board for everyone who opens it.
   **To look without changing the board**, don't save. Leaving the page drops the filter, and **Discard** puts it back
   as it was.
8. **To look at another player**, click the filter chip and change the name. **To see everyone again**, remove the
   chip with its ×.

## Good to know

- **The date range at the top also applies to every chart now**, the SQL ones included. Some charts also have their own
  window built in (most look at the last 30 days); the narrower of the two wins.
- **Several players at once:** add more names in step 5 (equals with several values means "any of these"). Or make a
  cohort under **People → Cohorts** (e.g. "Friends": player_name is any of …) and filter by **Cohort** instead of
  player_name.
- **Runs from before v0.45** (2026-10-07) were sent before players had names. They have no player_name, so they never
  match a name filter. Today that is 2 run_end events, shown as an empty name.
- **The same works on all nine boards** (Pulse, Players, Level Editor versions, Run curves, Run health & weapons,
  Deaths, Builds & items, Surveys, Coins).
- **One player's whole history**, event by event: **People** → search the name → open the person → **Events** tab.
- **If a board ever stops following the filter again** (for example after someone adds a SQL tile by hand in
  PostHog): tiles added to `tools/posthog_boards.py` get the placeholder automatically, so rebuild the boards with
  `python tools/posthog_boards.py`. A tile written by hand in PostHog needs `{filters}` in its `WHERE` clause, e.g.
  `... FROM events WHERE {filters} AND event = 'run_end'`.
