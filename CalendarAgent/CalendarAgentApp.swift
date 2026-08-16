import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem?
  private var settingsWindow: NSWindow?
  private var calendarWindow: NSWindow?
  private var settingsObserver: NSObjectProtocol?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    setupStatusItem()
    CalendarAgent.start()
    settingsObserver = NotificationCenter.default.addObserver(
      forName: .calendarAgentOpenSettings,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.showSettings()
    }
    showCalendar()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showCalendar()
    return true
  }

  func showCalendar() {
    if calendarWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Календарь РПЛ"
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 900, height: 560)
      let hosting = NSHostingView(rootView: CalendarWorkspaceView())
      hosting.sizingOptions = []
      hosting.autoresizingMask = [.width, .height]
      window.contentView = hosting
      window.center()
      calendarWindow = window
    }
    calendarWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func toggleCalendar() {
    if calendarWindow?.isVisible == true {
      calendarWindow?.orderOut(nil)
    } else {
      showCalendar()
    }
  }

  func showSettings() {
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "Настройки календаря"
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 720, height: 500)
      let hosting = NSHostingView(rootView: AgentSettingsView())
      hosting.sizingOptions = []
      hosting.autoresizingMask = [.width, .height]
      window.contentView = hosting
      window.center()
      settingsWindow = window
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = TrayIcon.image()
    item.button?.imagePosition = .imageOnly
    item.button?.toolTip = "Календарь РПЛ"
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      showStatusMenu()
    } else {
      toggleCalendar()
    }
  }

  private func showStatusMenu() {
    guard let button = statusItem?.button else { return }
    let menu = NSMenu()
    populateMenu(menu)
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    populateMenu(menu)
  }

  private func populateMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    menu.addItem(NSMenuItem(title: "Календарь", action: #selector(openCalendarWindow), keyEquivalent: ""))
    menu.addItem(.separator())

    let todayKey = CalendarMath.dateKey(Date())
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
    let matches = FootballSchedule.matches(
      from: start,
      to: end,
      includeRPL: CalendarOptions.showRPL,
      includeCup: CalendarOptions.showRussianCup
    ).filter { $0.dateKey == todayKey }

    if matches.isEmpty {
      let empty = NSMenuItem(title: "Сегодня матчей нет", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    } else {
      let header = NSMenuItem(title: "Сегодня", action: nil, keyEquivalent: "")
      header.isEnabled = false
      menu.addItem(header)
      for match in matches.prefix(8) {
        let title = "\(match.home) — \(match.away)  \(match.statusText)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let team = FollowedTeamNavigation.name, match.involves(team: team) {
          item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)]
          )
        }
        menu.addItem(item)
      }
    }

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(NSMenuItem(title: "Обновить расписание", action: #selector(refreshSchedule), keyEquivalent: "r"))
    menu.addItem(.separator())

    let login = NSMenuItem(
      title: "Запускать при входе в систему",
      action: #selector(toggleLoginItem),
      keyEquivalent: ""
    )
    login.state = LoginItem.isEnabled ? .on : .off
    menu.addItem(login)

    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q"))
  }

  @objc private func openCalendarWindow() {
    showCalendar()
  }

  @objc private func openSettings() {
    showSettings()
  }

  @objc private func refreshSchedule() {
    Task {
      await FootballSchedule.syncAll()
      EventCache.syncFromEventKit()
      CalendarWidgetKind.reload()
    }
  }

  @objc private func toggleLoginItem() {
    do {
      try LoginItem.setEnabled(!LoginItem.isEnabled)
    } catch {
      showSettings()
    }
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}

enum TrayIcon {
  static func image() -> NSImage {
    let side: CGFloat = 18
    let logo = NSImage(named: "TrayIcon")
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      NSColor.white.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
      logo?.draw(
        in: rect.insetBy(dx: 1.5, dy: 1.5),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
      )
      return true
    }
    image.isTemplate = false
    return image
  }
}

enum LoginItem {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func setEnabled(_ enabled: Bool) throws {
    switch (enabled, isEnabled) {
    case (true, false):
      try SMAppService.mainApp.register()
    case (false, true):
      try SMAppService.mainApp.unregister()
    default:
      break
    }
  }
}

enum SystemLinks {
  static func openCalendarPrivacy() {
    let urls = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
    ]
    for raw in urls {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
    }
  }

  static func openInternetAccounts() {
    let urls = [
      "x-apple.systempreferences:com.apple.settings.Storage",
      "x-apple.systempreferences:com.apple.Accounts-Settings.extension",
      "x-apple.systempreferences:com.apple.preferences.internetaccounts"
    ]
    for raw in urls {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
  }

  static func openCalendarApp() {
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
  }
}

@main
struct CalendarAgentApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      AgentSettingsView()
    }
  }
}
