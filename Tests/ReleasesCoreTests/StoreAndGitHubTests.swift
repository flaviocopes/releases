import Foundation
import Testing
@testable import ReleasesCore

struct ProjectStoreTests {
  private func store() -> ProjectStore {
    ProjectStore(fileURL: FileManager.default.temporaryDirectory
      .appending(path: "releases-store-\(UUID().uuidString)")
      .appending(path: "projects.json"))
  }

  @Test
  func addsOnceAndRemoves() async throws {
    let store = store()
    #expect(try await store.add("/Users/flavio/dev/soundscape"))
    #expect(try await !store.add("/Users/flavio/dev/soundscape"))
    #expect(try await store.add("/Users/flavio/dev/cli-tools"))
    #expect(try await store.load().projects.map(\.path) == ["/Users/flavio/dev/soundscape", "/Users/flavio/dev/cli-tools"])

    #expect(try await store.remove("/Users/flavio/dev/soundscape"))
    #expect(try await !store.remove("/Users/flavio/dev/soundscape"))
    #expect(try await store.load().projects.count == 1)
  }

  @Test
  func renamesAndGoesBackToTheFolderName() async throws {
    let store = store()
    try await store.add("/Users/flavio/dev/factorylog")
    #expect(try await store.rename("/Users/flavio/dev/factorylog", to: "  Factory Log "))
    #expect(try await store.load().projects.first?.displayName == "Factory Log")
    #expect(try await store.rename("/Users/flavio/dev/factorylog", to: ""))
    #expect(try await store.load().projects.first?.displayName == nil)
    #expect(try await !store.rename("/Users/flavio/dev/gone", to: "Gone"))
  }

  @Test
  func keepsOldReleasesWhenAFetchFails() async throws {
    let store = store()
    try await store.add("/Users/flavio/dev/soundscape")
    let release = Release(tag: "v1.0.2", url: URL(string: "https://github.com/flaviocopes/soundscape/releases/tag/v1.0.2")!)
    let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    _ = try await store.saveFetches(["/Users/flavio/dev/soundscape": .success([release])], at: fetchedAt)
    let list = try await store.saveFetches(
      ["/Users/flavio/dev/soundscape": .failure(GitHubError.Message(GitHubError.http(502)))],
      at: fetchedAt.addingTimeInterval(600)
    )

    let project = try #require(list.projects.first)
    #expect(project.releases == [release])
    #expect(project.releasesFetchedAt == fetchedAt)
    #expect(project.fetchError == "GitHub answered with HTTP 502.")
  }
}

struct GitHubClientTests {
  @Test
  func decodesReleasesNewestFirst() throws {
    let json = """
      [
        {
          "tag_name": "v1.0.1", "name": "Soundscape 1.0.1", "published_at": "2026-09-30T09:26:03Z",
          "created_at": "2026-09-30T09:20:00Z", "html_url": "https://github.com/flaviocopes/soundscape/releases/tag/v1.0.1",
          "draft": false, "prerelease": false, "body": "## What's new\\n- Fix",
          "assets": [{
            "name": "Soundscape-1.0.1.zip", "size": 2328474, "download_count": 3,
            "browser_download_url": "https://github.com/flaviocopes/soundscape/releases/download/v1.0.1/Soundscape-1.0.1.zip",
            "digest": "sha256:4b59"
          }]
        },
        {
          "tag_name": "v1.0.2", "name": "", "published_at": "2026-09-30T12:58:18Z",
          "created_at": "2026-09-30T12:50:00Z", "html_url": "https://github.com/flaviocopes/soundscape/releases/tag/v1.0.2",
          "draft": false, "prerelease": false, "body": null, "assets": []
        }
      ]
      """

    let releases = try GitHubClient.decodeReleases(Data(json.utf8))
    #expect(releases.map(\.tag) == ["v1.0.2", "v1.0.1"])
    #expect(releases[0].title == nil)
    #expect(releases[0].notes == nil)
    #expect(releases[1].title == "Soundscape 1.0.1")
    #expect(releases[1].downloadCount == 3)
    #expect(releases[1].assets.first?.digest == "sha256:4b59")
  }
}
