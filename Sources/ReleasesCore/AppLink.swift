import Foundation

public enum AppLinkError: LocalizedError, Sendable {
  case appNotFound

  public var errorDescription: String? {
    switch self {
    case .appNotFound:
      "The Releases app didn't open. Build it with ./Scripts/build-app.sh, which also registers its releases:// links."
    }
  }
}

/// A `releases://` link that tells the app what to show. `releases open` sends them.
public enum AppLink: Hashable, Sendable {
  /// The Latest Releases page.
  case home
  /// A project, in the list or just a folder on disk.
  case project(path: String)
  /// The Create Release sheet of a project, with the version and the notes filled in.
  case release(path: String, version: SemanticVersion?, notes: String?)
  /// Fetch the releases from GitHub and look for projects on disk, like ⌘R.
  case refresh

  public static let scheme = "releases"

  public var url: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    switch self {
    case .home:
      components.host = "home"
    case .project(let path):
      components.host = "project"
      components.queryItems = [URLQueryItem(name: "path", value: path)]
    case .release(let path, let version, let notes):
      components.host = "release"
      components.queryItems = [URLQueryItem(name: "path", value: path)]
      if let version {
        components.queryItems?.append(URLQueryItem(name: "version", value: version.description))
      }
      if let notes, !notes.isEmpty {
        components.queryItems?.append(URLQueryItem(name: "notes", value: notes))
      }
    case .refresh:
      components.host = "refresh"
    }
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url!
  }

  public init?(url: URL) {
    guard url.scheme == Self.scheme,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    func value(_ name: String) -> String? {
      guard let value = components.queryItems?.first(where: { $0.name == name })?.value, !value.isEmpty else { return nil }
      return value
    }

    switch components.host ?? "" {
    case "", "home":
      self = .home
    case "project":
      guard let path = value("path") else { return nil }
      self = .project(path: path)
    case "release":
      guard let path = value("path") else { return nil }
      self = .release(path: path, version: value("version").flatMap(SemanticVersion.init), notes: value("notes"))
    case "refresh":
      self = .refresh
    default:
      return nil
    }
  }

  /// Opens the link with Launch Services, which starts the app when it isn't running.
  /// `inBackground` leaves the app behind the current window.
  public func open(inBackground: Bool = false) throws {
    guard Shell.run("/usr/bin/open", (inBackground ? ["-g"] : []) + [url.absoluteString]).succeeded else {
      throw AppLinkError.appNotFound
    }
  }

  /// Whether the built app is running, so a link can reach it without launching it.
  public static var isAppRunning: Bool {
    Shell.run("/usr/bin/pgrep", ["-x", "Releases"]).succeeded
  }
}
