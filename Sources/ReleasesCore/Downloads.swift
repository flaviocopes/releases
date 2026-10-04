import Foundation

/// A project's downloads on one day: every release added up, the last time Releases looked that day.
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
  /// Before Releases saved its first count: a straight line from the launch, at zero, to that count.
  public var isEstimate: Bool

  public init(day: Date, downloads: Int, isEstimate: Bool) {
    self.day = day
    self.downloads = downloads
    self.isEstimate = isEstimate
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

  /// The counts Releases saved, oldest first, or the current one when it hasn't saved any yet.
  var downloadCounts: [DownloadSample] {
    if let history = project.downloadHistory, !history.isEmpty { return history }
    guard !releases.isEmpty else { return [] }
    return [DownloadSample(date: project.releasesFetchedAt ?? .now, downloads: totalDownloads)]
  }

  /// The downloads so far at `date`. Nil after the launch but before the first count Releases saved.
  public func downloads(at date: Date) -> Int? {
    guard let start = downloadsStart, date > start else { return 0 }
    return downloadCounts.last { $0.date <= date }?.downloads
  }

  /// The downloads since `date`, or nil when Releases doesn't know how many there were back then.
  public func downloads(since date: Date) -> Int? {
    downloads(at: date).map { max(totalDownloads - $0, 0) }
  }

  /// The downloads at the end of each day, from the first release to today.
  public func downloadsByDay(through now: Date = .now, calendar: Calendar = .current) -> [DownloadPoint] {
    guard let start = downloadsStart else { return [] }
    return days(from: start, through: now, calendar: calendar).map { downloadPoint(on: $0, calendar: calendar) }
  }

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

  /// When Releases saved its first download count.
  public var downloadsTrackedSince: Date? {
    compactMap { $0.project.downloadHistory?.first?.date }.min()
  }

  /// The downloads since `date`, or nil when Releases doesn't know how many a project had back then.
  public func downloads(since date: Date) -> Int? {
    var total = 0
    for project in self {
      guard let downloads = project.downloads(since: date) else { return nil }
      total += downloads
    }
    return total
  }

  /// Every project's downloads added up at the end of each day, from the first release to today.
  public func downloadsByDay(through now: Date = .now, calendar: Calendar = .current) -> [DownloadPoint] {
    guard let start = compactMap(\.downloadsStart).min() else { return [] }
    return days(from: start, through: now, calendar: calendar).map { day in
      let points = map { $0.downloadPoint(on: day, calendar: calendar) }
      return DownloadPoint(day: day, downloads: points.reduce(0) { $0 + $1.downloads }, isEstimate: points.contains(where: \.isEstimate))
    }
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
