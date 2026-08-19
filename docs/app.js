const MONTHS = [
  "января", "февраля", "марта", "апреля", "мая", "июня",
  "июля", "августа", "сентября", "октября", "ноября", "декабря",
];
const WEEKDAYS = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"];

const state = {
  data: null,
  tab: "table",
  tour: "next",
  team: "",
  timer: null,
  livePoints: localStorage.getItem("rpl-live-points") === "1",
  expandedId: null,
};

const $ = (id) => document.getElementById("" + id);

function esc(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function todayKey(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Moscow",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const pick = (type) => parts.find((part) => part.type === type).value;
  return `${pick("year")}-${pick("month")}-${pick("day")}`;
}

function fmtDate(iso) {
  const [year, month, day] = iso.split("-").map(Number);
  const local = new Date(year, month - 1, day);
  return `${day} ${MONTHS[month - 1]}, ${WEEKDAYS[local.getDay()]}`;
}

function fmtUpdated(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "нет отметки";
  return new Intl.DateTimeFormat("ru-RU", {
    timeZone: "Europe/Moscow",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function logo(slug) {
  return `assets/clubs/${slug}.png`;
}

function zone(rank) {
  if (rank <= 3) return "euro";
  if (rank >= 15) return "down";
  if (rank >= 13) return "play";
  return "";
}

function currentTour(matches) {
  const live = matches.find((match) => match.status === "live");
  if (live) return live.tour;
  const today = todayKey();
  const upcoming = matches.find((match) => match.status === "scheduled" && match.date >= today);
  if (upcoming) return upcoming.tour;
  return Math.max(...matches.map((match) => match.tour));
}

function scoreText(match) {
  if (match.status === "finished" || match.status === "live") {
    const home = match.homeScore ?? "–";
    const away = match.awayScore ?? "–";
    return `${home}:${away}`;
  }
  return match.time || "TBA";
}

function minuteKey(minute) {
  const text = String(minute || "").replace("'", "");
  const parts = text.split("+").map((part) => parseInt(part, 10) || 0);
  return (parts[0] || 0) * 100 + (parts[1] || 0);
}

function eventWho(event) {
  if (event.type === "goal" || event.type === "own_goal") {
    const note = event.type === "own_goal" ? "автогол" : event.assist;
    return `<span class="who">
      <i class="ico ${event.type}"></i>
      <span>${esc(event.player || "гол")}${note ? `<small>${esc(note)}</small>` : ""}</span>
    </span>`;
  }
  if (event.type === "yellow" || event.type === "red") {
    return `<span class="who"><i class="ico ${event.type}"></i><span>${esc(event.player || "карточка")}</span></span>`;
  }
  if (event.type === "sub") {
    return `<span class="who sub">
      <i class="ico sub"></i>
      <span><b class="in">${esc(event.playerIn || "")}</b><b class="out">${esc(event.playerOut || "")}</b></span>
    </span>`;
  }
  return "";
}

function matchDetails(match) {
  if (state.expandedId !== match.id) return "";
  if (match.status === "scheduled") {
    return `<div class="match-acc"><p class="acc-empty">События появятся после начала матча</p></div>`;
  }
  const events = [...(match.events || [])].sort((a, b) => minuteKey(a.minute) - minuteKey(b.minute));
  if (!events.length) {
    return `<div class="match-acc"><p class="acc-empty">Протокол ещё не загружен</p></div>`;
  }
  const rows = events.map((event) => `<li class="ev">
    <div class="col home">${event.side === "home" ? eventWho(event) : ""}</div>
    <div class="min">${esc(event.minute)}</div>
    <div class="col away">${event.side === "away" ? eventWho(event) : ""}</div>
  </li>`).join("");
  const meta = [match.stadium, match.referee ? `судья ${match.referee}` : ""]
    .filter(Boolean)
    .map(esc)
    .join(" · ");
  const stats = (match.stats || []).map((row) => `<div class="stat">
    <b>${esc(row.home)}</b><span>${esc(row.name)}</span><b>${esc(row.away)}</b>
  </div>`).join("");
  return `<div class="match-acc">
    ${meta ? `<p class="acc-meta">${meta}</p>` : ""}
    <ol class="events">${rows}</ol>
    ${stats ? `<div class="mini-stats">${stats}</div>` : ""}
  </div>`;
}

function resultOf(match, team) {
  const homeScore = Number(match.homeScore);
  const awayScore = Number(match.awayScore);
  if (!Number.isFinite(homeScore) || !Number.isFinite(awayScore)) return null;
  const scored = match.home === team ? homeScore : awayScore;
  const conceded = match.home === team ? awayScore : homeScore;
  if (scored > conceded) return "W";
  if (scored < conceded) return "L";
  return "D";
}

function teamForm(matches, team, includeLive) {
  return matches
    .filter((match) => {
      if (match.home !== team && match.away !== team) return false;
      if (match.homeScore == null || match.awayScore == null) return false;
      return match.status === "finished" || (includeLive && match.status === "live");
    })
    .sort((a, b) => a.date.localeCompare(b.date) || (a.time || "").localeCompare(b.time || ""))
    .map((match) => ({
      result: resultOf(match, team),
      live: match.status === "live",
      opponent: match.home === team ? match.away : match.home,
    }))
    .filter((item) => item.result);
}

function applyLiveResult(home, away, homeScore, awayScore) {
  home.played += 1;
  away.played += 1;
  home.goalsFor += homeScore;
  home.goalsAgainst += awayScore;
  away.goalsFor += awayScore;
  away.goalsAgainst += homeScore;
  home.goalDiff = home.goalsFor - home.goalsAgainst;
  away.goalDiff = away.goalsFor - away.goalsAgainst;
  if (homeScore > awayScore) {
    home.won += 1;
    home.points += 3;
    away.lost += 1;
  } else if (homeScore < awayScore) {
    away.won += 1;
    away.points += 3;
    home.lost += 1;
  } else {
    home.drawn += 1;
    away.drawn += 1;
    home.points += 1;
    away.points += 1;
  }
}

function displayedStandings(data) {
  const rows = data.standings.map((row) => ({
    ...row,
    baseRank: row.rank,
    liveApplied: false,
  }));
  if (!state.livePoints) return { rows, liveCount: 0 };

  const byName = new Map(rows.map((row) => [row.team, row]));
  let liveCount = 0;
  for (const match of data.matches) {
    if (match.status !== "live") continue;
    const homeScore = Number(match.homeScore);
    const awayScore = Number(match.awayScore);
    if (!Number.isFinite(homeScore) || !Number.isFinite(awayScore)) continue;
    const home = byName.get(match.home);
    const away = byName.get(match.away);
    if (!home || !away) continue;
    applyLiveResult(home, away, homeScore, awayScore);
    home.liveApplied = true;
    away.liveApplied = true;
    liveCount += 1;
  }
  if (!liveCount) return { rows, liveCount: 0 };

  rows.sort(
    (a, b) =>
      b.points - a.points
      || b.goalDiff - a.goalDiff
      || b.goalsFor - a.goalsFor
      || a.team.localeCompare(b.team, "ru")
  );
  rows.forEach((row, index) => {
    row.rank = index + 1;
  });
  return { rows, liveCount };
}

function formLabel(item) {
  const word = item.result === "W" ? "Победа" : item.result === "L" ? "Поражение" : "Ничья";
  return item.live ? `${word} (сейчас) vs ${item.opponent}` : `${word} vs ${item.opponent}`;
}

function matchesForView(data) {
  let rows = data.matches;
  if (state.team) {
    rows = rows.filter((match) => match.home === state.team || match.away === state.team);
  }
  if (state.tab === "results" || state.tour === "results") {
    return rows.filter((match) => match.status === "finished").slice().reverse();
  }
  if (state.tour === "all") return rows;
  if (state.tour === "next") {
    const tour = currentTour(data.matches);
    return rows.filter((match) => match.tour === tour);
  }
  return rows.filter((match) => match.tour === Number(state.tour));
}

function renderStandings(data) {
  const { rows, liveCount } = displayedStandings(data);
  $("table-note").textContent = state.livePoints && liveCount
    ? `Учтён текущий счёт ${liveCount} ${liveCount === 1 ? "матча" : "матчей"}`
    : state.livePoints
      ? "Нет live-матчей — таблица без изменений"
      : "Очки по завершённым матчам";

  $("standings").innerHTML = rows
    .map((row) => {
      const on = state.team === row.team ? " is-on" : "";
      const zenit = row.slug === "zenit" ? " zenit" : "";
      const form = teamForm(data.matches, row.team, state.livePoints)
        .map((item) => `<i class="${item.result}${item.live ? " is-live" : ""}" title="${formLabel(item)}"></i>`)
        .join("");
      const diff = row.goalDiff > 0 ? `+${row.goalDiff}` : `${row.goalDiff}`;
      const move = (row.baseRank || row.rank) - row.rank;
      const shift = move > 0
        ? `<span class="shift up">▲${move}</span>`
        : move < 0
          ? `<span class="shift down">▼${Math.abs(move)}</span>`
          : "";
      return `<tr class="${zone(row.rank)}${on}${zenit}" data-team="${row.team}">
        <td class="num">${row.rank}${shift}</td>
        <td class="club">
          <span class="club-cell">
            <img src="${logo(row.slug)}" alt="">
            <b>${row.team}</b>
          </span>
        </td>
        <td>${row.played}</td>
        <td>${row.won}</td>
        <td>${row.drawn}</td>
        <td>${row.lost}</td>
        <td class="wide">${row.goalsFor}:${row.goalsAgainst}</td>
        <td>${diff}</td>
        <td class="pts${row.liveApplied ? " live-pts" : ""}">${row.points}</td>
        <td class="form-col"><div class="form-scroll"><span class="form">${form}</span></div></td>
      </tr>`;
    })
    .join("");

  requestAnimationFrame(() => {
    document.querySelectorAll(".form-scroll").forEach((node) => {
      node.scrollLeft = node.scrollWidth;
    });
  });
}

function renderPills(data) {
  const tours = [...new Set(data.matches.map((match) => match.tour))].sort((a, b) => a - b);
  const liveTours = new Set(
    data.matches.filter((match) => match.status === "live").map((match) => match.tour)
  );
  const resultsOn = state.tab === "results" || state.tour === "results";
  const buttons = [
    `<button type="button" class="pill${state.tour === "next" && !resultsOn ? " is-on" : ""}" data-tour="next">Сейчас</button>`,
    `<button type="button" class="pill${resultsOn ? " is-on" : ""}" data-tour="results">Итоги</button>`,
    `<button type="button" class="pill${state.tour === "all" && !resultsOn ? " is-on" : ""}" data-tour="all">Все</button>`,
    ...tours.map((tour) => {
      const on = String(state.tour) === String(tour) ? " is-on" : "";
      const live = liveTours.has(tour) ? " live" : "";
      return `<button type="button" class="pill${on}${live}" data-tour="${tour}">${tour}</button>`;
    }),
  ];
  $("tour-pills").innerHTML = buttons.join("");
}

function renderMatches(data) {
  const rows = matchesForView(data);
  const live = data.matches.filter((match) => match.status === "live");
  const strip = $("live-strip");
  if (live.length) {
    strip.hidden = false;
    strip.innerHTML = `<span class="pulse"></span>Идёт ${live.length} ${live.length === 1 ? "матч" : "матча"}`;
  } else {
    strip.hidden = true;
    strip.innerHTML = "";
  }

  const title = (state.tab === "results" || state.tour === "results")
    ? "Результаты"
    : state.tour === "all"
      ? "Все туры"
      : `Тур ${state.tour === "next" ? currentTour(data.matches) : state.tour}`;
  $("matches-title").textContent = title;

  if (!rows.length) {
    $("match-list").innerHTML = `<p class="empty">Матчей нет</p>`;
    return;
  }

  let lastDay = "";
  const html = [];
  for (const match of rows) {
    if (match.date !== lastDay) {
      lastDay = match.date;
      html.push(`<div class="day-label">${fmtDate(match.date)}</div>`);
    }
    const zenit = match.homeSlug === "zenit" || match.awaySlug === "zenit" ? " zenit" : "";
    const liveCls = match.status === "live" ? " live" : "";
    const dim = state.team && match.home !== state.team && match.away !== state.team ? " is-dim" : "";
    const caption = match.status === "live"
      ? `<small class="live-min"><span class="pulse"></span>${match.live || "LIVE"}</small>`
      : match.status === "finished"
        ? `<small>итог</small>`
        : `<small>${match.time ? "МСК" : "дата"}</small>`;
    html.push(`<div class="match-wrap${zenit}${liveCls}${dim}${state.expandedId === match.id ? " open" : ""}" data-id="${esc(match.id)}">
      <article class="match">
        <div class="side home">
          <img class="crest" src="${logo(match.homeSlug)}" alt="">
          <span>${esc(match.home)}</span>
        </div>
        <div class="scorebox">
          <b>${esc(scoreText(match))}</b>
          ${caption}
        </div>
        <div class="side away">
          <span>${esc(match.away)}</span>
          <img class="crest" src="${logo(match.awaySlug)}" alt="">
        </div>
      </article>
      ${matchDetails(match)}
    </div>`);
  }
  $("match-list").innerHTML = html.join("");
}

function fillTeams(data) {
  const select = $("team-filter");
  const current = state.team;
  const names = displayedStandings(data).rows.map((row) => row.team);
  select.innerHTML = `<option value="">Все клубы</option>` + names
    .map((name) => `<option value="${name}">${name}</option>`)
    .join("");
  select.value = current;
}

function render() {
  const data = state.data;
  if (!data) return;
  document.querySelector(".layout").className = `layout is-${state.tab}`;
  document.querySelectorAll(".tab").forEach((button) => {
    button.classList.toggle("is-on", button.dataset.tab === state.tab);
  });
  $("updated").textContent = `Обновлено ${fmtUpdated(data.updatedAt)} · ${data.season}`;
  renderStandings(data);
  fillTeams(data);
  renderPills(data);
  renderMatches(data);
}

function scheduleRefresh(data) {
  clearInterval(state.timer);
  const live = data.matches.some((match) => match.status === "live");
  state.timer = setInterval(load, live ? 15000 : 60000);
}

async function load() {
  const response = await fetch(`data/rpl.json?t=${Date.now()}`, { cache: "no-store" });
  if (!response.ok) throw new Error("Нет данных");
  state.data = await response.json();
  render();
  scheduleRefresh(state.data);
}

$("live-points").checked = state.livePoints;
$("live-points").addEventListener("change", (event) => {
  state.livePoints = event.target.checked;
  localStorage.setItem("rpl-live-points", state.livePoints ? "1" : "0");
  render();
});

$("reload").addEventListener("click", () => {
  $("updated").textContent = "Обновляю…";
  load().catch((error) => {
    $("updated").textContent = error.message;
  });
});

document.querySelectorAll(".tab").forEach((button) => {
  button.addEventListener("click", () => {
    state.tab = button.dataset.tab;
    if (state.tab === "results") state.tour = "results";
    if (state.tab === "matches" && (state.tour === "all" || state.tour === "results")) state.tour = "next";
    render();
  });
});

$("tour-pills").addEventListener("click", (event) => {
  const button = event.target.closest("[data-tour]");
  if (!button) return;
  state.tour = button.dataset.tour;
  state.tab = state.tour === "results" ? "results" : "matches";
  render();
});

$("team-filter").addEventListener("change", (event) => {
  state.team = event.target.value;
  render();
});

$("match-list").addEventListener("click", (event) => {
  const head = event.target.closest("article.match");
  if (!head) return;
  const wrap = head.closest(".match-wrap");
  if (!wrap) return;
  state.expandedId = state.expandedId === wrap.dataset.id ? null : wrap.dataset.id;
  renderMatches(state.data);
});

$("standings").addEventListener("click", (event) => {
  if (event.target.closest(".form-scroll")) return;
  const row = event.target.closest("tr[data-team]");
  if (!row) return;
  state.team = state.team === row.dataset.team ? "" : row.dataset.team;
  state.tab = window.matchMedia("(max-width: 900px)").matches ? "matches" : state.tab;
  render();
});

load().catch((error) => {
  $("updated").textContent = error.message;
  $("match-list").innerHTML = `<p class="empty">${error.message}. Запустите <code>python docs/update.py</code>.</p>`;
});
