import Foundation
import Testing
@testable import ReleasesCore

struct ProjectFinderTests {
  private func isSoftware(_ files: [String: String]) throws -> Bool {
    ProjectFinder.isSoftware(try makeFolder(files))
  }

  @Test
  func recognizesAppsAndCommands() throws {
    #expect(try isSoftware(["project.yml": "name: Soundscape\ntargets:\n  Soundscape:\n    type: application"]))
    #expect(try isSoftware(["Shipyard.xcodeproj/project.pbxproj": ""]))
    #expect(try isSoftware(["Package.swift": #".executableTarget(name: "NoteRepo")"#]))
    #expect(try isSoftware(["package.json": #"{"name": "port-pilot", "bin": {"port-pilot": "cli.js"}}"#]))
    #expect(try isSoftware(["package.json": #"{"name": "mortgage", "devDependencies": {"electron": "^38.0.0"}}"#]))
    #expect(try isSoftware(["dist/Lunar Calendar.app": ""]))

    #expect(try !isSoftware(["project.yml": "site: flaviocopes.com"]))
    #expect(try !isSoftware(["Package.swift": #".library(name: "Kit", targets: ["Kit"])"#]))
    #expect(try !isSoftware(["package.json": #"{"name": "my-site", "dependencies": {"astro": "^5.0.0"}}"#]))
    #expect(try !isSoftware(["notes.md": "# Ideas"]))
  }

  @Test
  func looksNextToTheTrackedProjects() throws {
    let roots = ProjectFinder.roots(
      around: ["/Users/flavio/dev/soundscape", "/Users/flavio/dev/noterepo", "/Users/flavio/work/hub", "/Users/flavio/scratch"],
      home: URL(filePath: "/Users/flavio")
    )
    #expect(roots.map(\.path) == ["/Users/flavio/dev", "/Users/flavio/work"])
  }

  @Test
  func looksInTheUsualFoldersWhenTheListIsEmpty() throws {
    let home = try makeFolder(["dev/soundscape/project.yml": "targets:"])
    #expect(ProjectFinder.roots(around: [], home: home).map(\.lastPathComponent) == ["dev"])
  }

  @Test
  func skipsOtherPeoplesReposAndSecondCopies() {
    let owners: Set = ["flaviocopes"]
    let tracked: Set = ["flaviocopes/soundscape"]
    #expect(ProjectFinder.isWorthShowing(nil, owners: owners, tracked: tracked))
    #expect(ProjectFinder.isWorthShowing(GitHubRepository(owner: "FlavioCopes", name: "shipyard"), owners: owners, tracked: tracked))
    #expect(!ProjectFinder.isWorthShowing(GitHubRepository(owner: "pocketbase", name: "pocketbase"), owners: owners, tracked: tracked))
    #expect(!ProjectFinder.isWorthShowing(GitHubRepository(owner: "flaviocopes", name: "soundscape"), owners: owners, tracked: tracked))
    #expect(ProjectFinder.isWorthShowing(GitHubRepository(owner: "pocketbase", name: "pocketbase"), owners: [], tracked: []))
  }

  @Test
  func stage() {
    func found(repository: GitHubRepository?, releases: [Release]?) -> FoundProject {
      var project = TrackedProject(path: "/Users/flavio/dev/shipyard")
      project.releases = releases
      return FoundProject(snapshot: ProjectSnapshot(project: project, local: LocalProject(name: "Shipyard", repository: repository)))
    }
    let repository = GitHubRepository(owner: "flaviocopes", name: "shipyard")
    let release = Release(tag: "v1.2.0", url: URL(string: "https://github.com/flaviocopes/shipyard/releases/tag/v1.2.0")!)

    #expect(found(repository: nil, releases: nil).statusText == "Not on GitHub")
    #expect(found(repository: repository, releases: nil).stage == .onGitHub)
    #expect(found(repository: repository, releases: []).statusText == "Not released yet")
    #expect(found(repository: repository, releases: [release]).statusText == "Released v1.2.0")
  }

  @Test
  func discoversUntrackedSoftwareNewestFirst() async throws {
    let root = try makeFolder([
      "dev/soundscape/project.yml": "name: Soundscape\ntargets:",
      "dev/lunar-calendar/project.yml": "name: Lunar Calendar\ntargets:",
      "dev/ports/package.json": #"{"name": "ports", "bin": "cli.js"}"#,
      "dev/my-site/package.json": #"{"name": "my-site", "dependencies": {"astro": "^5.0.0"}}"#,
      "dev/scratch-tool/Package.swift": #".executableTarget(name: "Scratch")"#
    ])
    let dev = root.appending(path: "dev")
    let lastWeek = Date.now.addingTimeInterval(-7 * 86_400)
    try FileManager.default.setAttributes(
      [.modificationDate: lastWeek],
      ofItemAtPath: dev.appending(path: "lunar-calendar/project.yml").path
    )

    let store = ProjectStore(fileURL: root.appending(path: "projects.json"))
    try await store.add(dev.appending(path: "soundscape").path)
    try await store.hide(dev.appending(path: "scratch-tool").path)
    let tracker = ReleaseTracker(store: store)

    #expect(try await tracker.discover().map(\.name) == ["ports", "Lunar Calendar"])

    let lookup = try await tracker.lookup("Lunar Calendar")
    #expect(!lookup.isTracked)
    #expect(lookup.snapshot.project.path == dev.appending(path: "lunar-calendar").path)
    #expect(try await tracker.lookup("soundscape").isTracked)

    #expect(try await tracker.unhide("scratch-tool") == dev.appending(path: "scratch-tool").path)
    #expect(try await tracker.discover().map(\.name).contains("scratch-tool"))
    await #expect(throws: ProjectLookupError.self) { try await tracker.unhide("scratch-tool") }
  }

  @Test
  func oldListsDecodeWithoutHiddenPaths() throws {
    let list = try JSONDecoder().decode(ProjectList.self, from: Data(#"{"projects": []}"#.utf8))
    #expect(list.hiddenPaths == nil)
  }
}

struct AppLinkTests {
  @Test
  func roundTrips() {
    let links: [AppLink] = [
      .home,
      .refresh,
      .project(path: "/Users/flavio/dev/lunar calendar"),
      .release(path: "/Users/flavio/dev/soundscape", version: SemanticVersion("1.1.0"), notes: "Mention C++ & the\nmenu bar icon"),
      .release(path: "/Users/flavio/dev/soundscape", version: nil, notes: nil)
    ]
    for link in links {
      #expect(AppLink(url: link.url) == link)
    }
    #expect(AppLink.project(path: "/Users/flavio/dev/soundscape").url.absoluteString == "releases://project?path=/Users/flavio/dev/soundscape")
  }

  @Test
  func rejectsOtherLinks() {
    #expect(AppLink(url: URL(string: "releases://project")!) == nil)
    #expect(AppLink(url: URL(string: "releases://delete?path=/Users/flavio")!) == nil)
    #expect(AppLink(url: URL(string: "https://github.com/flaviocopes/releases")!) == nil)
  }
}
