import Foundation

public enum ReleaseStatus: String, Codable, Sendable {
  /// The folder is gone.
  case missing
  /// No `origin` remote on GitHub.
  case noRepository
  /// GitHub hasn't answered yet, or the last fetch failed.
  case notLoaded
  case neverReleased
  /// The project's version is newer than the latest release.
  case readyToRelease
  /// Commits landed after the latest release's tag.
  case unreleasedChanges
  case upToDate
  /// The project's version is older than the latest release.
  case versionBehind
}

/// Everything known about one project: its folder, its git state and its GitHub releases.
public struct ProjectSnapshot: Identifiable, Hashable, Sendable {
  public var project: TrackedProject
  public var local: LocalProject
  /// Commits after the latest release's tag. Nil when there's no release or the tag isn't local.
  public var unreleasedCommits: [Commit]?

  public init(project: TrackedProject, local: LocalProject, unreleasedCommits: [Commit]? = nil) {
    self.project = project
    self.local = local
    self.unreleasedCommits = unreleasedCommits
  }

  public var id: String { project.id }
  /// The name given in Releases, or the one read from the folder.
  public var name: String { project.displayName ?? local.name }

  /// The name to store for what someone typed: nil when it's empty or the folder's own name.
  public func displayName(for input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed == local.name ? nil : trimmed
  }
  public var repository: GitHubRepository? { local.repository }
  public var releases: [Release] { project.releases ?? [] }

  public var latestRelease: Release? {
    releases.first(where: \.isPublic)
  }

  /// The release that launched the project: its oldest public one, whatever its version.
  public var firstRelease: Release? {
    releases.last(where: \.isPublic)
  }

  public var localVersion: SemanticVersion? {
    local.version?.semantic
  }

  public var status: ReleaseStatus {
    guard local.exists else { return .missing }
    guard repository != nil else { return .noRepository }
    guard project.releases != nil else { return .notLoaded }
    guard let latest = latestRelease else { return .neverReleased }

    if let localVersion, let released = latest.version {
      if localVersion > released { return .readyToRelease }
      if localVersion < released { return .versionBehind }
    }
    if let unreleasedCommits, !unreleasedCommits.isEmpty {
      return .unreleasedChanges
    }
    return .upToDate
  }

  public var statusText: String {
    switch status {
    case .missing:
      "Folder not found"
    case .noRepository:
      local.isGitRepository ? "No GitHub remote" : "Not a git repository"
    case .notLoaded:
      project.fetchError ?? "Loading releases…"
    case .neverReleased:
      "Not released yet"
    case .readyToRelease:
      "\(localVersion?.description ?? "") ready to release"
    case .unreleasedChanges:
      "\(Self.commitCount(unreleasedCommits?.count ?? 0)) since \(latestRelease?.tag ?? "the last release")"
    case .upToDate:
      "Up to date"
    case .versionBehind:
      "The project says \(local.version?.version ?? "?"), GitHub has \(latestRelease?.tag ?? "?")"
    }
  }

  /// Released before, with commits or a newer version that aren't in a release yet.
  public var isWaitingToShip: Bool {
    status == .unreleasedChanges || status == .readyToRelease
  }

  /// The version to propose for the next release.
  public var suggestedVersion: SemanticVersion {
    switch (localVersion, latestRelease?.version) {
    case let (local?, released?) where local > released: local
    case let (_, released?): released.bumped(.patch)
    case let (local?, nil): local
    case (nil, nil): SemanticVersion(major: 1, minor: 0, patch: 0)
    }
  }

  /// The version the bump buttons start from: the latest release, or the project's version before the first one.
  public var bumpBase: SemanticVersion {
    latestRelease?.version ?? localVersion ?? SemanticVersion(major: 0, minor: 9, patch: 0)
  }

  public var totalDownloads: Int {
    releases.reduce(0) { $0 + $1.downloadCount }
  }

  /// What changed in a release: its section of CHANGELOG.md, or the changes in its GitHub notes.
  public func changes(in release: Release) -> [Change] {
    if let version = release.version?.description, let changes = local.changelog?[version], !changes.isEmpty {
      return changes
    }
    return ReleaseNotes.changes(in: release.notes ?? "")
  }

  static func commitCount(_ count: Int) -> String {
    count == 1 ? "1 commit" : "\(count) commits"
  }
}

public enum ProjectLookupError: LocalizedError, Sendable {
  case notFound(String, known: [String])
  case ambiguous(String, candidates: [String])
  case notHidden(String, hidden: [String])

  public var errorDescription: String? {
    switch self {
    case .notFound(let value, let known):
      known.isEmpty
        ? "No project matches '\(value)'. The list is empty, add one with 'releases add <folder>'."
        : "No project matches '\(value)'. Projects: \(known.joined(separator: ", ")). Run 'releases discover' for the ones on disk."
    case .ambiguous(let value, let candidates):
      "More than one project matches '\(value)'. Use the folder path:\n\(candidates.map { "  \($0)" }.joined(separator: "\n"))"
    case .notHidden(let value, let hidden):
      hidden.isEmpty
        ? "'\(value)' isn't hidden. Nothing is."
        : "'\(value)' isn't hidden. Hidden folders:\n\(hidden.map { "  \($0)" }.joined(separator: "\n"))"
    }
  }
}

/// One release of one project, for the timeline of every project's releases.
public struct TimelineEntry: Identifiable, Hashable, Sendable {
  public var project: ProjectSnapshot
  public var release: Release
  public var date: Date

  public var id: String { "\(project.id)#\(release.tag)" }

  /// A new app: the project's first public release.
  public var isFirstRelease: Bool {
    project.firstRelease?.tag == release.tag
  }
}

extension [ProjectSnapshot] {
  /// Every published release of every project, newest first. Drafts have no date, so they're left out.
  public func timeline() -> [TimelineEntry] {
    flatMap { project in
      project.releases.compactMap { release in
        guard !release.isDraft, let date = release.publishedAt else { return nil }
        return TimelineEntry(project: project, release: release, date: date)
      }
    }
    .sorted { $0.date > $1.date }
  }

  /// Newest release first. Projects without releases follow, by name.
  public func sortedByRelease() -> [ProjectSnapshot] {
    sorted { lhs, rhs in
      switch (lhs.latestRelease?.publishedAt, rhs.latestRelease?.publishedAt) {
      case let (l?, r?): l > r
      case (_?, nil): true
      case (nil, _?): false
      case (nil, nil): lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
    }
  }

  /// Finds a project by path, folder name, app name, or GitHub repo (`owner/name` or `name`).
  public func project(matching identifier: String) throws -> ProjectSnapshot {
    let expanded = (identifier as NSString).expandingTildeInPath
    let path = URL(filePath: expanded).standardizedFileURL.path
    if let exact = first(where: { $0.project.path == path }) {
      return exact
    }

    let needle = identifier.lowercased()
    let matches = filter { snapshot in
      [
        snapshot.project.folderName,
        snapshot.name,
        snapshot.local.name,
        snapshot.repository?.description,
        snapshot.repository?.name
      ]
      .compactMap { $0?.lowercased() }
      .contains(needle)
    }

    switch matches.count {
    case 1: return matches[0]
    case 0: throw ProjectLookupError.notFound(identifier, known: map(\.name))
    default: throw ProjectLookupError.ambiguous(identifier, candidates: matches.map(\.project.path))
    }
  }
}
