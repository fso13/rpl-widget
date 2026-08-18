#!/usr/bin/env python3
"""Two A4 landscape sheets: Russian Cup 2026/27 grid, Zenit-styled."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime

import generate as g

OUT = g.ROOT / "cup-2026-27-a4.html"
DATA = g.ROOT / "cup_matches.json"
REGIONS = g.ROOT / "cup_regions.json"
SHORT = {"Крылья Советов": "Крылья", "Динамо М": "Динамо", "Динамо Мх": "Дин. Мх"}
MD_WINDOW = {4: "13–15 окт", 5: "27–29 окт", 6: "24–26 ноя"}


def short(name: str) -> str:
    return SHORT.get(name, name)


def when_label(m: dict) -> str:
    if m.get("date"):
        dt = datetime.strptime(m["date"], "%Y-%m-%d")
        label = f"{dt.day} {g.WEEKDAY[dt.weekday()]}"
        if m.get("time"):
            return f"{label} {m['time']}"
        return label
    return m.get("window") or ""


def match_chip(m: dict, slugs: dict[str, str]) -> str:
    zenit = m["home"] == "Зенит" or m["away"] == "Зенит"
    home_cls = "ours" if m["home"] == "Зенит" else ""
    away_cls = "ours" if m["away"] == "Зенит" else ""
    return f"""<div class="chip{' zenit' if zenit else ''}">
  <span class="when">{g.html.escape(when_label(m))}</span>
  <span class="side {home_cls}">{g.mark(m["home"], slugs)}</span>
  <span class="score"><i></i><em>:</em><i></i></span>
  <span class="side {away_cls}">{g.mark(m["away"], slugs)}</span>
</div>"""


def group_card(letter: str, teams: list[str], matches: list[dict], slugs: dict[str, str]) -> str:
    zenit = "Зенит" in teams
    by_md: dict[int, list[dict]] = defaultdict(list)
    for m in matches:
        by_md[m["md"]].append(m)
    rows = []
    for md in range(1, 7):
        pair = by_md[md]
        chips = "".join(match_chip(m, slugs) for m in pair)
        extra = f'<i>{MD_WINDOW[md]}</i>' if md in MD_WINDOW else ""
        rows.append(f'<div class="md"><b>Тур {md}{extra}</b><div class="pair">{chips}</div></div>')
    table_rows = []
    for i, name in enumerate(teams, 1):
        table_rows.append(
            f"""<tr{' class="zenit-row"' if name == "Зенит" else ""}>
  <td class="pos">{i}</td>
  <td class="club"><span class="who">{g.mark(name, slugs)}<span>{g.html.escape(short(name))}</span></span></td>
  <td></td><td></td><td></td><td></td><td></td>
</tr>"""
        )
    return f"""<section class="group{' zenit-group' if zenit else ''}">
  <header><h3>Группа {letter}</h3><span>1–2 → плей-офф РПЛ · 3–4 → путь регионов</span></header>
  <table>
    <thead><tr><th>№</th><th>Команда</th><th>И</th><th>В</th><th>Пен</th><th>Мячи</th><th>О</th></tr></thead>
    <tbody>{"".join(table_rows)}</tbody>
  </table>
  <div class="mds">{"".join(rows)}</div>
</section>"""


def seed_line(text: str, blank: bool = False) -> str:
    cls = "seed blank" if blank else "seed"
    return f'<div class="{cls}"><span>{g.html.escape(text)}</span><i></i></div>'


def tie_card(dates: str, a: str, b: str, blank: bool = False, two_legs: bool = True) -> str:
    legs = """<div class="legs">
    <span>1</span><span class="score"><i></i><em>:</em><i></i></span>
    <span>2</span><span class="score"><i></i><em>:</em><i></i></span>
  </div>""" if two_legs else """<div class="legs one">
    <span class="score"><i></i><em>:</em><i></i></span>
  </div>"""
    return f"""<article class="tie">
  <header><span>{g.html.escape(dates)}</span></header>
  {seed_line(a, blank)}
  {seed_line(b, blank)}
  {legs}
</article>"""


def reg_row(m: dict) -> str:
    blank = "победитель" in (m["home"] + m["away"])
    return f"""<div class="rm{' blank' if blank else ''}">
  <span class="when">{g.html.escape(when_label(m))}</span>
  <span class="nm">{g.html.escape(m["home"])}</span>
  <span class="score"><i></i><em>:</em><i></i></span>
  <span class="nm">{g.html.escape(m["away"])}</span>
</div>"""


def reg_round(rnd: dict) -> str:
    cols = 2 if rnd["n"] in (2, 4) else 1
    return f"""<section class="reg r{rnd['n']}">
  <header>
    <h3>{g.html.escape(rnd["title"])}</h3>
    <span>{g.html.escape(rnd["span"])} · {g.html.escape(rnd.get("note") or "")}</span>
  </header>
  <div class="rlist cols-{cols}">{"".join(reg_row(m) for m in rnd["matches"])}</div>
</section>"""


def fork_svg(kind: str, reverse: bool) -> str:
    if kind == "16":
        d = "M100 25 H28 M100 75 H28 M28 25 V75 M28 50 H0" if reverse else "M0 25 H72 M0 75 H72 M72 25 V75 M72 50 H100"
    elif kind == "8":
        d = (
            "M100 16.666 H28 M100 83.333 H28 M28 16.666 V83.333 M28 50 H0"
            if reverse
            else "M0 16.666 H72 M0 83.333 H72 M72 16.666 V83.333 M72 50 H100"
        )
    else:
        d = "M100 50 H0" if reverse else "M0 50 H100"
    return (
        f'<svg class="fork" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">'
        f'<path d="{d}" fill="none" stroke="currentColor" stroke-width="1.85" '
        f'stroke-linejoin="miter" vector-effect="non-scaling-stroke"/></svg>'
    )


def playoff_block() -> str:
    rpl_r16 = [
        ("2–4 / 16–18 мар", "2 место группы A", "1 место группы D"),
        ("2–4 / 16–18 мар", "2 место группы C", "1 место группы B"),
        ("2–4 / 16–18 мар", "2 место группы D", "1 место группы A"),
        ("2–4 / 16–18 мар", "2 место группы B", "1 место группы C"),
    ]
    left = bracket_path(
        "Путь РПЛ",
        rpl_r16,
        ["6–8 / 20–22 апр", "6–8 / 20–22 апр"],
        "4–6 / 18–20 мая",
        regions=False,
        two_legs_sf=True,
    )
    right = bracket_path(
        "Путь регионов",
        [
            ("17–19 мар / 7–9 апр", "победитель р.6", "3/4 группы РПЛ"),
            ("17–19 мар / 7–9 апр", "победитель р.6", "3/4 группы РПЛ"),
            ("17–19 мар / 7–9 апр", "победитель р.6", "3/4 группы РПЛ"),
            ("17–19 мар / 7–9 апр", "победитель р.6", "3/4 группы РПЛ"),
        ],
        ["21–23 апр / 5–7 мая", "21–23 апр / 5–7 мая"],
        "19–21 мая",
        regions=True,
        two_legs_sf=False,
        reverse=True,
    )
    final = """<aside class="final-col">
  <h3 class="ghost">Финал</h3>
  <div class="labs ghost"><span>6 июня 2027</span></div>
  <div class="final-stage">
    <i class="bridge from-rpl"></i>
    <article class="final-card">
      <div class="cup-mark">★</div>
      <h3>Финал</h3>
      <div class="date">6 июня 2027</div>
      <div class="vs">
        <div class="lane">победитель Пути РПЛ</div>
        <div class="score"><i></i><em>:</em><i></i></div>
        <div class="lane">победитель Пути регионов</div>
      </div>
    </article>
    <i class="bridge from-regions"></i>
  </div>
</aside>"""
    return f'<div class="bracket">{left}{final}{right}</div>'


def bracket_path(
    title: str,
    r16: list[tuple[str, str, str]],
    qf: list[str],
    sf: str,
    *,
    regions: bool,
    two_legs_sf: bool,
    reverse: bool = False,
) -> str:
    ties16 = [tie_card(d, a, b, blank=regions) for d, a, b in r16]
    ties8 = [tie_card(d, "победитель", "победитель", blank=True) for d in qf]
    tie2 = tie_card(sf, "победитель", "победитель", blank=True, two_legs=two_legs_sf)
    r16_html = "".join(f'<div class="slot s16 n{i}">{html}</div>' for i, html in enumerate(ties16, 1))
    qf_html = "".join(f'<div class="slot s8 n{i}">{html}</div>' for i, html in enumerate(ties8, 1))
    sf_html = f'<div class="slot s2">{tie2}</div>'
    joins = (
        f'<i class="c16 a">{fork_svg("16", reverse)}</i>'
        f'<i class="c16 b">{fork_svg("16", reverse)}</i>'
        f'<i class="c8">{fork_svg("8", reverse)}</i>'
        f'<i class="cout">{fork_svg("out", reverse)}</i>'
    )
    if reverse:
        labs = "<span>1/2 финала</span><span>1/4 финала</span><span>1/8 финала</span>"
        inner = f"{sf_html}{joins}{qf_html}{r16_html}"
    else:
        labs = "<span>1/8 финала</span><span>1/4 финала</span><span>1/2 финала</span>"
        inner = f"{r16_html}{joins}{qf_html}{sf_html}"
    cls = "path side-regions" if regions else "path side-rpl"
    rev = " rev" if reverse else ""
    return f"""<section class="{cls}">
  <h3>{g.html.escape(title)}</h3>
  <div class="labs{rev}">{labs}</div>
  <div class="tree{rev}">{inner}</div>
</section>"""


def css(logo_css: str) -> str:
    return f"""
  :root {{
    --blue: #003082; --blue-deep: #001e54; --cyan: #0097db; --cyan-soft: #e7f5fc;
    --cyan-mid: #b9e3f6; --gold: #cfaf2b; --ink: #0c2340; --muted: #4d6a86;
    --paper: #f4f8fb; --card: #ffffff; --line: #c5d8ea; --box: #fff; --down: #9a3b33;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  html, body {{ background: #001e54; color: var(--ink); }}
  body {{
    font-family: "Avenir Next Condensed", "Avenir Next", "Helvetica Neue", Arial, sans-serif;
    -webkit-print-color-adjust: exact; print-color-adjust: exact;
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
  .stage {{ padding: 16px 12px 40px; display: flex; flex-direction: column; align-items: center; gap: 16px; }}
  .sheet {{
    width: 297mm; height: 210mm; background: var(--paper);
    display: grid; grid-template-rows: auto auto 1fr auto; overflow: hidden;
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
  .masthead .rpl {{
    width: 13mm; height: 13mm; background: #fff; border-radius: 2.2mm;
    display: flex; align-items: center; justify-content: center;
  }}
  .masthead .rpl img {{ width: 11mm; height: 11mm; object-fit: contain; display: block; }}
  .titles .eyebrow {{
    font-size: 8px; letter-spacing: .22em; text-transform: uppercase;
    color: var(--gold); font-weight: 700;
  }}
  h1 {{
    font-size: 16.5px; line-height: .95; font-weight: 800;
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
    background: #fff; padding: 1.5mm 6mm; border-bottom: 1.3px solid var(--cyan);
  }}
  .clubs .club {{ display: flex; align-items: center; justify-content: center; min-width: 0; }}
  .clubs .club img {{ width: 8.2mm; height: 8.2mm; object-fit: contain; display: block; }}
  .clubs .club.first {{
    background: var(--cyan-soft); border: 1px solid var(--cyan); border-radius: 1.4mm; padding: 0.5mm;
  }}
  .clubs .club.first img {{ width: 9.6mm; height: 9.6mm; }}
  .body-wrap {{ padding: 2mm 4.5mm 1.6mm; display: grid; grid-template-rows: 1fr auto; gap: 1.2mm; min-height: 0; }}
  .groups {{
    display: grid; grid-template-columns: 1fr 1fr; grid-template-rows: 1fr 1fr;
    gap: 1.8mm; min-height: 0;
  }}
  .group {{
    border: 1.2px solid var(--line); background: var(--card);
    display: grid; grid-template-rows: auto auto 1fr; min-height: 0; overflow: hidden;
  }}
  .group.zenit-group {{ border-color: var(--cyan); }}
  .group > header {{
    display: flex; justify-content: space-between; align-items: baseline; gap: 4px;
    background: var(--blue); color: #fff; padding: 1mm 1.6mm 0.9mm;
  }}
  .group.zenit-group > header {{ background: var(--cyan); }}
  .group h3 {{ font-size: 9.5px; letter-spacing: .12em; text-transform: uppercase; }}
  .group header span {{ font-size: 6.2px; opacity: .9; }}
  table {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
  thead th {{
    font-size: 5.8px; letter-spacing: .04em; text-transform: uppercase;
    color: var(--muted); font-weight: 700; padding: 0.7mm 0.3mm;
    border-bottom: 1px solid var(--line); text-align: center;
  }}
  thead th:nth-child(2) {{ text-align: left; padding-left: 1.2mm; }}
  tbody td {{
    border-bottom: 1px solid #e4eef5; height: 5.4mm; font-size: 7px; text-align: center;
  }}
  td.pos {{ width: 5mm; font-weight: 800; color: var(--blue); }}
  td.club {{ width: auto; text-align: left; padding-left: 1.2mm; }}
  td.club .who {{ display: flex; align-items: center; gap: 1.1mm; font-weight: 700; color: var(--ink); }}
  tr.zenit-row {{ background: var(--cyan-soft); }}
  tbody td:nth-child(n+3) {{ border-left: 1px dotted #d4e4f0; width: 7.2mm; }}
  .mds {{ display: flex; flex-direction: column; padding: 0.4mm 1.1mm 0.6mm; min-height: 0; }}
  .md {{
    display: grid; grid-template-columns: 9mm 1fr; align-items: center; gap: 0.6mm;
    flex: 1; min-height: 0; border-bottom: 1px dotted #dceaf3; position: relative;
  }}
  .md:last-child {{ border-bottom: 0; }}
  .md > b {{ font-size: 6.2px; color: var(--blue); letter-spacing: .04em; text-transform: uppercase; line-height: 1.15; }}
  .md > b i {{ display: block; font-style: normal; font-size: 5px; color: var(--muted); text-transform: none; letter-spacing: 0; font-weight: 600; }}
  .pair {{ display: grid; grid-template-columns: 1fr 1fr; gap: 1.2mm; }}
  .chip {{
    display: flex; align-items: center; gap: 0.7mm; min-width: 0; padding: 0.2mm 0.4mm;
  }}
  .chip.zenit {{ background: var(--cyan-soft); border-radius: 0.6mm; }}
  .when {{ width: 16mm; flex: none; font-size: 6px; font-weight: 700; color: var(--blue); line-height: 1.1; }}
  .side {{ display: flex; align-items: center; }}
  .side.ours .mark {{ outline: 1px solid var(--cyan); outline-offset: 0.2mm; border-radius: 0.5mm; }}
  .mark {{
    width: 5.6mm; height: 5.6mm; flex: none; display: block;
    background-size: contain; background-repeat: no-repeat; background-position: center;
  }}
  {logo_css}
  .score {{ display: flex; align-items: center; gap: 0.35mm; }}
  .score i {{
    display: block; width: 4.2mm; height: 4mm;
    border: 1px solid #7aa0bd; background: var(--box); border-radius: 0.3mm;
  }}
  .score em {{ font-size: 7px; font-style: normal; color: #7aa0bd; font-weight: 600; }}
  .chip.zenit .score i {{ border-color: var(--cyan); }}

  .bracket {{
    display: grid; grid-template-columns: 1fr 38mm 1fr; gap: 0; min-height: 0;
  }}
  .path, .final-col {{
    display: grid; grid-template-rows: auto auto 1fr; min-height: 0;
  }}
  .path {{
    border: 1.2px solid var(--line); background: var(--card); overflow: hidden;
    min-width: 0;
  }}
  .path.side-rpl {{ border-right: 0; }}
  .path.side-regions {{ border-left: 0; }}
  .path > h3, .final-col > h3 {{
    background: var(--blue); color: #fff; font-size: 8px; letter-spacing: .14em;
    text-transform: uppercase; padding: 1mm 2mm;
  }}
  .path.side-regions > h3 {{ background: var(--cyan); }}
  .final-col > h3.ghost, .final-col .labs.ghost {{ visibility: hidden; }}
  .labs {{
    display: grid; grid-template-columns: 1.3fr 8mm 1fr 8mm 0.85fr 5mm;
    font-size: 5.3px; letter-spacing: .08em; text-transform: uppercase;
    color: var(--muted); font-weight: 700; padding: 0.55mm 0 0 1.6mm;
  }}
  .labs span:nth-child(1) {{ text-align: left; }}
  .labs span:nth-child(2) {{ grid-column: 3; text-align: center; }}
  .labs span:nth-child(3) {{ grid-column: 5; text-align: center; }}
  .labs.rev {{
    grid-template-columns: 5mm 0.85fr 8mm 1fr 8mm 1.3fr;
    padding: 0.55mm 1.6mm 0 0;
  }}
  .labs.rev span:nth-child(1) {{ grid-column: 2; text-align: center; }}
  .labs.rev span:nth-child(2) {{ grid-column: 4; text-align: center; }}
  .labs.rev span:nth-child(3) {{ grid-column: 6; text-align: right; }}
  .tree {{
    display: grid; grid-template-columns: 1.3fr 8mm 1fr 8mm 0.85fr 5mm;
    grid-template-rows: repeat(8, 1fr);
    gap: 0; padding: 0.3mm 0 0.8mm 1.4mm; min-height: 0; height: 100%;
  }}
  .tree.rev {{
    grid-template-columns: 5mm 0.85fr 8mm 1fr 8mm 1.3fr;
    padding: 0.3mm 1.4mm 0.8mm 0;
  }}
  .tree .slot {{ min-height: 0; padding: 0.55mm 0.2mm; display: flex; }}
  .tree .tie {{ flex: 1; }}
  .tree .s16.n1 {{ grid-column: 1; grid-row: 1 / 3; }}
  .tree .s16.n2 {{ grid-column: 1; grid-row: 3 / 5; }}
  .tree .s16.n3 {{ grid-column: 1; grid-row: 5 / 7; }}
  .tree .s16.n4 {{ grid-column: 1; grid-row: 7 / 9; }}
  .tree .s8.n1 {{ grid-column: 3; grid-row: 2 / 4; }}
  .tree .s8.n2 {{ grid-column: 3; grid-row: 6 / 8; }}
  .tree .s2 {{ grid-column: 5; grid-row: 4 / 6; }}
  .tree .c16.a {{ grid-column: 2; grid-row: 1 / 5; }}
  .tree .c16.b {{ grid-column: 2; grid-row: 5 / 9; }}
  .tree .c8 {{ grid-column: 4; grid-row: 2 / 8; }}
  .tree .cout {{ grid-column: 6; grid-row: 4 / 6; }}
  .tree.rev .s16.n1 {{ grid-column: 6; grid-row: 1 / 3; }}
  .tree.rev .s16.n2 {{ grid-column: 6; grid-row: 3 / 5; }}
  .tree.rev .s16.n3 {{ grid-column: 6; grid-row: 5 / 7; }}
  .tree.rev .s16.n4 {{ grid-column: 6; grid-row: 7 / 9; }}
  .tree.rev .s8.n1 {{ grid-column: 4; grid-row: 2 / 4; }}
  .tree.rev .s8.n2 {{ grid-column: 4; grid-row: 6 / 8; }}
  .tree.rev .s2 {{ grid-column: 2; grid-row: 4 / 6; }}
  .tree.rev .c16.a {{ grid-column: 5; grid-row: 1 / 5; }}
  .tree.rev .c16.b {{ grid-column: 5; grid-row: 5 / 9; }}
  .tree.rev .c8 {{ grid-column: 3; grid-row: 2 / 8; }}
  .tree.rev .cout {{ grid-column: 1; grid-row: 4 / 6; }}
  .tree .c16, .tree .c8, .tree .cout {{
    position: relative; align-self: stretch; justify-self: stretch; color: var(--blue);
  }}
  .path.side-regions .c16, .path.side-regions .c8, .path.side-regions .cout {{ color: var(--cyan); }}
  .tree .fork {{
    position: absolute; inset: 0; width: 100%; height: 100%; overflow: hidden;
  }}
  .tie {{
    border: 1px solid #d3e3f0; background: #fff;
    border-left: 2.4px solid var(--blue);
    padding: 0.45mm 1mm 0.55mm;
    display: flex; flex-direction: column; gap: 0.15mm;
    min-height: 0; justify-content: center; width: 100%;
  }}
  .path.side-regions .tie {{
    border-left: 1px solid #d3e3f0; border-right: 2.4px solid var(--cyan);
  }}
  .tie header {{ display: flex; justify-content: flex-end; }}
  .tie header span {{ font-size: 5px; color: var(--muted); letter-spacing: .02em; }}
  .seed {{
    display: flex; align-items: center; gap: 0.8mm;
    border-bottom: 1.2px solid var(--blue); min-height: 3.5mm; padding: 0 0.3mm;
  }}
  .path.side-regions .seed {{ border-bottom-color: var(--cyan); }}
  .seed span {{ font-size: 5.8px; font-weight: 700; color: var(--ink); white-space: nowrap; }}
  .seed.blank span {{ color: var(--muted); font-weight: 600; }}
  .seed i {{ flex: 1; }}
  .legs {{
    display: grid; grid-template-columns: auto 1fr auto 1fr; gap: 0.4mm; align-items: center;
    margin-top: 0.35mm;
  }}
  .legs.one {{ grid-template-columns: 1fr; justify-items: center; }}
  .legs > span {{ font-size: 5.2px; color: var(--muted); font-weight: 700; }}
  .final-stage {{
    display: grid; grid-template-columns: 4.5mm 1fr 4.5mm; align-items: center;
    min-height: 0; padding: 0 0 1mm;
  }}
  .final-stage .bridge {{
    height: 1.65px; align-self: center; background: var(--gold);
  }}
  .final-stage .bridge.from-rpl {{ background: var(--blue); }}
  .final-stage .bridge.from-regions {{ background: var(--cyan); }}
  .final-card {{
    border: 1.8px solid var(--gold); background: #fffdf6;
    display: flex; flex-direction: column; justify-content: center; gap: 1mm;
    padding: 2.2mm 1.6mm 2mm; text-align: center;
    box-shadow: inset 0 0 0 1.1px #f3e4a8;
    min-height: 0;
  }}
  .final-card .cup-mark {{ color: var(--gold); font-size: 10px; letter-spacing: 0.5mm; line-height: 1; }}
  .final-card h3 {{
    font-size: 12px; letter-spacing: .2em; text-transform: uppercase; color: var(--blue);
  }}
  .final-card .date {{ font-size: 7.2px; color: var(--muted); font-weight: 700; }}
  .final-card .vs {{ display: flex; flex-direction: column; gap: 1.1mm; margin-top: 0.6mm; }}
  .final-card .lane {{
    border-bottom: 1.3px solid #6d8eaa; min-height: 5.4mm;
    font-size: 5.7px; color: var(--muted); text-align: left; padding: 0 0.6mm 0.4mm;
  }}
  .final-card .score {{ justify-content: center; }}
  .final-card .score i {{ width: 6.4mm; height: 5.6mm; border-color: var(--gold); }}
  .regions-page {{
    display: grid; grid-template-rows: minmax(0, 1fr) 62mm; gap: 1.4mm; min-height: 0;
  }}
  .reg-grid {{
    display: grid;
    grid-template-columns: 0.95fr 0.95fr 1.35fr 0.95fr;
    grid-template-rows: 1.05fr 0.95fr;
    gap: 1.3mm; min-height: 0;
  }}
  .reg {{
    border: 1.1px solid var(--line); background: var(--card);
    display: grid; grid-template-rows: auto 1fr; min-height: 0; overflow: hidden;
  }}
  .reg > header {{
    display: flex; justify-content: space-between; align-items: baseline; gap: 4px;
    background: var(--cyan); color: #fff; padding: 0.8mm 1.3mm;
  }}
  .reg.r1 > header, .reg.r2 > header, .reg.r3 > header {{ background: var(--blue); }}
  .reg h3 {{ font-size: 8px; letter-spacing: .1em; text-transform: uppercase; }}
  .reg header span {{ font-size: 5.6px; opacity: .9; }}
  .reg-grid .r2 {{ grid-column: 2 / span 2; grid-row: 1; }}
  .reg-grid .r1 {{ grid-column: 1; grid-row: 1; }}
  .reg-grid .r3 {{ grid-column: 4; grid-row: 1; }}
  .reg-grid .r4 {{ grid-column: 1 / span 2; grid-row: 2; }}
  .reg-grid .r5 {{ grid-column: 3; grid-row: 2; }}
  .reg-grid .r6 {{ grid-column: 4; grid-row: 2; }}
  .rlist {{ display: grid; gap: 0; padding: 0.4mm 0.8mm 0.5mm; min-height: 0; align-content: start; }}
  .rlist.cols-2 {{ grid-template-columns: 1fr 1fr; column-gap: 1.4mm; }}
  .rm {{
    display: grid; grid-template-columns: 12mm minmax(0, 1.1fr) auto minmax(0, 1.1fr);
    align-items: center; gap: 0.45mm; min-height: 4.1mm;
    border-bottom: 1px dotted #dceaf3; padding: 0.12mm 0;
  }}
  .rm.blank .nm {{ color: var(--muted); font-weight: 600; }}
  .rm .when {{ font-size: 5.3px; font-weight: 700; color: var(--blue); white-space: nowrap; }}
  .rm .nm {{ font-size: 6.5px; font-weight: 700; color: var(--ink); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
  .rm .score i {{ width: 3.6mm; height: 3.4mm; }}
  footer.sheet-foot {{
    display: flex; justify-content: space-between; gap: 10px;
    font-size: 6.6px; color: var(--muted);
  }}
  .badge {{ color: var(--blue); font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }}
  @media print {{
    .toolbar {{ display: none !important; }}
    html, body {{ background: #fff !important; width: 297mm; }}
    .stage {{ padding: 0 !important; gap: 0 !important; display: block; }}
    .sheet {{
      outline: none; transform: none !important; width: 297mm; height: 210mm;
      break-after: page; page-break-after: always;
    }}
    .sheet:last-of-type {{ break-after: auto; page-break-after: auto; }}
    @page {{ size: A4 landscape; margin: 0; }}
  }}
"""


def sheet(*, page: int, tag: str, date_line: str, extra: str, body: str, foot_mid: str, rpl: str, crest: str, clubs: str) -> str:
    return f"""<article class="sheet">
  <div class="kit"><i></i><i></i><i></i></div>
  <header class="masthead">
    <div class="rpl"><img src="{rpl}" alt="РПЛ"></div>
    <div class="titles">
      <div class="eyebrow">FONBET Кубок России · ФК Зенит</div>
      <h1>Кубок России 2026/27</h1>
      <div class="tag">{g.html.escape(tag)}</div>
    </div>
    <div class="crest"><img src="{crest}" alt="ФК Зенит"></div>
    <div class="meta">
      <div class="stars">★ ★</div>
      <div><b>{g.html.escape(date_line)}</b></div>
      <div>{g.html.escape(extra)}</div>
      <div class="page-no">Лист {page} из 2</div>
    </div>
  </header>
  <div class="clubs">{clubs}</div>
  <div class="body-wrap">
    {body}
    <footer class="sheet-foot">
      <span><span class="badge">1925</span> · голубая строка — матч «Зенита»</span>
      <span>{foot_mid}</span>
      <span>Квадраты — счёт · печатать в цвете, поля «минимум»</span>
    </footer>
  </div>
  <div class="kit"><i></i><i></i><i></i></div>
</article>"""


def build_html(data: dict, only_page: int | None = None) -> str:
    uris = g.load_club_uris()
    logo_css, slugs = g.logo_classes(uris)
    clubs = g.clubs_strip(uris)
    rpl = g.data_uri(g.RPL_LOGO)
    crest = g.data_uri(g.ZENIT_CREST)
    by_group: dict[str, list[dict]] = defaultdict(list)
    for m in data["matches"]:
        by_group[m["group"]].append(m)
    groups_html = "".join(
        group_card(letter, data["groups"][letter], by_group[letter], slugs)
        for letter in "ABCD"
    )
    page1 = sheet(
        page=1,
        tag="Лист 1 · Путь РПЛ · групповой этап",
        date_line="4 августа — 26 ноября 2026",
        extra="Ничья → пенальти: 2 и 1 очко",
        body=f'<div class="groups">{groups_html}</div>',
        foot_mid="Группы A–D · 6 туров · 1–2 места в плей-офф Пути РПЛ",
        rpl=rpl, crest=crest, clubs=clubs,
    )
    regions = g.json.loads(REGIONS.read_text(encoding="utf-8"))["rounds"]
    reg_html = "".join(reg_round(rnd) for rnd in regions)
    page2 = sheet(
        page=2,
        tag="Лист 2 · Путь регионов · отбор и плей-офф",
        date_line="28 июля 2026 — 6 июня 2027",
        extra="Ничья → пенальти · с 4-го раунда — Первая лига",
        body=f'<div class="regions-page"><div class="reg-grid">{reg_html}</div>{playoff_block()}</div>',
        foot_mid="Раунды 1–6 Пути регионов · внизу сетка плей-офф до финала",
        rpl=rpl, crest=crest, clubs=clubs,
    )
    sheets = {1: page1, 2: page2}
    stage = sheets[only_page] if only_page in sheets else page1 + page2
    return f"""<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Зенит · Кубок России 2026/27 · A4</title>
<style>{css(logo_css)}</style>
</head>
<body>
  <div class="toolbar">
    <button onclick="window.print()">Печать / PDF</button>
    <span>Два листа <b>A4 альбомная</b>, цвет. Поля «минимум» или «нет», фон графики включён.</span>
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
    data = g.json.loads(DATA.read_text(encoding="utf-8"))
    if len(data["matches"]) != 48:
        raise SystemExit(f"expected 48 group matches, got {len(data['matches'])}")
    regions = g.json.loads(REGIONS.read_text(encoding="utf-8"))["rounds"]
    counts = {rnd["n"]: len(rnd["matches"]) for rnd in regions}
    if counts.get(1) != 12 or counts.get(3) != 14:
        raise SystemExit(f"unexpected region counts: {counts}")
    OUT.write_text(build_html(data), encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
