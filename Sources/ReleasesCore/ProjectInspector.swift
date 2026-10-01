import Foundation

/// Where a project keeps its version, like `MARKETING_VERSION` in `project.yml`.
public struct VersionSource: Codable, Hashable, Sendable {
  public var version: String
  /// Path relative to the project folder.
  public var file: String
  public var key: String

  public init(version: String, file: String, key: String) {
    self.version = version
    self.file = file
    self.key = key
  }

  public var semantic: SemanticVersion? {
    SemanticVersion(version)
  }

  public var label: String {
    "\(key) in \(file)"
  }
}

/// What the project folder says about itself, read from disk and git.
public struct LocalProject: Codable, Hashable, Sendable {
  public var name: String
  public var exists: Bool
  public var isGitRepository: Bool
  public var repository: GitHubRepository?
  public var version: VersionSource?
  /// A built copy of the app, used for its icon.
  public var appPath: String?
  public var iconPath: String?
  public var branch: String?
  public var hasUncommittedChanges: Bool
  public var unpushedCommitCount: Int?
  /// The changes of each version in the project's CHANGELOG.md, keyed by `major.minor.patch`.
  public var changelog: [String: [Change]]?

  public init(
    name: String,
    exists: Bool = true,
    isGitRepository: Bool = true,
    repository: GitHubRepository? = nil,
    version: VersionSource? = nil,
    appPath: String? = nil,
    iconPath: String? = nil,
    branch: String? = nil,
    hasUncommittedChanges: Bool = false,
    unpushedCommitCount: Int? = nil,
    changelog: [String: [Change]]? = nil
  ) {
    self.name = name
    self.exists = exists
    self.isGitRepository = isGitRepository
    self.repository = repository
    self.version = version
    self.appPath = appPath
    self.iconPath = iconPath
    self.branch = branch
    self.hasUncommittedChanges = hasUncommittedChanges
    self.unpushedCommitCount = unpushedCommitCount
    self.changelog = changelog
  }
}

public struct ProjectInspector: Sendable {
  public init() {}

  public func inspect(_ folder: URL) -> LocalProject {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return LocalProject(name: folder.lastPathComponent, exists: false, isGitRepository: false)
    }

    let git = Git(directory: folder)
    let isGitRepository = git.root != nil
    let repository = git.remoteURL.flatMap(GitHubRepository.init(remoteURL:))
    let appPath = Self.builtApp(in: folder)

    return LocalProject(
      name: Self.name(of: folder, appPath: appPath, repository: repository),
      isGitRepository: isGitRepository,
      repository: repository,
      version: Self.version(in: folder),
      appPath: appPath,
      iconPath: appPath == nil ? Self.iconFile(in: folder) : nil,
      branch: isGitRepository ? git.branch : nil,
      hasUncommittedChanges: isGitRepository && git.hasUncommittedChanges,
      unpushedCommitCount: isGitRepository ? git.unpushedCommitCount : nil,
      changelog: Changelog.load(in: folder)
    )
  }

  /// The top folder of the git repository that contains `url`, so dropping a subfolder adds the whole project.
  public func projectRoot(for url: URL) -> URL {
    guard let root = Git(directory: url).root else { return url }
    return URL(filePath: root, directoryHint: .isDirectory)
  }

  // MARK: - Name and icon

  static func name(of folder: URL, appPath: String?, repository: GitHubRepository?) -> String {
    if let appPath {
      return URL(filePath: appPath).deletingPathExtension().lastPathComponent
    }
    if let yaml = read(folder, "project.yml"),
       let match = yaml.firstMatch(of: /(?m)^name:\s*"?([^"\n]+?)"?\s*$/) {
      return String(match.output.1)
    }
    if let json = packageJSON(in: folder) {
      let build = json["build"] as? [String: Any]
      if let name = (json["productName"] ?? build?["productName"] ?? json["name"]) as? String, !name.isEmpty {
        return name
      }
    }
    return repository?.name ?? folder.lastPathComponent
  }

  /// Folders where the build scripts of Xcode, SwiftPM and Electron apps put the app.
  static let appFolders = [
    "dist",
    "build",
    "build/release/Release",
    "build/Build/Products/Release",
    "dist/mac-universal",
    "dist/mac-arm64",
    "dist/mac",
    "release"
  ]

  static func builtApp(in folder: URL) -> String? {
    for relative in appFolders {
      let directory = folder.appending(path: relative, directoryHint: .isDirectory)
      guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
      if let app = entries.sorted().first(where: { $0.hasSuffix(".app") && !$0.contains("Screenshot") }) {
        return directory.appending(path: app).path
      }
    }
    return nil
  }

  static let iconFiles = [
    "Assets/AppIcon.png",
    "resources/AppIcon.png",
    "resources/icon.png",
    "build/icon.png",
    "icon.png"
  ]

  static func iconFile(in folder: URL) -> String? {
    iconFiles
      .map { folder.appending(path: $0).path }
      .first { FileManager.default.fileExists(atPath: $0) }
  }

  // MARK: - Version

  static func version(in folder: URL) -> VersionSource? {
    if let yaml = read(folder, "project.yml"),
       let match = yaml.firstMatch(of: /(?m)^\s*MARKETING_VERSION:\s*"?([0-9][^"\s]*)"?/) {
      return VersionSource(version: String(match.output.1), file: "project.yml", key: "MARKETING_VERSION")
    }

    if let version = packageJSON(in: folder)?["version"] as? String, !version.isEmpty {
      return VersionSource(version: version, file: "package.json", key: "version")
    }

    if let source = swiftConstant(in: folder) {
      return source
    }

    return xcodeProject(in: folder)
  }

  /// Finds a constant like `static let version = "1.0.0"` in `Sources/`, the way SwiftPM apps keep it.
  static func swiftConstant(in folder: URL) -> VersionSource? {
    let sources = folder.appending(path: "Sources", directoryHint: .isDirectory)
    guard let enumerator = FileManager.default.enumerator(
      at: sources,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }

    let pattern = /(?:let|var)\s+(version|current|appVersion|currentVersion)\s*(?::\s*String)?\s*=\s*"(\d+\.\d+(?:\.\d+)?)"/
    var files: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if size < 200_000 { files.append(url) }
      if files.count >= 500 { break }
    }

    // Version.swift and Commands.swift go first, so a constant elsewhere doesn't win by accident.
    files.sort { rank($0) < rank($1) || (rank($0) == rank($1) && $0.path < $1.path) }

    let base = folder.resolvingSymlinksInPath().pathComponents
    for url in files {
      guard let text = try? String(contentsOf: url, encoding: .utf8),
            let match = text.firstMatch(of: pattern) else { continue }
      let relative = url.resolvingSymlinksInPath().pathComponents.dropFirst(base.count).joined(separator: "/")
      return VersionSource(version: String(match.output.2), file: relative, key: String(match.output.1))
    }
    return nil
  }

  private static func rank(_ url: URL) -> Int {
    switch url.lastPathComponent {
    case "Version.swift": 0
    case "Commands.swift": 1
    default: 2
    }
  }

  static func xcodeProject(in folder: URL) -> VersionSource? {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
          let project = entries.sorted().first(where: { $0.hasSuffix(".xcodeproj") }) else {
      return nil
    }
    let file = "\(project)/project.pbxproj"
    guard let text = read(folder, file),
          let match = text.firstMatch(of: /MARKETING_VERSION = "?([0-9][^";]*)"?;/) else {
      return nil
    }
    return VersionSource(version: String(match.output.1), file: file, key: "MARKETING_VERSION")
  }

  // MARK: - Files

  static func read(_ folder: URL, _ relative: String) -> String? {
    try? String(contentsOf: folder.appending(path: relative), encoding: .utf8)
  }

  static func packageJSON(in folder: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: folder.appending(path: "package.json")) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}
