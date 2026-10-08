import Foundation

/// A project's downloads on one day: every release added up, the last time Releases Manager looked that day.
public struct DownloadSample: Codable, Hashable, Sendable {
  public var date: Date
  public var downloads: Int

  public init(date: Date, downloads: Int) {
    self.date = date
    self.downloads = downloads
  }
}

/// The downloads so far at the end of a day.
public struct DownloadPoint: Hashable, Sendable {
  /// The start of the day.
  public var day: Date
  public var downloads: Int
  /// Before Releases Manager saved its first count: a straight line from the launch, at zero, to that count.
  public var isEstimate: Bool

  public init(day: Date, downloads: Int, isEstimate: Bool) {
    self.day = day
    self.downloads = downloads
    self.isEstimate = isEstimate
  }
}

/// One app's downloads by day, or the apps with few downloads added up as "Other".
public struct DownloadSeries: Hashable, Sendable {
  public var name: String
  public var points: [DownloadPoint]

  public init(name: String, points: [DownloadPoint]) {
    self.name = name
    self.points = points
  }
}

extension [DownloadPoint] {
  /// The downloads of each day instead of the total so far. A day is an estimate when it or the day before is.
  public func perDay() -> [DownloadPoint] {
    var days: [DownloadPoint] = []
    var previous: DownloadPoint?
    for point in self {
      let downloads = Swift.max(point.downloads - (previous?.downloads ?? 0), 0)
      days.append(DownloadPoint(day: point.day, downloads: downloads, isEstimate: point.isEstimate || previous?.isEstimate == true))
      previous = point
    }
    return days
  }
}

extension [DownloadSeries] {
  /// Every series added up, day by day. They all cover the same days.
  public var total: [DownloadPoint] {
    guard let first else { return [] }
    return first.points.indices.map { index in
      let points = map { $0.points[index] }
      return DownloadPoint(day: first.points[index].day, downloads: points.reduce(0) { $0 + $1.downloads }, isEstimate: points.contains(where: \.isEstimate))
    }
  }
}

extension TrackedProject {
  /// Saves the total of every release, replacing the count saved earlier the same day.
  mutating func recordDownloads(at date: Date, calendar: Calendar = .current) {
    guard let releases, !releases.isEmpty else { return }
    let sample = DownloadSample(date: date, downloads: releases.reduce(0) { $0 + $1.downloadCount })
    var history = downloadHistory ?? []
    if let last = history.last, calendar.isDate(last.date, inSameDayAs: date) {
      history[history.count - 1] = sample
    } else {
      history.append(sample)
    }
    downloadHistory = history
  }
}

extension ProjectSnapshot {
  public var totalDownloads: Int {
    releases.reduce(0) { $0 + $1.downloadCount }
  }

  /// When the first release came out, prereleases included. The downloads started at zero then.
  public var downloadsStart: Date? {
    releases.compactMap { $0.isDraft ? nil : $0.publishedAt }.min()
  }

  /// The counts Releases Manager saved, oldest first, or the current one when it hasn't saved any yet.
  var downloadCounts: [DownloadSample] {
    if let history = project.downloadHistory, !history.isEmpty { return history }
    guard !releases.isEmpty else { return [] }
    return [DownloadSample(date: project.releasesFetchedAt ?? .now, downloads: totalDownloads)]
  }

  /// The downloads so far at `date`. Nil after the launch but before the first count Releases Manager saved.
  public func downloads(at date: Date) -> Int? {
    guard let start = downloadsStart, date > start else { return 0 }
    return downloadCounts.last { $0.date <= date }?.downloads
  }

  /// The downloads since `date`, or nil when Releases Manager doesn't know how many there were back then.
  public func downloads(since date: Date) -> Int? {
    downloads(at: date).map { max(totalDownloads - $0, 0) }
  }

  /// The downloads so far at the end of `day`.
  func downloadPoint(on day: Date, calendar: Calendar) -> DownloadPoint {
    let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
    if let downloads = downloads(at: end) {
      return DownloadPoint(day: day, downloads: downloads, isEstimate: false)
    }
    guard let start = downloadsStart, let first = downloadCounts.first else {
      return DownloadPoint(day: day, downloads: 0, isEstimate: false)
    }
    let progress = end.timeIntervalSince(start) / first.date.timeIntervalSince(start)
    return DownloadPoint(day: day, downloads: Int((Double(first.downloads) * min(progress, 1)).rounded()), isEstimate: true)
  }
}

extension [ProjectSnapshot] {
  public var totalDownloads: Int {
    reduce(0) { $0 + $1.totalDownloads }
  }

  /// When Releases Manager saved its first download count.
  public var downloadsTrackedSince: Date? {
    compactMap { $0.project.downloadHistory?.first?.date }.min()
  }

  /// The downloads since `date`, or nil when Releases Manager doesn't know how many a project had back then.
  public func downloads(since date: Date) -> Int? {
    var total = 0
    for project in self {
      guard let downloads = project.downloads(since: date) else { return nil }
      total += downloads
    }
    return total
  }

  /// The released apps, most downloaded first: the top `count` with at least `minimum` downloads
  /// each, and the others.
  public func splitByDownloads(top count: Int = 5, minimum: Int = 10) -> (top: [ProjectSnapshot], others: [ProjectSnapshot]) {
    let released = filter { $0.downloadsStart != nil }.sorted { lhs, rhs in
      lhs.totalDownloads == rhs.totalDownloads
        ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        : lhs.totalDownloads > rhs.totalDownloads
    }
    let top = Array(released.prefix(count).prefix { $0.totalDownloads >= minimum })
    return (top, Array(released.dropFirst(top.count)))
  }

  /// The top apps' downloads so far at the end of each day, from the first release to today, the
  /// most downloaded first. The others come last, added up as "Other".
  public func downloadSeries(top count: Int = 5, minimum: Int = 10, through now: Date = .now, calendar: Calendar = .current) -> [DownloadSeries] {
    let (top, others) = splitByDownloads(top: count, minimum: minimum)
    guard let start = (top + others).compactMap(\.downloadsStart).min() else { return [] }
    let days = days(from: start, through: now, calendar: calendar)

    func points(_ projects: [ProjectSnapshot]) -> [DownloadPoint] {
      days.map { day in
        let points = projects.map { $0.downloadPoint(on: day, calendar: calendar) }
        return DownloadPoint(day: day, downloads: points.reduce(0) { $0 + $1.downloads }, isEstimate: points.contains(where: \.isEstimate))
      }
    }

    let series = top.map { DownloadSeries(name: $0.name, points: points([$0])) }
    return others.isEmpty ? series : series + [DownloadSeries(name: "Other", points: points(others))]
  }
}

private func days(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
  var days: [Date] = []
  var day = calendar.startOfDay(for: start)
  let last = calendar.startOfDay(for: end)
  while day <= last {
    days.append(day)
    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
    day = next
  }
  return days
}
