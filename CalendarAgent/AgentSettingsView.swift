import AppKit
import EventKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
  enum Pane: String, CaseIterable, Identifiable, Hashable {
    case calendars, widget, football, system

    var id: String { rawValue }

    var title: String {
      switch self {
      case .calendars: return "Календари"
      case .widget: return "Виджет"
      case .football: return "Футбол"
      case .system: return "Система"
      }
    }

    var symbol: String {
      switch self {
      case .calendars: return "calendar"
      case .widget: return "rectangle.grid.2x2"
      case .football: return "sportscourt"
      case .system: return "gearshape"
      }
    }
  }

  @Published var pane: Pane = .calendars
  @Published var status = EKEventStore.authorizationStatus(for: .event)
  @Published var calendars: [EKCalendar] = []
  @Published var isRequestingAccess = false
  @Published var isRefreshingFootball = false
  @Published var footballError: String?
  @Published var lastFootballSync: Date?
  @Published var loginError: String?

  @Published var startMonday = CalendarOptions.startMonday
  @Published var weekNumbers = CalendarOptions.weekNumbers
  @Published var holidays = CalendarOptions.holidays
  @Published var showRPL = CalendarOptions.showRPL
  @Published var showRussianCup = CalendarOptions.showRussianCup
  @Published var followedTeam = FollowedTeamNavigation.name ?? ""
  @Published var launchAtLogin = LoginItem.isEnabled

  private var storeObserver: NSObjectProtocol?

  var hasAccess: Bool { status == .fullAccess }

  var teamChoices: [String] {
    [""] + FootballSchedule.followedTeamChoices()
  }

  var groupedCalendars: [(source: String, items: [EKCalendar])] {
    let groups = Dictionary(grouping: calendars, by: \.source.title)
    return groups.keys.sorted { $0.localizedCompare($1) == .orderedAscending }.map { source in
      (source, groups[source] ?? [])
    }
  }

  init() {
    reloadCalendars()
    lastFootballSync = FootballSchedule.lastSyncDate
    storeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: EventLoader.store,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reloadCalendars()
      }
    }
  }

  deinit {
    if let storeObserver {
      NotificationCenter.default.removeObserver(storeObserver)
    }
  }

  func reloadCalendars() {
    status = EKEventStore.authorizationStatus(for: .event)
    EventLoader.store.refreshSourcesIfNecessary()
    calendars = CalendarSelection.availableCalendars()
    WidgetNavStore.update { $0.hasCalendarAccess = hasAccess }
  }

  func requestAccess() async {
    isRequestingAccess = true
    defer { isRequestingAccess = false }
    _ = try? await EventLoader.store.requestFullAccessToEvents()
    reloadCalendars()
    if hasAccess {
      persistCalendars()
      CalendarAgent.start()
    }
  }

  func persistCalendars() {
    EventCache.syncFromEventKit()
    CalendarWidgetKind.reload()
  }

  func persistWidget() {
    CalendarOptions.startMonday = startMonday
    CalendarOptions.weekNumbers = weekNumbers
    CalendarOptions.holidays = holidays
    CalendarOptions.showRPL = showRPL
    CalendarOptions.showRussianCup = showRussianCup
    FollowedTeamNavigation.name = followedTeam.isEmpty ? nil : followedTeam
    CalendarWidgetKind.reload()
  }

  func refreshFootball() async {
    isRefreshingFootball = true
    footballError = nil
    defer { isRefreshingFootball = false }
    await FootballSchedule.syncAll()
    lastFootballSync = FootballSchedule.lastSyncDate
    if FootballSchedule.load().isEmpty {
      footballError = "Не удалось загрузить расписание. Проверьте сеть и попробуйте ещё раз."
    }
    CalendarWidgetKind.reload()
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try LoginItem.setEnabled(enabled)
      loginError = nil
    } catch {
      loginError = "Не получилось изменить автозапуск. Скопируйте приложение в «Программы» и повторите."
    }
    launchAtLogin = LoginItem.isEnabled
  }
}

struct AgentSettingsView: View {
  @StateObject private var model = SettingsModel()

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      ScrollView {
        paneContent
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(24)
      }
      .background(Color(nsColor: .windowBackgroundColor))
    }
    .frame(minWidth: 720, minHeight: 500)
    .onChange(of: model.startMonday) { _, _ in model.persistWidget() }
    .onChange(of: model.weekNumbers) { _, _ in model.persistWidget() }
    .onChange(of: model.holidays) { _, _ in model.persistWidget() }
    .onChange(of: model.showRPL) { _, _ in model.persistWidget() }
    .onChange(of: model.showRussianCup) { _, _ in model.persistWidget() }
    .onChange(of: model.followedTeam) { _, _ in model.persistWidget() }
    .onAppear { model.reloadCalendars() }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Календарь РПЛ")
        .font(.headline)
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 8)
      ForEach(SettingsModel.Pane.allCases) { pane in
        Button {
          model.pane = pane
        } label: {
          Label(pane.title, systemImage: pane.symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(model.pane == pane ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(model.pane == pane ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
    .padding(8)
    .frame(width: 196)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  @ViewBuilder
  private var paneContent: some View {
    switch model.pane {
    case .calendars: calendarsPane
    case .widget: widgetPane
    case .football: footballPane
    case .system: systemPane
    }
  }

  private var calendarsPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      header("Календари", "Выберите, какие календари попадают в виджет. События читаются из стандартного приложения «Календарь».")

      accessCard

      if model.hasAccess {
        HStack {
          Button("Выбрать все") {
            CalendarSelection.setAll(enabled: true)
            model.persistCalendars()
            model.reloadCalendars()
          }
          Button("Снять все") {
            CalendarSelection.setAll(enabled: false)
            model.persistCalendars()
            model.reloadCalendars()
          }
          Spacer()
          Button("Добавить учётную запись…") {
            SystemLinks.openInternetAccounts()
          }
          Button("Открыть Календарь") {
            SystemLinks.openCalendarApp()
          }
        }

        if model.calendars.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
            Text("Календарей пока нет")
              .font(.headline)
            Text("Добавьте iCloud, Google или другую учётную запись в Системных настройках, затем нажмите «Обновить».")
              .font(.callout)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            Button("Обновить список") { model.reloadCalendars() }
          }
          .frame(maxWidth: .infinity, minHeight: 160)
        } else {
          VStack(alignment: .leading, spacing: 16) {
            ForEach(model.groupedCalendars, id: \.source) { group in
              VStack(alignment: .leading, spacing: 8) {
                Text(group.source)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.secondary)
                ForEach(group.items, id: \.calendarIdentifier) { calendar in
                  Toggle(isOn: calendarEnabledBinding(calendar)) {
                    HStack(spacing: 8) {
                      Circle()
                        .fill(calendarColor(calendar))
                        .frame(width: 10, height: 10)
                      Text(calendar.title)
                      if calendar.type == .subscription || calendar.type == .birthday {
                        Text(calendar.type == .birthday ? "дни рождения" : "подписка")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                  }
                }
              }
            }
          }
          .padding(12)
          .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }

  private var accessCard: some View {
    GroupBox {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: model.hasAccess ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
          .font(.title2)
          .foregroundStyle(model.hasAccess ? .green : .orange)
        VStack(alignment: .leading, spacing: 4) {
          Text(model.hasAccess ? "Доступ к календарям разрешён" : "Нужен доступ к календарям")
            .font(.headline)
          Text(accessDetail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        if model.hasAccess {
          Button("Обновить") { model.reloadCalendars() }
        } else if model.status == .denied || model.status == .restricted {
          Button("Открыть настройки") { SystemLinks.openCalendarPrivacy() }
        } else {
          Button(model.isRequestingAccess ? "Запрос…" : "Разрешить доступ") {
            Task { await model.requestAccess() }
          }
          .disabled(model.isRequestingAccess)
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding(6)
    }
  }

  private var accessDetail: String {
    switch model.status {
    case .fullAccess:
      return "Виджет показывает события только из отмеченных календарей."
    case .denied, .restricted:
      return "Доступ запрещён. Включите его в Системных настройках → Конфиденциальность и безопасность → Календари."
    case .writeOnly:
      return "Сейчас разрешена только запись. Нужен полный доступ, чтобы читать события."
    default:
      return "Разрешите полный доступ, чтобы подключить календари iCloud, Google и другие."
    }
  }

  private var widgetPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      header("Виджет", "Эти параметры сразу обновляют календарь на рабочем столе.")
      settingsCard {
        Toggle("Неделя с понедельника", isOn: $model.startMonday)
        Toggle("Номера недель", isOn: $model.weekNumbers)
        Toggle("Праздники РФ", isOn: $model.holidays)
      }
      Text("Чтобы добавить виджет: правый клик по рабочему столу → «Изменить виджеты» → «Календарь».")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private var footballPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      header("Футбол", "Расписание матчей подтягивается с Матч ТВ и кэшируется для виджета.")
      settingsCard {
        Toggle("Матчи РПЛ", isOn: $model.showRPL)
        Toggle("Кубок России", isOn: $model.showRussianCup)
        Divider()
        Picker("Следить за командой", selection: $model.followedTeam) {
          Text(FollowedTeamNavigation.noneTitle).tag("")
          ForEach(FootballSchedule.followedTeamChoices(), id: \.self) { name in
            Text(name).tag(name)
          }
        }
        Divider()
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Последнее обновление")
            Text(syncText)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task { await model.refreshFootball() }
          } label: {
            if model.isRefreshingFootball {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Обновить сейчас")
            }
          }
          .disabled(model.isRefreshingFootball)
        }
      }
      if let footballError = model.footballError {
        Text(footballError)
          .font(.callout)
          .foregroundStyle(.red)
      }
    }
  }

  private var systemPane: some View {
    VStack(alignment: .leading, spacing: 16) {
      header("Система", "Приложение живёт в строке меню и не занимает место в Dock.")
      settingsCard {
        Toggle("Запускать при входе в систему", isOn: $model.launchAtLogin)
          .onChange(of: model.launchAtLogin) { _, value in
            model.setLaunchAtLogin(value)
          }
        if let loginError = model.loginError {
          Text(loginError)
            .font(.callout)
            .foregroundStyle(.red)
        }
        Text("Для автозапуска скопируйте приложение в «Программы».")
          .font(.callout)
          .foregroundStyle(.secondary)
        Divider()
        LabeledContent("Название", value: "Календарь РПЛ")
        LabeledContent("Роль", value: "Фоновый агент и настройки виджета")
      }
    }
  }

  private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
  }

  private var syncText: String {
    guard let date = model.lastFootballSync else { return "ещё не обновлялось" }
    return date.formatted(.relative(presentation: .named).locale(CalendarMath.russian))
  }

  private func header(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.title2.weight(.semibold))
      Text(subtitle)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func calendarEnabledBinding(_ calendar: EKCalendar) -> Binding<Bool> {
    Binding(
      get: { CalendarSelection.isEnabled(calendar) },
      set: { enabled in
        CalendarSelection.setEnabled(calendar, enabled: enabled)
        model.persistCalendars()
      }
    )
  }

  private func calendarColor(_ calendar: EKCalendar) -> Color {
    if let cgColor = calendar.cgColor {
      return Color(nsColor: NSColor(cgColor: cgColor) ?? .systemBlue)
    }
    return .accentColor
  }
}
