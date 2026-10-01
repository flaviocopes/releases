import Foundation

/// A project folder on disk that isn't in the list, like an app that was never released.
public struct FoundProject: Identifiable, Hashable, Sendable {
  /// The project as if it were in the list, with the releases GitHub returned.
  public var snapshot: ProjectSnapshot
  /// The newest commit or file, whichever is more recent.
  public var lastActivity: Date?

  public init(snapshot: ProjectSnapshot, lastActivity: Date? = nil) {
    self.snapshot = snapshot
    self.lastActivity = lastActivity
  }

  public var id: String { snapshot.id }
  public var name: String { snapshot.name }

  public enum Stage: String, Codable, Sendable {
    /// No GitHub remote, or not a git repository at all.
    case notOnGitHub
    /// On GitHub, but its releases weren't fetched.
    case onGitHub
    case notReleased
    case released
  }

  public var stage: Stage {
    guard snapshot.repository != nil else { return .notOnGitHub }
    guard snapshot.project.releases != nil else { return .onGitHub }
    return snapshot.latestRelease == nil ? .notReleased : .released
  }

  public var statusText: String {
    switch stage {
    case .notOnGitHub: "Not on GitHub"
    case .onGitHub: "On GitHub"
    case .notReleased: "Not released yet"
    case .released: "Released \(snapshot.latestRelease?.tag ?? "")"
    }
  }
}

/// Finds apps and CLIs in the folders that hold the tracked projects, like ~/dev.
public enum ProjectFinder {
  /// Where to look when the list is empty, inside the home folder.
  static let usualFolders = ["dev", "Developer", "Projects", "code"]

  /// Folders full of generated files, skipped when looking for the newest file.
  static let generatedFolders: Set<String> = ["node_modules", "build", "dist", "DerivedData", "Pods", "vendor", "target"]

  /// The folders that hold the tracked projects. The home folder is never one of them:
  /// looking inside Desktop or Documents makes macOS ask for permission.
  static func roots(around paths: [String], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
    let homePath = home.standardizedFileURL.path
    var roots: [String] = []
    for path in paths {
      let parent = URL(filePath: path).deletingLastPathComponent().standardizedFileURL.path
      guard parent != homePath, !homePath.hasPrefix(parent + "/"), parent != "/", !roots.contains(parent) else { continue }
      roots.append(parent)
    }
    if roots.isEmpty {
      roots = usualFolders
        .map { home.appending(path: $0, directoryHint: .isDirectory).standardizedFileURL.path }
        .filter { FileManager.default.fileExists(atPath: $0) }
    }
    return roots.map { URL(filePath: $0, directoryHint: .isDirectory) }
  }

  /// Folders right inside `roots` that look like an app or a CLI, minus the `skipping` paths.
  static func candidates(in roots: [URL], skipping: Set<String>) -> [URL] {
    roots.flatMap { root in
      let entries = (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )) ?? []
      return entries.filter { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
          && url.pathExtension != "app"
          && !skipping.contains(url.standardizedFileURL.path)
          && isSoftware(url)
      }
    }
    .sorted { $0.path < $1.path }
  }

  /// Xcode and SwiftPM apps and tools, Electron and Tauri apps, and npm packages with a command.
  static func isSoftware(_ folder: URL) -> Bool {
    if let yaml = ProjectInspector.read(folder, "project.yml"), yaml.contains("targets:") {
      return true
    }
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    if entries.contains(where: { $0.hasSuffix(".xcodeproj") }) {
      return true
    }
    if let manifest = ProjectInspector.read(folder, "Package.swift"),
       manifest.contains("executableTarget(") || manifest.contains(".executable(") {
      return true
    }
    if let json = ProjectInspector.packageJSON(in: folder) {
      if json["bin"] != nil {
        return true
      }
      let dependencies = ["dependencies", "devDependencies"]
        .compactMap { json[$0] as? [String: Any] }
        .flatMap(\.keys)
      if dependencies.contains(where: { $0 == "electron" || $0.hasPrefix("@tauri-apps/") }) {
        return true
      }
    }
    return ProjectInspector.builtApp(in: folder) != nil
  }

  /// Clones of other people's repos, and second copies of tracked projects, aren't worth showing.
  /// `owners` are the GitHub accounts of the tracked projects, lowercased. Empty means anyone's.
  static func isWorthShowing(_ repository: GitHubRepository?, owners: Set<String>, tracked: Set<String>) -> Bool {
    guard let repository else { return true }
    if tracked.contains(repository.description.lowercased()) { return false }
    return owners.isEmpty || owners.contains(repository.owner.lowercased())
  }

  /// The newest commit or file, whichever is more recent. Looks at `limit` files at most.
  static func lastActivity(of folder: URL, limit: Int = 2000) -> Date? {
    var newest = Git(directory: folder).lastCommitDate
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
    guard let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return newest
    }

    var count = 0
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isDirectory == true, generatedFolders.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }
      if let date = values?.contentModificationDate, date > (newest ?? .distantPast) {
        newest = date
      }
      count += 1
      if count >= limit { break }
    }
    return newest
  }
}
