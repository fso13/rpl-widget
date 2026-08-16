import Darwin
import EventKit
import Foundation
import SwiftUI
import WidgetKit

enum EventLoader {
  static let store = EKEventStore()

  static var hasAccess: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  static func prepare() async {
    if !hasAccess {
      _ = try? await store.requestFullAccessToEvents()
    }
    store.refreshSourcesIfNecessary()
  }

  static func events(from start: Date, to end: Date) -> [CalendarEventItem] {
    let fromStore = eventsFromStore(from: start, to: end)
    if !fromStore.isEmpty { return fromStore }
    return cachedEvents(from: start, to: end)
  }

  static func cachedEvents(from start: Date, to end: Date) -> [CalendarEventItem] {
    EventCache.load().filter { $0.start < end && $0.end > start }
  }

  static func eventsFromStore(from start: Date, to end: Date) -> [CalendarEventItem] {
    guard hasAccess else { return [] }
    let calendars = CalendarSelection.selectedCalendars()
    guard !calendars.isEmpty else { return [] }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return store.events(matching: predicate)
      .map(CalendarEventItem.init)
      .sorted { lhs, rhs in
        if lhs.start == rhs.start { return lhs.title < rhs.title }
        return lhs.start < rhs.start
      }
  }
}

enum CalendarSelection {
  static var enabledIDs: Set<String>? {
    get {
      guard let ids = WidgetNavStore.load().enabledCalendarIDs else { return nil }
      return Set(ids)
    }
    set {
      WidgetNavStore.update { $0.enabledCalendarIDs = newValue.map { Array($0).sorted() } }
    }
  }

  static func availableCalendars() -> [EKCalendar] {
    guard EventLoader.hasAccess else { return [] }
    return EventLoader.store.calendars(for: .event).sorted { lhs, rhs in
      let leftSource = lhs.source.title
      let rightSource = rhs.source.title
      if leftSource != rightSource {
        return leftSource.localizedCompare(rightSource) == .orderedAscending
      }
      return lhs.title.localizedCompare(rhs.title) == .orderedAscending
    }
  }

  static func selectedCalendars() -> [EKCalendar] {
    let all = availableCalendars()
    guard let enabled = enabledIDs else { return all }
    return all.filter { enabled.contains($0.calendarIdentifier) }
  }

  static func isEnabled(_ calendar: EKCalendar) -> Bool {
    guard let enabled = enabledIDs else { return true }
    return enabled.contains(calendar.calendarIdentifier)
  }

  static func setEnabled(_ calendar: EKCalendar, enabled: Bool) {
    var next = enabledIDs ?? Set(availableCalendars().map(\.calendarIdentifier))
    if enabled {
      next.insert(calendar.calendarIdentifier)
    } else {
      next.remove(calendar.calendarIdentifier)
    }
    enabledIDs = next
  }

  static func setAll(enabled: Bool) {
    if enabled {
      enabledIDs = nil
    } else {
      enabledIDs = []
    }
  }
}

enum AppSupport {
  static var directory: URL {
    let dir = realHome.appendingPathComponent("Library/Application Support/ru.rudenko.macCalendar")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Sandboxed widget `homeDirectoryForCurrentUser` is the container.
  /// Host writes to the real home; the widget entitlement allows that path.
  static var realHome: URL {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
      let path = String(cString: dir)
      if !path.isEmpty {
        return URL(fileURLWithPath: path, isDirectory: true)
      }
    }
    return FileManager.default.homeDirectoryForCurrentUser
  }
}

enum CalendarWidgetKind {
  static let id = "MonthCalendarWidget"

  static func reload() {
    WidgetCenter.shared.reloadTimelines(ofKind: id)
    WidgetCenter.shared.reloadAllTimelines()
  }
}

enum EventCache {
  static var fileURL: URL {
    AppSupport.directory.appendingPathComponent("events.json")
  }

  static func syncFromEventKit() {
    let calendar = Calendar.current
    let now = Date()
    let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
    let end = calendar.date(byAdding: .month, value: 18, to: now) ?? now
    save(EventLoader.eventsFromStore(from: start, to: end))
  }

  static func save(_ events: [CalendarEventItem]) {
    guard let data = try? JSONEncoder().encode(events) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  static func load() -> [CalendarEventItem] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    return (try? JSONDecoder().decode([CalendarEventItem].self, from: data)) ?? []
  }
}

enum CalendarAgent {
  private static var observer: NSObjectProtocol?
  private static var footballTimer: Timer?

  static func start() {
    WidgetNavStore.update { $0.hasCalendarAccess = EventLoader.hasAccess }
    EventCache.syncFromEventKit()
    Task {
      await FootballSchedule.syncAll()
      WidgetCenter.shared.reloadAllTimelines()
    }
    WidgetCenter.shared.reloadAllTimelines()
    if observer == nil {
      observer = NotificationCenter.default.addObserver(
        forName: .EKEventStoreChanged,
        object: EventLoader.store,
        queue: .main
      ) { _ in
        EventCache.syncFromEventKit()
        WidgetCenter.shared.reloadAllTimelines()
      }
    }
    if footballTimer == nil {
      let timer = Timer(timeInterval: 15 * 60, repeats: true) { _ in
        Task {
          await FootballSchedule.syncAll()
          WidgetCenter.shared.reloadAllTimelines()
        }
      }
      RunLoop.main.add(timer, forMode: .common)
      footballTimer = timer
    }
  }
}

struct CalendarEventItem: Codable, Hashable, Identifiable {
  let id: String
  let dateKey: String
  let endDateKey: String
  let start: Date
  let end: Date
  let isAllDay: Bool
  let title: String
  let color: CodableColor

  init(event: EKEvent) {
    let startDate = event.startDate ?? Date()
    let exclusiveEnd = event.endDate ?? startDate
    id = "\(event.eventIdentifier ?? UUID().uuidString)-\(startDate.timeIntervalSince1970)"
    dateKey = CalendarMath.dateKey(startDate)
    let lastDay = event.isAllDay
      ? Calendar.current.date(byAdding: .second, value: -1, to: exclusiveEnd) ?? exclusiveEnd
      : exclusiveEnd
    endDateKey = CalendarMath.dateKey(lastDay)
    start = startDate
    end = exclusiveEnd
    isAllDay = event.isAllDay
    title = event.title?.isEmpty == false ? event.title! : "Событие"
    color = CodableColor(cgColor: event.calendar?.cgColor)
  }

  func covers(_ date: Date) -> Bool {
    let key = CalendarMath.dateKey(date)
    return key >= dateKey && key <= endDateKey
  }
}

struct CodableColor: Codable, Hashable {
  var red: Double
  var green: Double
  var blue: Double
  var alpha: Double

  var color: Color {
    Color(red: red, green: green, blue: blue, opacity: alpha)
  }

  init(cgColor: CGColor?) {
    if let comps = cgColor?.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
       comps.count >= 3 {
      red = Double(comps[0])
      green = Double(comps[1])
      blue = Double(comps[2])
      alpha = Double(comps.count > 3 ? comps[3] : 1)
    } else {
      red = 0.2
      green = 0.45
      blue = 0.95
      alpha = 1
    }
  }
}

enum WidgetNavStore {
  private static let lock = NSLock()
  private static var url: URL { AppSupport.directory.appendingPathComponent("widget-state.json") }

  struct State: Codable {
    var displayedMonth: TimeInterval?
    var selectedDateKey: String
    var agendaOffset: Int
    var followedTeam: String
    var startMonday: Bool
    var weekNumbers: Bool
    var holidays: Bool
    var showRPL: Bool
    var showRussianCup: Bool
    var hasCalendarAccess: Bool
    var enabledCalendarIDs: [String]?

    enum CodingKeys: String, CodingKey {
      case displayedMonth, selectedDateKey, agendaOffset, followedTeam
      case startMonday, weekNumbers, holidays, showRPL, showRussianCup, hasCalendarAccess
      case enabledCalendarIDs
    }

    init(
      displayedMonth: TimeInterval?,
      selectedDateKey: String,
      agendaOffset: Int,
      followedTeam: String,
      startMonday: Bool = true,
      weekNumbers: Bool = false,
      holidays: Bool = true,
      showRPL: Bool = true,
      showRussianCup: Bool = true,
      hasCalendarAccess: Bool = false,
      enabledCalendarIDs: [String]? = nil
    ) {
      self.displayedMonth = displayedMonth
      self.selectedDateKey = selectedDateKey
      self.agendaOffset = agendaOffset
      self.followedTeam = followedTeam
      self.startMonday = startMonday
      self.weekNumbers = weekNumbers
      self.holidays = holidays
      self.showRPL = showRPL
      self.showRussianCup = showRussianCup
      self.hasCalendarAccess = hasCalendarAccess
      self.enabledCalendarIDs = enabledCalendarIDs
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      displayedMonth = try container.decodeIfPresent(TimeInterval.self, forKey: .displayedMonth)
      selectedDateKey = try container.decodeIfPresent(String.self, forKey: .selectedDateKey) ?? CalendarMath.dateKey(Date())
      agendaOffset = try container.decodeIfPresent(Int.self, forKey: .agendaOffset) ?? 0
      followedTeam = try container.decodeIfPresent(String.self, forKey: .followedTeam) ?? "Зенит"
      startMonday = try container.decodeIfPresent(Bool.self, forKey: .startMonday) ?? true
      weekNumbers = try container.decodeIfPresent(Bool.self, forKey: .weekNumbers) ?? false
      holidays = try container.decodeIfPresent(Bool.self, forKey: .holidays) ?? true
      showRPL = try container.decodeIfPresent(Bool.self, forKey: .showRPL) ?? true
      showRussianCup = try container.decodeIfPresent(Bool.self, forKey: .showRussianCup) ?? true
      hasCalendarAccess = try container.decodeIfPresent(Bool.self, forKey: .hasCalendarAccess) ?? false
      enabledCalendarIDs = try container.decodeIfPresent([String].self, forKey: .enabledCalendarIDs)
    }
  }

  static func load() -> State {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked()
  }

  static func update(_ mutate: (inout State) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    var state = loadLocked()
    mutate(&state)
    if let data = try? JSONEncoder().encode(state) {
      try? data.write(to: url, options: .atomic)
    }
  }

  private static func loadLocked() -> State {
    if let data = try? Data(contentsOf: url),
       let state = try? JSONDecoder().decode(State.self, from: data) {
      return state
    }
    return State(
      displayedMonth: UserDefaults.standard.object(forKey: "displayed_month_start") as? Double,
      selectedDateKey: UserDefaults.standard.string(forKey: "selected_date_key") ?? CalendarMath.dateKey(Date()),
      agendaOffset: UserDefaults.standard.integer(forKey: "agenda_offset"),
      followedTeam: {
        if UserDefaults.standard.object(forKey: "followed_team_name") == nil { return "Зенит" }
        return UserDefaults.standard.string(forKey: "followed_team_name") ?? "Зенит"
      }()
    )
  }
}

enum CalendarNavigation {
  static var displayedMonth: Date {
    get {
      let calendar = Calendar.current
      if let interval = WidgetNavStore.load().displayedMonth {
        return calendar.date(from: calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: interval)))
          ?? Date()
      }
      return calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }
    set {
      let calendar = Calendar.current
      let start = calendar.date(from: calendar.dateComponents([.year, .month], from: newValue)) ?? newValue
      WidgetNavStore.update { $0.displayedMonth = start.timeIntervalSince1970 }
    }
  }

  static var selectedDateKey: String {
    get { WidgetNavStore.load().selectedDateKey }
    set { WidgetNavStore.update { $0.selectedDateKey = newValue } }
  }

  static var selectedDate: Date {
    date(fromKey: selectedDateKey) ?? Date()
  }

  static var agendaOffset: Int {
    get { WidgetNavStore.load().agendaOffset }
    set { WidgetNavStore.update { $0.agendaOffset = max(0, newValue) } }
  }

  static func shift(months: Int = 0, years: Int = 0) {
    let calendar = Calendar.current
    var date = displayedMonth
    if years != 0 {
      date = calendar.date(byAdding: .year, value: years, to: date) ?? date
    }
    if months != 0 {
      date = calendar.date(byAdding: .month, value: months, to: date) ?? date
    }
    displayedMonth = date
    snapSelectedDateToDisplayedMonth()
  }

  static func snapSelectedDateToDisplayedMonth() {
    let month = displayedMonth
    if CalendarMath.isSameMonth(selectedDate, month) { return }
    let calendar = Calendar.current
    let today = Date()
    let target = CalendarMath.isSameMonth(today, month)
      ? today
      : (calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month)
    selectDay(CalendarMath.dateKey(target))
  }

  static func selectDay(_ dateKey: String) {
    WidgetNavStore.update { state in
      state.selectedDateKey = dateKey
      state.agendaOffset = 0
      if let date = date(fromKey: dateKey) {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
        state.displayedMonth = start.timeIntervalSince1970
      }
    }
  }

  static func shiftSelectedDay(by days: Int) {
    let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    selectDay(CalendarMath.dateKey(next))
  }

  static func goToToday() {
    WidgetNavStore.update { state in
      state.displayedMonth = nil
      state.selectedDateKey = CalendarMath.dateKey(Date())
      state.agendaOffset = 0
    }
  }

  static func shiftAgenda(by delta: Int, total: Int, pageSize: Int) {
    let maxOffset = max(0, total - pageSize)
    WidgetNavStore.update { state in
      state.agendaOffset = min(maxOffset, max(0, state.agendaOffset + delta))
    }
  }

  static func date(fromKey key: String) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}

enum CalendarOptions {
  static var startMonday: Bool {
    get { WidgetNavStore.load().startMonday }
    set { WidgetNavStore.update { $0.startMonday = newValue } }
  }

  static var weekNumbers: Bool {
    get { WidgetNavStore.load().weekNumbers }
    set { WidgetNavStore.update { $0.weekNumbers = newValue } }
  }

  static var holidays: Bool {
    get { WidgetNavStore.load().holidays }
    set { WidgetNavStore.update { $0.holidays = newValue } }
  }

  static var showRPL: Bool {
    get { WidgetNavStore.load().showRPL }
    set { WidgetNavStore.update { $0.showRPL = newValue } }
  }

  static var showRussianCup: Bool {
    get { WidgetNavStore.load().showRussianCup }
    set { WidgetNavStore.update { $0.showRussianCup = newValue } }
  }
}

enum FollowedTeamNavigation {
  static let noneTitle = "Не следить"

  static var name: String? {
    get {
      let value = WidgetNavStore.load().followedTeam
      return value.isEmpty ? nil : value
    }
    set { WidgetNavStore.update { $0.followedTeam = newValue ?? "" } }
  }

  static var displayName: String { name ?? noneTitle }

  static func shift(by delta: Int) {
    let options = [""] + FootballSchedule.followedTeamChoices()
    let current = name ?? ""
    let index = options.firstIndex(of: current) ?? 0
    let next = (index + delta + options.count) % options.count
    name = options[next].isEmpty ? nil : options[next]
  }
}

enum CalendarMath {
  static let russian = Locale(identifier: "ru_RU")

  static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func monthGrid(for month: Date, startMonday: Bool) -> [Date] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = russian
    calendar.firstWeekday = startMonday ? 2 : 1
    let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    let weekday = calendar.component(.weekday, from: startOfMonth)
    let offset = startMonday ? (weekday + 5) % 7 : weekday - 1
    let gridStart = calendar.date(byAdding: .day, value: -offset, to: startOfMonth) ?? startOfMonth
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
  }

  static func isoWeek(_ date: Date) -> Int {
    Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
  }

  static func isSameDay(_ a: Date, _ b: Date) -> Bool {
    Calendar.current.isDate(a, inSameDayAs: b)
  }

  static func isSameMonth(_ a: Date, _ b: Date) -> Bool {
    let cal = Calendar.current
    return cal.component(.year, from: a) == cal.component(.year, from: b)
      && cal.component(.month, from: a) == cal.component(.month, from: b)
  }

  static func isWeekend(_ date: Date) -> Bool {
    let day = Calendar.current.component(.weekday, from: date)
    return day == 1 || day == 7
  }

  static func weekdaySymbols(startMonday: Bool) -> [String] {
    let names = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    return startMonday ? names : ["Вс"] + names.dropLast()
  }
}

enum RussianHolidays {
  static func name(on date: Date) -> String? {
    map(for: Calendar.current.component(.year, from: date))[CalendarMath.dateKey(date)]
  }

  static func map(for year: Int) -> [String: String] {
    var result: [String: String] = [:]
    for day in 1...8 {
      result[String(format: "%04d-01-%02d", year, day)] = "Новогодние каникулы"
    }
    result[String(format: "%04d-01-07", year)] = "Рождество Христово"
    result[String(format: "%04d-02-23", year)] = "День защитника Отечества"
    result[String(format: "%04d-03-08", year)] = "Международный женский день"
    result[String(format: "%04d-05-01", year)] = "Праздник Весны и Труда"
    result[String(format: "%04d-05-09", year)] = "День Победы"
    result[String(format: "%04d-06-12", year)] = "День России"
    result[String(format: "%04d-11-04", year)] = "День народного единства"
    return result
  }
}
