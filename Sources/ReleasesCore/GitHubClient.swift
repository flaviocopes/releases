import Foundation

public enum GitHubError: LocalizedError, Sendable {
  case notFound(GitHubRepository)
  case rateLimited(resetsAt: Date?)
  case http(Int)

  public var errorDescription: String? {
    switch self {
    case .notFound(let repository):
      "GitHub can't find \(repository). If the repo is private, sign in with 'gh auth login'."
    case .rateLimited(let resetsAt):
      if let resetsAt {
        "GitHub's rate limit is used up until \(resetsAt.formatted(date: .omitted, time: .shortened)). Sign in with 'gh auth login' for a higher limit."
      } else {
        "GitHub's rate limit is used up. Sign in with 'gh auth login' for a higher limit."
      }
    case .http(let status):
      "GitHub answered with HTTP \(status)."
    }
  }
}

public struct GitHubClient: Sendable {
  private let token: String?
  private let session: URLSession

  public init(token: String? = GitHubClient.defaultToken(), session: URLSession = .shared) {
    self.token = token
    self.session = session
  }

  /// `GH_TOKEN` or `GITHUB_TOKEN`, or the token of the `gh` CLI. Nil means unauthenticated
  /// requests: public repos only, 60 an hour.
  public static func defaultToken() -> String? {
    let environment = ProcessInfo.processInfo.environment
    if let token = environment["GH_TOKEN"] ?? environment["GITHUB_TOKEN"], !token.isEmpty {
      return token
    }
    guard let gh = Shell.find("gh") else { return nil }
    let result = Shell.run(gh, ["auth", "token"])
    return result.succeeded && !result.output.isEmpty ? result.output : nil
  }

  public var isAuthenticated: Bool {
    token != nil
  }

  /// The newest 100 releases, drafts included when the token can see them.
  public func releases(of repository: GitHubRepository) async throws -> [Release] {
    var request = URLRequest(
      url: URL(string: "https://api.github.com/repos/\(repository.owner)/\(repository.name)/releases?per_page=100")!
    )
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("Releases", forHTTPHeaderField: "User-Agent")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.timeoutInterval = 20

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0

    switch status {
    case 200:
      return try Self.decodeReleases(data)
    case 404:
      throw GitHubError.notFound(repository)
    case 403, 429:
      let reset = (response as? HTTPURLResponse)?
        .value(forHTTPHeaderField: "X-RateLimit-Reset")
        .flatMap(TimeInterval.init)
        .map { Date(timeIntervalSince1970: $0) }
      throw GitHubError.rateLimited(resetsAt: reset)
    default:
      throw GitHubError.http(status)
    }
  }

  static func decodeReleases(_ data: Data) throws -> [Release] {
    struct APIAsset: Decodable {
      var name: String
      var size: Int
      var download_count: Int
      var browser_download_url: URL
      var digest: String?
    }

    struct APIRelease: Decodable {
      var tag_name: String
      var name: String?
      var published_at: Date?
      var created_at: Date?
      var html_url: URL
      var draft: Bool
      var prerelease: Bool
      var body: String?
      var assets: [APIAsset]
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let releases = try decoder.decode([APIRelease].self, from: data)

    return releases.map { release in
      Release(
        tag: release.tag_name,
        title: release.name?.isEmpty == false ? release.name : nil,
        publishedAt: release.published_at ?? release.created_at,
        url: release.html_url,
        isDraft: release.draft,
        isPrerelease: release.prerelease,
        notes: release.body?.isEmpty == false ? release.body : nil,
        assets: release.assets.map {
          ReleaseAsset(
            name: $0.name,
            size: $0.size,
            downloadCount: $0.download_count,
            downloadURL: $0.browser_download_url,
            digest: $0.digest
          )
        }
      )
    }
    .sorted { ($0.publishedAt ?? .distantFuture) > ($1.publishedAt ?? .distantFuture) }
  }
}
