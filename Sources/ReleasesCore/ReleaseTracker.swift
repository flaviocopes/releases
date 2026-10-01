import Foundation

public enum AddError: LocalizedError, Sendable {
  case notAFolder(String)

  public var errorDescription: String? {
    switch self {
    case .notAFolder(let path): "'\(path)' isn't a folder."
    }
  }
}

/// Reads the project list, inspects each folder and fetches the releases from GitHub.
public struct ReleaseTracker: Sendable {
  public let store: ProjectStore
  private let inspector = ProjectInspector()
  private let github: GitHubClient

  public init(store: ProjectStore = ProjectStore(), github: GitHubClient = GitHubClient()) {
    self.store = store
    self.github = github
  }

  /// Every project, from disk and the cached releases. No network.
  public func snapshots() async throws -> [ProjectSnapshot] {
    let list = try await store.load()
    return await inspect(list.projects).sortedByRelease()
  }

  /// Fetches the releases of projects whose cache is older than `maxAge`, then returns every project.
  /// A nil `maxAge` fetches them all. `only` limits the fetch to some project paths.
  public func refresh(maxAge: TimeInterval? = nil, only: Set<String>? = nil, now: Date = .now) async throws -> [ProjectSnapshot] {
    let list = try await store.load()
    let locals = await inspect(list.projects)

    let stale = locals.filter { snapshot in
      guard snapshot.repository != nil else { return false }
      if let only, !only.contains(snapshot.id) { return false }
      guard let maxAge, let fetchedAt = snapshot.project.releasesFetchedAt else { return true }
      return now.timeIntervalSince(fetchedAt) > maxAge
    }
    guard !stale.isEmpty else { return locals.sortedByRelease() }

    let github = github
    let fetches = await withTaskGroup(of: (String, Result<[Release], GitHubError.Message>).self) { group in
      for snapshot in stale {
        guard let repository = snapshot.repository else { continue }
        group.addTask {
          do {
            return (snapshot.id, .success(try await github.releases(of: repository)))
          } catch {
            return (snapshot.id, .failure(GitHubError.Message(error)))
          }
        }
      }
      var results: [String: Result<[Release], GitHubError.Message>] = [:]
      for await (path, result) in group {
        results[path] = result
      }
      return results
    }

    let updated = try await store.saveFetches(fetches, at: now)
    return await inspect(updated.projects).sortedByRelease()
  }

  /// Adds the project that contains `url`, fetches its releases and returns it.
  public func add(_ url: URL) async throws -> (snapshot: ProjectSnapshot, isNew: Bool) {
    let folder = url.standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw AddError.notAFolder(url.path)
    }

    let root = inspector.projectRoot(for: folder).path
    let isNew = try await store.add(root)
    let snapshots = try await refresh(maxAge: isNew ? nil : 300, only: [root])
    guard let snapshot = snapshots.first(where: { $0.id == root }) else {
      throw ProjectLookupError.notFound(root, known: [])
    }
    return (snapshot, isNew)
  }

  @discardableResult
  public func remove(_ path: String) async throws -> Bool {
    try await store.remove(path)
  }

  // MARK: - Projects on disk

  /// Apps and CLIs next to the tracked projects that aren't in the list or hidden, the most recently
  /// worked on first. Clones of other people's repos are left out. `fetchReleases` asks GitHub for
  /// the releases of the ones on GitHub.
  public func discover(fetchReleases: Bool = true) async throws -> [FoundProject] {
    let list = try await store.load()
    let trackedRepositories = list.projects.compactMap {
      Git(directory: $0.url).remoteURL.flatMap(GitHubRepository.init(remoteURL:))
    }
    let owners = Set(trackedRepositories.map { $0.owner.lowercased() })
    let tracked = Set(trackedRepositories.map { $0.description.lowercased() })
    let folders = ProjectFinder.candidates(
      in: ProjectFinder.roots(around: list.projects.map(\.path)),
      skipping: Set(list.projects.map(\.path) + (list.hiddenPaths ?? []))
    )

    let projects = await withTaskGroup(of: FoundProject?.self) { group in
      for folder in folders {
        group.addTask {
          let local = inspector.inspect(folder)
          guard ProjectFinder.isWorthShowing(local.repository, owners: owners, tracked: tracked) else { return nil }
          return await self.found(folder, local: local, fetchReleases: fetchReleases)
        }
      }
      var projects: [FoundProject] = []
      for await project in group {
        if let project { projects.append(project) }
      }
      return projects
    }
    return projects.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
  }

  /// A folder as a project that isn't in the list. `fetchReleases` asks GitHub for its releases.
  public func found(at folder: URL, fetchReleases: Bool = true) async -> FoundProject {
    await found(folder, local: inspector.inspect(folder), fetchReleases: fetchReleases)
  }

  private func found(_ folder: URL, local: LocalProject, fetchReleases: Bool) async -> FoundProject {
    var project = TrackedProject(path: folder.standardizedFileURL.path)
    if fetchReleases, let repository = local.repository {
      do {
        project.releases = try await github.releases(of: repository)
        project.releasesFetchedAt = .now
      } catch {
        project.fetchError = error.localizedDescription
      }
    }

    var snapshot = ProjectSnapshot(project: project, local: local)
    if local.isGitRepository, let tag = snapshot.latestRelease?.tag {
      snapshot.unreleasedCommits = Git(directory: folder).commits(since: tag)
    }
    let lastActivity = local.exists ? ProjectFinder.lastActivity(of: folder) : nil
    return FoundProject(snapshot: snapshot, lastActivity: lastActivity)
  }

  /// A tracked project, or any project folder on disk: its path, or the name of one `discover` finds.
  public func lookup(_ identifier: String, fetchReleases: Bool = true) async throws -> (snapshot: ProjectSnapshot, isTracked: Bool) {
    let tracked = try await snapshots()
    do {
      return (try tracked.project(matching: identifier), true)
    } catch ProjectLookupError.notFound {}

    let url = URL(filePath: (identifier as NSString).expandingTildeInPath, directoryHint: .isDirectory)
      .absoluteURL
      .standardizedFileURL
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
      let root = inspector.projectRoot(for: url)
      if let match = tracked.first(where: { $0.id == root.standardizedFileURL.path }) {
        return (match, true)
      }
      return (await found(at: root, fetchReleases: fetchReleases).snapshot, false)
    }

    let onDisk = try await discover(fetchReleases: false).map(\.snapshot)
    let match: ProjectSnapshot
    do {
      match = try onDisk.project(matching: identifier)
    } catch ProjectLookupError.notFound {
      throw ProjectLookupError.notFound(identifier, known: tracked.map(\.name))
    }
    guard fetchReleases else { return (match, false) }
    return (await self.found(at: match.project.url).snapshot, false)
  }

  @discardableResult
  public func hide(_ path: String) async throws -> Bool {
    try await store.hide(path)
  }

  public func hiddenPaths() async throws -> [String] {
    try await store.load().hiddenPaths ?? []
  }

  /// Shows a hidden folder again. `identifier` is its path or folder name. Returns the path.
  @discardableResult
  public func unhide(_ identifier: String) async throws -> String {
    let hidden = try await hiddenPaths()
    let path = URL(filePath: (identifier as NSString).expandingTildeInPath).absoluteURL.standardizedFileURL.path
    let exact = hidden.filter { $0 == path }
    let matches = exact.isEmpty
      ? hidden.filter { URL(filePath: $0).lastPathComponent.lowercased() == identifier.lowercased() }
      : exact
    switch matches.count {
    case 0: throw ProjectLookupError.notHidden(identifier, hidden: hidden)
    case 1:
      try await store.unhide(matches[0])
      return matches[0]
    default: throw ProjectLookupError.ambiguous(identifier, candidates: matches)
    }
  }

  /// Inspects the folders in parallel. Each one runs a few quick git commands.
  private func inspect(_ projects: [TrackedProject]) async -> [ProjectSnapshot] {
    let inspector = inspector
    return await withTaskGroup(of: ProjectSnapshot.self) { group in
      for project in projects {
        group.addTask {
          Self.snapshot(of: project, inspector: inspector)
        }
      }
      var snapshots: [ProjectSnapshot] = []
      for await snapshot in group {
        snapshots.append(snapshot)
      }
      return snapshots
    }
  }

  static func snapshot(of project: TrackedProject, inspector: ProjectInspector) -> ProjectSnapshot {
    let local = inspector.inspect(project.url)
    var snapshot = ProjectSnapshot(project: project, local: local)
    if local.isGitRepository, let tag = snapshot.latestRelease?.tag {
      snapshot.unreleasedCommits = Git(directory: project.url).commits(since: tag)
    }
    return snapshot
  }
}
