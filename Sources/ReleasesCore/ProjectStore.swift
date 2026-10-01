import Foundation

/// The list of project folders, saved as JSON. The app and the CLI share the same file.
public actor ProjectStore {
  public nonisolated let fileURL: URL

  public init(fileURL: URL = ProjectStore.defaultFileURL) {
    self.fileURL = fileURL
  }

  public static var defaultFileURL: URL {
    if let custom = ProcessInfo.processInfo.environment["RELEASES_STORE"], !custom.isEmpty {
      return URL(filePath: custom)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/Releases", directoryHint: .isDirectory)
      .appending(path: "projects.json", directoryHint: .notDirectory)
  }

  public func load() throws -> ProjectList {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return ProjectList()
    }
    let data = try Data(contentsOf: fileURL)
    return try Self.decoder.decode(ProjectList.self, from: data)
  }

  /// Adds a folder. Returns false when it was already in the list.
  @discardableResult
  public func add(_ path: String, at date: Date = .now) throws -> Bool {
    var list = try load()
    guard !list.projects.contains(where: { $0.path == path }) else {
      return false
    }
    list.projects.append(TrackedProject(path: path, addedAt: date))
    try save(list)
    return true
  }

  /// Removes a folder. Returns false when it wasn't in the list.
  @discardableResult
  public func remove(_ path: String) throws -> Bool {
    var list = try load()
    let count = list.projects.count
    list.projects.removeAll { $0.path == path }
    guard list.projects.count != count else { return false }
    try save(list)
    return true
  }

  /// Leaves a folder out of the projects found on disk. Returns false when it was already hidden.
  @discardableResult
  public func hide(_ path: String) throws -> Bool {
    var list = try load()
    var hidden = list.hiddenPaths ?? []
    guard !hidden.contains(path) else { return false }
    hidden.append(path)
    list.hiddenPaths = hidden.sorted()
    try save(list)
    return true
  }

  /// Returns false when the folder wasn't hidden.
  @discardableResult
  public func unhide(_ path: String) throws -> Bool {
    var list = try load()
    guard var hidden = list.hiddenPaths, let index = hidden.firstIndex(of: path) else { return false }
    hidden.remove(at: index)
    list.hiddenPaths = hidden.isEmpty ? nil : hidden
    try save(list)
    return true
  }

  /// Saves what GitHub returned for each project path: its releases, or the error message.
  public func saveFetches(_ fetches: [String: Result<[Release], GitHubError.Message>], at date: Date = .now) throws -> ProjectList {
    var list = try load()
    for index in list.projects.indices {
      guard let fetch = fetches[list.projects[index].path] else { continue }
      switch fetch {
      case .success(let releases):
        list.projects[index].releases = releases
        list.projects[index].releasesFetchedAt = date
        list.projects[index].fetchError = nil
      case .failure(let error):
        list.projects[index].fetchError = error.text
      }
    }
    try save(list)
    return list
  }

  private func save(_ list: ProjectList) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try Self.encoder.encode(list)
    try data.write(to: fileURL, options: .atomic)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

extension GitHubError {
  /// A fetch error as text, so it can be stored and sent between tasks.
  public struct Message: Error, Sendable {
    public var text: String

    public init(_ error: Error) {
      text = error.localizedDescription
    }
  }
}
