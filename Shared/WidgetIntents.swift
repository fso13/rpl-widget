import AppIntents
import WidgetKit

struct ShiftDisplayedPeriodIntent: AppIntent {
  static var title: LocalizedStringResource = "Сдвинуть календарь"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Месяцев")
  var months: Int

  @Parameter(title: "Лет")
  var years: Int

  init() {
    months = 0
    years = 0
  }

  init(months: Int, years: Int = 0) {
    self.months = months
    self.years = years
  }

  func perform() async throws -> some IntentResult {
    CalendarNavigation.shift(months: months, years: years)
    CalendarWidgetKind.reload()
    return .result()
  }
}

struct GoToTodayIntent: AppIntent {
  static var title: LocalizedStringResource = "Текущий месяц"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  func perform() async throws -> some IntentResult {
    CalendarNavigation.goToToday()
    CalendarWidgetKind.reload()
    return .result()
  }
}

struct ShiftFollowedTeamIntent: AppIntent {
  static var title: LocalizedStringResource = "Сменить команду"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Сдвиг")
  var delta: Int

  init() { delta = 0 }

  init(delta: Int) { self.delta = delta }

  func perform() async throws -> some IntentResult {
    FollowedTeamNavigation.shift(by: delta)
    CalendarWidgetKind.reload()
    return .result()
  }
}

struct ShiftAgendaIntent: AppIntent {
  static var title: LocalizedStringResource = "Листать события"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Сдвиг")
  var delta: Int

  @Parameter(title: "Всего")
  var total: Int

  @Parameter(title: "На странице")
  var pageSize: Int

  init() {
    delta = 0
    total = 0
    pageSize = 4
  }

  init(delta: Int, total: Int, pageSize: Int) {
    self.delta = delta
    self.total = total
    self.pageSize = pageSize
  }

  func perform() async throws -> some IntentResult {
    CalendarNavigation.shiftAgenda(by: delta, total: total, pageSize: pageSize)
    CalendarWidgetKind.reload()
    return .result()
  }
}

struct ShiftSelectedDayIntent: AppIntent {
  static var title: LocalizedStringResource = "Сдвинуть день"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "Дней")
  var days: Int

  init() { days = 0 }

  init(days: Int) { self.days = days }

  func perform() async throws -> some IntentResult {
    CalendarNavigation.shiftSelectedDay(by: days)
    CalendarWidgetKind.reload()
    return .result()
  }
}

struct SelectDayIntent: AppIntent {
  static var title: LocalizedStringResource = "Выбрать день"
  static var openAppWhenRun = false
  static var isDiscoverable = false

  @Parameter(title: "День")
  var dateKey: String

  init() { dateKey = "" }

  init(dateKey: String) { self.dateKey = dateKey }

  func perform() async throws -> some IntentResult {
    CalendarNavigation.selectDay(dateKey)
    CalendarWidgetKind.reload()
    return .result()
  }
}
