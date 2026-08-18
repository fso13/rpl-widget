#!/usr/bin/env python3
"""Two A4 landscape sheets: tours 1–17 and 18–30, for colour print."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime
from pathlib import Path

import generate as g

OUT = g.ROOT / "rpl-2026-27-a4.html"
AUTUMN = range(1, 18)
SPRING = range(18, 31)


def tour_dates(by_tour: dict[int, list[dict]], tours: range) -> list[datetime]:
    dates = [
        datetime.strptime(m["date"], "%Y-%m-%d")
        for t in tours
        for m in by_tour.get(t, [])
    ]
    dates.sort()
    return dates


def standings_block() -> str:
    return f"""<aside class="standings">
  <header>
    <h2>Таблица</h2>
    <p>После тура стирайте строку и вписывайте клуб на новое место</p>
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
    <tbody>{g.table_rows()}</tbody>
  </table>
  <div class="legend">
    <span><span class="swatch zenit"></span><b>Зенит</b> в календаре</span>
    <span><span class="swatch euro"></span><b>1–3</b> евро</span>
    <span><span class="swatch down"></span><b>15–16</b> вылет</span>
  </div>
</aside>"""


def sheet(
    *,
    page: int,
    title_tag: str,
    date_line: str,
    extra_meta: str,
    tours_html: str,
    standings: str,
    body_class: str,
    foot_mid: str,
    rpl: str,
    crest: str,
    clubs: str,
) -> str:
    return f"""<article class="sheet">
  <div class="kit"><i></i><i></i><i></i></div>
  <header class="masthead">
    <div class="rpl"><img src="{rpl}" alt="РПЛ"></div>
    <div class="titles">
      <div class="eyebrow">Альфа-Банк Российская Премьер-Лига · ФК Зенит</div>
      <h1>Календарь РПЛ 2026/27</h1>
      <div class="tag">{g.html.escape(title_tag)}</div>
    </div>
    <div class="crest"><img src="{crest}" alt="ФК Зенит"></div>
    <div class="meta">
      <div class="stars">★ ★</div>
      <div><b>{g.html.escape(date_line)}</b></div>
      <div>{g.html.escape(extra_meta)}</div>
      <div class="page-no">Лист {page} из 2</div>
    </div>
  </header>
  <div class="clubs">{clubs}</div>
  <div class="body-wrap">
    <div class="body {body_class}">
      <div class="tours">{tours_html}</div>
      {standings}
    </div>
    <footer class="sheet-foot">
      <span><span class="badge">1925</span> · голубая строка — матч «Зенита»</span>
      <span>{foot_mid}</span>
      <span>Квадраты — счёт хозяева : гости · печатать в цвете, поля «минимум»</span>
    </footer>
  </div>
  <div class="kit"><i></i><i></i><i></i></div>
</article>"""


def css(logo_css: str) -> str:
    return f"""
  :root {{
    --blue: #003082;
    --blue-deep: #001e54;
    --cyan: #0097db;
    --cyan-soft: #e7f5fc;
    --cyan-mid: #b9e3f6;
    --gold: #cfaf2b;
    --ink: #0c2340;
    --muted: #4d6a86;
    --paper: #f4f8fb;
    --card: #ffffff;
    --line: #c5d8ea;
    --box: #fff;
    --down: #9a3b33;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  html, body {{ background: #001e54; color: var(--ink); }}
  body {{
    font-family: "Avenir Next Condensed", "Avenir Next", "Helvetica Neue", Arial, sans-serif;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
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
  .toolbar span {{ opacity: .9; max-width: 820px; }}
  .stage {{ padding: 16px 12px 40px; display: flex; flex-direction: column; align-items: center; gap: 16px; }}
  .sheet {{
    width: 297mm; height: 210mm;
    background: var(--paper);
    display: grid; grid-template-rows: auto auto auto 1fr auto;
    overflow: hidden;
  }}
  .kit {{ display: grid; grid-template-rows: 1.6mm 1mm 1.6mm; }}
  .kit i:nth-child(1) {{ background: var(--blue); }}
  .kit i:nth-child(2) {{ background: #fff; }}
  .kit i:nth-child(3) {{ background: var(--cyan); }}
  .masthead {{
    background: var(--blue); color: #fff;
    padding: 2.4mm 6mm 2.2mm;
    display: grid; grid-template-columns: auto 1fr auto auto;
    gap: 4mm; align-items: center;
  }}
  .rpl {{
    width: 13mm; height: 13mm; background: #fff; border-radius: 2.2mm;
    display: flex; align-items: center; justify-content: center; flex: none;
  }}
  .rpl img {{ width: 11mm; height: 11mm; object-fit: contain; display: block; }}
  .titles .eyebrow {{
    font-size: 8px; letter-spacing: .22em; text-transform: uppercase;
    color: var(--gold); font-weight: 700;
  }}
  h1 {{
    font-size: 17px; line-height: .95; font-weight: 800;
    letter-spacing: .04em; text-transform: uppercase; margin-top: 0.7mm;
  }}
  .tag {{
    margin-top: 0.9mm; font-size: 9px; letter-spacing: .1em; text-transform: uppercase;
    color: var(--cyan-mid); font-weight: 600;
  }}
  .crest img {{ height: 14mm; width: auto; display: block; mix-blend-mode: screen; }}
  .meta {{ text-align: right; font-size: 8.5px; color: #c5e6f6; line-height: 1.35; }}
  .meta b {{ color: #fff; }}
  .stars {{ color: var(--gold); letter-spacing: 1.2mm; font-size: 10px; margin-bottom: 0.4mm; }}
  .page-no {{ margin-top: 0.6mm; color: var(--gold); font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }}
  .clubs {{
    display: grid; grid-template-columns: repeat(16, 1fr); gap: 1.4mm; align-items: center;
    background: #fff; padding: 1.6mm 6mm; border-bottom: 1.3px solid var(--cyan);
  }}
  .clubs .club {{ display: flex; align-items: center; justify-content: center; min-width: 0; }}
  .clubs .club img {{ width: 8.5mm; height: 8.5mm; object-fit: contain; display: block; }}
  .clubs .club.first {{
    background: var(--cyan-soft); border: 1px solid var(--cyan);
    border-radius: 1.4mm; padding: 0.6mm;
  }}
  .clubs .club.first img {{ width: 10mm; height: 10mm; }}
  .body-wrap {{
    padding: 2mm 5mm 1.6mm;
    display: grid; grid-template-rows: 1fr auto; gap: 1.3mm; min-height: 0;
  }}
  .body.autumn {{
    display: grid; grid-template-columns: minmax(0, 1fr); min-height: 0;
  }}
  .body.spring {{
    display: grid; grid-template-columns: minmax(0, 1fr) 78mm; gap: 2mm; min-height: 0;
  }}
  .tours {{
    display: grid; gap: 1.3mm; min-height: 0;
  }}
  .body.autumn .tours {{
    grid-template-columns: repeat(6, minmax(0, 1fr));
    grid-template-rows: repeat(3, 1fr);
  }}
  .body.spring .tours {{
    grid-template-columns: repeat(5, minmax(0, 1fr));
    grid-template-rows: repeat(3, 1fr);
  }}
  .tour {{
    border: 1px solid var(--line); background: var(--card);
    display: flex; flex-direction: column; min-height: 0; overflow: hidden;
  }}
  .tour header {{
    display: flex; justify-content: space-between; align-items: baseline; gap: 3px;
    padding: 1mm 1.2mm 0.9mm; background: var(--blue); color: #fff;
  }}
  .tour.spring header {{ background: var(--cyan); }}
  .tour .num {{ font-size: 8px; font-weight: 800; letter-spacing: .04em; text-transform: uppercase; }}
  .tour .span {{ font-size: 6.4px; opacity: .92; white-space: nowrap; }}
  .matches {{ flex: 1; display: flex; flex-direction: column; padding: 0.2mm 0.6mm 0.3mm; }}
  .match {{
    display: flex; align-items: center; justify-content: flex-start;
    gap: 0.6mm; flex: 1; min-height: 0;
    border-bottom: 1px dotted #d4e4f0;
  }}
  .match:last-child {{ border-bottom: 0; }}
  .match.zenit {{
    background: var(--cyan-soft); margin: 0 -0.6mm; padding: 0 0.6mm;
  }}
  .when {{
    display: flex; flex-direction: column; justify-content: center;
    width: 7.2mm; flex: none; line-height: 1.05;
  }}
  .when b {{ font-size: 6.2px; font-weight: 700; color: var(--blue); }}
  .when i {{ font-size: 5.6px; font-style: normal; color: var(--muted); }}
  .when i:empty {{ display: none; }}
  .side {{ display: flex; align-items: center; flex: none; }}
  .side.ours .mark {{
    outline: 1px solid var(--cyan); outline-offset: 0.2mm; border-radius: 0.6mm;
  }}
  .mark {{
    width: 6.6mm; height: 6.6mm; flex: none; display: block;
    background-size: contain; background-repeat: no-repeat; background-position: center;
  }}
  {logo_css}
  .score {{ display: flex; align-items: center; justify-content: center; gap: 0.45mm; flex: none; }}
  .score i {{
    display: block; width: 4.8mm; height: 4.5mm;
    border: 1px solid #7aa0bd; background: var(--box); border-radius: 0.35mm;
  }}
  .match.zenit .score i {{ border-color: var(--cyan); }}
  .score em {{ font-size: 8px; font-style: normal; color: #7aa0bd; font-weight: 600; }}
  .note {{
    border: 1px dashed var(--cyan); background: var(--cyan-soft);
    padding: 2.2mm 2.4mm; color: var(--muted); font-size: 7.2px; line-height: 1.35;
    display: flex; flex-direction: column; justify-content: center; gap: 1.1mm;
  }}
  .note b {{ color: var(--blue); font-size: 8px; letter-spacing: .06em; text-transform: uppercase; }}
  .standings {{
    border: 1.2px solid var(--blue); background: var(--card);
    display: flex; flex-direction: column; min-height: 0;
  }}
  .standings > header {{ background: var(--blue); color: #fff; padding: 1.5mm 1.8mm 1.3mm; }}
  .standings h2 {{ font-size: 10px; letter-spacing: .14em; text-transform: uppercase; }}
  .standings header p {{ font-size: 6.4px; opacity: .86; margin-top: 0.6mm; line-height: 1.25; color: var(--cyan-mid); }}
  table {{ width: 100%; border-collapse: collapse; flex: 1; table-layout: fixed; }}
  col.pos {{ width: 5mm; }}
  col.club {{ width: auto; }}
  col.cell {{ width: 5.2mm; }}
  col.goals {{ width: 7.4mm; }}
  col.pts {{ width: 5.4mm; }}
  col.hint {{ width: 4.8mm; }}
  thead th {{
    font-size: 5.8px; letter-spacing: .04em; text-transform: uppercase;
    color: var(--muted); font-weight: 700; padding: 1mm 0.15mm 0.8mm;
    border-bottom: 1px solid var(--line); text-align: center;
  }}
  thead th:nth-child(2) {{ text-align: left; padding-left: 1.3mm; }}
  tbody tr {{ height: 6.15%; }}
  td {{ border-bottom: 1px solid #dceaf3; }}
  td.pos {{ text-align: center; font-weight: 800; font-size: 9px; color: var(--blue); }}
  td.club {{ padding: 0 1.3mm 0 1.4mm; }}
  td.club span {{ display: block; height: 3.8mm; border-bottom: 1px solid #6d8eaa; }}
  td.cell {{ border-left: 1px dotted #d4e4f0; }}
  td.hint {{
    font-size: 4.8px; letter-spacing: .03em; text-transform: uppercase;
    color: var(--muted); text-align: right; padding-right: 0.8mm;
  }}
  tr.euro td.pos {{ color: var(--cyan); }}
  tr.down td.pos {{ color: var(--down); }}
  .legend {{
    display: flex; justify-content: space-between; gap: 3px;
    padding: 1.2mm 1.6mm 1.3mm; font-size: 6px; color: var(--muted);
    border-top: 1px solid var(--line); background: var(--cyan-soft);
  }}
  .legend b {{ color: var(--ink); }}
  .swatch {{ display: inline-block; width: 5px; height: 5px; margin-right: 2px; vertical-align: -1px; }}
  .swatch.euro {{ background: var(--cyan); }}
  .swatch.down {{ background: var(--down); }}
  .swatch.zenit {{ background: var(--blue); }}
  footer.sheet-foot {{
    display: flex; justify-content: space-between; gap: 10px;
    font-size: 6.6px; color: var(--muted);
  }}
  .badge {{
    display: inline-block; color: var(--blue); font-weight: 700; letter-spacing: .08em;
    text-transform: uppercase;
  }}
  @media print {{
    .toolbar {{ display: none !important; }}
    html, body {{ background: #fff !important; width: 297mm; }}
    .stage {{ padding: 0 !important; gap: 0 !important; display: block; }}
    .sheet {{
      outline: none; transform: none !important;
      width: 297mm; height: 210mm;
      break-after: page; page-break-after: always;
    }}
    .sheet:last-of-type {{ break-after: auto; page-break-after: auto; }}
    .crest img {{ mix-blend-mode: screen; }}
    @page {{ size: A4 landscape; margin: 0; }}
  }}
"""


def build_html(matches: list[dict], only_page: int | None = None) -> str:
    by_tour: dict[int, list[dict]] = defaultdict(list)
    for m in matches:
        by_tour[m["tour"]].append(m)
    for tour in by_tour:
        by_tour[tour].sort(key=lambda m: (m["date"], m.get("time") or "", m["home"]))
    uris = g.load_club_uris()
    logo_css, slugs = g.logo_classes(uris)
    clubs = g.clubs_strip(uris)
    rpl = g.data_uri(g.RPL_LOGO)
    crest = g.data_uri(g.ZENIT_CREST)
    autumn_dates = tour_dates(by_tour, AUTUMN)
    spring_dates = tour_dates(by_tour, SPRING)
    autumn_tours = "".join(g.render_tour(t, by_tour[t], slugs) for t in AUTUMN)
    autumn_tours += """<div class="note">
  <b>Лист 1 · осень</b>
  <span>Голубая строка — матч «Зенита». В квадраты вписывайте счёт.</span>
  <span>Таблица чемпионата — на втором листе, туры 18–30.</span>
</div>"""
    spring_tours = "".join(g.render_tour(t, by_tour[t], slugs) for t in SPRING)
    page1 = sheet(
        page=1,
        title_tag="Лист 1 · Осень · туры 1–17",
        date_line=g.fmt_range(autumn_dates),
        extra_meta="Газпром Арена · время МСК, туры 1–9",
        tours_html=autumn_tours,
        standings="",
        body_class="autumn",
        foot_mid="Осень: синие шапки туров 1–17",
        rpl=rpl,
        crest=crest,
        clubs=clubs,
    )
    page2 = sheet(
        page=2,
        title_tag="Лист 2 · Весна · туры 18–30",
        date_line=g.fmt_range(spring_dates),
        extra_meta="С 10-го тура время объявляют позже",
        tours_html=spring_tours,
        standings=standings_block(),
        body_class="spring",
        foot_mid="Весна: голубые шапки туров 18–30",
        rpl=rpl,
        crest=crest,
        clubs=clubs,
    )
    sheets = {1: page1, 2: page2}
    if only_page in sheets:
        stage = sheets[only_page]
    else:
        stage = page1 + page2
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Зенит · календарь РПЛ 2026/27 · A4</title>
<style>{css(logo_css)}</style>
</head>
<body>
  <div class="toolbar">
    <button onclick="window.print()">Печать / PDF</button>
    <span>Два листа <b>A4 альбомная</b>, цвет. Поля «минимум» или «нет», фон графики включён, колонтитулы выкл.</span>
  </div>
  <div class="stage">{stage}</div>
  <script>
    function fit() {{
      const stage = document.querySelector(".stage");
      const sheets = [...document.querySelectorAll(".sheet")];
      if (!sheets.length) return;
      if (matchMedia("print").matches) {{
        sheets.forEach(s => s.style.transform = "");
        stage.style.height = "";
        return;
      }}
      const scale = Math.min((innerWidth - 28) / sheets[0].offsetWidth, 1);
      sheets.forEach(sheet => {{
        sheet.style.transformOrigin = "top center";
        sheet.style.transform = "scale(" + scale + ")";
      }});
      stage.style.height = (sheets[0].offsetHeight * scale * sheets.length + 40) + "px";
    }}
    addEventListener("resize", fit);
    addEventListener("beforeprint", () => {{
      document.querySelectorAll(".sheet").forEach(s => s.style.transform = "none");
    }});
    addEventListener("afterprint", fit);
    fit();
  </script>
</body>
</html>
"""


def main() -> None:
    matches = g.json.loads(g.DATA.read_text(encoding="utf-8"))
    if len(matches) != 240:
        raise SystemExit(f"expected 240 matches, got {len(matches)}")
    OUT.write_text(build_html(matches), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
