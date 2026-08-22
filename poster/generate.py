#!/usr/bin/env python3
"""Generate a Zenit-styled printable RPL 2026/27 wall poster."""

from __future__ import annotations

import base64
import html
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "rpl-2026-27.html"
DATA = ROOT / "matches.json"
CLUBS_DIR = ROOT / "assets/clubs"
RPL_LOGO = ROOT / "assets/rpl-bear.png"
ZENIT_CREST = ROOT / "assets/zenit-2star.png"

WEEKDAY = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
MONTH = {
    1: "янв", 2: "фев", 3: "мар", 4: "апр", 5: "мая", 6: "июн",
    7: "июл", 8: "авг", 9: "сен", 10: "окт", 11: "ноя", 12: "дек",
}
SHORT = {"Крылья Советов": "Крылья"}


def team(name: str) -> str:
    return SHORT.get(name, name)


def data_uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def load_club_uris() -> dict[str, str]:
    uris: dict[str, str] = {}
    for path in CLUBS_DIR.glob("*.png"):
        uris[path.stem.replace("_", " ")] = data_uri(path)
    return uris


def club_order(names: list[str]) -> list[str]:
    rest = sorted((n for n in names if n != "Зенит"), key=lambda s: s.replace("ё", "е").lower())
    return ["Зенит"] + rest


def fmt_range(dates: list[datetime]) -> str:
    first, last = dates[0], dates[-1]
    if first.date() == last.date():
        return f"{first.day} {MONTH[first.month]}, {WEEKDAY[first.weekday()]}"
    if first.month == last.month:
        return f"{first.day}–{last.day} {MONTH[first.month]}"
    return f"{first.day} {MONTH[first.month]} – {last.day} {MONTH[last.month]}"


def logo_classes(uris: dict[str, str]) -> tuple[str, dict[str, str]]:
    slugs: dict[str, str] = {}
    rules: list[str] = []
    for i, name in enumerate(club_order(list(uris))):
        slug = f"lg{i}"
        slugs[name] = slug
        rules.append(f".{slug}{{background-image:url({uris[name]})}}")
    return "\n".join(rules), slugs


def mark(name: str, slugs: dict[str, str]) -> str:
    slug = slugs.get(name, "")
    if not slug:
        return ""
    return f'<i class="mark {slug}"></i>'


def render_tour(tour: int, matches: list[dict], slugs: dict[str, str]) -> str:
    dates = [datetime.strptime(m["date"], "%Y-%m-%d") for m in matches]
    timed = any(m.get("time") for m in matches)
    season = "autumn" if tour <= 17 else "spring"
    extra = " timed" if timed else " untimed"
    rows = []
    for m in matches:
        dt = datetime.strptime(m["date"], "%Y-%m-%d")
        when = f"{dt.day} {WEEKDAY[dt.weekday()]}"
        time = m.get("time") or ""
        zenit = m["home"] == "Зенит" or m["away"] == "Зенит"
        home_cls = "ours" if m["home"] == "Зенит" else ""
        away_cls = "ours" if m["away"] == "Зенит" else ""
        rows.append(
            f"""<div class="match{' zenit' if zenit else ''}">
  <span class="when"><b>{html.escape(when)}</b><i>{html.escape(time)}</i></span>
  <span class="side home {home_cls}">{mark(m["home"], slugs)}</span>
  <span class="score"><i></i><em>:</em><i></i></span>
  <span class="side away {away_cls}">{mark(m["away"], slugs)}</span>
</div>"""
        )
    return f"""<section class="tour {season}{extra}">
  <header><span class="num">Тур {tour}</span><span class="span">{html.escape(fmt_range(dates))}</span></header>
  <div class="matches">{"".join(rows)}</div>
</section>"""


def clubs_strip(uris: dict[str, str]) -> str:
    items = []
    for name in club_order(list(uris)):
        cls = "club first" if name == "Зенит" else "club"
        items.append(
            f'<div class="{cls}"><img src="{uris[name]}" alt="{html.escape(name)}"></div>'
        )
    return "".join(items)


def table_rows() -> str:
    parts = []
    for i in range(1, 17):
        zone = " euro" if i <= 3 else " down" if i >= 15 else ""
        hint = "евро" if i <= 3 else "вылет" if i >= 15 else ""
        parts.append(
            f"""<tr class="{zone.strip()}">
  <td class="pos">{i}</td>
  <td class="club"><span></span></td>
  <td class="cell"></td><td class="cell"></td><td class="cell"></td><td class="cell"></td>
  <td class="cell goals"></td>
  <td class="cell pts"></td>
  <td class="hint">{html.escape(hint)}</td>
</tr>"""
        )
    return "".join(parts)


def build_html(matches: list[dict]) -> str:
    by_tour: dict[int, list[dict]] = defaultdict(list)
    for m in matches:
        by_tour[m["tour"]].append(m)
    for tour in by_tour:
        by_tour[tour].sort(key=lambda m: (m["date"], m.get("time") or "", m["home"]))
    uris = load_club_uris()
    logo_css, slugs = logo_classes(uris)
    tours_html = "".join(render_tour(t, by_tour[t], slugs) for t in range(1, 31))
    rpl = data_uri(RPL_LOGO)
    crest = data_uri(ZENIT_CREST)
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Зенит · календарь РПЛ 2026/27</title>
<style>
  :root {{
    --blue: #003082;
    --blue-deep: #001e54;
    --cyan: #0097db;
    --cyan-soft: #e7f5fc;
    --cyan-mid: #b9e3f6;
    --gold: #cfaf2b;
    --ink: #0c2340;
    --muted: #4d6a86;
    --paper: #eef6fb;
    --card: #ffffff;
    --line: #c5d8ea;
    --box: #fff;
    --down: #9a3b33;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  html, body {{ background: #001e54; color: var(--ink); }}
  body {{
    font-family: "Avenir Next Condensed", "Avenir Next", "Helvetica Neue", Arial, sans-serif;
  }}
  .toolbar {{
    position: sticky; top: 0; z-index: 5;
    display: flex; gap: 12px; align-items: center; justify-content: center; flex-wrap: wrap;
    padding: 10px 16px; background: var(--blue-deep); color: #d7ecf7;
    font: 13px/1.3 "Helvetica Neue", Arial, sans-serif;
  }}
  .toolbar button {{
    border: 0; background: var(--cyan); color: #fff;
    padding: 8px 14px; border-radius: 4px; cursor: pointer; font-weight: 700;
  }}
  .toolbar span {{ opacity: .9; max-width: 740px; }}
  .stage {{ padding: 20px 12px 40px; display: flex; justify-content: center; }}
  .sheet {{
    width: 594mm; height: 420mm;
    background: var(--paper);
    display: grid; grid-template-rows: auto auto auto 1fr auto;
    overflow: hidden;
  }}
  .kit {{
    display: grid; grid-template-rows: 2mm 1.3mm 2mm;
  }}
  .kit i:nth-child(1) {{ background: var(--blue); }}
  .kit i:nth-child(2) {{ background: #fff; }}
  .kit i:nth-child(3) {{ background: var(--cyan); }}
  .masthead {{
    background: var(--blue);
    color: #fff;
    padding: 3.6mm 7mm 3.2mm;
    display: grid;
    grid-template-columns: auto 1fr auto auto;
    gap: 5.5mm;
    align-items: center;
  }}
  .rpl {{
    width: 18mm; height: 18mm;
    background: #fff;
    border-radius: 3mm;
    display: flex; align-items: center; justify-content: center;
    flex: none;
  }}
  .rpl img {{ width: 15mm; height: 15mm; object-fit: contain; display: block; }}
  .titles .eyebrow {{
    font-size: 10px; letter-spacing: .26em; text-transform: uppercase;
    color: var(--gold); font-weight: 700;
  }}
  h1 {{
    font-size: 24px; line-height: .95; font-weight: 800;
    letter-spacing: .04em; text-transform: uppercase;
    margin-top: 1mm;
  }}
  .tag {{
    margin-top: 1.3mm;
    font-size: 11px; letter-spacing: .12em; text-transform: uppercase;
    color: var(--cyan-mid); font-weight: 600;
  }}
  .crest img {{
    height: 20mm; width: auto; display: block;
    mix-blend-mode: screen;
  }}
  .meta {{
    text-align: right; font-size: 10.5px; color: #c5e6f6; line-height: 1.4;
  }}
  .meta b {{ color: #fff; }}
  .stars {{
    color: var(--gold); letter-spacing: 1.5mm; font-size: 12px;
    margin-bottom: 0.8mm;
  }}
  .clubs {{
    display: grid;
    grid-template-columns: repeat(16, 1fr);
    gap: 2mm;
    align-items: center;
    background: #fff;
    padding: 2.6mm 7mm;
    border-bottom: 1.6px solid var(--cyan);
  }}
  .clubs .club {{
    display: flex; align-items: center; justify-content: center;
    min-width: 0;
  }}
  .clubs .club img {{
    width: 13mm; height: 13mm; object-fit: contain; display: block;
  }}
  .clubs .club.first {{
    background: var(--cyan-soft);
    border: 1px solid var(--cyan);
    border-radius: 2mm;
    padding: 1.2mm;
  }}
  .clubs .club.first img {{ width: 16mm; height: 16mm; }}
  .body-wrap {{
    padding: 2.6mm 5mm 2.2mm;
    display: grid; grid-template-rows: 1fr auto; gap: 1.8mm; min-height: 0;
  }}
  .body {{
    display: grid; grid-template-columns: minmax(0, 1fr) 86mm; gap: 2.6mm; min-height: 0;
  }}
  .tours {{
    display: grid;
    grid-template-columns: repeat(8, minmax(0, 1fr));
    grid-template-rows: repeat(4, 1fr);
    gap: 1.5mm;
    min-height: 0;
  }}
  .tour {{
    border: 1px solid var(--line); background: var(--card);
    display: flex; flex-direction: column; min-height: 0; overflow: hidden;
  }}
  .tour header {{
    display: flex; justify-content: space-between; align-items: baseline; gap: 3px;
    padding: 1.3mm 1.4mm 1.1mm; background: var(--blue); color: #fff;
  }}
  .tour.spring header {{ background: var(--cyan); }}
  .tour .num {{ font-size: 8.8px; font-weight: 800; letter-spacing: .04em; text-transform: uppercase; }}
  .tour .span {{ font-size: 7px; opacity: .92; white-space: nowrap; }}
  .matches {{ flex: 1; display: flex; flex-direction: column; padding: 0.3mm 0.7mm 0.4mm; }}
  .match {{
    display: flex; align-items: center; justify-content: flex-start;
    gap: 0.8mm; flex: 1; min-height: 0;
    border-bottom: 1px dotted #d4e4f0;
  }}
  .match:last-child {{ border-bottom: 0; }}
  .match.zenit {{
    background: var(--cyan-soft);
    margin: 0 -0.7mm;
    padding: 0 0.7mm;
  }}
  .when {{
    display: flex; flex-direction: column; justify-content: center;
    width: 6.8mm; flex: none; line-height: 1.05;
  }}
  .when b {{ font-size: 6px; font-weight: 700; color: var(--blue); }}
  .when i {{ font-size: 5.8px; font-style: normal; color: var(--muted); }}
  .when i:empty {{ display: none; }}
  .side {{
    display: flex; align-items: center; flex: none;
  }}
  .side.ours .mark {{
    outline: 1.1px solid var(--cyan);
    outline-offset: 0.25mm;
    border-radius: 0.8mm;
  }}
  .mark {{
    width: 9.4mm; height: 9.4mm; flex: none; display: block;
    background-size: contain; background-repeat: no-repeat; background-position: center;
  }}
  {logo_css}
  .score {{ display: flex; align-items: center; justify-content: center; gap: 0.6mm; flex: none; }}
  .score i {{
    display: block; width: 5.8mm; height: 5.4mm;
    border: 1.1px solid #7aa0bd; background: var(--box); border-radius: 0.4mm;
  }}
  .match.zenit .score i {{ border-color: var(--cyan); }}
  .score em {{ font-size: 10px; font-style: normal; color: #7aa0bd; font-weight: 600; }}
  .standings {{
    width: 86mm; border: 1.4px solid var(--blue); background: var(--card);
    display: flex; flex-direction: column; min-height: 0;
  }}
  .standings > header {{ background: var(--blue); color: #fff; padding: 1.8mm 2.2mm 1.6mm; }}
  .standings h2 {{ font-size: 11px; letter-spacing: .14em; text-transform: uppercase; }}
  .standings header p {{ font-size: 7.2px; opacity: .86; margin-top: 0.8mm; line-height: 1.25; color: var(--cyan-mid); }}
  table {{ width: 100%; border-collapse: collapse; flex: 1; table-layout: fixed; }}
  col.pos {{ width: 5.2mm; }}
  col.club {{ width: auto; }}
  col.cell {{ width: 5.4mm; }}
  col.goals {{ width: 8mm; }}
  col.pts {{ width: 5.8mm; }}
  col.hint {{ width: 5.2mm; }}
  thead th {{
    font-size: 6.4px; letter-spacing: .04em; text-transform: uppercase;
    color: var(--muted); font-weight: 700; padding: 1.2mm 0.2mm 1mm;
    border-bottom: 1px solid var(--line); text-align: center;
  }}
  thead th:nth-child(2) {{ text-align: left; padding-left: 1.6mm; }}
  tbody tr {{ height: 6.15%; }}
  td {{ border-bottom: 1px solid #dceaf3; }}
  td.pos {{
    text-align: center; font-weight: 800; font-size: 10px; color: var(--blue);
  }}
  td.club {{ padding: 0 1.6mm 0 1.8mm; }}
  td.club span {{
    display: block; height: 4.8mm; border-bottom: 1.1px solid #6d8eaa;
  }}
  td.cell {{ border-left: 1px dotted #d4e4f0; }}
  td.hint {{
    font-size: 5.2px; letter-spacing: .03em; text-transform: uppercase;
    color: var(--muted); text-align: right; padding-right: 1mm;
  }}
  tr.euro td.pos {{ color: var(--cyan); }}
  tr.down td.pos {{ color: var(--down); }}
  .legend {{
    display: flex; justify-content: space-between; gap: 4px;
    padding: 1.5mm 2mm 1.6mm; font-size: 6.6px; color: var(--muted);
    border-top: 1px solid var(--line); background: var(--cyan-soft);
  }}
  .legend b {{ color: var(--ink); }}
  .swatch {{ display: inline-block; width: 6px; height: 6px; margin-right: 3px; vertical-align: -1px; }}
  .swatch.euro {{ background: var(--cyan); }}
  .swatch.down {{ background: var(--down); }}
  .swatch.zenit {{ background: var(--blue); }}
  footer.sheet-foot {{
    display: flex; justify-content: space-between; gap: 12px;
    font-size: 7.6px; color: var(--muted);
  }}
  .badge {{
    display: inline-block; color: var(--blue); font-weight: 700; letter-spacing: .08em;
    text-transform: uppercase;
  }}
  @media print {{
    .toolbar {{ display: none !important; }}
    html, body {{ background: #fff; }}
    .stage {{ padding: 0; }}
    .sheet {{ outline: none; transform: none !important; }}
    .crest img {{ mix-blend-mode: screen; }}
    @page {{ size: A2 landscape; margin: 0; }}
  }}
</style>
</head>
<body>
  <div class="toolbar">
    <button onclick="window.print()">Печать / PDF</button>
    <span>Печатать на <b>A2 альбомная</b>. Поля «Нет», фон включён, колонтитулы выкл. Голубые строки — матчи «Зенита».</span>
  </div>
  <div class="stage">
    <article class="sheet">
      <div class="kit"><i></i><i></i><i></i></div>
      <header class="masthead">
        <div class="rpl"><img src="{rpl}" alt="РПЛ"></div>
        <div class="titles">
          <div class="eyebrow">Альфа-Банк Российская Премьер-Лига · ФК Зенит</div>
          <h1>Календарь РПЛ 2026/27</h1>
          <div class="tag">Сине-бело-голубые · 30 туров · место для счёта</div>
        </div>
        <div class="crest"><img src="{crest}" alt="ФК Зенит"></div>
        <div class="meta">
          <div class="stars">★ ★</div>
          <div><b>24 июля 2026 — 29 мая 2027</b></div>
          <div>Газпром Арена · время МСК, туры 1–17</div>
          <div>С 18-го тура время объявляют позже</div>
        </div>
      </header>
      <div class="clubs">{clubs_strip(uris)}</div>
      <div class="body-wrap">
        <div class="body">
          <div class="tours">{tours_html}</div>
          <aside class="standings">
            <header>
              <h2>Таблица</h2>
              <p>Без названий: после тура стирайте строку и вписывайте клуб на новое место</p>
            </header>
            <table>
              <colgroup>
                <col class="pos"><col class="club">
                <col class="cell"><col class="cell"><col class="cell"><col class="cell">
                <col class="goals"><col class="pts"><col class="hint">
              </colgroup>
              <thead>
                <tr>
                  <th>№</th><th>Команда</th><th>И</th><th>В</th><th>Н</th><th>П</th><th>Мячи</th><th>О</th><th></th>
                </tr>
              </thead>
              <tbody>{table_rows()}</tbody>
            </table>
            <div class="legend">
              <span><span class="swatch zenit"></span><b>Зенит</b> в календаре</span>
              <span><span class="swatch euro"></span><b>1–3</b> евро</span>
              <span><span class="swatch down"></span><b>15–16</b> вылет</span>
            </div>
          </aside>
        </div>
        <footer class="sheet-foot">
          <span><span class="badge">1925</span> · эмблемы команд · Зенит выделен голубым</span>
          <span>Осень: синие туры 1–17 · весна: голубые туры 18–30</span>
          <span>Голубая строка — матч «Зенита» · квадраты — счёт хозяева : гости</span>
        </footer>
      </div>
      <div class="kit"><i></i><i></i><i></i></div>
    </article>
  </div>
  <script>
    function fit() {{
      const sheet = document.querySelector(".sheet");
      const stage = document.querySelector(".stage");
      if (!sheet) return;
      if (matchMedia("print").matches) {{
        sheet.style.transform = "";
        stage.style.height = "";
        return;
      }}
      const scale = Math.min((innerWidth - 28) / sheet.offsetWidth, (innerHeight - 88) / sheet.offsetHeight, 1);
      sheet.style.transformOrigin = "top center";
      sheet.style.transform = "scale(" + scale + ")";
      stage.style.height = (sheet.offsetHeight * scale + 20) + "px";
    }}
    addEventListener("resize", fit);
    addEventListener("beforeprint", () => {{
      document.querySelector(".sheet").style.transform = "none";
    }});
    addEventListener("afterprint", fit);
    fit();
  </script>
</body>
</html>
"""


def main() -> None:
    matches = json.loads(DATA.read_text(encoding="utf-8"))
    if len(matches) != 240:
        raise SystemExit(f"expected 240 matches, got {len(matches)}")
    uris = load_club_uris()
    if len(uris) != 16:
        raise SystemExit(f"expected 16 club logos, got {sorted(uris)}")
    OUT.write_text(build_html(matches), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
