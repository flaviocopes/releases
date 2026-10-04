import Foundation
import Testing
@testable import ReleasesCore

struct DownloadsTests {
  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    Self.utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }

  private func release(_ tag: String, _ published: Date, downloads: Int) -> Release {
    let base = "https://github.com/flaviocopes/soundscape/releases"
    return Release(
      tag: tag,
      publishedAt: published,
      url: URL(string: "\(base)/tag/\(tag)")!,
      assets: [ReleaseAsset(name: "Soundscape.zip", size: 3_400_000, downloadCount: downloads, downloadURL: URL(string: "\(base)/download/\(tag)/Soundscape.zip")!)]
    )
  }

  /// Launched on September 20 at noon. Releases first saw 100 downloads on October 1, then 130 on October 3.
  private func soundscape() -> ProjectSnapshot {
    var project = TrackedProject(path: "/Users/flavio/dev/soundscape")
    project.releases = [release("v1.1.0", date(10, 2), downloads: 20), release("v1.0.0", date(9, 20, 12), downloads: 110)]
    project.downloadHistory = [DownloadSample(date: date(10, 1, 10), downloads: 100), DownloadSample(date: date(10, 3, 18), downloads: 130)]
    return ProjectSnapshot(project: project, local: LocalProject(name: "Soundscape"))
  }

  /// Launched on October 2 at noon, with 40 downloads at the only fetch so far, on October 4.
  private func noteRepo() -> ProjectSnapshot {
    var project = TrackedProject(path: "/Users/flavio/dev/noterepo")
    project.releases = [release("v1.0.0", date(10, 2, 12), downloads: 40)]
    project.releasesFetchedAt = date(10, 4, 18)
    return ProjectSnapshot(project: project, local: LocalProject(name: "NoteRepo"))
  }

  @Test
  func savesOneCountADay() {
    var project = TrackedProject(path: "/Users/flavio/dev/soundscape")
    project.recordDownloads(at: date(10, 4, 8), calendar: Self.utc)
    #expect(project.downloadHistory == nil)

    project.releases = [release("v1.0.0", date(9, 20), downloads: 12)]
    project.recordDownloads(at: date(10, 4, 8), calendar: Self.utc)
    project.releases = [release("v1.0.0", date(9, 20), downloads: 15)]
    project.recordDownloads(at: date(10, 4, 20), calendar: Self.utc)
    project.recordDownloads(at: date(10, 5, 9), calendar: Self.utc)

    #expect(project.downloadHistory == [DownloadSample(date: date(10, 4, 20), downloads: 15), DownloadSample(date: date(10, 5, 9), downloads: 15)])
  }

  @Test
  func everyFetchSavesTheCount() async throws {
    let store = ProjectStore(fileURL: FileManager.default.temporaryDirectory
      .appending(path: "releases-downloads-\(UUID().uuidString)")
      .appending(path: "projects.json"))
    try await store.add("/Users/flavio/dev/soundscape")
    let list = try await store.saveFetches(["/Users/flavio/dev/soundscape": .success([release("v1.0.0", date(9, 20), downloads: 42)])], at: date(10, 4, 9))
    #expect(list.projects.first?.downloadHistory == [DownloadSample(date: date(10, 4, 9), downloads: 42)])
  }

  @Test
  func estimatesTheDaysBeforeTheFirstCount() {
    let points = soundscape().downloadsByDay(through: date(10, 4, 19), calendar: Self.utc)

    #expect(points.count == 15)
    #expect(points.first == DownloadPoint(day: date(9, 20), downloads: 5, isEstimate: true))
    #expect(points[10] == DownloadPoint(day: date(9, 30), downloads: 96, isEstimate: true))
    #expect(points.suffix(4).map(\.downloads) == [100, 100, 130, 130])
    #expect(points.suffix(4).allSatisfy { !$0.isEstimate })
  }

  @Test
  func knowsTheDownloadsSinceADateOnlyAfterTheFirstCount() {
    let soundscape = soundscape()
    #expect(soundscape.downloads(since: date(9, 1)) == 130)
    #expect(soundscape.downloads(since: date(10, 2)) == 30)
    #expect(soundscape.downloads(since: date(9, 25)) == nil)
  }

  @Test
  func addsUpEveryProject() {
    let projects = [soundscape(), noteRepo()]
    let points = projects.downloadsByDay(through: date(10, 4, 19), calendar: Self.utc)

    #expect(points.first == DownloadPoint(day: date(9, 20), downloads: 5, isEstimate: true))
    #expect(points[11] == DownloadPoint(day: date(10, 1), downloads: 100, isEstimate: false))
    #expect(points[12] == DownloadPoint(day: date(10, 2), downloads: 109, isEstimate: true))
    #expect(points.last == DownloadPoint(day: date(10, 4), downloads: 170, isEstimate: false))
    #expect(projects.totalDownloads == 170)
    #expect(projects.downloads(since: date(10, 2)) == 70)
    #expect(projects.downloads(since: date(10, 3)) == nil)
    #expect(projects.downloadsTrackedSince == date(10, 1, 10))
  }
}
