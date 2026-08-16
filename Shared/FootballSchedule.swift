import AppKit
import Foundation
import SwiftUI

enum FootballCompetition: String, Codable, Hashable {
  case rpl = "РПЛ"
  case cup = "Кубок"
}

struct FootballMatch: Codable, Hashable, Identifiable {
  var id: String
  var dateKey: String
  var home: String
  var away: String
  var homeLogoURL: String
  var awayLogoURL: String
  var homeScore: String?
  var awayScore: String?
  var time: String?
  var live: String?
  var competition: FootballCompetition

  var statusText: String {
    if let live, !live.isEmpty { return live }
    if let homeScore, let awayScore, !homeScore.isEmpty, !awayScore.isEmpty {
      return "\(homeScore):\(awayScore)"
    }
    if let time, !time.isEmpty, time.uppercased() != "TBA" { return time }
    return "TBA"
  }

  func involves(team: String) -> Bool {
    home == team || away == team || TeamNameMatch.matches(team, home) || TeamNameMatch.matches(team, away)
  }

  func opponentName(for team: String) -> String? {
    if TeamNameMatch.matches(team, home) { return away }
    if TeamNameMatch.matches(team, away) { return home }
    return nil
  }

  func opponentLogoURL(for team: String) -> String? {
    if TeamNameMatch.matches(team, home) { return awayLogoURL }
    if TeamNameMatch.matches(team, away) { return homeLogoURL }
    return nil
  }
}

struct FootballMatchView: Hashable, Identifiable {
  var match: FootballMatch
  var homeLogo: Data?
  var awayLogo: Data?
  var id: String { match.id }

  func opponentLogo(for team: String) -> Data? {
    if TeamNameMatch.matches(team, match.home) { return awayLogo }
    if TeamNameMatch.matches(team, match.away) { return homeLogo }
    return nil
  }
}

enum TeamNameMatch {
  static func matches(_ a: String, _ b: String) -> Bool {
    let x = normalize(a)
    let y = normalize(b)
    if x.isEmpty || y.isEmpty { return false }
    if x == y { return true }
    if x.count >= 4 && (y == x || y.hasPrefix(x + " ") || x.hasPrefix(y + " ")) { return true }
    return false
  }

  static func normalize(_ raw: String) -> String {
    var s = raw.lowercased().replacingOccurrences(of: "ё", with: "е")
    for prefix in ["пфк ", "фк "] {
      if s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
    }
    return s
      .replacingOccurrences(of: "«", with: "")
      .replacingOccurrences(of: "»", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum FootballSchedule {
  private static let rplURL = URL(string: "https://matchtv.ru/football/rpl/calendar")!
  private static let cupURL = URL(string: "https://matchtv.ru/football/russian-cup/calendar")!
  private static let cacheName = "football.json"
  private static let stampName = "football.stamp"

  private static var directory: URL { AppSupport.directory }

  private static var cacheURL: URL { directory.appendingPathComponent(cacheName) }
  private static var stampURL: URL { directory.appendingPathComponent(stampName) }
  private static var logosDir: URL {
    let dir = directory.appendingPathComponent("logos")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  static var lastSyncDate: Date? {
    guard let raw = try? String(contentsOf: stampURL),
          let interval = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          interval > 0
    else { return nil }
    return Date(timeIntervalSince1970: interval)
  }

  static func refreshIfStale() async {
    let stamp = (try? Date(timeIntervalSince1970: Double(String(contentsOf: stampURL)) ?? 0)) ?? .distantPast
    if Date().timeIntervalSince(stamp) < 20 * 60, !load().isEmpty { return }
    await syncAll()
  }

  static func syncAll() async {
    async let rpl = fetch(from: rplURL, competition: .rpl)
    async let cup = fetch(from: cupURL, competition: .cup)
    let matches = ((try? await rpl) ?? []) + ((try? await cup) ?? [])
    guard !matches.isEmpty else { return }
    if let data = try? JSONEncoder().encode(matches) {
      try? data.write(to: cacheURL, options: .atomic)
      try? String(Date().timeIntervalSince1970).write(to: stampURL, atomically: true, encoding: .utf8)
    }
    await prefetchLogos(for: matches)
  }

  static func load() -> [FootballMatch] {
    guard let data = try? Data(contentsOf: cacheURL) else { return [] }
    return (try? JSONDecoder().decode([FootballMatch].self, from: data)) ?? []
  }

  static func teamNames() -> [String] {
    followedTeamChoices()
  }

  static func followedTeamChoices() -> [String] {
    let matches = load()
    let rpl = Set(matches.filter { $0.competition == .rpl }.flatMap { [$0.home, $0.away] })
    if !rpl.isEmpty {
      return rpl.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
    let all = Set(matches.flatMap { [$0.home, $0.away] })
    if !all.isEmpty {
      return all.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
    return [
      "Зенит", "Спартак", "ЦСКА", "Краснодар", "Динамо М", "Локомотив",
      "Ростов", "Рубин", "Крылья Советов", "Акрон", "Оренбург",
      "Балтика", "Сочи", "Ахмат", "Динамо Мх", "Родина"
    ]
  }

  static func matches(
    from start: Date,
    to end: Date,
    includeRPL: Bool,
    includeCup: Bool
  ) -> [FootballMatch] {
    let startKey = CalendarMath.dateKey(start)
    let endKey = CalendarMath.dateKey(end)
    return load().filter { match in
      switch match.competition {
      case .rpl: if !includeRPL { return false }
      case .cup: if !includeCup { return false }
      }
      return match.dateKey >= startKey && match.dateKey <= endKey
    }
  }

  static func views(
    from start: Date,
    to end: Date,
    includeRPL: Bool,
    includeCup: Bool
  ) -> [FootballMatchView] {
    matches(from: start, to: end, includeRPL: includeRPL, includeCup: includeCup).map {
      FootballMatchView(match: $0, homeLogo: logoData(for: $0.homeLogoURL), awayLogo: logoData(for: $0.awayLogoURL))
    }
  }

  private static func fetch(from url: URL, competition: FootballCompetition) async throws -> [FootballMatch] {
    var request = URLRequest(url: url)
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
      forHTTPHeaderField: "User-Agent"
    )
    request.timeoutInterval = 20
    let (data, _) = try await URLSession.shared.data(for: request)
    guard let html = String(data: data, encoding: .utf8) else { return [] }
    return parse(html: html, competition: competition)
  }

  static func parse(html: String, competition: FootballCompetition) -> [FootballMatch] {
    let ns = html as NSString
    let dateRe = try! NSRegularExpression(pattern: #"id="date_([^"]+)""#)
    let dateMatches = dateRe.matches(in: html, range: NSRange(location: 0, length: ns.length))
    var result: [FootballMatch] = []
    for (index, match) in dateMatches.enumerated() {
      guard match.numberOfRanges > 1 else { continue }
      let dateRaw = ns.substring(with: match.range(at: 1))
      let dateKey = String(dateRaw.prefix(10))
      let bodyStart = match.range.location + match.range.length
      let bodyEnd = index + 1 < dateMatches.count ? dateMatches[index + 1].range.location : ns.length
      guard bodyEnd > bodyStart else { continue }
      let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
      result.append(contentsOf: parseDay(body, dateKey: dateKey, competition: competition))
    }
    return result
  }

  private static func parseDay(_ body: String, dateKey: String, competition: FootballCompetition) -> [FootballMatch] {
    let cards = body.components(separatedBy: "e-tournament-game-card-team-vs-team-content").dropFirst()
    return cards.compactMap { card in
      let titles = captureAll(#"m-tournament-game-participant__title">([^<]+)"#, in: card)
      let logos = capturePairs(#"alt="Логотип ([^"]+)" src="([^"]+)""#, in: card)
      guard titles.count >= 2 else { return nil }
      let home = titles[0].trimmingCharacters(in: .whitespacesAndNewlines)
      let away = titles[1].trimmingCharacters(in: .whitespacesAndNewlines)
      let scores = captureAll(#"m-tournament-game-participant-score-block__score">([^<]*)"#, in: card)
      let time = captureFirst(#"e-tournament-game-card-additional-top-content__future-time[^>]*>\s*([^<]+)"#, in: card)
      let live = captureFirst(#"e-tournament-game-card-additional-top-content__live[^>]*>\s*([^<]+)"#, in: card)
      let homeLogo = logos.first?.1 ?? ""
      let awayLogo = logos.dropFirst().first?.1 ?? ""
      return FootballMatch(
        id: "\(competition.rawValue)-\(dateKey)-\(home)-\(away)",
        dateKey: dateKey,
        home: home,
        away: away,
        homeLogoURL: homeLogo,
        awayLogoURL: awayLogo,
        homeScore: scores.count > 0 && !scores[0].isEmpty ? scores[0] : nil,
        awayScore: scores.count > 1 && !scores[1].isEmpty ? scores[1] : nil,
        time: time,
        live: live,
        competition: competition
      )
    }
  }

  private static func prefetchLogos(for matches: [FootballMatch]) async {
    var urls = Set<String>()
    for match in matches {
      urls.insert(match.homeLogoURL)
      urls.insert(match.awayLogoURL)
    }
    await withTaskGroup(of: Void.self) { group in
      for urlString in urls where !urlString.isEmpty {
        group.addTask { await downloadLogo(urlString) }
      }
    }
  }

  private static func downloadLogo(_ urlString: String) async {
    if logoData(for: urlString) != nil { return }
    guard let url = URL(string: urlString) else { return }
    var request = URLRequest(url: url)
    request.timeoutInterval = 12
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
    let png = pngData(from: data) ?? data
    try? png.write(to: logoFile(for: urlString), options: .atomic)
  }

  static func logoData(for urlString: String) -> Data? {
    guard !urlString.isEmpty else { return nil }
    return try? Data(contentsOf: logoFile(for: urlString))
  }

  static func logoImage(for urlString: String) -> NSImage? {
    guard !urlString.isEmpty else { return nil }
    if let cached = imageCache.object(forKey: urlString as NSString) {
      return cached
    }
    guard let data = logoData(for: urlString), let image = NSImage(data: data) else { return nil }
    imageCache.setObject(image, forKey: urlString as NSString)
    return image
  }

  private static let imageCache = NSCache<NSString, NSImage>()

  private static func logoFile(for urlString: String) -> URL {
    let digest = urlString.unicodeScalars.reduce(into: UInt64(5381)) { hash, scalar in
      hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
    }
    return logosDir.appendingPathComponent("\(String(digest, radix: 16)).png")
  }

  private static func pngData(from data: Data) -> Data? {
    guard let image = NSImage(data: data) else { return nil }
    let size = NSSize(width: 64, height: 64)
    let output = NSImage(size: size)
    output.lockFocus()
    NSColor.clear.set()
    NSRect(origin: .zero, size: size).fill()
    let rect = NSRect(origin: .zero, size: size)
    image.draw(
      in: rect,
      from: NSRect(origin: .zero, size: image.size),
      operation: .sourceOver,
      fraction: 1
    )
    output.unlockFocus()
    guard let tiff = output.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  private static func captureFirst(_ pattern: String, in text: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
          match.numberOfRanges > 1,
          match.range(at: 1).location != NSNotFound
    else { return nil }
    return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func captureAll(_ pattern: String, in text: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
      guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
      return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private static func capturePairs(_ pattern: String, in text: String) -> [(String, String)] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
      guard match.numberOfRanges > 2,
            match.range(at: 1).location != NSNotFound,
            match.range(at: 2).location != NSNotFound
      else { return nil }
      return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
    }
  }
}

struct TeamLogoView: View {
  var urlString: String
  var name: String
  var side: CGFloat

  var body: some View {
    Group {
      if let image = FootballSchedule.logoImage(for: urlString) {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
      } else {
        Text(String(name.prefix(1)))
          .font(.system(size: max(7, side * 0.55), weight: .bold))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.secondary.opacity(0.15), in: Circle())
      }
    }
    .frame(width: side, height: side)
  }
}
