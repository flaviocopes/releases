import Foundation
import ReleasesCore

enum Output {
  static let isTerminal = isatty(STDOUT_FILENO) != 0

  static func json<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  /// Prints a hint below the main output. Skipped when piping, so scripts stay clean.
  static func hint(_ message: String) {
    guard isTerminal else { return }
    print("\n\(message)")
  }

  static func error(_ message: String) {
    note("Error: \(message)")
  }

  /// Writes to stderr, flushing stdout first so the two streams stay in order.
  static func note(_ message: String) {
    fflush(stdout)
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  /// Pads without ever cutting the text, unlike `String.padding`.
  static func pad(_ text: String, to width: Int) -> String {
    let missing = width - text.count
    return missing > 0 ? text + String(repeating: " ", count: missing) : text
  }

  static func trimTrailingSpaces(_ line: String) -> String {
    var trimmed = line
    while trimmed.last == " " { trimmed.removeLast() }
    return trimmed
  }

  static func date(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .omitted) ?? ""
  }

  /// Aligned columns. The last column is never padded.
  static func columns(_ rows: [[String]]) {
    guard let count = rows.first?.count else { return }
    let widths = (0..<count).map { column in rows.map { $0[column].count }.max() ?? 0 }
    for row in rows {
      let line = row.enumerated().map { column, value in
        column == count - 1 ? value : pad(value, to: widths[column] + 2)
      }
      print(trimTrailingSpaces(line.joined()))
    }
  }

  /// One line per project: name, version in the project, latest release, its date, and the status.
  static func table(_ snapshots: [ProjectSnapshot]) {
    guard !snapshots.isEmpty else {
      print("No projects yet. Add one with 'releases add <folder>'.")
      return
    }

    var rows = snapshots.map { snapshot in
      [
        snapshot.name,
        snapshot.local.version?.version ?? "-",
        snapshot.latestRelease?.tag ?? "-",
        date(snapshot.latestRelease?.publishedAt),
        snapshot.statusText
      ]
    }
    if isTerminal {
      rows.insert(["PROJECT", "VERSION", "RELEASE", "DATE", "STATUS"], at: 0)
    }
    columns(rows)
  }

  /// One line per project, most downloaded first: its downloads, the last 7 days and its releases. Then the total.
  static func downloads(_ snapshots: [ProjectSnapshot], weekAgo: Date) {
    var rows = snapshots.map { snapshot in
      [
        snapshot.name,
        snapshot.totalDownloads.formatted(),
        week(snapshot.downloads(since: weekAgo)),
        "\(snapshot.releases.count { !$0.isDraft })"
      ]
    }
    if isTerminal {
      rows.insert(["PROJECT", "DOWNLOADS", "LAST 7 DAYS", "RELEASES"], at: 0)
      rows.append(["Total", snapshots.totalDownloads.formatted(), week(snapshots.downloads(since: weekAgo)), ""])
    }
    columns(rows)
  }

  /// A project's downloads, each release's, and the counts saved so far.
  static func downloads(of snapshot: ProjectSnapshot, weekAgo: Date) {
    let total = snapshot.totalDownloads
    var summary = "\(snapshot.name): \(total == 1 ? "1 download" : "\(total.formatted()) downloads")"
    if let week = snapshot.downloads(since: weekAgo) {
      summary += ", \(week.formatted()) in the last 7 days"
    }
    print(summary)

    let releases = snapshot.releases.filter { !$0.isDraft }
    guard !releases.isEmpty else {
      print("\nNo releases on GitHub yet.")
      return
    }
    print("\nReleases:")
    columns(releases.map { ["  \($0.tag)", date($0.publishedAt), $0.downloadCount.formatted()] })

    let history = snapshot.project.downloadHistory ?? []
    if !history.isEmpty {
      print("\nSaved counts:")
      columns(history.suffix(14).map { ["  \(date($0.date))", $0.downloads.formatted()] })
      if history.count > 14 {
        hint("Showing the last 14 of \(history.count) days. Use --json to see them all.")
      }
    }
  }

  /// The last 14 days, newest first: the downloads of each day and the total so far. Estimates start with ~.
  static func downloadsByDay(_ series: [DownloadSeries]) {
    let total = series.total
    let days = total.perDay()
    let shown = total.indices.reversed().prefix(14)
    var rows = shown.map { index in
      [
        date(total[index].day),
        (days[index].isEstimate ? "~" : "") + "+\(days[index].downloads.formatted())",
        (total[index].isEstimate ? "~" : "") + total[index].downloads.formatted()
      ]
    }
    if isTerminal {
      rows.insert(["DAY", "DOWNLOADS", "TOTAL"], at: 0)
    }
    columns(rows)
    if shown.contains(where: { days[$0].isEstimate }) {
      hint("~ is an estimate. GitHub only keeps the total so far, so the days before Releases saved its first count are spread evenly from each launch.")
    }
    if total.count > shown.count {
      hint("Showing the last \(shown.count) of \(total.count) days. Use --json to see them all.")
    }
  }

  private static func week(_ downloads: Int?) -> String {
    downloads.map { "+\($0.formatted())" } ?? "-"
  }

  /// One line per project found on disk: name, where it stands, when it was last worked on, and its folder.
  static func found(_ projects: [FoundProject]) {
    var rows = projects.map { project in
      [
        project.name,
        project.statusText,
        project.lastActivity?.formatted(.relative(presentation: .named)) ?? "-",
        project.id.replacingOccurrences(of: NSHomeDirectory(), with: "~")
      ]
    }
    if isTerminal {
      rows.insert(["PROJECT", "STATUS", "WORKED ON", "FOLDER"], at: 0)
    }
    columns(rows)
  }

  static func details(_ snapshot: ProjectSnapshot, isTracked: Bool = true) {
    print(snapshot.name)
    if let repository = snapshot.repository {
      print(repository.url.absoluteString)
    }
    if !isTracked {
      print("Not in the list. Add it with: releases add \(snapshot.project.path)")
    }
    print("")

    var rows: [(String, String)] = [("Path", snapshot.project.path)]
    if let source = snapshot.local.version {
      rows.append(("Version", "\(source.version) (\(source.label))"))
    }
    if let branch = snapshot.local.branch {
      var parts = [branch]
      if let unpushed = snapshot.local.unpushedCommitCount, unpushed > 0 {
        parts.append("\(unpushed) not pushed")
      }
      if snapshot.local.hasUncommittedChanges {
        parts.append("uncommitted changes")
      }
      rows.append(("Branch", parts.joined(separator: ", ")))
    }
    rows.append(("Status", snapshot.statusText))
    if !snapshot.releases.isEmpty {
      rows.append(("Downloads", snapshot.totalDownloads.formatted()))
    }
    if let fetchedAt = snapshot.project.releasesFetchedAt {
      rows.append(("Fetched", fetchedAt.formatted(date: .abbreviated, time: .shortened)))
    }

    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      print("\(pad(label + ":", to: width + 2))\(value)")
    }

    if let commits = snapshot.unreleasedCommits, !commits.isEmpty, let latest = snapshot.latestRelease {
      print("\nSince \(latest.tag):")
      columns(commits.map { ["  \($0.hash)", $0.subject] })
    }

    guard !snapshot.releases.isEmpty else {
      if snapshot.project.releases != nil {
        print("\nNo releases on GitHub yet.")
      }
      return
    }

    print("\nReleases:")
    for release in snapshot.releases {
      var flags: [String] = []
      if release.isDraft { flags.append("draft") }
      if release.isPrerelease { flags.append("prerelease") }
      if release.id == snapshot.firstRelease?.id { flags.append("first release") }
      let downloads = release.downloadCount == 1 ? "1 download" : "\(release.downloadCount) downloads"
      print(trimTrailingSpaces(
        (["", release.tag, date(release.publishedAt), downloads, release.url.absoluteString] + flags.map { "[\($0)]" }).joined(separator: "  ")
      ))
      for change in snapshot.changes(in: release) {
        print("      - \(plain(change.headline))")
      }
    }
  }

  /// Markdown without the bold and code markers, for the terminal.
  static func plain(_ markdown: String) -> String {
    markdown.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
  }
}

/// The JSON shape of a release, with the changes pulled out of its notes or the changelog.
struct ReleaseJSON: Encodable {
  var tag: String
  var title: String?
  var publishedAt: Date?
  var url: URL
  var isDraft: Bool
  var isPrerelease: Bool
  var isFirstRelease: Bool
  var downloadCount: Int
  var assets: [ReleaseAsset]
  var changes: [String]

  init(_ release: Release, in snapshot: ProjectSnapshot) {
    tag = release.tag
    title = release.title
    publishedAt = release.publishedAt
    url = release.url
    isDraft = release.isDraft
    isPrerelease = release.isPrerelease
    isFirstRelease = release.id == snapshot.firstRelease?.id
    downloadCount = release.downloadCount
    assets = release.assets
    changes = snapshot.changes(in: release).map(\.text)
  }
}

/// The JSON shape of one release in `releases recent`.
struct TimelineJSON: Encodable {
  var project: String
  var path: String
  var repository: String?
  var tag: String
  var title: String?
  var publishedAt: Date
  var url: URL
  var isPrerelease: Bool
  var isFirstRelease: Bool
  var downloadCount: Int
  var changes: [String]

  init(_ entry: TimelineEntry) {
    project = entry.project.name
    path = entry.project.project.path
    repository = entry.project.repository?.description
    tag = entry.release.tag
    title = entry.release.title
    publishedAt = entry.date
    url = entry.release.url
    isPrerelease = entry.release.isPrerelease
    isFirstRelease = entry.isFirstRelease
    downloadCount = entry.release.downloadCount
    changes = entry.project.changes(in: entry.release).map(\.text)
  }
}

/// The JSON shape of `releases downloads`.
struct DownloadsJSON: Encodable {
  var total: Int
  /// Nil until Releases has a count from a week ago for every project.
  var lastSevenDays: Int?
  var trackedSince: Date?
  var projects: [ProjectDownloadsJSON]

  init(_ snapshots: [ProjectSnapshot], weekAgo: Date) {
    total = snapshots.totalDownloads
    lastSevenDays = snapshots.downloads(since: weekAgo)
    trackedSince = snapshots.downloadsTrackedSince
    projects = snapshots.map { ProjectDownloadsJSON($0, weekAgo: weekAgo) }
  }
}

/// The JSON shape of one day in `releases downloads --by-day`, newest first.
struct DayDownloadsJSON: Encodable {
  struct AppDownloads: Encodable {
    /// The app's name, or "Other" for the apps after the top 5 and the ones under 10 downloads.
    var name: String
    var downloads: Int
  }

  var day: Date
  var downloads: Int
  var total: Int
  var isEstimate: Bool
  var apps: [AppDownloads]

  static func days(_ series: [DownloadSeries]) -> [DayDownloadsJSON] {
    let total = series.total
    let days = total.perDay()
    let apps = series.map { ($0.name, $0.points.perDay()) }
    return total.indices.reversed().map { index in
      DayDownloadsJSON(
        day: total[index].day,
        downloads: days[index].downloads,
        total: total[index].downloads,
        isEstimate: days[index].isEstimate,
        apps: apps.compactMap { name, points in
          points[index].downloads > 0 ? AppDownloads(name: name, downloads: points[index].downloads) : nil
        }
      )
    }
  }
}

/// The JSON shape of one project in `releases downloads`.
struct ProjectDownloadsJSON: Encodable {
  struct ReleaseDownloads: Encodable {
    var tag: String
    var publishedAt: Date?
    var downloads: Int
  }

  var name: String
  var path: String
  var downloads: Int
  var lastSevenDays: Int?
  var releases: [ReleaseDownloads]
  /// One count a day, oldest first.
  var history: [DownloadSample]

  init(_ snapshot: ProjectSnapshot, weekAgo: Date) {
    name = snapshot.name
    path = snapshot.project.path
    downloads = snapshot.totalDownloads
    lastSevenDays = snapshot.downloads(since: weekAgo)
    releases = snapshot.releases.filter { !$0.isDraft }.map {
      ReleaseDownloads(tag: $0.tag, publishedAt: $0.publishedAt, downloads: $0.downloadCount)
    }
    history = snapshot.project.downloadHistory ?? []
  }
}

/// The JSON shape of a project, flat enough for agents and scripts.
struct ProjectJSON: Encodable {
  var name: String
  /// The name read from the folder, when the project has another name in Releases.
  var detectedName: String?
  var path: String
  var isTracked: Bool
  var repository: String?
  var url: URL?
  var version: String?
  var versionFile: String?
  var branch: String?
  var hasUncommittedChanges: Bool
  var status: ReleaseStatus
  var statusText: String
  var latestRelease: ReleaseJSON?
  var unreleasedCommits: [Commit]?
  var releases: [ReleaseJSON]?
  var releasesFetchedAt: Date?

  init(_ snapshot: ProjectSnapshot, includeReleases: Bool, isTracked: Bool = true) {
    name = snapshot.name
    detectedName = snapshot.project.displayName == nil ? nil : snapshot.local.name
    path = snapshot.project.path
    self.isTracked = isTracked
    repository = snapshot.repository?.description
    url = snapshot.repository?.url
    version = snapshot.local.version?.version
    versionFile = snapshot.local.version?.file
    branch = snapshot.local.branch
    hasUncommittedChanges = snapshot.local.hasUncommittedChanges
    status = snapshot.status
    statusText = snapshot.statusText
    latestRelease = snapshot.latestRelease.map { ReleaseJSON($0, in: snapshot) }
    unreleasedCommits = snapshot.unreleasedCommits
    releases = includeReleases ? snapshot.releases.map { ReleaseJSON($0, in: snapshot) } : nil
    releasesFetchedAt = snapshot.project.releasesFetchedAt
  }
}

/// The JSON shape of a project `releases discover` finds on disk.
struct FoundJSON: Encodable {
  var name: String
  var path: String
  var stage: FoundProject.Stage
  var statusText: String
  var lastActivity: Date?
  var repository: String?
  var url: URL?
  var latestRelease: String?
  var version: String?
  var isGitRepository: Bool
  var hasUncommittedChanges: Bool

  init(_ project: FoundProject) {
    name = project.name
    path = project.id
    stage = project.stage
    statusText = project.statusText
    lastActivity = project.lastActivity
    repository = project.snapshot.repository?.description
    url = project.snapshot.repository?.url
    latestRelease = project.snapshot.latestRelease?.tag
    version = project.snapshot.local.version?.version
    isGitRepository = project.snapshot.local.isGitRepository
    hasUncommittedChanges = project.snapshot.local.hasUncommittedChanges
  }
}

struct RenameJSON: Encodable {
  var name: String
  var detectedName: String
  var path: String
}

struct NameJSON: Encodable {
  var name: String
  var path: String
}

struct PromptJSON: Encodable {
  var project: String
  var path: String
  var version: String
  var tag: String
  var prompt: String
  var openedInCursor: Bool
}

struct CheckPromptJSON: Encodable {
  var projects: [NameJSON]
  /// Nil when nothing is waiting to ship.
  var prompt: String?
  var openedInCursor: Bool
}

struct OpenJSON: Encodable {
  /// What opened: app, release, github, cursor or finder.
  var opened: String
  var project: String?
  var path: String?
  var url: URL?
}

struct HelpJSON: Encodable {
  var version: String
  var commands: [CommandSpec]
}
