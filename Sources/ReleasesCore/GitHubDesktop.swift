import Foundation

public enum GitHubDesktopError: LocalizedError, Sendable {
  case notInstalled
  case couldNotOpen

  public var errorDescription: String? {
    switch self {
    case .notInstalled: "GitHub Desktop isn't installed."
    case .couldNotOpen: "GitHub Desktop didn't open."
    }
  }
}

/// Opens a project folder in GitHub Desktop, which adds the repository the first time.
public enum GitHubDesktop {
  static let bundleIdentifier = "com.github.GitHubClient"

  public static var isInstalled: Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["/Applications/GitHub Desktop.app", "\(home)/Applications/GitHub Desktop.app"]
      .contains { FileManager.default.fileExists(atPath: $0) }
  }

  public static func open(_ folder: URL) throws {
    guard isInstalled else { throw GitHubDesktopError.notInstalled }
    guard Shell.run("/usr/bin/open", ["-b", bundleIdentifier, folder.path]).succeeded else {
      throw GitHubDesktopError.couldNotOpen
    }
  }
}
