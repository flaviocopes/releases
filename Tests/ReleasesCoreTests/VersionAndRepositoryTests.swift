import Foundation
import Testing
@testable import ReleasesCore

struct SemanticVersionTests {
  @Test
  func parsesTagsAndShortVersions() {
    #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
    #expect(SemanticVersion("2.0.0-beta.1") == SemanticVersion(major: 2, minor: 0, patch: 0))
    #expect(SemanticVersion("Soundscape 1.0") == nil)
    #expect(SemanticVersion("latest") == nil)
  }

  @Test
  func comparesNumerically() {
    #expect(SemanticVersion("1.0.10")! > SemanticVersion("1.0.9")!)
    #expect(SemanticVersion("1.0")! == SemanticVersion("v1.0.0")!)
    #expect(SemanticVersion("0.9.0")! < SemanticVersion("1.0.0")!)
  }

  @Test
  func bumps() {
    let version = SemanticVersion("1.2.3")!
    #expect(version.bumped(.patch).description == "1.2.4")
    #expect(version.bumped(.minor).description == "1.3.0")
    #expect(version.bumped(.major).description == "2.0.0")
    #expect(version.tag == "v1.2.3")
  }
}

struct GitHubRepositoryTests {
  @Test
  func readsRemoteURLs() {
    let expected = GitHubRepository(owner: "flaviocopes", name: "soundscape")
    #expect(GitHubRepository(remoteURL: "https://github.com/flaviocopes/soundscape.git") == expected)
    #expect(GitHubRepository(remoteURL: "https://github.com/flaviocopes/soundscape") == expected)
    #expect(GitHubRepository(remoteURL: "git@github.com:flaviocopes/soundscape.git") == expected)
    #expect(GitHubRepository(remoteURL: "ssh://git@github.com/flaviocopes/soundscape.git\n") == expected)
    #expect(GitHubRepository(remoteURL: "https://github.com/flaviocopes/port-pilot/") == GitHubRepository(owner: "flaviocopes", name: "port-pilot"))
    #expect(GitHubRepository(remoteURL: "https://gitlab.com/flaviocopes/soundscape.git") == nil)
  }

  @Test
  func parsesGitLog() {
    let commits = Git.parseLog("""
      a1b2c3d\t2026-09-30T14:00:00+02:00\tFix the play button
      e4f5a6b\t2026-09-29T10:00:00+02:00\tLoop sounds\twithout a gap
      """)
    #expect(commits.map(\.hash) == ["a1b2c3d", "e4f5a6b"])
    #expect(commits[1].subject == "Loop sounds\twithout a gap")
    #expect(commits[0].date == (try? Date("2026-09-30T12:00:00Z", strategy: .iso8601)))
  }
}
