import AppKit
import EventKit
import SwiftUI
import WidgetKit

enum DockHider {
  @discardableResult
  static func hide() -> Bool {
    for window in NSApp.windows where window.isVisible {
      window.orderOut(nil)
    }
    return NSApp.setActivationPolicy(.accessory)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var setupWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var settingsCloser: WindowCloser?

  func applicationDidFinishLaunching(_ notification: Notification) {
    WidgetCenter.shared.reloadAllTimelines()
    DayEventsPanel.startListening()
    if EventLoader.hasAccess {
      CalendarAgent.start()
      if !DayEventsPanel.isVisible {
        DockHider.hide()
      }
    } else {
      NSApp.setActivationPolicy(.regular)
      showSetupWindow()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if DayEventsPanel.isVisible {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      return true
    }
    if EventLoader.hasAccess {
      CalendarAgent.start()
      showSettingsWindow()
      return true
    }
    showSetupWindow()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  func hideSetupAndBecomeAgent() {
    setupWindow?.orderOut(nil)
    setupWindow?.close()
    setupWindow = nil
    CalendarAgent.start()
    DockHider.hide()
  }

  func showSettingsWindow() {
    NSApp.setActivationPolicy(.regular)
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "Настройки календаря"
      window.isReleasedWhenClosed = false
      let closer = WindowCloser()
      window.delegate = closer
      settingsCloser = closer
      window.contentView = NSHostingView(rootView: WidgetSettingsView())
      window.center()
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showSetupWindow() {
    if setupWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "Календарь"
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: SetupView())
      window.center()
      setupWindow = window
    }
    setupWindow?.makeKeyAndOrderFront(nil)
  }
}

@main
struct CalendarHostApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // Без WindowGroup окно не создаётся само и не удерживает иконку в Dock.
    Settings {
      EmptyView()
    }
  }
}

struct SetupView: View {
  @State private var status = EKEventStore.authorizationStatus(for: .event)
  @State private var isRequesting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Календарь")
        .font(.largeTitle.weight(.semibold))

      Text("Контейнер для виджета. События берутся из стандартного «Календаря». Нажатие на день в виджете показывает события этого дня.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Label("Разрешите доступ к календарям", systemImage: accessGranted ? "checkmark.circle.fill" : "1.circle")
            .foregroundStyle(accessGranted ? .green : .primary)
          Label("Правый клик по рабочему столу → «Изменить виджеты»", systemImage: "2.circle")
          Label("Или клик по дате в строке меню → «Изменить виджеты»", systemImage: "3.circle")
          Label("Найдите «Календарь» или CalendarHost", systemImage: "4.circle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button(accessGranted ? "Доступ разрешён" : "Разрешить доступ") {
        Task { await requestAccess() }
      }
      .disabled(accessGranted || isRequesting)
      .keyboardShortcut(.defaultAction)

      if status == .denied || status == .restricted {
        Text("Доступ запрещён. Включите его в Системных настройках → Конфиденциальность и безопасность → Календари.")
          .font(.callout)
          .foregroundStyle(.red)
      }

      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(minWidth: 420, minHeight: 360)
    .onAppear {
      status = EKEventStore.authorizationStatus(for: .event)
      if accessGranted {
        becomeAgent()
      }
    }
  }

  private var accessGranted: Bool {
    status == .fullAccess
  }

  private func requestAccess() async {
    isRequesting = true
    defer { isRequesting = false }
    do {
      _ = try await EventLoader.store.requestFullAccessToEvents()
    } catch {
      // Статус всё равно перечитаем ниже.
    }
    status = EKEventStore.authorizationStatus(for: .event)
    if accessGranted {
      becomeAgent()
    }
  }

  private func becomeAgent() {
    CalendarAgent.start()
    DispatchQueue.main.async {
      (NSApp.delegate as? AppDelegate)?.hideSetupAndBecomeAgent()
    }
  }
}

struct WidgetSettingsView: View {
  @State private var startMonday = CalendarOptions.startMonday
  @State private var weekNumbers = CalendarOptions.weekNumbers
  @State private var holidays = CalendarOptions.holidays
  @State private var showRPL = CalendarOptions.showRPL
  @State private var showRussianCup = CalendarOptions.showRussianCup

  var body: some View {
    Form {
      Toggle("Неделя с понедельника", isOn: $startMonday)
      Toggle("Номера недель", isOn: $weekNumbers)
      Toggle("Праздники РФ", isOn: $holidays)
      Toggle("Матчи РПЛ", isOn: $showRPL)
      Toggle("Кубок России", isOn: $showRussianCup)
      Text("Эти параметры больше не в меню виджета — открытие настроек виджета ломало его. Изменения сразу обновляют календарь на рабочем столе.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
    .padding(20)
    .frame(width: 400, height: 280)
    .onChange(of: startMonday) { _, value in save { CalendarOptions.startMonday = value } }
    .onChange(of: weekNumbers) { _, value in save { CalendarOptions.weekNumbers = value } }
    .onChange(of: holidays) { _, value in save { CalendarOptions.holidays = value } }
    .onChange(of: showRPL) { _, value in save { CalendarOptions.showRPL = value } }
    .onChange(of: showRussianCup) { _, value in save { CalendarOptions.showRussianCup = value } }
  }

  private func save(_ update: () -> Void) {
    update()
    CalendarWidgetKind.reload()
  }
}
