#!/usr/bin/env python3
"""Fetch RPL 2026/27 standings, schedule and scores from Match TV into docs/data/rpl.json."""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
DOCS = Path(__file__).resolve().parent
OUT = DOCS / "data" / "rpl.json"
LOCAL_SCHEDULE = ROOT / "poster" / "matches.json"

CALENDAR_URL = "https://matchtv.ru/football/rpl/calendar"
TABLE_URL = "https://matchtv.ru/football/rpl/table"
UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)

TEAM_SLUGS = {
    "Акрон": "akron",
    "Ахмат": "akhmat",
    "Балтика": "baltika",
    "Динамо М": "dinamo-m",
    "Динамо Мх": "dinamo-mh",
    "Зенит": "zenit",
    "Краснодар": "krasnodar",
    "Крылья Советов": "krylia",
    "Локомотив": "lokomotiv",
    "Оренбург": "orenburg",
    "Родина": "rodina",
    "Ростов": "rostov",
    "Рубин": "rubin",
    "Спартак": "spartak",
    "Факел": "fakel",
    "ЦСКА": "cska",
}

FORM_MAP = {"winner": "W", "tie": "D", "loser": "L"}
MSK = ZoneInfo("Europe/Moscow")


def fetch(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept-Encoding": "identity",
            "Accept-Language": "ru,en;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=40) as response:
        return response.read().decode("utf-8", "replace")


def capture_first(pattern: str, text: str) -> str | None:
    match = re.search(pattern, text)
    return match.group(1).strip() if match else None


def capture_all(pattern: str, text: str) -> list[str]:
    return [item.strip() for item in re.findall(pattern, text)]


def normalize(name: str) -> str:
    value = name.lower().replace("ё", "е")
    for prefix in ("пфк ", "фк "):
        if value.startswith(prefix):
            value = value[len(prefix) :]
    return value.replace("«", "").replace("»", "").strip()


def slug_for(name: str) -> str:
    if name in TEAM_SLUGS:
        return TEAM_SLUGS[name]
    key = normalize(name)
    for team, slug in TEAM_SLUGS.items():
        if normalize(team) == key:
            return slug
    return re.sub(r"[^a-z0-9]+", "-", key) or "team"


def cell_number(key: str, row: str) -> int | None:
    idx = row.find(f"m-table-body-cell--key-{key}")
    if idx < 0:
        return None
    rest = row[idx:]
    end = rest.find("</td>")
    if end < 0:
        return None
    raw = capture_first(r">([+\-]?\d+)</span>", rest[: end + 5])
    if raw is None:
        return None
    return int(raw.replace("+", ""))


def parse_standings(html: str) -> dict[str, Any]:
    season = capture_first(r"(\d{4}-\d{2})(?!-\d)", html) or "2026-27"
    rows: list[dict[str, Any]] = []
    for chunk in html.split("p-tournament-standings-table__row")[1:]:
        rank = cell_number("rank", chunk)
        team = capture_first(r'e-tournament-tables-team__link-text">([^<]+)', chunk)
        if rank is None or not team:
            continue
        form = [
            FORM_MAP[status]
            for status in capture_all(r"m-game-status-circles__circle--status-([a-z]+)", chunk)
            if status in FORM_MAP
        ]
        gf = cell_number("goalsFor", chunk) or 0
        ga = cell_number("goalsAgainst", chunk) or 0
        diff = cell_number("goalsDifference", chunk)
        rows.append(
            {
                "rank": rank,
                "team": team,
                "slug": slug_for(team),
                "played": cell_number("played", chunk) or 0,
                "won": cell_number("won", chunk) or 0,
                "drawn": cell_number("drawn", chunk) or 0,
                "lost": cell_number("lost", chunk) or 0,
                "goalsFor": gf,
                "goalsAgainst": ga,
                "goalDiff": gf - ga if diff is None else diff,
                "points": cell_number("points", chunk) or 0,
                "form": form[-5:],
            }
        )
    rows.sort(key=lambda row: row["rank"])
    return {"season": season.replace("-", "/"), "rows": rows}


def parse_card(card: str, tour: int, date_key: str, href: str | None = None) -> dict[str, Any] | None:
    titles = capture_all(r'm-tournament-game-participant__title">([^<]+)', card)
    if len(titles) < 2:
        return None
    home, away = titles[0], titles[1]
    scores = capture_all(r'm-tournament-game-participant-score-block__score">([^<]*)', card)
    time = capture_first(
        r"e-tournament-game-card-additional-top-content__future-time[^>]*>\s*([^<]+)",
        card,
    )
    live = capture_first(
        r"e-tournament-game-card-additional-top-content__live[^>]*>\s*([^<]+)",
        card,
    )
    href = href or capture_first(r'href="(/football/rpl/\d+-[^"]+)"', card)
    home_score = scores[0] if len(scores) > 0 and scores[0] != "" else None
    away_score = scores[1] if len(scores) > 1 and scores[1] != "" else None
    if live:
        status = "live"
    elif home_score is not None and away_score is not None:
        status = "finished"
    else:
        status = "scheduled"
    kickoff = None
    if time:
        kickoff = re.sub(r"\s+", "", time).replace(".", ":")
        if kickoff.upper() == "TBA":
            kickoff = None
    return {
        "id": f"rpl-{date_key}-{home}-{away}",
        "tour": tour,
        "date": date_key,
        "time": kickoff,
        "home": home,
        "away": away,
        "homeSlug": slug_for(home),
        "awaySlug": slug_for(away),
        "homeScore": int(home_score) if home_score is not None and home_score.isdigit() else home_score,
        "awayScore": int(away_score) if away_score is not None and away_score.isdigit() else away_score,
        "live": live,
        "status": status,
        "url": href,
    }


def parse_calendar(html: str) -> list[dict[str, Any]]:
    parts = re.split(r'p-tournament-calendar-tour__heading">Тур\s+(\d+)', html)
    found: dict[tuple[int, str, str, str], dict[str, Any]] = {}
    # split keeps capture groups: [preamble, "1", body, "2", body, ...]
    for i in range(1, len(parts), 2):
        tour = int(parts[i])
        body = parts[i + 1] if i + 1 < len(parts) else ""
        date_matches = list(re.finditer(r'id="date_([^"]+)"', body))
        if not date_matches:
            continue
        for index, marker in enumerate(date_matches):
            date_key = marker.group(1)[:10]
            start = marker.end()
            end = date_matches[index + 1].start() if index + 1 < len(date_matches) else len(body)
            day = body[start:end]
            chunks = day.split("e-tournament-game-card-team-vs-team-content")
            for index, card in enumerate(chunks[1:], start=1):
                prev = chunks[index - 1]
                hrefs = re.findall(r'href="(/football/rpl/\d+-[^"]+)"', prev)
                parsed = parse_card(card, tour, date_key, href=hrefs[-1] if hrefs else None)
                if not parsed:
                    continue
                key = (tour, date_key, normalize(parsed["home"]), normalize(parsed["away"]))
                found[key] = parsed
    matches = list(found.values())
    matches.sort(key=lambda item: (item["tour"], item["date"], item["time"] or "", item["home"]))
    return matches


def load_local_schedule() -> list[dict[str, Any]]:
    if not LOCAL_SCHEDULE.exists():
        return []
    raw = json.loads(LOCAL_SCHEDULE.read_text(encoding="utf-8"))
    matches = []
    for item in raw:
        home, away = item["home"], item["away"]
        matches.append(
            {
                "id": f"rpl-{item['date']}-{home}-{away}",
                "tour": int(item["tour"]),
                "date": item["date"],
                "time": item.get("time") or None,
                "home": home,
                "away": away,
                "homeSlug": slug_for(home),
                "awaySlug": slug_for(away),
                "homeScore": None,
                "awayScore": None,
                "live": None,
                "status": "scheduled",
            }
        )
    return matches


def merge_matches(local: list[dict[str, Any]], live: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_pair: dict[tuple[str, str, int], dict[str, Any]] = {}
    by_day: dict[tuple[str, str, str], dict[str, Any]] = {}
    for match in live:
        by_pair[(normalize(match["home"]), normalize(match["away"]), match["tour"])] = match
        by_day[(match["date"], normalize(match["home"]), normalize(match["away"]))] = match

    merged: list[dict[str, Any]] = []
    used = set()
    for item in local:
        key_pair = (normalize(item["home"]), normalize(item["away"]), item["tour"])
        key_day = (item["date"], normalize(item["home"]), normalize(item["away"]))
        overlay = by_pair.get(key_pair) or by_day.get(key_day)
        row = dict(item)
        if overlay:
            used.add(id(overlay))
            for field in ("date", "time", "homeScore", "awayScore", "live", "status", "id", "url"):
                if overlay.get(field) not in (None, ""):
                    row[field] = overlay[field]
            row["home"] = overlay["home"]
            row["away"] = overlay["away"]
            row["homeSlug"] = overlay["homeSlug"]
            row["awaySlug"] = overlay["awaySlug"]
            row["tour"] = overlay["tour"]
        merged.append(row)

    teams_in_tour: dict[int, set[str]] = defaultdict(set)
    for row in merged:
        teams_in_tour[row["tour"]].add(normalize(row["home"]))
        teams_in_tour[row["tour"]].add(normalize(row["away"]))

    for match in live:
        if id(match) in used:
            continue
        key_pair = (normalize(match["home"]), normalize(match["away"]), match["tour"])
        already = any(
            normalize(row["home"]) == key_pair[0]
            and normalize(row["away"]) == key_pair[1]
            and row["tour"] == key_pair[2]
            for row in merged
        )
        if already:
            continue
        occupied = teams_in_tour[match["tour"]]
        if key_pair[0] in occupied or key_pair[1] in occupied:
            continue
        merged.append(match)
        occupied.add(key_pair[0])
        occupied.add(key_pair[1])

    merged.sort(key=lambda item: (item["tour"], item["date"], item["time"] or "", item["home"]))
    return merged


def standings_from_matches(matches: list[dict[str, Any]]) -> list[dict[str, Any]]:
    stats: dict[str, dict[str, Any]] = {}

    def team_row(name: str) -> dict[str, Any]:
        if name not in stats:
            stats[name] = {
                "team": name,
                "slug": slug_for(name),
                "played": 0,
                "won": 0,
                "drawn": 0,
                "lost": 0,
                "goalsFor": 0,
                "goalsAgainst": 0,
                "goalDiff": 0,
                "points": 0,
                "form": [],
            }
        return stats[name]

    finished = [m for m in matches if m["status"] == "finished" and m["homeScore"] is not None and m["awayScore"] is not None]
    finished.sort(key=lambda m: (m["date"], m["time"] or ""))
    for match in finished:
        home, away = team_row(match["home"]), team_row(match["away"])
        hs, aws = int(match["homeScore"]), int(match["awayScore"])
        for side, gf, ga in ((home, hs, aws), (away, aws, hs)):
            side["played"] += 1
            side["goalsFor"] += gf
            side["goalsAgainst"] += ga
            side["goalDiff"] = side["goalsFor"] - side["goalsAgainst"]
        if hs > aws:
            home["won"] += 1
            home["points"] += 3
            home["form"].append("W")
            away["lost"] += 1
            away["form"].append("L")
        elif hs < aws:
            away["won"] += 1
            away["points"] += 3
            away["form"].append("W")
            home["lost"] += 1
            home["form"].append("L")
        else:
            home["drawn"] += 1
            away["drawn"] += 1
            home["points"] += 1
            away["points"] += 1
            home["form"].append("D")
            away["form"].append("D")

    rows = list(stats.values())
    for row in rows:
        row["form"] = row["form"][-5:]
    rows.sort(
        key=lambda row: (-row["points"], -row["goalDiff"], -row["goalsFor"], row["team"])
    )
    for index, row in enumerate(rows, start=1):
        row["rank"] = index
    return rows


EVENT_TITLES = r"Гол|Автогол|Желтая карточка|Красная карточка|Изменение составов"
DETAIL_VERSION = 3
EVENT_TYPES = {
    "Гол": "goal",
    "Автогол": "own_goal",
    "Желтая карточка": "yellow",
    "Красная карточка": "red",
    "Изменение составов": "sub",
}


def clean_minute(raw: str | None) -> str:
    return (raw or "").replace("’", "'").replace("′", "'").strip()


def parse_overview_goals(html: str) -> list[dict[str, Any]]:
    start = html.find("p-game-main-info-goals-overview")
    if start < 0:
        return []
    end = html.find("p-game-timeline", start)
    block = html[start : end if end > start else start + 25000]
    events: list[dict[str, Any]] = []
    for part in re.split(r"p-game-main-info-goals-overview-goal ", block)[1:]:
        side = "home" if "variant-home" in part[:150] else "away"
        player = capture_first(r"goals-overview-goal__scorer[^>]*>([^<]+)", part)
        assist = capture_first(r"goals-overview-goal__assistents[^>]*>([^<]+)", part)
        minute = clean_minute(capture_first(r'goals-overview-goal__minute">([^<]+)', part))
        if not player or not minute:
            continue
        own = "автогол" in part.lower() or "own-goal" in part.lower() or "owngoal" in part.lower()
        events.append(
            {
                "type": "own_goal" if own else "goal",
                "side": side,
                "minute": minute,
                "player": player,
                "assist": assist,
            }
        )
    return events


def parse_timeline_events(html: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for marker in re.finditer(rf'title="({EVENT_TITLES})"', html):
        kind = EVENT_TYPES[marker.group(1)]
        window = html[max(0, marker.start() - 500) : marker.end() + 4500]
        minute = clean_minute(capture_first(r'event-time__minute">([^<]+)', window))
        before = window[: max(window.find('title="'), 0)]
        side = "home" if "event-time--variant-home" in before else "away"
        event: dict[str, Any] = {"type": kind, "side": side, "minute": minute}
        if kind in ("goal", "own_goal"):
            event["player"] = capture_first(r"goal-template__scorer[^>]*>([^<]+)", window)
            event["assist"] = capture_first(r"goal-template__assistant[^>]*>([^<]+)", window)
        elif kind in ("yellow", "red"):
            event["player"] = capture_first(r"basic-template__name[^>]*>([^<]+)", window)
        elif kind == "sub":
            incoming = None
            outgoing = None
            names = capture_all(r"changing-template-player__name[^>]*>([^<]+)", window)
            for part in window.split("changing-template-player ")[1:3]:
                name = capture_first(r"changing-template-player__name[^>]*>([^<]+)", part)
                if not name:
                    continue
                if "2DB343" in part:
                    incoming = name
                elif "F43E31" in part:
                    outgoing = name
            if incoming is None and names:
                incoming = names[0]
            if outgoing is None and len(names) > 1:
                outgoing = names[1]
            event["playerIn"] = incoming
            event["playerOut"] = outgoing
        events.append(event)
    return events


def merge_events(overview: list[dict[str, Any]], timeline: list[dict[str, Any]]) -> list[dict[str, Any]]:
    own_keys = {
        (item["minute"], item.get("player"))
        for item in timeline
        if item["type"] == "own_goal"
    }
    goals: list[dict[str, Any]] = []
    seen: set[tuple[str, str | None]] = set()
    source = overview or [item for item in timeline if item["type"] in ("goal", "own_goal")]
    for item in source:
        key = (item["minute"], item.get("player"))
        if key in seen:
            continue
        seen.add(key)
        row = dict(item)
        if key in own_keys:
            row["type"] = "own_goal"
        goals.append(row)
    extras = [item for item in timeline if item["type"] not in ("goal", "own_goal")]
    merged = goals + extras

    def sort_key(item: dict[str, Any]) -> tuple[int, int, str]:
        text = str(item.get("minute") or "").replace("'", "")
        parts = text.split("+")
        main = int(re.sub(r"\D", "", parts[0]) or 0)
        extra = int(re.sub(r"\D", "", parts[1]) or 0) if len(parts) > 1 else 0
        return (main, extra, item.get("type") or "")

    merged.sort(key=sort_key)
    return merged


def parse_match_detail(html: str) -> dict[str, Any]:
    stadium = capture_first(r"p-game-main-info-header__stadium-name[^>]*>([^<]+)", html)
    referee = capture_first(r"p-game-main-info-header__referee-name[^>]*>([^<]+)", html)
    events = merge_events(parse_overview_goals(html), parse_timeline_events(html))
    stats: list[dict[str, str]] = []
    for home, name, away in re.findall(
        r'color--text-color--gray-500">([^<]+)</span>'
        r'<span class="typography typography--variant-body-m-regular color color--text-color--gray-800">([^<]+)</span>'
        r'<span class="typography typography--variant-body-l-regular color color--text-color--gray-500">([^<]+)</span>',
        html,
    ):
        stats.append({"name": name.strip(), "home": home.strip(), "away": away.strip()})
    return {
        "stadium": stadium,
        "referee": referee,
        "events": events,
        "stats": stats,
        "detailsVersion": DETAIL_VERSION,
    }


def previous_matches() -> dict[str, dict[str, Any]]:
    if not OUT.exists():
        return {}
    try:
        payload = json.loads(OUT.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return {item["id"]: item for item in payload.get("matches", []) if "id" in item}


def details_complete(old: dict[str, Any]) -> bool:
    if old.get("detailsVersion") != DETAIL_VERSION:
        return False
    for event in old.get("events") or []:
        kind = event.get("type")
        if kind in ("goal", "own_goal") and not event.get("player"):
            return False
        if kind in ("yellow", "red") and not event.get("player"):
            return False
        if kind == "sub" and not (event.get("playerIn") and event.get("playerOut")):
            return False
    home_score, away_score = old.get("homeScore"), old.get("awayScore")
    if isinstance(home_score, int) and isinstance(away_score, int):
        scored = sum(1 for event in old.get("events") or [] if event.get("type") in ("goal", "own_goal"))
        if scored != home_score + away_score:
            return False
    return True


def enrich_matches(matches: list[dict[str, Any]]) -> None:
    cached = previous_matches()
    fetched = 0
    for match in matches:
        old = cached.get(match["id"], {})
        if not match.get("url"):
            match["url"] = old.get("url")
        reuse = (
            match["status"] == "finished"
            and details_complete(old)
            and old.get("url") == match.get("url")
        )
        if reuse:
            match["events"] = old["events"]
            match["stats"] = old.get("stats") or []
            match["stadium"] = old.get("stadium")
            match["referee"] = old.get("referee")
            match["detailsVersion"] = old.get("detailsVersion")
            continue
        if match["status"] not in ("finished", "live") or not match.get("url"):
            continue
        url = match["url"]
        if url.startswith("/"):
            url = "https://matchtv.ru" + url
        try:
            detail = parse_match_detail(fetch(url))
        except Exception as error:
            print(f"detail fail {match['id']}: {error}", file=sys.stderr)
            if old.get("events"):
                match["events"] = old["events"]
                match["stats"] = old.get("stats") or []
                match["stadium"] = old.get("stadium")
                match["referee"] = old.get("referee")
            continue
        match.update(detail)
        fetched += 1
    if fetched:
        print(f"fetched details for {fetched} matches")


def build() -> dict[str, Any]:
    table_html = fetch(TABLE_URL)
    calendar_html = fetch(CALENDAR_URL)
    table = parse_standings(table_html)
    live_matches = parse_calendar(calendar_html)
    local_matches = load_local_schedule()
    matches = merge_matches(local_matches, live_matches) if local_matches else live_matches
    enrich_matches(matches)

    standings = table["rows"]
    if len(standings) != 16:
        standings = standings_from_matches(matches)

    now = datetime.now(timezone.utc).astimezone(MSK)
    payload = {
        "season": table["season"] or "2026/27",
        "updatedAt": now.isoformat(timespec="seconds"),
        "source": "matchtv.ru",
        "standings": standings,
        "matches": matches,
    }
    if len(matches) < 16:
        raise SystemExit(f"too few matches parsed: {len(matches)}")
    if not standings:
        raise SystemExit("empty standings")
    return payload


def main() -> None:
    try:
        payload = build()
    except Exception as error:
        print(f"update failed: {error}", file=sys.stderr)
        raise

    OUT.parent.mkdir(parents=True, exist_ok=True)
    previous = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if rendered == previous:
        print(f"unchanged {OUT} ({len(payload['matches'])} matches)")
        return
    OUT.write_text(rendered, encoding="utf-8")
    print(
        f"wrote {OUT} · {len(payload['standings'])} teams · "
        f"{len(payload['matches'])} matches · {payload['updatedAt']}"
    )


if __name__ == "__main__":
    main()
