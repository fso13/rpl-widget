import AppIntents
import Foundation
import WidgetKit

enum DayEventsRequest {
  static let showNotification = Notification.Name("ru.rudenko.macCalendar.showDayEvents")
  private static var fileURL: URL { AppSupport.directory.appendingPathComponent("pending-day.txt") }

  static func request(_ dateKey: String) {
    try? dateKey.write(to: fileURL, atomically: true, encoding: .utf8)
    NotificationCenter.default.post(name: showNotification, object: dateKey)
  }

  static func takePendingDateKey() -> String? {
    guard let key = try? String(contentsOf: fileURL, encoding: .utf8), !key.isEmpty else {
      return nil
    }
    try? FileManager.default.removeItem(at: fileURL)
    return key.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct ShowDayEventsIntent: AppIntent {
  static var title: LocalizedStringResource = "Все события дня"
  static var openAppWhenRun = true
  static var isDiscoverable = false

  @Parameter(title: "День")
  var dateKey: String

  init() {
    dateKey = ""
  }

  init(dateKey: String) {
    self.dateKey = dateKey
  }

  func perform() async throws -> some IntentResult {
    CalendarNavigation.selectDay(dateKey)
    CalendarWidgetKind.reload()
    DayEventsRequest.request(dateKey)
    return .result()
  }
}
