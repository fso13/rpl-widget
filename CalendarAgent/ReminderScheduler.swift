import AppKit
import Foundation
import UserNotifications

@MainActor
final class ReminderScheduler: NSObject {
  static let shared = ReminderScheduler()

  private let prefix = "calagent."
  private let categoryEvent = "EVENT"
  private let categoryMatch = "MATCH"
  private let actionOpen = "OPEN"
  private let actionJoin = "JOIN"
  private var observer: NSObjectProtocol?
  private var started = false

  func start() {
    guard !started else {
      Task { await reschedule() }
      return
    }
    started = true
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let open = UNNotificationAction(identifier: actionOpen, title: "Открыть", options: [.foreground])
    let join = UNNotificationAction(identifier: actionJoin, title: "Подключиться", options: [.foreground])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: categoryEvent, actions: [join, open], intentIdentifiers: []),
      UNNotificationCategory(identifier: categoryMatch, actions: [open], intentIdentifiers: [])
    ])
    observer = NotificationCenter.default.addObserver(
      forName: .calendarDataDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.reschedule() }
    }
    Task { await reschedule() }
  }

  func requestAccess() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    if granted {
      await reschedule()
    }
    return granted
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func sendTest() async {
    _ = await requestAccess()
    let content = UNMutableNotificationContent()
    content.title = "Напоминание работает"
    content.body = "Так будут выглядеть уведомления о событиях и матчах."
    content.sound = ReminderOptions.sound ? .default : nil
    let request = UNNotificationRequest(
      identifier: prefix + "test",
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
    )
    try? await UNUserNotificationCenter.current().add(request)
  }

  func reschedule() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let pending = await center.pendingNotificationRequests()
    center.removePendingNotificationRequests(
      withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
    )
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

    let now = Date()
    var items: [PlannedReminder] = []
    if ReminderOptions.eventsEnabled {
      items.append(contentsOf: eventReminders(now: now))
    }
    if ReminderOptions.matchesEnabled {
      items.append(contentsOf: matchReminders(now: now))
    }
    let upcoming = items
      .filter { $0.fireDate.timeIntervalSince(now) > 5 }
      .sorted { $0.fireDate < $1.fireDate }
      .prefix(60)

    for item in upcoming {
      let content = UNMutableNotificationContent()
      content.title = item.title
      content.body = item.body
      content.sound = ReminderOptions.sound ? .default : nil
      content.categoryIdentifier = item.category
      content.userInfo = item.userInfo
      let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
      let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
      let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
      try? await center.add(request)
    }
  }

  private struct PlannedReminder {
    var id: String
    var fireDate: Date
    var title: String
    var body: String
    var category: String
    var userInfo: [String: String]
  }

  private func eventReminders(now: Date) -> [PlannedReminder] {
    let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
    let events = EventLoader.events(from: now, to: horizon)
    let lead = TimeInterval(ReminderOptions.eventLeadMinutes * 60)
    return events.compactMap { event in
      var fire: Date?
      if event.isAllDay {
        guard ReminderOptions.allDay else { return nil }
        fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: event.start)
      } else {
        fire = event.start.addingTimeInterval(-lead)
      }
      if let scheduled = fire, scheduled <= now, event.start > now {
        fire = event.start
      }
      guard let fire, fire > now else { return nil }
      var body = event.timeLabel(on: event.start)
      if let location = event.location, !location.isEmpty {
        body += " · \(location)"
      } else if let calendarName = event.calendarName {
        body += " · \(calendarName)"
      }
      var userInfo = ["kind": "event", "dateKey": event.dateKey]
      if let join = event.joinLinks.first?.url {
        userInfo["joinURL"] = join
        body += " · есть ссылка для подключения"
      }
      return PlannedReminder(
        id: requestID("event", event.id),
        fireDate: fire,
        title: event.title,
        body: body,
        category: categoryEvent,
        userInfo: userInfo
      )
    }
  }

  private func matchReminders(now: Date) -> [PlannedReminder] {
    let horizon = Calendar.current.date(byAdding: .day, value: 21, to: now) ?? now
    let matches = FootballSchedule.matches(
      from: now,
      to: horizon,
      includeRPL: CalendarOptions.showRPL,
      includeCup: CalendarOptions.showRussianCup
    )
    let team = FollowedTeamNavigation.name
    let lead = TimeInterval(ReminderOptions.matchLeadMinutes * 60)
    return matches.compactMap { match in
      if ReminderOptions.followedTeamOnly {
        guard let team, match.involves(team: team) else { return nil }
      }
      guard !match.isFinishedOrLive, let kickoff = match.kickoff else { return nil }
      let fire = kickoff.addingTimeInterval(-lead)
      let actualFire = fire > now ? fire : kickoff
      guard actualFire > now else { return nil }
      let when = kickoff.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(CalendarMath.russian))
      return PlannedReminder(
        id: requestID("match", match.id),
        fireDate: actualFire,
        title: "\(match.home) — \(match.away)",
        body: "\(match.competition.rawValue) · \(when)",
        category: categoryMatch,
        userInfo: ["kind": "match", "dateKey": match.dateKey]
      )
    }
  }

  private func requestID(_ kind: String, _ raw: String) -> String {
    let digest = raw.unicodeScalars.reduce(into: UInt64(5381)) { hash, scalar in
      hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
    }
    return "\(prefix)\(kind).\(String(digest, radix: 16))"
  }

  private func handle(_ response: UNNotificationResponse) {
    let info = response.notification.request.content.userInfo
    let dateKey = info["dateKey"] as? String
    let join = info["joinURL"] as? String
    if response.actionIdentifier == actionJoin, let join, let url = URL(string: join) {
      NSWorkspace.shared.open(url)
    }
    NotificationCenter.default.post(name: .calendarAgentShowCalendar, object: dateKey)
  }
}

extension Notification.Name {
  static let calendarAgentShowCalendar = Notification.Name("ru.rudenko.macCalendar.agent.showCalendar")
}

extension ReminderScheduler: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      handle(response)
      completionHandler()
    }
  }
}
