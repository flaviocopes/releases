import Foundation

/// The prompt that asks an agent to publish a release.
public enum ReleasePrompt {
  /// Commits listed in the prompt. Cursor's deeplinks stop at 10,000 characters.
  static let maxCommits = 30

  public static func make(for snapshot: ProjectSnapshot, version: SemanticVersion, notes: String = "") -> String {
    var lines = ["Release \(snapshot.name) \(version).", ""]

    lines.append("Project: \(snapshot.project.path)")
    if let repository = snapshot.repository {
      lines.append("GitHub: \(repository)")
    }
    if let source = snapshot.local.version {
      lines.append("Current version: \(source.version), set as \(source.label)")
    }

    if let latest = snapshot.latestRelease {
      var line = "Last release: \(latest.tag)"
      if let date = latest.publishedAt {
        line += ", published \(date.formatted(date: .abbreviated, time: .omitted))"
      }
      lines.append(line)

      if let commits = snapshot.unreleasedCommits, !commits.isEmpty {
        lines.append("")
        lines.append("Changes since \(latest.tag):")
        for commit in commits.prefix(maxCommits) {
          lines.append("- \(commit.subject)")
        }
        if commits.count > maxCommits {
          lines.append("- and \(commits.count - maxCommits) more, see git log \(latest.tag)..HEAD")
        }
      }

      lines.append("")
      lines.append(
        "Follow the \"Later releases\" steps of the open-source-release skill if you have it. Set the version to \(version), commit, tag \(version.tag) and push. Build the zip, write the release notes with what's new first, publish the GitHub release and verify the download."
      )
    } else if snapshot.repository == nil {
      lines.append("")
      lines.append(
        "This is the first release, and the project isn't on GitHub yet. Follow the open-source-release skill from the start if you have it, creating the repo too, and use \(version) as the version and \(version.tag) as the tag."
      )
      lines.append(Self.firstReleaseSteps(version, createRepository: true))
    } else {
      lines.append("")
      lines.append(
        "This is the first release. Follow the open-source-release skill from the start if you have it, and use \(version) as the version and \(version.tag) as the tag."
      )
      lines.append(Self.firstReleaseSteps(version, createRepository: false))
    }

    if snapshot.local.hasUncommittedChanges {
      lines.append("")
      lines.append("The working tree has uncommitted changes. Ask me whether they belong in this release before committing anything.")
    }

    let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extra.isEmpty {
      lines.append("")
      lines.append(extra)
    }

    return lines.joined(separator: "\n")
  }

  /// What to do without the skill.
  static func firstReleaseSteps(_ version: SemanticVersion, createRepository: Bool) -> String {
    let start = createRepository ? "Create the GitHub repo and push the project. Then set" : "Set"
    return "Without the skill: \(start) the version to \(version), commit, tag \(version.tag) and push. Build the app and zip it, publish a GitHub release with the zip and notes on what it does and how to install it, and verify the download."
  }
}

public enum CursorError: LocalizedError, Sendable {
  case notInstalled
  case couldNotOpen

  public var errorDescription: String? {
    switch self {
    case .notInstalled: "Cursor isn't installed. Copy the prompt instead."
    case .couldNotOpen: "Cursor didn't open."
    }
  }
}

/// Opens a project in Cursor with a prompt ready in the chat. Cursor asks before running it.
public enum Cursor {
  static let bundleIdentifier = "com.todesktop.230313mzl4w4u92"

  public static var isInstalled: Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["/Applications/Cursor.app", "\(home)/Applications/Cursor.app"]
      .contains { FileManager.default.fileExists(atPath: $0) }
  }

  /// `cursor://anysphere.cursor-deeplink/prompt?text=…`. `+` is encoded too, or it would turn into a space.
  public static func promptURL(_ prompt: String) -> URL {
    var components = URLComponents()
    components.scheme = "cursor"
    components.host = "anysphere.cursor-deeplink"
    components.path = "/prompt"
    components.queryItems = [URLQueryItem(name: "text", value: prompt)]
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url!
  }

  public static func open(_ folder: URL) throws {
    guard isInstalled else { throw CursorError.notInstalled }
    guard Shell.run("/usr/bin/open", ["-b", bundleIdentifier, folder.path]).succeeded else {
      throw CursorError.couldNotOpen
    }
  }

  /// The deeplink can't pick a window, so the folder opens first and the prompt follows once its window is in front.
  public static func start(prompt: String, in folder: URL, delay: Duration = .milliseconds(1500)) async throws {
    try open(folder)
    try await Task.sleep(for: delay)
    guard Shell.run("/usr/bin/open", [promptURL(prompt).absoluteString]).succeeded else {
      throw CursorError.couldNotOpen
    }
  }

  /// Each release in its own window. Cursor needs the pause to take a prompt before the next
  /// folder comes to the front, or the prompt lands in the wrong window.
  public static func start(_ releases: [(prompt: String, folder: URL)], pause: Duration = .seconds(2)) async throws {
    for (index, release) in releases.enumerated() {
      if index > 0 {
        try await Task.sleep(for: pause)
      }
      try await start(prompt: release.prompt, in: release.folder)
    }
  }
}
