import AppKit
import SwiftUI

enum DayEventsPanel {
  private static var window: NSWindow?
  private static var observer: NSObjectProtocol?
  private static var closer: WindowCloser?

  static func startListening() {
    if observer == nil {
      observer = NotificationCenter.default.addObserver(
        forName: DayEventsRequest.showNotification,
        object: nil,
        queue: .main
      ) { note in
        let key = (note.object as? String) ?? DayEventsRequest.takePendingDateKey() ?? CalendarMath.dateKey(Date())
        show(dateKey: key)
      }
    }
    if let pending = DayEventsRequest.takePendingDateKey() {
      show(dateKey: pending)
    }
  }

  static func show(dateKey: String) {
    let date = CalendarNavigation.date(fromKey: dateKey) ?? Date()
    NSApp.setActivationPolicy(.regular)
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 420, height: 360)
      let closer = WindowCloser()
      window.delegate = closer
      Self.closer = closer
      Self.window = window
    }
    window?.title = date
      .formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(CalendarMath.russian))
      .capitalized
    window?.contentView = NSHostingView(rootView: DayEventsView(date: date))
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static var isVisible: Bool {
    window?.isVisible == true
  }
}

final class WindowCloser: NSObject, NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    DockHider.hide()
  }
}

struct DayEventsView: View {
  var date: Date

  var body: some View {
    let matches = FootballSchedule.views(
      from: date,
      to: Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date,
      includeRPL: true,
      includeCup: true
    ).filter { $0.match.dateKey == CalendarMath.dateKey(date) }
    let events = EventLoader.events(
      from: Calendar.current.startOfDay(for: date),
      to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
    ).filter { $0.covers(date) }
    let holiday = RussianHolidays.name(on: date)

    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(CalendarMath.russian)).capitalized)
          .font(.title2.weight(.semibold))

        if let holiday {
          Text(holiday)
            .font(.headline)
            .foregroundStyle(.red)
        }

        if matches.isEmpty && events.isEmpty {
          Text("Нет событий")
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }

        if !matches.isEmpty {
          Text("Матчи")
            .font(.headline)
          ForEach(matches) { match in
            HStack(spacing: 8) {
              Text(match.match.competition.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(match.match.competition == .rpl ? Color.blue : Color.orange)
                .frame(width: 48, alignment: .leading)
              logo(match.homeLogo, name: match.match.home)
              Text(match.match.statusText)
                .font(.body.monospacedDigit().weight(.semibold))
              logo(match.awayLogo, name: match.match.away)
              Text("\(match.match.home) – \(match.match.away)")
                .foregroundStyle(.secondary)
              Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
          }
        }

        if !events.isEmpty {
          Text("События")
            .font(.headline)
            .padding(.top, matches.isEmpty ? 0 : 8)
          ForEach(events) { event in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Circle().fill(event.color.color).frame(width: 8, height: 8)
              Text(timeLabel(event))
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
              Text(event.title)
                .font(.body)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
    .frame(minWidth: 420, minHeight: 320)
  }

  @ViewBuilder
  private func logo(_ data: Data?, name: String) -> some View {
    if let data, let image = NSImage(data: data) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 28, height: 28)
    } else {
      Text(String(name.prefix(1)))
        .font(.caption.weight(.bold))
        .frame(width: 28, height: 28)
        .background(Color.secondary.opacity(0.15), in: Circle())
    }
  }

  private func timeLabel(_ event: CalendarEventItem) -> String {
    if event.isAllDay { return "весь день" }
    if CalendarMath.isSameDay(event.start, date) {
      return event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(CalendarMath.russian))
    }
    return "…"
  }
}
