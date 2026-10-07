"""Builds the 88fits boards in PostHog (pass 59, Garry: "how do I see all the charts that you described?").

    python tools/posthog_boards.py            # (re)build every board
    python tools/posthog_boards.py --check    # run every board's queries, build nothing

Seven dashboards, each one column of at most six tiles so they read on a phone: Pulse, Players, Level Editor versions,
Run curves, Deaths, Builds & items, Surveys. Re-running deletes the boards this script made before (their description
carries MARKER) with their insights, and builds them again, so the script is the source of truth: change a tile here,
not in PostHog. Every query is tried against the project first; a tile whose query fails is skipped and named.

The personal API key (phx_..., scopes dashboard/insight/cohort write and query read) lives in
tools/posthog_personal_key.txt, which git ignores. It is a secret: never commit it, never put it in the game (the game
carries only the write-only phc_ project key in game/config/analytics.json).
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


def arr(prop):
    """A run_summary per-minute array property as numbers."""
    return "JSONExtract(ifNull(properties.%s, '[]'), 'Array(Float64)')" % prop


def curve(cols):
    """The median of each per-minute array of run_summary, minute by minute (cols: [(column name, property)])."""
    zipped = ", ".join([arr(cols[0][1]).replace("JSONExtract", "arrayEnumerate(JSONExtract", 1) + ")"] + [arr(p) for _, p in cols])
    picks = ", ".join("round(median(z.%d), 1) AS %s" % (k + 2, name) for k, (name, _) in enumerate(cols))
    return ("SELECT z.1 AS minute, %s, count() AS runs FROM (SELECT arrayJoin(arrayZip(%s)) AS z FROM events "
            "WHERE event = 'run_summary' AND %s) GROUP BY minute ORDER BY minute") % (picks, zipped, RECENT)


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
    ("88fits · Run curves", "Your local dashboard's curves from every phone: the median of all runs, minute by minute of play.", [
        ("The crowd against the cap", line(curve([("alive", "m_alive"), ("cap", "m_cap")]), "minute", ["alive", "cap"])),
        ("Spawned and killed a minute", line(curve([("spawned", "m_spawned"), ("killed", "m_killed")]), "minute", ["spawned", "killed"])),
        ("Pressure against the build's power", line(curve([("pressure", "m_press"), ("build_dps", "m_est")]), "minute", ["pressure", "build_dps"])),
        ("Lowest health (share) and level", line(curve([("lowest_hp", "m_hp"), ("level", "m_level")]), "minute", ["lowest_hp", "level"])),
        ("HP lost a minute", line(curve([("hp_lost", "m_took")]), "minute", ["hp_lost"])),
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
        return "HTTP %d: %s" % (st, str(r)[:200])
    return ""


def old_boards():
    out, path = [], "/api/projects/@current/dashboards/?limit=200"
    while path:
        st, r = api(path)
        if st != 200:
            sys.exit("Could not list dashboards: %s %s" % (st, r))
        out += [d for d in r.get("results", []) if MARKER in str(d.get("description", "")) and not d.get("deleted")]
        nxt = r.get("next")
        path = nxt[len(HOST):] if nxt else None
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
    for d in old_boards():
        st, _ = api("/api/projects/@current/dashboards/%d/" % d["id"], {"deleted": True, "delete_insights": True}, "PATCH")
        print("removed the old %s (%s)" % (d["name"], st))
    bad = {(n, t) for n, t, _ in failed}
    for name, desc, tiles in BOARDS:
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


KEY = _key()

if __name__ == "__main__":
    main()
