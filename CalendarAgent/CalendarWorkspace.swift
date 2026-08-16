import AppKit
import EventKit
import SwiftUI

extension Notification.Name {
  static let calendarAgentOpenSettings = Notification.Name("ru.rudenko.macCalendar.agent.openSettings")
}

@MainActor
final class CalendarWorkspace: ObservableObject {
  @Published var displayedMonth: Date
  @Published var selectedDate: Date
  @Published var events: [CalendarEventItem] = []
  @Published var football: [FootballMatchView] = []
  @Published var hasAccess = EventLoader.hasAccess
  @Published var isRefreshing = false
  @Published var draft: EventDraft?
  @Published var errorText: String?
  @Published var hoveredDate: Date?

  private var storeObserver: NSObjectProtocol?

  init() {
    let month = CalendarNavigation.displayedMonth
    displayedMonth = month
    selectedDate = CalendarNavigation.selectedDate
    if !CalendarMath.isSameMonth(selectedDate, month) {
      selectedDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month)) ?? month
    }
    reload()
    storeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: EventLoader.store,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
  }

  deinit {
    if let storeObserver {
      NotificationCenter.default.removeObserver(storeObserver)
    }
  }

  var startMonday: Bool { CalendarOptions.startMonday }
  var weekNumbers: Bool { CalendarOptions.weekNumbers }
  var holidays: Bool { CalendarOptions.holidays }
  var followedTeam: String? { FollowedTeamNavigation.name }

  var monthTitle: String {
    displayedMonth
      .formatted(.dateTime.month(.wide).year().locale(CalendarMath.russian))
      .capitalized
  }

  var selectedTitle: String {
    selectedDate
      .formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(CalendarMath.russian))
      .capitalized
  }

  var grid: [Date] {
    CalendarMath.monthGrid(for: displayedMonth, startMonday: startMonday)
  }

  var weekdayLabels: [String] {
    CalendarMath.weekdaySymbols(startMonday: startMonday)
  }

  var selectedHoliday: String? {
    holidays ? RussianHolidays.name(on: selectedDate) : nil
  }

  var selectedEvents: [CalendarEventItem] {
    events.filter { $0.covers(selectedDate) }
  }

  var selectedMatches: [FootballMatchView] {
    let key = CalendarMath.dateKey(selectedDate)
    return football.filter { $0.match.dateKey == key }
  }

  var upcomingMatches: [FootballMatchView] {
    let today = CalendarMath.dateKey(Date())
    return football
      .filter { $0.match.dateKey >= today }
      .filter { view in
        guard let team = followedTeam else { return true }
        return view.match.involves(team: team)
      }
      .prefix(6)
      .map { $0 }
  }

  var writableCalendars: [EKCalendar] {
    CalendarSelection.selectedCalendars().filter(\.allowsContentModifications)
  }

  func events(on date: Date) -> [CalendarEventItem] {
    events.filter { $0.covers(date) }
  }

  func matches(on date: Date) -> [FootballMatchView] {
    let key = CalendarMath.dateKey(date)
    return football.filter { $0.match.dateKey == key }
  }

  func opponentLogo(on date: Date) -> (url: String, name: String)? {
    guard let team = followedTeam else { return nil }
    guard let match = matches(on: date).map(\.match).first(where: { $0.involves(team: team) }) else { return nil }
    guard let url = match.opponentLogoURL(for: team), let name = match.opponentName(for: team) else { return nil }
    return (url, name)
  }

  func shiftMonth(_ delta: Int) {
    let calendar = Calendar.current
    displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
    snapSelectedDayToMonth()
    persistAndReload()
  }

  func shiftYear(_ delta: Int) {
    let calendar = Calendar.current
    displayedMonth = calendar.date(byAdding: .year, value: delta, to: displayedMonth) ?? displayedMonth
    snapSelectedDayToMonth()
    persistAndReload()
  }

  func shiftDay(_ delta: Int) {
    let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
    select(next)
  }

  func goToToday() {
    let today = Date()
    displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
    selectedDate = today
    persistAndReload()
  }

  func showMonth(_ date: Date) {
    displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    snapSelectedDayToMonth()
    persistAndReload()
  }

  func select(_ date: Date) {
    selectedDate = date
    if !CalendarMath.isSameMonth(date, displayedMonth) {
      displayedMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
      reload()
    }
    persistNav()
    CalendarWidgetKind.reload()
  }

  func openEditor(for item: CalendarEventItem? = nil) {
    draft = EventDraft(date: selectedDate, existing: item.flatMap(eventKitEvent(matching:)))
  }

  func save(_ draft: EventDraft) {
    errorText = nil
    let store = EventLoader.store
    let event = draft.existing ?? EKEvent(eventStore: store)
    event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Событие" : draft.title
    event.isAllDay = draft.isAllDay
    event.startDate = draft.start
    event.endDate = draft.isAllDay
      ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: draft.start)) ?? draft.start
      : draft.end
    if event.endDate <= event.startDate {
      event.endDate = event.startDate.addingTimeInterval(3600)
    }
    event.calendar = writableCalendars.first { $0.calendarIdentifier == draft.calendarID }
      ?? store.defaultCalendarForNewEvents
      ?? writableCalendars.first
    guard event.calendar != nil else {
      errorText = "Нет календаря, в который можно записать событие."
      return
    }
    do {
      try store.save(event, span: .thisEvent)
      self.draft = nil
      EventCache.syncFromEventKit()
      reload()
      CalendarWidgetKind.reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func delete(_ item: CalendarEventItem) {
    guard let event = eventKitEvent(matching: item) else { return }
    do {
      try EventLoader.store.remove(event, span: .thisEvent)
      EventCache.syncFromEventKit()
      reload()
      CalendarWidgetKind.reload()
    } catch {
      errorText = error.localizedDescription
    }
  }

  func refresh() async {
    isRefreshing = true
    defer { isRefreshing = false }
    await EventLoader.prepare()
    await FootballSchedule.syncAll()
    EventCache.syncFromEventKit()
    reload()
    CalendarWidgetKind.reload()
  }

  func reload() {
    hasAccess = EventLoader.hasAccess
    let calendar = Calendar.current
    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
    let rangeStart = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
    let rangeEnd = calendar.date(byAdding: .month, value: 1, to: monthStart).flatMap {
      calendar.date(byAdding: .day, value: 14, to: $0)
    } ?? displayedMonth
    events = EventLoader.events(from: rangeStart, to: rangeEnd)
    football = FootballSchedule.views(
      from: rangeStart,
      to: rangeEnd,
      includeRPL: CalendarOptions.showRPL,
      includeCup: CalendarOptions.showRussianCup
    )
  }

  private func snapSelectedDayToMonth() {
    if CalendarMath.isSameMonth(selectedDate, displayedMonth) { return }
    let calendar = Calendar.current
    let today = Date()
    if CalendarMath.isSameMonth(today, displayedMonth) {
      selectedDate = today
      return
    }
    let day = min(
      calendar.component(.day, from: selectedDate),
      calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 28
    )
    var parts = calendar.dateComponents([.year, .month], from: displayedMonth)
    parts.day = day
    selectedDate = calendar.date(from: parts) ?? displayedMonth
  }

  private func persistNav() {
    CalendarNavigation.displayedMonth = displayedMonth
    CalendarNavigation.selectDay(CalendarMath.dateKey(selectedDate))
  }

  private func persistAndReload() {
    persistNav()
    reload()
    CalendarWidgetKind.reload()
  }

  private func eventKitEvent(matching item: CalendarEventItem) -> EKEvent? {
    let start = item.start.addingTimeInterval(-2)
    let end = item.end.addingTimeInterval(2)
    let calendars = CalendarSelection.selectedCalendars()
    guard !calendars.isEmpty else { return nil }
    let predicate = EventLoader.store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return EventLoader.store.events(matching: predicate).first { event in
      (event.title ?? "") == item.title && abs((event.startDate ?? .distantPast).timeIntervalSince(item.start)) < 2
    }
  }
}

struct EventDraft: Identifiable {
  var id = UUID()
  var title: String
  var isAllDay: Bool
  var start: Date
  var end: Date
  var calendarID: String
  var existing: EKEvent?

  init(date: Date, existing: EKEvent?) {
    self.existing = existing
    if let existing {
      title = existing.title ?? ""
      isAllDay = existing.isAllDay
      start = existing.startDate ?? date
      end = existing.endDate ?? start.addingTimeInterval(3600)
      calendarID = existing.calendar?.calendarIdentifier ?? ""
    } else {
      let startOfDay = Calendar.current.startOfDay(for: date)
      let hour = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date) ?? startOfDay
      title = ""
      isAllDay = false
      start = hour
      end = hour.addingTimeInterval(3600)
      calendarID = EventLoader.store.defaultCalendarForNewEvents?.calendarIdentifier
        ?? CalendarSelection.selectedCalendars().first(where: \.allowsContentModifications)?.calendarIdentifier
        ?? ""
    }
  }
}

struct CalendarWorkspaceView: View {
  @StateObject private var workspace = CalendarWorkspace()
  @State private var showMonthPicker = false

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        toolbar
        if !workspace.hasAccess {
          accessBanner
        }
        weekdayHeader
        monthGrid
      }
      Divider()
      dayPanel
        .frame(width: 340)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .frame(minWidth: 980, minHeight: 620)
    .focusable()
    .focusEffectDisabled()
    .onKeyPress(.leftArrow) { workspace.shiftDay(-1); return .handled }
    .onKeyPress(.rightArrow) { workspace.shiftDay(1); return .handled }
    .onKeyPress(.upArrow) { workspace.shiftDay(-7); return .handled }
    .onKeyPress(.downArrow) { workspace.shiftDay(7); return .handled }
    .onAppear { workspace.reload() }
    .sheet(item: $workspace.draft) { draft in
      EventEditorView(draft: draft, calendars: workspace.writableCalendars) { saved in
        workspace.save(saved)
      } onCancel: {
        workspace.draft = nil
      }
    }
    .alert("Не удалось сохранить", isPresented: Binding(
      get: { workspace.errorText != nil },
      set: { if !$0 { workspace.errorText = nil } }
    )) {
      Button("OK", role: .cancel) { workspace.errorText = nil }
    } message: {
      Text(workspace.errorText ?? "")
    }
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      Button { workspace.shiftYear(-1) } label: {
        Image(systemName: "chevron.backward.2")
      }
      .help("Предыдущий год")
      Button { workspace.shiftMonth(-1) } label: {
        Image(systemName: "chevron.left")
      }
      .help("Предыдущий месяц")
      .keyboardShortcut(.leftArrow, modifiers: .command)

      Button {
        showMonthPicker.toggle()
      } label: {
        Text(workspace.monthTitle)
          .font(.title2.weight(.semibold))
          .foregroundStyle(.primary)
          .frame(minWidth: 220)
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showMonthPicker, arrowEdge: .bottom) {
        MonthPickerView(month: workspace.displayedMonth) { date in
          workspace.showMonth(date)
          showMonthPicker = false
        }
      }

      Button { workspace.shiftMonth(1) } label: {
        Image(systemName: "chevron.right")
      }
      .help("Следующий месяц")
      .keyboardShortcut(.rightArrow, modifiers: .command)
      Button { workspace.shiftYear(1) } label: {
        Image(systemName: "chevron.forward.2")
      }
      .help("Следующий год")

      Button("Сегодня") { workspace.goToToday() }
        .keyboardShortcut("t", modifiers: .command)

      Spacer()

      Picker("Команда", selection: followedTeamBinding) {
        Text(FollowedTeamNavigation.noneTitle).tag("")
        ForEach(FootballSchedule.followedTeamChoices(), id: \.self) { name in
          Text(name).tag(name)
        }
      }
      .frame(maxWidth: 180)

      Button {
        Task { await workspace.refresh() }
      } label: {
        if workspace.isRefreshing {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "arrow.clockwise")
        }
      }
      .help("Обновить")
      .keyboardShortcut("r", modifiers: .command)

      Button {
        NotificationCenter.default.post(name: .calendarAgentOpenSettings, object: nil)
      } label: {
        Image(systemName: "gearshape")
      }
      .help("Настройки")
      .keyboardShortcut(",", modifiers: .command)

      Button {
        workspace.openEditor()
      } label: {
        Image(systemName: "plus")
      }
      .help("Новое событие")
      .keyboardShortcut("n", modifiers: .command)
      .disabled(!workspace.hasAccess || workspace.writableCalendars.isEmpty)
    }
    .buttonStyle(.borderless)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var accessBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: "calendar.badge.exclamationmark")
        .foregroundStyle(.orange)
      Text("Нет доступа к календарям — матчи РПЛ всё равно видны. Разрешите доступ, чтобы показывать события.")
        .font(.callout)
      Spacer()
      Button("Настройки") {
        NotificationCenter.default.post(name: .calendarAgentOpenSettings, object: nil)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.12))
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      if workspace.weekNumbers {
        Text("").frame(width: 28)
      }
      ForEach(Array(workspace.weekdayLabels.enumerated()), id: \.offset) { _, label in
        Text(label.uppercased())
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 6)
  }

  private var monthGrid: some View {
    let days = workspace.grid
    return GeometryReader { geo in
      let rows: CGFloat = 6
      let rowHeight = geo.size.height / rows
      VStack(spacing: 0) {
        ForEach(0..<6, id: \.self) { row in
          HStack(spacing: 0) {
            if workspace.weekNumbers {
              Text("\(CalendarMath.isoWeek(days[row * 7]))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: rowHeight)
            }
            ForEach(0..<7, id: \.self) { col in
              let date = days[row * 7 + col]
              DayCellView(
                date: date,
                displayedMonth: workspace.displayedMonth,
                selectedDate: workspace.selectedDate,
                hovered: workspace.hoveredDate.map { CalendarMath.isSameDay($0, date) } ?? false,
                holidaysEnabled: workspace.holidays,
                events: workspace.events(on: date),
                matches: workspace.matches(on: date),
                opponent: workspace.opponentLogo(on: date)
              )
              .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
              .contentShape(Rectangle())
              .onHover { inside in
                workspace.hoveredDate = inside ? date : nil
              }
              .onTapGesture(count: 2) {
                workspace.select(date)
                workspace.openEditor()
              }
              .onTapGesture {
                workspace.select(date)
              }
              .contextMenu {
                Button("Выбрать день") { workspace.select(date) }
                Button("Новое событие") {
                  workspace.select(date)
                  workspace.openEditor()
                }
                .disabled(!workspace.hasAccess)
                Button("Сегодня") { workspace.goToToday() }
              }
            }
          }
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.bottom, 8)
  }

  private var dayPanel: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text(workspace.selectedTitle)
          .font(.title3.weight(.semibold))
        if let holiday = workspace.selectedHoliday {
          Text(holiday)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.red)
        }
      }
      .padding(16)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if !workspace.selectedMatches.isEmpty {
            sectionTitle("Матчи")
            ForEach(workspace.selectedMatches) { view in
              MatchCard(view: view)
            }
          }

          sectionTitle("События")
          if workspace.selectedEvents.isEmpty {
            Text("Нет событий")
              .foregroundStyle(.secondary)
              .font(.callout)
          } else {
            ForEach(workspace.selectedEvents) { event in
              EventRow(event: event, selectedDate: workspace.selectedDate) {
                workspace.openEditor(for: event)
              } onDelete: {
                workspace.delete(event)
              }
            }
          }

          Button {
            workspace.openEditor()
          } label: {
            Label("Новое событие", systemImage: "plus")
              .frame(maxWidth: .infinity)
          }
          .disabled(!workspace.hasAccess || workspace.writableCalendars.isEmpty)

          if !workspace.upcomingMatches.isEmpty {
            sectionTitle(workspace.followedTeam.map { "Ближайшие матчи · \($0)" } ?? "Ближайшие матчи")
            ForEach(workspace.upcomingMatches) { view in
              Button {
                if let date = CalendarNavigation.date(fromKey: view.match.dateKey) {
                  workspace.select(date)
                }
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(matchDateLabel(view.match.dateKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  MatchCard(view: view)
                }
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(16)
      }

      Divider()
      HStack {
        Button("Открыть Календарь Apple") {
          SystemLinks.openCalendarApp()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .font(.caption)
        Spacer()
      }
      .padding(12)
    }
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var followedTeamBinding: Binding<String> {
    Binding(
      get: { workspace.followedTeam ?? "" },
      set: { value in
        FollowedTeamNavigation.name = value.isEmpty ? nil : value
        workspace.reload()
        CalendarWidgetKind.reload()
        workspace.objectWillChange.send()
      }
    )
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(.headline)
  }

  private func matchDateLabel(_ key: String) -> String {
    guard let date = CalendarNavigation.date(fromKey: key) else { return key }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(CalendarMath.russian)).capitalized
  }
}

struct DayCellView: View {
  var date: Date
  var displayedMonth: Date
  var selectedDate: Date
  var hovered: Bool
  var holidaysEnabled: Bool
  var events: [CalendarEventItem]
  var matches: [FootballMatchView]
  var opponent: (url: String, name: String)?

  var body: some View {
    let inMonth = CalendarMath.isSameMonth(date, displayedMonth)
    let isToday = CalendarMath.isSameDay(date, Date())
    let isSelected = CalendarMath.isSameDay(date, selectedDate)
    let isHoliday = holidaysEnabled && RussianHolidays.name(on: date) != nil
    let weekend = CalendarMath.isWeekend(date)

    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text("\(Calendar.current.component(.day, from: date))")
          .font(.system(size: 13, weight: isToday || isSelected ? .bold : .semibold))
          .foregroundStyle(isToday ? Color.white : numberColor(holiday: isHoliday, weekend: weekend))
          .frame(width: 24, height: 24)
          .background {
            if isToday {
              Circle().fill(Color.red)
            } else if isSelected {
              Circle().stroke(Color.accentColor, lineWidth: 1.5)
            }
          }
        Spacer(minLength: 0)
        if let opponent {
          TeamLogoView(urlString: opponent.url, name: opponent.name, side: 16)
        } else if !matches.isEmpty {
          Image(systemName: "sportscourt")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.green)
        }
      }

              ForEach(Array(matches.prefix(1))) { view in
        Text("\(view.match.home) – \(view.match.away)")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.green)
          .lineLimit(1)
      }

              ForEach(Array(events.prefix(matches.isEmpty ? 3 : 2))) { event in
        HStack(spacing: 4) {
          Capsule().fill(event.color.color).frame(width: 3, height: 11)
          Text(event.title)
            .font(.system(size: 10))
            .lineLimit(1)
        }
      }

      if events.count > (matches.isEmpty ? 3 : 2) {
        Text("ещё \(events.count - (matches.isEmpty ? 3 : 2))")
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(cellBackground(inMonth: inMonth, selected: isSelected, hovered: hovered))
    .overlay(Rectangle().stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    .opacity(inMonth ? 1 : 0.42)
  }

  private func numberColor(holiday: Bool, weekend: Bool) -> Color {
    if holiday || weekend { return .red }
    return .primary
  }

  private func cellBackground(inMonth: Bool, selected: Bool, hovered: Bool) -> Color {
    if selected { return Color.accentColor.opacity(0.12) }
    if hovered { return Color.primary.opacity(0.05) }
    return Color.clear
  }
}

struct MatchCard: View {
  var view: FootballMatchView

  var body: some View {
    HStack(spacing: 8) {
      Text(view.match.competition.rawValue)
        .font(.caption.weight(.bold))
        .foregroundStyle(view.match.competition == .rpl ? Color.blue : Color.orange)
        .frame(width: 44, alignment: .leading)
      logo(view.homeLogo, name: view.match.home)
      Text(view.match.statusText)
        .font(.callout.monospacedDigit().weight(.semibold))
      logo(view.awayLogo, name: view.match.away)
      Text("\(view.match.home) – \(view.match.away)")
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .padding(8)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private func logo(_ data: Data?, name: String) -> some View {
    if let data, let image = NSImage(data: data) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: 22, height: 22)
    } else {
      Text(String(name.prefix(1)))
        .font(.caption.weight(.bold))
        .frame(width: 22, height: 22)
        .background(Color.secondary.opacity(0.15), in: Circle())
    }
  }
}

struct EventRow: View {
  var event: CalendarEventItem
  var selectedDate: Date
  var onEdit: () -> Void
  var onDelete: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Capsule().fill(event.color.color).frame(width: 4, height: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.body.weight(.medium))
        Text(timeLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(8)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    .contentShape(Rectangle())
    .onTapGesture(count: 2, perform: onEdit)
    .contextMenu {
      Button("Изменить", action: onEdit)
      Button("Удалить", role: .destructive, action: onDelete)
    }
  }

  private var timeLabel: String {
    if event.isAllDay { return "весь день" }
    if CalendarMath.isSameDay(event.start, selectedDate) {
      return event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(CalendarMath.russian))
    }
    return "…"
  }
}

struct MonthPickerView: View {
  var month: Date
  var onPick: (Date) -> Void
  @State private var year: Int

  init(month: Date, onPick: @escaping (Date) -> Void) {
    self.month = month
    self.onPick = onPick
    _year = State(initialValue: Calendar.current.component(.year, from: month))
  }

  var body: some View {
    let calendar = Calendar.current
    let currentMonth = calendar.component(.month, from: month)
    VStack(spacing: 12) {
      HStack {
        Button { year -= 1 } label: {
          Image(systemName: "chevron.left")
        }
        Text(String(year))
          .font(.headline)
          .frame(minWidth: 80)
        Button { year += 1 } label: {
          Image(systemName: "chevron.right")
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
        ForEach(1...12, id: \.self) { value in
          let date = calendar.date(from: DateComponents(year: year, month: value, day: 1)) ?? month
          Button {
            onPick(date)
          } label: {
            Text(date.formatted(.dateTime.month(.abbreviated).locale(CalendarMath.russian)).capitalized)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 6)
              .background(
                value == currentMonth && year == calendar.component(.year, from: month)
                  ? Color.accentColor.opacity(0.2)
                  : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(16)
    .frame(width: 280)
  }
}

struct EventEditorView: View {
  @State var draft: EventDraft
  var calendars: [EKCalendar]
  var onSave: (EventDraft) -> Void
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.existing == nil ? "Новое событие" : "Событие")
        .font(.title2.weight(.semibold))
      TextField("Название", text: $draft.title)
        .textFieldStyle(.roundedBorder)
      Toggle("Весь день", isOn: $draft.isAllDay)
      DatePicker(draft.isAllDay ? "День" : "Начало", selection: $draft.start, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
      if !draft.isAllDay {
        DatePicker("Конец", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
      }
      if !calendars.isEmpty {
        Picker("Календарь", selection: $draft.calendarID) {
          ForEach(calendars, id: \.calendarIdentifier) { calendar in
            Text(calendar.title).tag(calendar.calendarIdentifier)
          }
        }
      }
      Spacer()
      HStack {
        Button("Отмена", role: .cancel, action: onCancel)
        Spacer()
        Button("Сохранить") { onSave(draft) }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 420, height: 320)
  }
}
