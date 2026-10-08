"""Builds the 88fits boards in PostHog (pass 59, Garry: "how do I see all the charts that you described?").

    python tools/posthog_boards.py            # (re)build every board
    python tools/posthog_boards.py --check    # run every board's queries, build nothing

Eight dashboards, each one column so they read on a phone: Pulse, Players, Level Editor versions, Run curves, Run health
& weapons (pass 60: the rest of analytics/dashboard.html's charts), Deaths, Builds & items, Surveys. Re-running keeps
the boards this script made before (their description carries MARKER, their ids and links stay) and replaces their tiles, so
the script is the source of truth: change a tile here, not in PostHog. Every query is tried against the project first; a tile
whose query fails is skipped and named.

The personal API key (phx_..., scopes dashboard/insight/cohort write and query read) lives in
tools/posthog_personal_key.txt, which git ignores. It is a secret: never commit it, never put it in the game (the game
carries only the write-only phc_ project key in game/config/analytics.json).

The curves read run_summary's per-minute arrays (RunAnalytics.summary). fit_summary folds a long run into two- or
four-minute buckets, so a bucket lands on its END minute (index x bucket_s / 60) and per-bucket sums are scaled to a
per-minute rate by the bucket's own seconds (m_secs); buckets under 20 s (the short last one) are left out. Runs from
before pass 60 lack the new arrays and are skipped by the tiles that need them (`need`).
"""
import json
import os
import sys
import urllib.error
import urllib.request

HOST = "https://eu.posthog.com"
KEY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "posthog_personal_key.txt")
MARKER = "[made by tools/posthog_boards.py]"
DAYS = 30

# the player's name (pass 59: the person property player_name), or the start of the install id before a v0.45 launch
PLAYER = "coalesce(person.properties.player_name, concat('id ', left(distinct_id, 8)))"
RECENT = "timestamp > now() - INTERVAL %d DAY" % DAYS
SUMMARIES = "event = 'run_summary' AND " + RECENT + " AND isNotNull(properties.m_secs)"


def arr(prop):
    """A run_summary per-minute array property as numbers."""
    return "JSONExtract(ifNull(properties.%s, '[]'), 'Array(Float64)')" % prop


def zipped(props, need=None):
    """The inner SELECT: one row per (run, bucket) with z = (index, seconds in the bucket, props...) and b = bucket_s."""
    cols = ", ".join(["arrayEnumerate(%s)" % arr("m_secs"), arr("m_secs")] + [arr(p) for p in props])
    where = SUMMARIES + ((" AND isNotNull(properties.%s)" % need) if need else "")
    return ("(SELECT arrayJoin(arrayZip(%s)) AS z, coalesce(toFloat(properties.bucket_s), 60.0) AS b FROM events WHERE %s)"
            % (cols, where))


def curve_sql(props, picks, need=None):
    """Minute by minute (the bucket's end minute) the given aggregate expressions over z (z.1 index, z.2 seconds,
    z.3.. = props in order), with the number of runs in each minute."""
    return ("SELECT toInt(round(z.1 * b / 60)) AS minute, %s, count() AS runs FROM %s WHERE z.2 >= 20 GROUP BY minute "
            "ORDER BY minute") % (", ".join(picks), zipped(props, need))


def curve(cols, rates=(), need=None, step=1):
    """The median of each per-minute array, minute by minute. cols: [(column name, property)]; names in `rates` are
    per-bucket sums turned into a per-minute rate."""
    picks = []
    for k, (name, _) in enumerate(cols):
        expr = "z.%d" % (k + 3)
        if name in rates:
            expr = "%s * 60 / z.2" % expr
        picks.append("round(median(%s), %d) AS %s" % (expr, step, name))
    return curve_sql([p for _, p in cols], picks, need)


def totals(prop, value_name, kind="Float64"):
    """One row per key of a run_summary {id: amount} map, summed over the runs: (id, value_name)."""
    return ("SELECT kv.1 AS id, sum(kv.2) AS %s FROM (SELECT arrayJoin(JSONExtractKeysAndValues(ifNull(properties.%s, '{}'), '%s')) AS kv "
            "FROM events WHERE %s) GROUP BY id") % (value_name, prop, kind, SUMMARIES)


# ---------------------------------------------------------------- tiles

def trend(event, display, math="total", breakdown=None, date_from="-30d", interval="day", props=None, breakdown_type="event"):
    src = {"kind": "TrendsQuery", "series": [{"kind": "EventsNode", "event": event, "name": event, "math": math}],
           "interval": interval, "dateRange": {"date_from": date_from}, "trendsFilter": {"display": display}}
    if breakdown:
        src["breakdownFilter"] = {"breakdown": breakdown, "breakdown_type": breakdown_type}
    if props:
        src["properties"] = props
    return {"kind": "InsightVizNode", "source": src}


def table(sql):
    return {"kind": "DataTableNode", "source": {"kind": "HogQLQuery", "query": sql}}


def line(sql, x, ys, display="ActionsLineGraph"):
    return {"kind": "DataVisualizationNode", "source": {"kind": "HogQLQuery", "query": sql}, "display": display,
            "chartSettings": {"xAxis": {"column": x}, "yAxis": [{"column": y} for y in ys]}}


def curve_tile(title, cols, rates=(), need=None, step=1):
    return (title, line(curve(cols, rates, need, step), "minute", [name for name, _ in cols]))


BOARDS = [
    ("88fits · Pulse", "Right now, on one phone screen: runs and players, how runs end, where heroes fall, survey answers.", [
        ("Runs today", trend("run_end", "BoldNumber", date_from="dStart")),
        ("Players this week", trend("app_open", "BoldNumber", math="dau", date_from="-7d")),
        ("Extract rate, last 7 days", table(
            "SELECT count() AS runs, round(100 * countIf(properties.result = 'extract') / count(), 1) AS extract_pct, "
            "round(100 * countIf(properties.result = 'death') / count(), 1) AS death_pct, round(avg(properties.t) / 60, 1) AS avg_minutes "
            "FROM events WHERE event = 'run_end' AND timestamp > now() - INTERVAL 7 DAY")),
        ("Runs a day, by how they ended", trend("run_end", "ActionsBar", breakdown="result")),
        ("Where heroes fall (stage)", trend("player_died", "ActionsBarValue", breakdown="stage")),
        ("Survey answers this week", trend("survey sent", "BoldNumber", date_from="-7d")),
    ]),
    ("88fits · Players", "Each player by the name the game gave them (Settings shows it by the version). Filter any board by a cohort of your friends.", [
        ("Players", table(
            "SELECT " + PLAYER + " AS player, countIf(event = 'run_end') AS runs, "
            "countIf(event = 'run_end' AND properties.result = 'extract') AS extracts, countIf(event = 'player_died') AS deaths, "
            "round(maxIf(properties.t, event = 'run_end') / 60, 1) AS longest_min, countIf(event = 'app_open') AS opens, "
            "countIf(event = 'survey sent') AS surveys, max(timestamp) AS last_seen FROM events WHERE " + RECENT +
            " GROUP BY player ORDER BY last_seen DESC")),
        ("Recent runs", table(
            "SELECT timestamp, " + PLAYER + " AS player, properties.hero AS hero, properties.result AS result, "
            "round(properties.t / 60, 1) AS minutes, properties.stage AS stage, properties.level AS level, properties.kills AS kills "
            "FROM events WHERE event = 'run_end' AND " + RECENT + " ORDER BY timestamp DESC LIMIT 50")),
        ("Opens a day, by player", trend("app_open", "ActionsBar", breakdown="player_name", breakdown_type="person")),
        ("Phones: frame rate", table(
            "SELECT properties.device AS device, properties.os AS os, count() AS runs, round(median(properties.fps_avg), 1) AS fps, "
            "round(median(properties.fps_low), 1) AS fps_1pct_low FROM events WHERE event = 'run_summary' AND " + RECENT +
            " GROUP BY device, os ORDER BY runs DESC")),
    ]),
    ("88fits · Level Editor versions", "Results split by map_rev: a short fingerprint of the map's timeline as the game loaded it, so every Level Editor save shows as its own row.", [
        ("By map version", table(
            "SELECT properties.map_rev AS map_rev, min(timestamp) AS first_seen, count() AS runs, "
            "round(100 * countIf(properties.result = 'extract') / count(), 1) AS extract_pct, "
            "round(100 * countIf(properties.result = 'death') / count(), 1) AS death_pct, round(avg(properties.t) / 60, 1) AS avg_min, "
            "round(avg(properties.level), 1) AS avg_level, round(avg(properties.kills)) AS avg_kills, "
            "countIf(properties.stage = 1) AS ended_stage1, countIf(properties.stage = 2) AS ended_stage2, countIf(properties.stage >= 3) AS ended_stage3 "
            "FROM events WHERE event = 'run_end' AND " + RECENT + " GROUP BY map_rev ORDER BY first_seen DESC")),
        ("Runs a day, by map version", trend("run_end", "ActionsBar", breakdown="map_rev")),
        ("Deaths by stage, by map version", table(
            "SELECT properties.map_rev AS map_rev, properties.stage AS stage, count() AS deaths, round(avg(properties.t) / 60, 1) AS avg_minute "
            "FROM events WHERE event = 'player_died' AND " + RECENT + " GROUP BY map_rev, stage ORDER BY map_rev, stage")),
    ]),
    ("88fits · Run curves", "The local dashboard's curves from every phone: the median of all runs, minute by minute of play (the crowd, the pressure, the build's power, progression).", [
        curve_tile("The crowd against the cap", [("alive", "m_alive"), ("cap", "m_cap"), ("load", "m_load"), ("hard_cap", "m_hard_cap")], need="m_load"),
        curve_tile("Spawned and killed a minute", [("spawned", "m_spawned"), ("killed", "m_killed")], rates=("spawned", "killed")),
        curve_tile("Crowd pressure (sum of max HP x damage)", [("pressure", "m_press")]),
        curve_tile("The crowd's HP and bite (sums over the living)", [("crowd_hp", "m_press_hp"), ("crowd_damage", "m_press_dmg")]),
        ("The build's power: estimated against real DPS", line(curve_sql(
            ["m_est", "m_dmg"], ["round(median(z.3), 1) AS build_dps", "round(median(z.4 / z.2), 1) AS real_dps"]),
            "minute", ["build_dps", "real_dps"])),
        ("Power against pressure", line(curve_sql(
            ["m_est", "m_dmg", "m_press_dmg", "m_press_hp"],
            ["round(median(z.3 / greatest(z.5, 1)), 2) AS build_dps_per_crowd_damage",
             "round(100 * median((z.4 / z.2) / greatest(z.6, 1)), 2) AS real_dps_pct_of_crowd_hp"]),
            "minute", ["build_dps_per_crowd_damage", "real_dps_pct_of_crowd_hp"])),
        curve_tile("Level and XP into the level", [("level", "m_level"), ("xp_into_level", "m_xp")], need="m_xp", step=2),
        curve_tile("Gold, Strongbox and kills", [("gold", "m_gold"), ("banked", "m_banked"), ("kills", "m_kills")], need="m_kills"),
    ]),
    ("88fits · Run health & weapons", "The hero's health minute by minute, what hit him, which weapon carried, the estimate against the damage that landed, the creatures (pass 60).", [
        ("Latest builds", table(
            "SELECT timestamp, " + PLAYER + " AS player, properties.build_text AS build, round(toFloat(properties.est_end)) AS build_dps, "
            "properties.minutes AS minutes FROM events WHERE event = 'run_summary' AND isNotNull(properties.build_text) AND " + RECENT +
            " ORDER BY timestamp DESC LIMIT 30")),
        ("Lowest health and shield (shares of max HP)", line(curve_sql(
            ["m_hp", "m_shield", "m_hp_max"],
            ["round(median(z.3), 2) AS lowest_hp", "round(median(z.4 / greatest(z.5, 1)), 2) AS shield"], need="m_shield"),
            "minute", ["lowest_hp", "shield"])),
        curve_tile("HP lost, thrown at him and healed a minute", [("hp_lost", "m_took"), ("thrown", "m_took_raw"), ("healed", "m_healed")],
                   rates=("hp_lost", "thrown", "healed"), need="m_took_raw"),
        curve_tile("Hits, evaded and shield spent a minute", [("hits", "m_hits"), ("evaded", "m_evaded"), ("shield_spent", "m_shielded")],
                   rates=("hits", "evaded", "shield_spent"), need="m_evaded"),
        curve_tile("Seconds a minute under 30%, shielded, invulnerable", [("under_30pct_s", "m_low_s"), ("shielded_s", "m_shield_s"), ("invulnerable_s", "m_invuln_s")],
                   rates=("under_30pct_s", "shielded_s", "invulnerable_s"), need="m_shield_s"),
        ("Who carries each minute (the weapon with the most damage)", table(
            "SELECT minute, argMax(weapon, dmg) AS top_weapon, round(100 * max(dmg) / greatest(sum(dmg), 1)) AS share_pct, "
            "round(sum(dmg)) AS damage FROM (SELECT toInt(round(z.1 * b / 60)) AS minute, weapon, sum(z.2) AS dmg FROM ("
            "SELECT arrayJoin(arrayZip(arrayEnumerate(kv.2), kv.2)) AS z, kv.1 AS weapon, b FROM ("
            "SELECT arrayJoin(JSONExtractKeysAndValues(ifNull(properties.dmg_by_minute, '{}'), 'Array(Float64)')) AS kv, "
            "coalesce(toFloat(properties.bucket_s), 60.0) AS b FROM events WHERE " + SUMMARIES + " AND isNotNull(properties.dmg_by_minute))) "
            "GROUP BY minute, weapon) GROUP BY minute ORDER BY minute")),
        ("Estimate against real, by weapon (all runs)", table(
            "SELECT id AS weapon, round(sum(estimated)) AS estimated, round(sum(real)) AS real, round(sum(kills)) AS kills FROM ("
            "SELECT id, estimated, 0 AS real, 0 AS kills FROM (" + totals("est_by_weapon", "estimated") + ") UNION ALL "
            "SELECT id, 0 AS estimated, real, 0 AS kills FROM (" + totals("dmg_by_weapon", "real") + ") UNION ALL "
            "SELECT id, 0 AS estimated, 0 AS real, kills FROM (" + totals("kills_by_weapon", "kills") + ")) "
            "GROUP BY weapon ORDER BY real DESC LIMIT 25")),
        ("The creatures (all runs)", table(
            "SELECT id AS creature, round(sum(spawned)) AS spawned, round(sum(killed)) AS killed, round(sum(hp_lost)) AS hp_lost_to_it FROM ("
            "SELECT id, spawned, 0 AS killed, 0 AS hp_lost FROM (" + totals("spawned_by_creature", "spawned") + ") UNION ALL "
            "SELECT id, 0 AS spawned, killed, 0 AS hp_lost FROM (" + totals("killed_by_creature", "killed") + ") UNION ALL "
            "SELECT id, 0 AS spawned, 0 AS killed, hp_lost FROM (" + totals("took_by_creature", "hp_lost") + ")) "
            "GROUP BY creature ORDER BY hp_lost_to_it DESC LIMIT 30")),
        ("HP lost by kind of hit", table(
            "SELECT id AS kind, round(hp_lost) AS hp_lost FROM (" + totals("took_kind", "hp_lost") + ") ORDER BY hp_lost DESC")),
    ]),
    ("88fits · Deaths", "Where, when and to what the heroes fall.", [
        ("Top killers", table(
            "SELECT properties.killer AS killer, properties.killer_kind AS kind, count() AS deaths, round(avg(properties.t) / 60, 1) AS avg_minute, "
            "round(avg(properties.level), 1) AS avg_level FROM events WHERE event = 'player_died' AND " + RECENT +
            " GROUP BY killer, kind ORDER BY deaths DESC LIMIT 20")),
        ("Deaths by minute of the run", line(
            "SELECT toInt(floor(properties.t / 60)) AS minute, count() AS deaths FROM events WHERE event = 'player_died' AND " + RECENT +
            " GROUP BY minute ORDER BY minute", "minute", ["deaths"], display="ActionsBar")),
        ("Deaths by stage", trend("player_died", "ActionsBarValue", breakdown="stage")),
        ("Last deaths", table(
            "SELECT timestamp, " + PLAYER + " AS player, properties.hero AS hero, properties.stage AS stage, round(properties.t / 60, 1) AS minute, "
            "properties.level AS level, properties.killer AS killer, properties.kills AS kills FROM events WHERE event = 'player_died' AND " + RECENT +
            " ORDER BY timestamp DESC LIMIT 30")),
        ("Down! answers", trend("revive_chosen", "ActionsBarValue", breakdown="choice")),
    ]),
    ("88fits · Builds & items", "What gets offered, picked, banished and what does the damage.", [
        ("Picked against offered (level-ups)", table(
            "SELECT item, offered, picked, round(100 * picked / offered, 1) AS pick_pct FROM ("
            "SELECT c AS item, count() AS offered, countIf(c = pk) AS picked FROM (SELECT JSONExtract(ifNull(properties.cards, '[]'), 'Array(String)') AS cs, "
            "properties.picked AS pk FROM events WHERE event = 'level_up' AND " + RECENT + ") ARRAY JOIN cs AS c GROUP BY item) "
            "ORDER BY offered DESC LIMIT 40")),
        ("Damage by weapon (all runs)", table(
            "SELECT w AS source, round(sum(v)) AS damage FROM (SELECT JSONExtractKeysAndValues(ifNull(properties.dmg_by_weapon, '{}'), 'Float64') AS kv "
            "FROM events WHERE event = 'run_summary' AND " + RECENT + ") ARRAY JOIN kv.1 AS w, kv.2 AS v GROUP BY source ORDER BY damage DESC LIMIT 25")),
        ("Heroes", table(
            "SELECT properties.hero AS hero, properties.hero_look AS look, count() AS runs, round(100 * countIf(properties.result = 'extract') / count(), 1) AS extract_pct, "
            "round(avg(properties.t) / 60, 1) AS avg_min, round(avg(properties.level), 1) AS avg_level FROM events WHERE event = 'run_end' AND " + RECENT +
            " GROUP BY hero, look ORDER BY runs DESC")),
        ("Banished", trend("card_banished", "ActionsBarValue", breakdown="id")),
        ("Chests: taken or let go", trend("chest_opened", "ActionsBarValue", breakdown="taken")),
    ]),
    ("88fits · Surveys", "The end-of-run questions (written in PostHog Surveys). The Surveys page has the full results; these tiles put them beside the players.", [
        ("Answers", table(
            "SELECT timestamp, " + PLAYER + " AS player, properties.$survey_name AS survey, JSONExtractString(q, 'question') AS question, "
            "JSONExtractRaw(q, 'response') AS answer FROM events ARRAY JOIN JSONExtractArrayRaw(ifNull(properties.$survey_questions, '[]')) AS q "
            "WHERE event = 'survey sent' AND " + RECENT + " ORDER BY timestamp DESC LIMIT 100")),
        ("Shown, answered, dismissed", table(
            "SELECT properties.$survey_name AS survey, countIf(event = 'survey shown') AS shown, countIf(event = 'survey sent') AS answered, "
            "countIf(event = 'survey dismissed') AS dismissed FROM events WHERE event IN ('survey shown', 'survey sent', 'survey dismissed') AND " + RECENT +
            " GROUP BY survey")),
        ("Who stopped the questions", table(
            "SELECT timestamp, " + PLAYER + " AS player, event, properties.where AS where FROM events "
            "WHERE event IN ('survey_opt_out', 'survey_opt_in') ORDER BY timestamp DESC LIMIT 50")),
    ]),
]


# ---------------------------------------------------------------- the API

def _key():
    if not os.path.exists(KEY_FILE):
        sys.exit("No key: put the phx_ personal API key in %s (git ignores it)." % KEY_FILE)
    k = open(KEY_FILE, encoding="utf-8").read().strip()
    if not k.startswith("phx_"):
        sys.exit("%s does not hold a phx_ personal API key." % KEY_FILE)
    return k


def api(path, body=None, method=None):
    req = urllib.request.Request(HOST + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method or ("POST" if body is not None else "GET"),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:500]


def query_ok(q):
    """Runs a tile's query once; returns "" or why it failed."""
    st, r = api("/api/projects/@current/query/", {"query": q.get("source", {})})
    if st != 200:
        return "HTTP %d: %s" % (st, str(r)[:300])
    return ""


def old_boards():
    """The boards this script made before, by name (their description carries MARKER)."""
    out, path = {}, "/api/projects/@current/dashboards/?limit=200"
    while path:
        st, r = api(path)
        if st != 200:
            sys.exit("Could not list dashboards: %s %s" % (st, r))
        for d in r.get("results", []):
            if MARKER in str(d.get("description", "")) and not d.get("deleted"):
                out[d["name"]] = d
        nxt = r.get("next")
        path = nxt[len(HOST):] if nxt else None
    return out


def board_insights(dashboard_id):
    """The insights on a dashboard, read from the dashboard itself (its `tiles`); the insights list's `dashboards`
    filter answered 500 for most boards."""
    st, r = api("/api/projects/@current/dashboards/%d/" % dashboard_id)
    if st != 200:
        print("could not read the tiles of %d: %s %s" % (dashboard_id, st, r))
        return []
    out = []
    for t in r.get("tiles", []) or []:
        ins = t.get("insight")
        if isinstance(ins, dict) and ins.get("id"):
            out.append(ins)
    return out


def main():
    check_only = "--check" in sys.argv
    failed = []
    for name, _, tiles in BOARDS:
        for title, q in tiles:
            why = query_ok(q)
            if why:
                failed.append((name, title, why))
    for f in failed:
        print("query fails: %s / %s: %s" % f)
    if check_only:
        print("checked %d tiles, %d fail" % (sum(len(t) for _, _, t in BOARDS), len(failed)))
        return
    # a board that exists keeps its id (and Garry's links): its tiles are replaced; a new name is created
    old = old_boards()
    bad = {(n, t) for n, t, _ in failed}
    for name, desc, tiles in BOARDS:
        d = old.get(name)
        if d:
            for ins in board_insights(d["id"]):
                if MARKER in str(ins.get("description", "")):
                    api("/api/projects/@current/insights/%d/" % ins["id"], {"deleted": True}, "PATCH")
            st, d2 = api("/api/projects/@current/dashboards/%d/" % d["id"], {"description": desc + " " + MARKER}, "PATCH")
            if st == 200:
                d = d2
        else:
            st, d = api("/api/projects/@current/dashboards/", {"name": name, "description": desc + " " + MARKER})
            if st not in (200, 201):
                print("could not make %s: %s %s" % (name, st, d))
                continue
        made = 0
        for title, q in tiles:
            if (name, title) in bad:
                continue
            st, ins = api("/api/projects/@current/insights/", {"name": title, "query": q, "dashboards": [d["id"]], "description": MARKER})
            if st in (200, 201):
                made += 1
            else:
                print("  could not add %s: %s %s" % (title, st, ins))
        print("%s: %d tiles · %s/project/%s/dashboard/%d" % (name, made, HOST, d.get("team_id", "@current"), d["id"]))
    for name, d in old.items():
        if name not in [n for n, _, _ in BOARDS]:
            print("not in the script any more (left alone): %s (%d)" % (name, d["id"]))


KEY = _key()

if __name__ == "__main__":
    main()
