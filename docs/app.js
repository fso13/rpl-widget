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
};

const $ = (id) => document.getElementById(id);

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
  $("standings").innerHTML = data.standings
    .map((row) => {
      const on = state.team === row.team ? " is-on" : "";
      const zenit = row.slug === "zenit" ? " zenit" : "";
      const form = (row.form || [])
        .map((item) => `<i class="${item}">${item}</i>`)
        .join("");
      const diff = row.goalDiff > 0 ? `+${row.goalDiff}` : `${row.goalDiff}`;
      return `<tr class="${zone(row.rank)}${on}${zenit}" data-team="${row.team}">
        <td class="num">${row.rank}</td>
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
        <td class="pts">${row.points}</td>
        <td class="form-col"><span class="form">${form}</span></td>
      </tr>`;
    })
    .join("");
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
    html.push(`<article class="match${zenit}${liveCls}${dim}">
      <div class="side home">
        <img class="crest" src="${logo(match.homeSlug)}" alt="">
        <span>${match.home}</span>
      </div>
      <div class="scorebox">
        <b>${scoreText(match)}</b>
        ${caption}
      </div>
      <div class="side away">
        <span>${match.away}</span>
        <img class="crest" src="${logo(match.awaySlug)}" alt="">
      </div>
    </article>`);
  }
  $("match-list").innerHTML = html.join("");
}

function fillTeams(data) {
  const select = $("team-filter");
  const current = state.team;
  const names = data.standings.map((row) => row.team);
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

$("standings").addEventListener("click", (event) => {
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
