import Foundation
import Testing
@testable import ReleasesCore

struct ProjectSnapshotTests {
  private let repository = GitHubRepository(owner: "flaviocopes", name: "soundscape")

  private func release(_ tag: String, daysAgo: Double = 1, prerelease: Bool = false) -> Release {
    Release(
      tag: tag,
      publishedAt: Date(timeIntervalSince1970: 1_790_000_000 - daysAgo * 86_400),
      url: URL(string: "https://github.com/flaviocopes/soundscape/releases/tag/\(tag)")!,
      isPrerelease: prerelease
    )
  }

  private func snapshot(
    path: String = "/Users/flavio/dev/soundscape",
    name: String = "Soundscape",
    version: String? = "1.0.2",
    releases: [Release]? = [],
    commits: [Commit]? = nil,
    repository: GitHubRepository?? = nil,
    exists: Bool = true
  ) -> ProjectSnapshot {
    var project = TrackedProject(path: path)
    project.releases = releases
    let local = LocalProject(
      name: name,
      exists: exists,
      repository: repository ?? self.repository,
      version: version.map { VersionSource(version: $0, file: "project.yml", key: "MARKETING_VERSION") }
    )
    return ProjectSnapshot(project: project, local: local, unreleasedCommits: commits)
  }

  @Test
  func status() {
    #expect(snapshot(releases: [release("v1.0.2")], commits: []).status == .upToDate)
    #expect(snapshot(releases: [release("v1.0.2")], commits: [Commit(hash: "a1b2c3d", subject: "Fix")]).status == .unreleasedChanges)
    #expect(snapshot(version: "1.1.0", releases: [release("v1.0.2")], commits: []).status == .readyToRelease)
    #expect(snapshot(version: "1.0.0", releases: [release("v1.0.2")], commits: []).status == .versionBehind)
    #expect(snapshot(releases: []).status == .neverReleased)
    #expect(snapshot(releases: nil).status == .notLoaded)
    #expect(snapshot(repository: .some(nil)).status == .noRepository)
    #expect(snapshot(exists: false).status == .missing)
  }

  @Test
  func statusText() {
    let commits = [Commit(hash: "a1b2c3d", subject: "Fix"), Commit(hash: "e4f5a6b", subject: "Loop")]
    #expect(snapshot(releases: [release("v1.0.2")], commits: commits).statusText == "2 commits since v1.0.2")
    #expect(snapshot(version: "1.1.0", releases: [release("v1.0.2")]).statusText == "1.1.0 ready to release")
  }

  @Test
  func prereleasesDontCountAsLatest() {
    let snapshot = snapshot(releases: [release("v2.0.0", daysAgo: 0, prerelease: true), release("v1.0.2")])
    #expect(snapshot.latestRelease?.tag == "v1.0.2")
  }

  @Test
  func aGivenNameWinsAndBothNamesFindTheProject() throws {
    var renamed = snapshot(path: "/Users/flavio/dev/factorylog", name: "factorylog")
    renamed.project.displayName = "Factory Log"
    #expect(renamed.name == "Factory Log")
    #expect(try [renamed].project(matching: "factory log").id == renamed.id)
    #expect(try [renamed].project(matching: "factorylog").id == renamed.id)
    #expect(renamed.displayName(for: " Factory Log ") == "Factory Log")
    #expect(renamed.displayName(for: "factorylog") == nil)
    #expect(renamed.displayName(for: "  ") == nil)
  }

  @Test
  func firstReleaseIsTheOldestPublicOne() {
    let snapshot = snapshot(releases: [release("v1.1.0", daysAgo: 1), release("v1.0.0", daysAgo: 5), release("v0.9.0", daysAgo: 9, prerelease: true)])
    #expect(snapshot.firstRelease?.tag == "v1.0.0")
    #expect([snapshot].timeline().filter(\.isFirstRelease).map(\.release.tag) == ["v1.0.0"])
    #expect(self.snapshot(releases: []).firstRelease == nil)
  }

  @Test
  func suggestsTheNextVersion() {
    #expect(snapshot(version: "1.0.2", releases: [release("v1.0.2")]).suggestedVersion.description == "1.0.3")
    #expect(snapshot(version: "1.1.0", releases: [release("v1.0.2")]).suggestedVersion.description == "1.1.0")
    #expect(snapshot(version: "1.0.0", releases: []).suggestedVersion.description == "1.0.0")
    #expect(snapshot(version: nil, releases: []).suggestedVersion.description == "1.0.0")
  }

  @Test
  func sortsByLatestReleaseThenName() {
    let sorted = [
      snapshot(path: "/dev/b", name: "Beta", releases: []),
      snapshot(path: "/dev/old", name: "Old", releases: [release("v1.0.0", daysAgo: 30)]),
      snapshot(path: "/dev/a", name: "alpha", releases: nil),
      snapshot(path: "/dev/new", name: "New", releases: [release("v1.0.0", daysAgo: 1)])
    ].sortedByRelease()

    #expect(sorted.map(\.name) == ["New", "Old", "alpha", "Beta"])
  }

  @Test
  func timelineMergesProjectsNewestFirst() {
    var draft = release("v1.1.0", daysAgo: 0)
    draft.isDraft = true
    let timeline = [
      snapshot(path: "/dev/soundscape", name: "Soundscape", releases: [release("v1.0.2", daysAgo: 1), release("v1.0.0", daysAgo: 5)]),
      snapshot(path: "/dev/noterepo", name: "NoteRepo", releases: [draft, release("v2.0.0", daysAgo: 3)]),
      snapshot(path: "/dev/shipyard", name: "Shipyard", releases: nil)
    ].timeline()

    #expect(timeline.map { "\($0.project.name) \($0.release.tag)" } == ["Soundscape v1.0.2", "NoteRepo v2.0.0", "Soundscape v1.0.0"])
  }

  @Test
  func findsProjectsByNameFolderOrRepo() throws {
    let snapshots = [
      snapshot(path: "/Users/flavio/dev/cli-tools", name: "CLI Tools", repository: GitHubRepository(owner: "flaviocopes", name: "cli-tools")),
      snapshot(path: "/Users/flavio/dev/soundscape", name: "Soundscape")
    ]

    #expect(try snapshots.project(matching: "cli tools").name == "CLI Tools")
    #expect(try snapshots.project(matching: "cli-tools").name == "CLI Tools")
    #expect(try snapshots.project(matching: "flaviocopes/soundscape").name == "Soundscape")
    #expect(try snapshots.project(matching: "/Users/flavio/dev/soundscape/").name == "Soundscape")
    #expect(throws: ProjectLookupError.self) { try snapshots.project(matching: "noterepo") }
  }

  @Test
  func promptListsTheChangesAndTheSkill() {
    let commits = [Commit(hash: "a1b2c3d", subject: "Fix the play button")]
    var snapshot = snapshot(releases: [release("v1.0.2")], commits: commits)
    snapshot.local.hasUncommittedChanges = true

    let prompt = ReleasePrompt.make(for: snapshot, version: SemanticVersion("1.1.0")!, notes: "Mention the menu bar icon.")
    #expect(prompt.hasPrefix("Release Soundscape 1.1.0."))
    #expect(prompt.contains("Current version: 1.0.2, set as MARKETING_VERSION in project.yml"))
    #expect(prompt.contains("Changes since v1.0.2:\n- Fix the play button"))
    #expect(prompt.contains("tag v1.1.0"))
    #expect(prompt.contains("\"Later releases\" steps of the open-source-release skill"))
    #expect(prompt.contains("uncommitted changes"))
    #expect(prompt.hasSuffix("Mention the menu bar icon."))
  }

  @Test
  func promptForTheFirstRelease() {
    let prompt = ReleasePrompt.make(for: snapshot(version: "1.0.0", releases: []), version: SemanticVersion("1.0.0")!)
    #expect(prompt.contains("This is the first release."))
    #expect(!prompt.contains("Last release"))
  }

  @Test
  func promptForAProjectNotOnGitHub() {
    let prompt = ReleasePrompt.make(for: snapshot(releases: nil, repository: .some(nil)), version: SemanticVersion("1.0.0")!)
    #expect(prompt.contains("isn't on GitHub yet"))
    #expect(prompt.contains("creating the repo too"))
    #expect(prompt.contains("Without the skill: Create the GitHub repo"))
    #expect(!prompt.contains("GitHub: "))
  }

  @Test
  func cursorDeeplinkEncodesThePrompt() {
    let url = Cursor.promptURL("Release C++ tools 1.0.0.\nGo & ship")
    #expect(url.absoluteString.hasPrefix("cursor://anysphere.cursor-deeplink/prompt?text="))
    #expect(url.absoluteString.contains("C%2B%2B"))
    #expect(url.absoluteString.contains("%26"))
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Release C++ tools 1.0.0.\nGo & ship")
  }
}
