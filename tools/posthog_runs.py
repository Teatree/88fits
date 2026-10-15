"""Downloads the runs the game sent to PostHog (pass 78, lane DASH; Garry: "save raw data in some kind of JSON or
something like that and make it so that I'm able to download it. Then take that data and basically dress it up into one
of my HTML reports").

    python tools/posthog_runs.py                                  # the last 30 days, the runs not downloaded yet
    python tools/posthog_runs.py --player "Hungry Outlaw 94"      # one player (repeat --player for several)
    python tools/posthog_runs.py --since 2026-10-01               # from a day on;  --all: everything ever sent
    python tools/posthog_runs.py --list                           # what is there, by player, without downloading
    python tools/posthog_runs.py --force                          # download again what is already on disk
    python tools/posthog_runs.py --out analytics/remote           # where they go (the default)

At the end of every run the game (core/autoload/Analytics.gd run_record, with the player's consent, never from a tool)
sends the run's whole record (the file analytics/dashboard.html reads: header, a row a second, events) as run_record
events: gzip + base64, cut into parts. This finds them with PostHog's query API (HogQL, keyset pages on the timestamp;
first a cheap list without the payloads, then the payloads of the runs not on disk), joins each run's parts, unzips and
checks them (the parts all there, the sizes, the md5 of the record), and writes:

    analytics/remote/<player>/<stamp>_<run id>.json   the record exactly as the game wrote it, plus a `remote` block
                                                      (player, label, install, received, parts, dev, recovered)
    analytics/remote/<player>/<stamp>_<run id>.js     the same for the dashboard (a file:// page reads scripts only)
    analytics/remote/index.json, index.js             every player and run (window.REMOTE): the dashboard's
                                                      "Remote runs" switch lists them

The player is the person's player_name in PostHog (Garry's own `label` shown beside it); an install without a name is
"id <first 8 of its install id>". analytics/remote/ is git-ignored. The personal API key (phx_..., query read) comes
from tools/posthog_personal_key.txt, which git ignores: it is never printed and never written anywhere. PostHog limits
what a personal key may read an hour; past it the download stops with what it has (run it again later).
How-to: analytics/howto/03_remote_runs.md.
"""
import argparse
import base64
import datetime
import gzip
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import analytics_csv  # noqa: E402  (the index row the game writes, made from a run file)

HOST = "https://eu.posthog.com"
KEY_FILE = os.path.join(HERE, "posthog_personal_key.txt")
OUT_DEFAULT = os.path.join(ROOT, "analytics", "remote")
DAYS_DEFAULT = 30
LIST_PAGE = 10000        # rows a list query asks for (PostHog returns up to 50k with a LIMIT)
FETCH_BATCH = 12         # run_record parts a payload query asks for (~0.1 MB each)
EVENT = "run_record"

# what the queries cost, from PostHog's response headers (a personal key reads from an hourly budget)
STATS = {"queries": 0, "bytes_read": 0, "budget_left": None}


class BudgetSpent(Exception):
    """PostHog answered 429: the personal key's hourly read budget is spent (or too many queries)."""


# ---------------------------------------------------------------- the API

def _key():
    if not os.path.exists(KEY_FILE):
        sys.exit("No key: put the phx_ personal API key in %s (git ignores it)." % KEY_FILE)
    k = open(KEY_FILE, encoding="utf-8").read().strip()
    if not k.startswith("phx_"):
        sys.exit("%s does not hold a phx_ personal API key." % KEY_FILE)
    return k


def hogql(query):
    """One HogQL query: (columns, rows). A test replaces this function with recorded answers (no network)."""
    body = json.dumps({"query": {"kind": "HogQLQuery", "query": query}, "name": "posthog_runs.py"}).encode()
    req = urllib.request.Request(HOST + "/api/projects/@current/query/", data=body, method="POST",
                                 headers={"Authorization": "Bearer " + _key(), "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                STATS["queries"] += 1
                try:
                    STATS["bytes_read"] += int(r.headers.get("X-PostHog-Query-Bytes-Read") or 0)
                    left = r.headers.get("X-PostHog-Query-Budget-Remaining-Bytes")
                    if left is not None:
                        STATS["budget_left"] = int(left)
                except ValueError:
                    pass
                d = json.loads(r.read().decode("utf-8"))
                return d.get("columns") or [], d.get("results") or []
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", "replace")[:300]
            if e.code == 429:
                wait = e.headers.get("Retry-After") if e.headers else None
                raise BudgetSpent("PostHog says wait %s s (%s)" % (wait or "?", msg))
            if e.code >= 500 and attempt < 2:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit("PostHog answered HTTP %d: %s" % (e.code, msg))
        except urllib.error.URLError as e:
            if attempt < 2:
                time.sleep(3 * (attempt + 1))
                continue
            sys.exit("Could not reach PostHog (%s): %s" % (HOST, e.reason))
    sys.exit("PostHog did not answer")


def _q(s):
    """A string literal for HogQL."""
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


# ---------------------------------------------------------------- finding and fetching

def list_parts(since, until=None):
    """Every run_record part since `since` (a datetime, UTC): [{uuid, ts, distinct_id, player_name, label}], oldest first,
    without the payloads (the cheap pass: the uuid, timestamp and distinct_id columns and the person's two names)."""
    out, seen = [], set()
    lo = since.strftime("%Y-%m-%d %H:%M:%S")
    hi = (" AND timestamp <= toDateTime(%s)" % _q(until.strftime("%Y-%m-%d %H:%M:%S"))) if until else ""
    while True:
        q = ("SELECT toString(uuid), toString(timestamp), distinct_id, coalesce(toString(person.properties.player_name), ''), "
             "coalesce(toString(person.properties.label), '') FROM events WHERE event = %s AND timestamp >= toDateTime(%s)%s "
             "ORDER BY timestamp ASC LIMIT %d") % (_q(EVENT), _q(lo), hi, LIST_PAGE)
        _, rows = hogql(q)
        new = 0
        for r in rows:
            if r[0] in seen:
                continue
            seen.add(r[0])
            new += 1
            out.append({"uuid": r[0], "ts": r[1], "distinct_id": r[2], "player_name": r[3] or "", "label": r[4] or ""})
        if len(rows) < LIST_PAGE or not new:
            return out
        lo = str(rows[-1][1])[:19]   # the next page from the last timestamp (the uuids seen are skipped)


def fetch_parts(items):
    """The parts' events with their properties: {uuid: properties}, FETCH_BATCH at a time, each query bounded by its
    parts' timestamps (PostHog sorts events by day: a narrow range reads little)."""
    out = {}
    for i in range(0, len(items), FETCH_BATCH):
        chunk = items[i:i + FETCH_BATCH]
        lo = min(str(x["ts"])[:19] for x in chunk)
        hi = max(str(x["ts"])[:19] for x in chunk)
        q = ("SELECT toString(uuid), properties FROM events WHERE event = %s AND timestamp >= toDateTime(%s) - INTERVAL 1 SECOND "
             "AND timestamp <= toDateTime(%s) + INTERVAL 1 SECOND AND toString(uuid) IN (%s) LIMIT %d") % (
            _q(EVENT), _q(lo), _q(hi), ", ".join(_q(x["uuid"]) for x in chunk), len(chunk) * 2)
        _, rows = hogql(q)
        for r in rows:
            p = r[1]
            if isinstance(p, str):
                try:
                    p = json.loads(p)
                except ValueError:
                    continue
            if isinstance(p, dict):
                out[r[0]] = p
    return out


def join_parts(parts):
    """A run's record from its run_record properties (any order): (json text, "") or (None, why not)."""
    by = {}
    n = 0
    for p in parts:
        try:
            by[int(p.get("part", 0))] = p
            n = int(p.get("parts", 0))
        except (TypeError, ValueError):
            return None, "a part without its number"
    if n <= 0:
        return None, "no part count"
    missing = [i for i in range(1, n + 1) if i not in by]
    if missing:
        return None, "parts missing: %s of %d" % (missing, n)
    first = by[1]
    if str(first.get("enc", "gzip+base64")) != "gzip+base64":
        return None, "an encoding this tool does not know: %s" % first.get("enc")
    try:
        gz = base64.b64decode("".join(str(by[i].get("data", "")) for i in range(1, n + 1)), validate=True)
    except (ValueError, TypeError):
        return None, "the base64 does not read"
    if int(first.get("gz_bytes", -1)) != len(gz):
        return None, "the zipped size is %d, the parts say %s" % (len(gz), first.get("gz_bytes"))
    try:
        raw = gzip.decompress(gz)
    except (OSError, EOFError):
        return None, "the gzip does not unzip"
    if int(first.get("raw_bytes", -1)) != len(raw):
        return None, "the record is %d bytes, the parts say %s" % (len(raw), first.get("raw_bytes"))
    if hashlib.md5(raw).hexdigest() != str(first.get("md5", "")):
        return None, "the md5 differs"
    return raw.decode("utf-8"), ""


# ---------------------------------------------------------------- the folder

def slug(s):
    s = re.sub(r"[^A-Za-z0-9_-]+", "_", str(s).strip()).strip("_")
    return s[:60] or "player"


def player_name_of(item):
    return item.get("player_name") or ("id " + str(item.get("distinct_id", ""))[:8])


def player_keys(items, existing=None):
    """{distinct_id: folder key}: the player's name as a folder; two installs with one name apart by their id."""
    keys = dict(existing or {})
    used = {}
    for did, k in keys.items():
        used.setdefault(k, did)
    for it in items:
        did = str(it.get("distinct_id", ""))
        if did in keys:
            continue
        k = slug(player_name_of(it))
        if k in used and used[k] != did:
            k = slug(k + "_" + did[:6])
        keys[did] = k
        used[k] = did
    return keys


def run_file_name(rec, run_id):
    stamp = str(rec.get("stamp") or str(rec.get("started", "run")).replace(":", "-"))
    return "%s_%s" % (slug(stamp), slug(str(run_id)[:8] or "run"))


def write_run(out_dir, key, rec, remote):
    """The record (with its `remote` block) as <key>/<name>.json and the .js twin; returns the .json's path under out_dir."""
    rec = dict(rec)
    rec["remote"] = remote
    name = run_file_name(rec, remote.get("run_id") or rec.get("run_id") or "")
    folder = os.path.join(out_dir, key)
    os.makedirs(folder, exist_ok=True)
    text = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
    rel = key + "/" + name + ".json"
    with open(os.path.join(folder, name + ".json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    with open(os.path.join(folder, name + ".js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("(window.RUN_FILES = window.RUN_FILES || {})[%s] = %s;\n" % (json.dumps(rel), text))
    return rel


def _old_index(out_dir):
    """The index as last written: {file: row} (a row is reused while its file is not newer than the index)."""
    path = os.path.join(out_dir, "index.json")
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        return {str(r.get("file")): r for r in d.get("runs") or [] if isinstance(r, dict)}, os.path.getmtime(path)
    except (OSError, ValueError, AttributeError):
        return {}, 0.0


def _row_of(out_dir, key, fname, old, old_t):
    """A run file's index row: from the last index when the file is not newer, else made from the file (None: no run)."""
    rel = key + "/" + fname
    path = os.path.join(out_dir, key, fname)
    r = old.get(rel)
    if r is not None and r.get("run_id") is not None and os.path.getmtime(path) <= old_t:
        return r
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        return None
    rm = d.get("remote") if isinstance(d, dict) else None
    if not isinstance(rm, dict):
        return None
    row = analytics_csv.index_row(d, fname)
    row.update({"file": rel, "js": rel[:-5] + ".js", "player": key, "player_name": rm.get("player", ""), "player_label": rm.get("label", ""),
                "distinct_id": rm.get("distinct_id", ""), "received": rm.get("received", ""), "uuids": rm.get("uuids") or [],
                "run_id": str(rm.get("run_id") or d.get("run_id") or ""), "dev": bool(rm.get("dev") or (d.get("settings") or {}).get("dev")),
                "parts": rm.get("parts", 1)})
    if rm.get("recovered"):
        row["recovered"] = True
    return row


def run_rows(out_dir):
    """Every downloaded run's index row (the folder's files, the last index reused for the unchanged ones)."""
    rows = []
    if not os.path.isdir(out_dir):
        return rows
    old, old_t = _old_index(out_dir)
    for key in sorted(os.listdir(out_dir)):
        folder = os.path.join(out_dir, key)
        if not os.path.isdir(folder):
            continue
        for f in sorted(os.listdir(folder)):
            if f.endswith(".json"):
                r = _row_of(out_dir, key, f, old, old_t)
                if r is not None:
                    rows.append(r)
    return rows


def on_disk(out_dir):
    """The runs already downloaded: {run_id: index row} and {distinct_id: folder key}."""
    runs, keys = {}, {}
    for r in run_rows(out_dir):
        runs[str(r.get("run_id", ""))] = r
        if r.get("distinct_id"):
            keys[str(r["distinct_id"])] = r["player"]
    return runs, keys


def build_index(out_dir, made=None):
    """analytics/remote/index.json and index.js from the run files there: the players and every run's index row."""
    rows, players = run_rows(out_dir), {}
    for row in rows:
        p = players.setdefault(row["player"], {"key": row["player"], "name": row.get("player_name") or row["player"], "label": "",
                                               "distinct_ids": [], "runs": 0, "dev_runs": 0, "first": "", "last": "", "play_s": 0.0})
        if row.get("distinct_id") and row["distinct_id"] not in p["distinct_ids"]:
            p["distinct_ids"].append(row["distinct_id"])
        if row.get("player_label"):
            p["label"] = row["player_label"]
        p["runs"] += 1
        p["dev_runs"] += 1 if row.get("dev") else 0
        st = str(row.get("started", ""))
        p["first"] = min(p["first"], st) if p["first"] else st
        p["last"] = max(p["last"], st)
        p["play_s"] = round(p["play_s"] + float(row.get("length") or 0), 1)
    rows.sort(key=lambda x: (str(x.get("started", "")), str(x.get("file", ""))))
    idx = {"made": made or datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"), "host": HOST,
           "players": sorted(players.values(), key=lambda p: p["last"], reverse=True), "runs": rows}
    os.makedirs(out_dir, exist_ok=True)
    text = json.dumps(idx, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    with open(os.path.join(out_dir, "index.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("window.REMOTE = %s;\n" % text)
    return idx


# ---------------------------------------------------------------- the whole download

def wanted(item, players):
    if not players:
        return True
    names = {str(item.get("player_name", "")).lower(), str(item.get("label", "")).lower(), player_name_of(item).lower(),
             str(item.get("distinct_id", "")).lower()}
    return any(p.lower() in names for p in players)


def download(out_dir=OUT_DEFAULT, since=None, players=(), force=False, list_only=False, log=print):
    """The whole job; returns {found, runs, new, skipped, incomplete: [...], players, index}."""
    since = since or (datetime.datetime.utcnow() - datetime.timedelta(days=DAYS_DEFAULT))
    report = {"found": 0, "runs": 0, "new": 0, "skipped": 0, "incomplete": [], "bad": [], "budget": "", "index": None}
    try:
        items = [it for it in list_parts(since) if wanted(it, players)]
    except BudgetSpent as e:
        log("PostHog's read budget for the personal key is used up for now: %s. Nothing was downloaded; try again later." % e)
        report["budget"] = str(e)
        return report
    report["found"] = len(items)
    have, keys = on_disk(out_dir)
    keys = player_keys(items, keys)
    done_uuids = set()
    for r in have.values():
        done_uuids.update(r["uuids"])
    by_player = {}
    for it in items:
        by_player.setdefault(keys[str(it["distinct_id"])], []).append(it)
    if list_only:
        for k, its in sorted(by_player.items()):
            have_n = sum(1 for it in its if it["uuid"] in done_uuids)
            log("%-32s %4d parts (%d already here) %s .. %s" % (k, len(its), have_n, its[0]["ts"][:16], its[-1]["ts"][:16]))
        report["players"] = sorted(by_player)
        return report
    todo = [it for it in items if force or it["uuid"] not in done_uuids]
    report["skipped"] = len(items) - len(todo)
    log("run_record parts since %s: %d (%d already downloaded), from %d player%s" % (
        since.strftime("%Y-%m-%d"), len(items), report["skipped"], len(by_player), "" if len(by_player) == 1 else "s"))
    props = {}
    try:
        props = fetch_parts(todo)
    except BudgetSpent as e:
        log("PostHog's read budget ran out mid-way (%s): the runs fetched so far are kept; run again later for the rest." % e)
        report["budget"] = str(e)
    # each run's parts together
    runs = {}
    meta = {it["uuid"]: it for it in todo}
    for uuid, p in props.items():
        rid = str(p.get("run_id") or "")
        runs.setdefault(rid, []).append((uuid, p))
    for rid, got in runs.items():
        parts = [p for _, p in got]
        text, why = join_parts(parts)
        it = meta[got[0][0]]
        if text is None:
            (report["incomplete"] if why.startswith("parts missing") else report["bad"]).append("%s (%s): %s" % (rid[:8], player_name_of(it), why))
            continue
        try:
            rec = json.loads(text)
        except ValueError:
            report["bad"].append("%s: the record is not JSON" % rid[:8])
            continue
        first = sorted(parts, key=lambda p: int(p.get("part", 0)))[0]
        remote = {"player": player_name_of(it), "label": it.get("label", ""), "distinct_id": it.get("distinct_id", ""), "run_id": rid,
                  "received": min(meta[u]["ts"] for u, _ in got), "parts": int(first.get("parts", 1)), "uuids": sorted(u for u, _ in got),
                  "dev": bool(first.get("dev")), "app_version": first.get("app_version", ""), "device": first.get("device", ""),
                  "os": first.get("os", ""), "format": first.get("format", 1)}
        for k in ("recovered", "rows_left_out"):
            if first.get(k):
                remote[k] = True
        old = have.get(rid)
        if old and force:
            try:
                os.remove(os.path.join(out_dir, old["file"]))
                os.remove(os.path.join(out_dir, old["file"][:-5] + ".js"))
            except OSError:
                pass
        rel = write_run(out_dir, keys[str(it["distinct_id"])], rec, remote)
        report["new"] += 1
        log("  %s  %s  %s %s, %s, %s" % (rel, remote["received"][:16], rec.get("hero_name", rec.get("hero", "?")), rec.get("result", "?"),
                                          "%d:%02d" % divmod(int(float(rec.get("length") or 0)), 60), "dev" if remote["dev"] else "player"))
    report["index"] = build_index(out_dir)
    report["runs"] = len(report["index"]["runs"])
    report["players"] = [p["key"] for p in report["index"]["players"]]
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description="Download the runs the game sent to PostHog into analytics/remote/ (see the module doc).")
    ap.add_argument("--player", action="append", default=[], help="only this player (player_name, Garry's label or the install id); repeat for several")
    ap.add_argument("--since", help="from this day on (YYYY-MM-DD); the default is the last %d days" % DAYS_DEFAULT)
    ap.add_argument("--all", action="store_true", help="everything ever sent")
    ap.add_argument("--out", default=OUT_DEFAULT, help="the folder (default analytics/remote)")
    ap.add_argument("--list", action="store_true", help="list what PostHog has, by player, without downloading")
    ap.add_argument("--force", action="store_true", help="download again the runs already in the folder")
    a = ap.parse_args(argv)
    if a.all:
        since = datetime.datetime(2026, 1, 1)
    elif a.since:
        try:
            since = datetime.datetime.strptime(a.since, "%Y-%m-%d")
        except ValueError:
            sys.exit("--since takes a day like 2026-10-01")
    else:
        since = None
    out = os.path.abspath(a.out)
    rep = download(out, since, a.player, a.force, a.list)
    if a.list:
        return 0
    for line in rep["incomplete"]:
        print("incomplete (not all parts in PostHog yet: try again in a few minutes): " + line)
    for line in rep["bad"]:
        print("could not read: " + line)
    left = STATS["budget_left"]
    print("%d new run%s, %d in %s from %d player%s; PostHog read %.1f MB in %d quer%s%s" % (
        rep["new"], "" if rep["new"] == 1 else "s", rep["runs"], os.path.relpath(out, ROOT) if out.startswith(ROOT) else out,
        len(rep.get("players") or []), "" if len(rep.get("players") or []) == 1 else "s", STATS["bytes_read"] / 1e6, STATS["queries"],
        "y" if STATS["queries"] == 1 else "ies", "" if left is None else " (%.0f MB of the hourly budget left)" % (left / 1e6)))
    print("Open analytics/dashboard.html and press Remote runs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
