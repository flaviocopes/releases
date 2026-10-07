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
  func waitingToShipMeansReleasedWithSomethingNew() {
    #expect(snapshot(releases: [release("v1.0.2")], commits: [Commit(hash: "a1b2c3d", subject: "Fix")]).isWaitingToShip)
    #expect(snapshot(version: "1.1.0", releases: [release("v1.0.2")], commits: []).isWaitingToShip)
    #expect(!snapshot(releases: [release("v1.0.2")], commits: []).isWaitingToShip)
    #expect(!snapshot(version: "1.0.0", releases: []).isWaitingToShip)
  }

  @Test
  func waitingToShipListsTheMostCommitsFirst() {
    func commits(_ count: Int) -> [Commit] {
      (0..<count).map { Commit(hash: "a1b2c3\($0)", subject: "Change \($0)") }
    }

    let waiting = [
      snapshot(path: "/dev/blueprint", name: "Blueprint", releases: [release("v1.0.2")], commits: commits(1)),
      snapshot(path: "/dev/calculum", name: "Calculum", releases: [release("v1.0.2")], commits: []),
      snapshot(path: "/dev/postdeck", name: "Postdeck", releases: [release("v1.0.2")], commits: commits(9)),
      snapshot(path: "/dev/snake", name: "Snake", version: "1.1.0", releases: [release("v1.0.0")], commits: commits(5)),
      snapshot(path: "/dev/soundscape", name: "Soundscape", releases: [release("v1.0.2")], commits: commits(1)),
      snapshot(path: "/dev/noterepo", name: "NoteRepo", version: "2.3.0", releases: [release("v2.2.0")], commits: nil)
    ].waitingToShip()

    #expect(waiting.map(\.name) == ["Postdeck", "Snake", "Blueprint", "Soundscape", "NoteRepo"])
  }

  @Test
  func checkPromptNamesEveryFolder() {
    var snake = snapshot(path: "/Users/flavio/dev/snake", name: "Snake", version: "1.1.0", releases: [release("v1.0.0")], commits: [
      Commit(hash: "a1b2c3d", subject: "Add a pause button"),
      Commit(hash: "e4f5a6b", subject: "README: link the demo")
    ])
    snake.local.hasUncommittedChanges = true
    let blueprint = snapshot(path: "/Users/flavio/dev/blueprint", name: "Blueprint", releases: [release("v1.0.2")], commits: [
      Commit(hash: "c7d8e9f", subject: "Remove the CI workflow")
    ])

    let prompt = ReleasePrompt.check([snake, blueprint], notes: "Skip Blueprint this week.")
    #expect(prompt.hasPrefix("Check which of my projects need a new release."))
    #expect(prompt.contains("- Snake, /Users/flavio/dev/snake: 2 commits since v1.0.0, version already set to 1.1.0, uncommitted changes\n- Blueprint, /Users/flavio/dev/blueprint: 1 commit since v1.0.2"))
    #expect(prompt.contains("Wait for my go-ahead"))
    #expect(prompt.contains("\"Later releases\" steps of the open-source-release skill"))
    #expect(prompt.contains("ask me whether they belong in the release"))
    #expect(prompt.hasSuffix("Skip Blueprint this week."))
    #expect(!ReleasePrompt.check([blueprint]).contains("uncommitted"))
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
  func firstReleasesListOneLaunchPerProjectNewestFirst() {
    let launches = [
      snapshot(path: "/dev/soundscape", name: "Soundscape", releases: [release("v1.1.0", daysAgo: 1), release("v1.0.0", daysAgo: 40)]),
      snapshot(path: "/dev/noterepo", name: "NoteRepo", releases: [release("v2.0.0", daysAgo: 3), release("v1.0.0", daysAgo: 10)]),
      snapshot(path: "/dev/shipyard", name: "Shipyard", releases: [release("v0.1.0", daysAgo: 2, prerelease: true)])
    ].timeline().filter(\.isFirstRelease)

    #expect(launches.map { "\($0.project.name) \($0.release.tag)" } == ["NoteRepo v1.0.0", "Soundscape v1.0.0"])
  }

  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    Self.utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
  }

  @Test
  func periodsAreTodayYesterdayTheLastSevenDaysThenMonths() {
    let now = date(10, 4, 19, 53)
    func period(_ date: Date) -> TimelinePeriod { TimelinePeriod(date, now: now, calendar: Self.utc) }

    #expect(period(date(10, 4, 0, 5)) == .today)
    #expect(period(date(10, 4, 22)) == .today)
    #expect(period(date(10, 3, 23, 59)) == .yesterday)
    #expect(period(date(10, 3, 0, 0)) == .yesterday)
    #expect(period(date(10, 2)) == .lastSevenDays)
    #expect(period(date(9, 28, 0, 0)) == .lastSevenDays)
    #expect(period(date(9, 27, 23, 59)) == .month(date(9, 1, 0, 0)))
    #expect(period(date(8, 14)) == .month(date(8, 1, 0, 0)))
  }

  @Test
  func groupsFirstReleasesByPeriodNewestFirst() {
    func launch(_ name: String, _ date: Date) -> ProjectSnapshot {
      snapshot(path: "/dev/\(name.lowercased())", name: name, releases: [
        Release(tag: "v1.0.0", publishedAt: date, url: URL(string: "https://github.com/flaviocopes/\(name.lowercased())/releases/tag/v1.0.0")!)
      ])
    }

    let groups = [
      launch("Calculum", date(10, 2)),
      launch("Blueprint", date(10, 4, 9)),
      launch("Soundscape", date(9, 21)),
      launch("Postdeck", date(10, 3)),
      launch("NoteRepo", date(9, 29)),
      launch("Shipyard", date(8, 30))
    ]
    .timeline()
    .filter(\.isFirstRelease)
    .groupedByPeriod(now: date(10, 4, 19, 53), calendar: Self.utc)

    #expect(groups.map(\.period) == [.today, .yesterday, .lastSevenDays, .month(date(9, 1, 0, 0)), .month(date(8, 1, 0, 0))])
    #expect(groups.map { $0.entries.map(\.project.name) } == [["Blueprint"], ["Postdeck"], ["Calculum", "NoteRepo"], ["Soundscape"], ["Shipyard"]])
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
  func codexDeeplinkEncodesThePromptAndFolder() {
    let prompt = "Release C++ tools 1.0.0.\nGo & ship #新"
    let folder = URL(filePath: "/Users/flavio/dev/C++ & Tools")
    let url = Codex.promptURL(prompt, in: folder)
    #expect(url.scheme == "codex")
    #expect(url.host == "new")
    #expect(url.absoluteString.contains("C%2B%2B"))
    #expect(url.absoluteString.contains("%26"))
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.first { $0.name == "prompt" }?.value == prompt)
    #expect(query?.first { $0.name == "path" }?.value == folder.path)
    #expect(query?.first { $0.name == "mode" }?.value == "codex")
    #expect(url.fragment == nil)
  }

  @Test
  func codexCheckPromptHasNoProjectFolder() {
    let url = Codex.promptURL("Check every project.")
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.contains { $0.name == "path" } == false)
    #expect(query?.first { $0.name == "prompt" }?.value == "Check every project.")
  }

  @Test
  func codexBatchKeepsEveryPromptInOneDraft() throws {
    let first = (prompt: "Release Inkwell.\nProject: /Users/flavio/dev/inkwell", folder: URL(filePath: "/Users/flavio/dev/inkwell"))
    let second = (prompt: "Release Portside.\nProject: /Users/flavio/dev/portside", folder: URL(filePath: "/Users/flavio/dev/portside"))
    #expect(Codex.releaseURL([]) == nil)
    #expect(Codex.releaseURL([first]) == Codex.promptURL(first.prompt, in: first.folder))
    let url = try #require(Codex.releaseURL([first, second]))
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let prompt = try #require(query.first { $0.name == "prompt" }?.value)
    #expect(prompt.contains(first.prompt))
    #expect(prompt.contains(second.prompt))
    #expect(prompt.contains("one at a time"))
    #expect(!query.contains { $0.name == "path" })
  }
}
