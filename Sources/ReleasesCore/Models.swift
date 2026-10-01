import Foundation

/// A GitHub repository, like `flaviocopes/soundscape`.
public struct GitHubRepository: Codable, Hashable, Sendable, CustomStringConvertible {
  public var owner: String
  public var name: String

  public init(owner: String, name: String) {
    self.owner = owner
    self.name = name
  }

  /// Reads `https://github.com/owner/name(.git)`, `git@github.com:owner/name.git`
  /// and `ssh://git@github.com/owner/name`. Returns nil for other hosts.
  public init?(remoteURL: String) {
    let pattern = /github\.com[:\/]([A-Za-z0-9_.\-]+)\/([A-Za-z0-9_.\-]+?)(?:\.git)?\/?$/
    guard let match = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).firstMatch(of: pattern) else {
      return nil
    }
    owner = String(match.output.1)
    name = String(match.output.2)
  }

  public var description: String {
    "\(owner)/\(name)"
  }

  public var url: URL {
    URL(string: "https://github.com/\(owner)/\(name)")!
  }

  public var releasesURL: URL {
    url.appending(path: "releases")
  }
}

public struct ReleaseAsset: Codable, Hashable, Sendable {
  public var name: String
  public var size: Int
  public var downloadCount: Int
  public var downloadURL: URL
  /// GitHub's checksum of the upload, like `sha256:8b08…`.
  public var digest: String?

  public init(name: String, size: Int, downloadCount: Int, downloadURL: URL, digest: String? = nil) {
    self.name = name
    self.size = size
    self.downloadCount = downloadCount
    self.downloadURL = downloadURL
    self.digest = digest
  }
}

/// A release published on GitHub.
public struct Release: Codable, Hashable, Sendable, Identifiable {
  public var tag: String
  public var title: String?
  public var publishedAt: Date?
  public var url: URL
  public var isDraft: Bool
  public var isPrerelease: Bool
  public var notes: String?
  public var assets: [ReleaseAsset]

  public init(
    tag: String,
    title: String? = nil,
    publishedAt: Date? = nil,
    url: URL,
    isDraft: Bool = false,
    isPrerelease: Bool = false,
    notes: String? = nil,
    assets: [ReleaseAsset] = []
  ) {
    self.tag = tag
    self.title = title
    self.publishedAt = publishedAt
    self.url = url
    self.isDraft = isDraft
    self.isPrerelease = isPrerelease
    self.notes = notes
    self.assets = assets
  }

  public var id: String { tag }

  public var version: SemanticVersion? {
    SemanticVersion(tag)
  }

  public var downloadCount: Int {
    assets.reduce(0) { $0 + $1.downloadCount }
  }

  /// Drafts and prereleases don't count as the latest release, the same way the updater sees it.
  public var isPublic: Bool {
    !isDraft && !isPrerelease
  }
}

/// A project folder in the list, with the releases last fetched from GitHub.
public struct TrackedProject: Codable, Hashable, Sendable, Identifiable {
  public var path: String
  public var addedAt: Date
  /// A name given in Releases, shown instead of the one read from the folder. It changes nothing in the project.
  public var displayName: String?
  public var releases: [Release]?
  public var releasesFetchedAt: Date?
  public var fetchError: String?

  public init(path: String, addedAt: Date = .now) {
    self.path = path
    self.addedAt = addedAt
  }

  public var id: String { path }

  public var url: URL {
    URL(filePath: path, directoryHint: .isDirectory)
  }

  public var folderName: String {
    url.lastPathComponent
  }
}

public struct ProjectList: Codable, Sendable {
  public var projects: [TrackedProject] = []
  /// Folders left out of the projects found on disk.
  public var hiddenPaths: [String]?

  public init(projects: [TrackedProject] = [], hiddenPaths: [String]? = nil) {
    self.projects = projects
    self.hiddenPaths = hiddenPaths
  }
}

public struct Commit: Codable, Hashable, Sendable, Identifiable {
  public var hash: String
  public var subject: String
  public var date: Date?

  public init(hash: String, subject: String, date: Date? = nil) {
    self.hash = hash
    self.subject = subject
    self.date = date
  }

  public var id: String { hash }
}
