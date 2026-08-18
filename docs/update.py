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


def parse_card(card: str, tour: int, date_key: str) -> dict[str, Any] | None:
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
            for card in day.split("e-tournament-game-card-team-vs-team-content")[1:]:
                parsed = parse_card(card, tour, date_key)
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
            for field in ("date", "time", "homeScore", "awayScore", "live", "status", "id"):
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


def build() -> dict[str, Any]:
    table_html = fetch(TABLE_URL)
    calendar_html = fetch(CALENDAR_URL)
    table = parse_standings(table_html)
    live_matches = parse_calendar(calendar_html)
    local_matches = load_local_schedule()
    matches = merge_matches(local_matches, live_matches) if local_matches else live_matches

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
