import AppIntents
import AppKit
import SwiftUI
import WidgetKit

struct CalendarConfigIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Календарь"
  static var description: IntentDescription = IntentDescription("Месяц и события из стандартного Календаря")

  @Parameter(title: "Неделя с понедельника", default: true)
  var startMonday: Bool

  @Parameter(title: "Номера недель", default: false)
  var weekNumbers: Bool

  @Parameter(title: "Праздники РФ", default: true)
  var holidays: Bool
}

struct CalendarEntry: TimelineEntry {
  let date: Date
  let displayedMonth: Date
  let selectedDate: Date
  let startMonday: Bool
  let weekNumbers: Bool
  let holidays: Bool
  let showRPL: Bool
  let showRussianCup: Bool
  let followedTeamName: String?
  let opponentInitials: [String: String]
  let opponentLogoURLs: [String: String]
  let events: [CalendarEventItem]
  let football: [FootballMatch]
  let agendaOffset: Int
  let hasAccess: Bool

  var visibleFootball: [FootballMatch] {
    football.filter { match in
      switch match.competition {
      case .rpl: return showRPL
      case .cup: return showRussianCup
      }
    }
  }

  var isCurrentMonth: Bool {
    CalendarMath.isSameMonth(displayedMonth, date)
  }
}

struct CalendarProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> CalendarEntry {
    makeEntry(configuration: CalendarConfigIntent(), now: Date())
  }

  func snapshot(for configuration: CalendarConfigIntent, in context: Context) async -> CalendarEntry {
    makeEntry(configuration: configuration, now: Date())
  }

  func timeline(for configuration: CalendarConfigIntent, in context: Context) async -> Timeline<CalendarEntry> {
    let entry = makeEntry(configuration: configuration, now: Date())
    let calendar = Calendar.current
    let midnight = calendar.nextDate(
      after: Date(),
      matching: DateComponents(hour: 0, minute: 1),
      matchingPolicy: .nextTime
    ) ?? Date().addingTimeInterval(3600)
    let soon = Date().addingTimeInterval(15 * 60)
    return Timeline(entries: [entry], policy: .after(min(midnight, soon)))
  }

  private func makeEntry(configuration: CalendarConfigIntent, now: Date) -> CalendarEntry {
    let calendar = Calendar.current
    let displayedMonth = clampedDisplayedMonth(now: now)
    if !CalendarMath.isSameMonth(CalendarNavigation.selectedDate, displayedMonth) {
      CalendarNavigation.snapSelectedDateToDisplayedMonth()
    }
    let selectedDate = CalendarNavigation.selectedDate
    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    var rangeStart = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
    var rangeEnd = calendar.date(byAdding: .month, value: 1, to: monthStart).flatMap {
      calendar.date(byAdding: .day, value: 7, to: $0)
    } ?? now
    if selectedDate < rangeStart { rangeStart = selectedDate }
    if selectedDate > rangeEnd { rangeEnd = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate }
    let football = FootballSchedule.matches(
      from: rangeStart,
      to: rangeEnd,
      includeRPL: true,
      includeCup: true
    )
    let followedTeamName = FollowedTeamNavigation.name
    var opponentInitials: [String: String] = [:]
    var opponentLogoURLs: [String: String] = [:]
    if let team = followedTeamName {
      for match in football where match.involves(team: team) {
        if let name = match.opponentName(for: team) {
          opponentInitials[match.dateKey] = String(name.prefix(1))
        }
        if let url = match.opponentLogoURL(for: team), !url.isEmpty {
          opponentLogoURLs[match.dateKey] = url
        }
      }
    }
    let cachedEvents = EventLoader.cachedEvents(from: rangeStart, to: rangeEnd)
    let options = WidgetNavStore.load()
    return CalendarEntry(
      date: now,
      displayedMonth: displayedMonth,
      selectedDate: selectedDate,
      startMonday: configuration.startMonday,
      weekNumbers: configuration.weekNumbers,
      holidays: configuration.holidays,
      showRPL: options.showRPL,
      showRussianCup: options.showRussianCup,
      followedTeamName: followedTeamName,
      opponentInitials: opponentInitials,
      opponentLogoURLs: opponentLogoURLs,
      events: cachedEvents,
      football: football,
      agendaOffset: CalendarNavigation.agendaOffset,
      hasAccess: options.hasCalendarAccess || !EventCache.load().isEmpty
    )
  }

  private func clampedDisplayedMonth(now: Date) -> Date {
    let displayed = CalendarNavigation.displayedMonth
    let years = Calendar.current.dateComponents([.year], from: now, to: displayed).year ?? 0
    if abs(years) > 1 {
      CalendarNavigation.goToToday()
      return CalendarNavigation.displayedMonth
    }
    return displayed
  }
}

struct MonthCalendarWidgetV2: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: CalendarWidgetKind.id,
      intent: CalendarConfigIntent.self,
      provider: CalendarProvider()
    ) { entry in
      CalendarWidgetView(entry: entry)
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .privacySensitive(false)
        .invalidatableContent()
        .containerBackground(for: .widget) {
          Color(nsColor: .windowBackgroundColor)
        }
    }
    .configurationDisplayName("Календарь")
    .description("Месяц, события Календаря и матчи РПЛ / Кубка России.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    .contentMarginsDisabled()
  }
}

@main
struct MonthCalendarWidgetV2Bundle: WidgetBundle {
  var body: some Widget {
    MonthCalendarWidgetV2()
  }
}

struct CalendarWidgetView: View {
  var entry: CalendarEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .systemSmall:
      SmallDateView(entry: entry)
    case .systemLarge:
      MonthGridView(entry: entry, eventLimit: 2)
    case .systemExtraLarge:
      ExtraLargeCalendarView(entry: entry)
    default:
      MonthGridView(entry: entry, eventLimit: 2)
    }
  }
}

struct MonthHeader: View {
  var entry: CalendarEntry
  var compact: Bool = false

  private var title: String {
    entry.displayedMonth
      .formatted(.dateTime.month(.wide).year().locale(CalendarMath.russian))
      .capitalized
  }

  var body: some View {
    let chevron: CGFloat = compact ? 18 : 22
    VStack(spacing: compact ? 1 : 2) {
      HStack(spacing: 4) {
        Button(intent: ShiftDisplayedPeriodIntent(months: -1)) {
          Image(systemName: "chevron.left")
            .font(.system(size: compact ? 11 : 12, weight: .bold))
            .frame(width: chevron, height: chevron)
        }
        .buttonStyle(.plain)

        Group {
          if entry.isCurrentMonth {
            Text(title)
          } else {
            Button(intent: GoToTodayIntent()) {
              HStack(spacing: 4) {
                Text(title)
                Circle().fill(Color.red).frame(width: 5, height: 5)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .frame(maxWidth: .infinity)

        Button(intent: ShiftDisplayedPeriodIntent(months: 1)) {
          Image(systemName: "chevron.right")
            .font(.system(size: compact ? 11 : 12, weight: .bold))
            .frame(width: chevron, height: chevron)
        }
        .buttonStyle(.plain)
      }

      Button(intent: ShiftFollowedTeamIntent(delta: 1)) {
        Text(entry.followedTeamName ?? FollowedTeamNavigation.noneTitle)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(entry.followedTeamName == nil ? Color.secondary : Color.green)
          .lineLimit(1)
          .frame(maxWidth: .infinity)
          .frame(height: compact ? 14 : 16)
      }
      .buttonStyle(.plain)
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct SmallDateView: View {
  var entry: CalendarEntry

  var body: some View {
    let calendar = Calendar.current
    let day = entry.selectedDate
    let weekday = day.formatted(.dateTime.weekday(.wide).locale(CalendarMath.russian))
    let month = day.formatted(.dateTime.month(.wide).locale(CalendarMath.russian))
    let holiday = entry.holidays ? RussianHolidays.name(on: day) : nil
    let dayEvents = entry.events.filter { $0.covers(day) }
    let dayFootball = entry.visibleFootball.filter { $0.dateKey == CalendarMath.dateKey(day) }

    VStack(alignment: .leading, spacing: 2) {
      Text(weekday.capitalized)
        .font(.caption.weight(.semibold))
        .foregroundStyle(CalendarMath.isSameDay(day, entry.date) ? .red : .secondary)
        .textCase(.uppercase)
      Text("\(calendar.component(.day, from: day))")
        .font(.system(size: 42, weight: .bold, design: .rounded))
      Text(month.capitalized)
        .font(.subheadline.weight(.medium))
      if let holiday {
        Text(holiday)
          .font(.caption)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if !dayFootball.isEmpty {
        ForEach(dayFootball.prefix(2)) { match in
          FootballMatchRow(match: match, compact: true)
        }
      } else if dayEvents.isEmpty {
        Text("Нет событий")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(dayEvents.prefix(3))) { event in
          HStack(spacing: 5) {
            Circle().fill(event.color.color).frame(width: 7, height: 7)
            Text(event.title)
              .font(.caption)
              .lineLimit(1)
          }
        }
      }
      MonthHeader(entry: entry, compact: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct MonthGridView: View {
  var entry: CalendarEntry
  var eventLimit: Int

  var body: some View {
    VStack(spacing: 2) {
      MonthHeader(entry: entry, compact: eventLimit > 0)
      calendarGrid
      if eventLimit > 0 {
        AgendaView(entry: entry, pageSize: eventLimit)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
  }

  private var calendarGrid: some View {
    let days = CalendarMath.monthGrid(for: entry.displayedMonth, startMonday: entry.startMonday)
    let labels = CalendarMath.weekdaySymbols(startMonday: entry.startMonday)
    return VStack(spacing: 0) {
      HStack(spacing: 0) {
        if entry.weekNumbers {
          Text("").frame(width: 16)
        }
        ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
          Text(label.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.bottom, 1)
      ForEach(0..<6, id: \.self) { row in
        HStack(spacing: 0) {
          if entry.weekNumbers {
            Text("\(CalendarMath.isoWeek(days[row * 7]))")
              .font(.system(size: 9))
              .foregroundStyle(.tertiary)
              .frame(width: 16)
          }
          ForEach(0..<7, id: \.self) { col in
            let date = days[row * 7 + col]
            let dateKey = CalendarMath.dateKey(date)
            DayCell(
              date: date,
              inMonth: CalendarMath.isSameMonth(date, entry.displayedMonth),
              isToday: CalendarMath.isSameDay(date, entry.date),
              isSelected: CalendarMath.isSameDay(date, entry.selectedDate),
              isWeekend: CalendarMath.isWeekend(date),
              isHoliday: entry.holidays && RussianHolidays.name(on: date) != nil,
              hasFootball: entry.visibleFootball.contains { $0.dateKey == dateKey },
              eventColors: entry.events.filter { $0.covers(date) }.prefix(3).map(\.color.color),
              opponentInitial: entry.opponentInitials[dateKey],
              opponentLogoURL: entry.opponentLogoURLs[dateKey],
              compact: eventLimit > 0
            )
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
  }
}

struct DayCell: View {
  var date: Date
  var inMonth: Bool
  var isToday: Bool
  var isSelected: Bool
  var isWeekend: Bool
  var isHoliday: Bool
  var hasFootball: Bool
  var eventColors: [Color]
  var opponentInitial: String? = nil
  var opponentLogoURL: String? = nil
  var compact: Bool = false

  var body: some View {
    let day = Calendar.current.component(.day, from: date)
    let side: CGFloat = compact ? 16 : 22
    VStack(spacing: 0) {
      Text("\(day)")
        .font(.system(size: compact ? 11 : 13, weight: isToday || isSelected ? .bold : .medium))
        .foregroundStyle(isToday ? .white : textColor)
        .frame(width: side, height: side)
        .background {
          if isToday {
            Circle().fill(Color.red)
          }
        }
        .overlay {
          if isSelected && !isToday {
            Circle().stroke(Color.primary, lineWidth: 1.2)
          }
        }
      HStack(spacing: 1) {
        if let opponentLogoURL {
          TeamLogoView(
            urlString: opponentLogoURL,
            name: opponentInitial ?? "•",
            side: compact ? 10 : 12
          )
        } else if let opponentInitial {
          Text(opponentInitial)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.green)
            .frame(width: 8, height: 8)
            .background(Color.green.opacity(0.2), in: Circle())
        } else if hasFootball {
          Image(systemName: "soccerball")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.green)
        }
        ForEach(Array(eventColors.enumerated()), id: \.offset) { _, color in
          Circle()
            .fill(color)
            .frame(width: 3, height: 3)
        }
      }
      .frame(height: compact ? 7 : 10)
    }
    .opacity(inMonth ? 1 : 0.35)
  }

  private var textColor: Color {
    if isHoliday || isWeekend { return .red }
    return .primary
  }
}

struct AgendaView: View {
  var entry: CalendarEntry
  var pageSize: Int

  var body: some View {
    let rows = agendaRows
    let total = rows.count
    let maxOffset = max(0, total - pageSize)
    let offset = min(max(0, entry.agendaOffset), maxOffset)
    let page = Array(rows.dropFirst(offset).prefix(pageSize))

    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 2) {
        Button(intent: ShiftSelectedDayIntent(days: -1)) {
          Image(systemName: "chevron.left")
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        Text(dayTitle)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Button(intent: ShiftSelectedDayIntent(days: 1)) {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        Spacer(minLength: 0)
      }

      if let holiday = entry.holidays ? RussianHolidays.name(on: entry.selectedDate) : nil {
        Text(holiday)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.red)
          .lineLimit(1)
      }

      if !entry.hasAccess && rows.isEmpty {
        Text("Нет доступа к календарям. Запустите приложение-контейнер и разрешите доступ.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if rows.isEmpty {
        Text("Нет событий")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(page) { row in
          switch row.kind {
          case .match(let match):
            FootballMatchRow(match: match, compact: true)
          case .event(let event):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Circle().fill(event.color.color).frame(width: 7, height: 7)
              Text(timeLabel(event))
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
              Text(event.title)
                .font(.caption)
                .lineLimit(2)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var dayTitle: String {
    entry.selectedDate
      .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(CalendarMath.russian))
      .capitalized
  }

  private var agendaRows: [AgendaRow] {
    let key = CalendarMath.dateKey(entry.selectedDate)
    let matches = entry.visibleFootball.filter { $0.dateKey == key }.map {
      AgendaRow(id: "m-\($0.id)", kind: .match($0))
    }
    let events = entry.events.filter { $0.covers(entry.selectedDate) }.map {
      AgendaRow(id: "e-\($0.id)", kind: .event($0))
    }
    return matches + events
  }

  private func timeLabel(_ event: CalendarEventItem) -> String {
    if event.isAllDay { return "весь день" }
    if CalendarMath.isSameDay(event.start, entry.selectedDate) {
      return event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(CalendarMath.russian))
    }
    return "…"
  }
}

private struct AgendaRow: Identifiable {
  enum Kind {
    case match(FootballMatch)
    case event(CalendarEventItem)
  }

  var id: String
  var kind: Kind
}

struct ExtraLargeCalendarView: View {
  var entry: CalendarEntry

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      MonthGridView(entry: entry, eventLimit: 0)
        .frame(maxWidth: .infinity)
      AgendaView(entry: entry, pageSize: 5)
        .frame(maxWidth: 340, alignment: .leading)
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
  }
}

struct FootballMatchRow: View {
  var match: FootballMatch
  var compact: Bool

  var body: some View {
    HStack(spacing: compact ? 5 : 6) {
      Text(match.competition.rawValue)
        .font(.system(size: compact ? 10 : 11, weight: .bold))
        .foregroundStyle(match.competition == .rpl ? Color.blue : Color.orange)
        .frame(width: compact ? 36 : 44, alignment: .leading)
      TeamLogoView(urlString: match.homeLogoURL, name: match.home, side: compact ? 16 : 22)
      Text(match.statusText)
        .font((compact ? Font.caption2 : Font.caption).monospacedDigit().weight(.semibold))
        .lineLimit(1)
      TeamLogoView(urlString: match.awayLogoURL, name: match.away, side: compact ? 16 : 22)
      Text("\(match.home) – \(match.away)")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }
}
