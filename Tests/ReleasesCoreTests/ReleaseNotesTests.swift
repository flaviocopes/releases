import Foundation
import Testing
@testable import ReleasesCore

struct ReleaseNotesTests {
  @Test
  func takesWhatsNewAndSkipsTheInstallSteps() {
    let changes = ReleaseNotes.changes(in: """
      Soundscape mixes the Background Sounds built into macOS. Version 1.0.2 updates itself.

      ## What's new

      - **Updates from inside the app.** Once a day, Soundscape asks GitHub whether there's a newer version.
        When there is, it shows what's new.
      - **Check for Updates…** in the Soundscape menu checks right away.

      ## Install

      Download `Soundscape-1.0.2.zip`, unzip it, and drag Soundscape to your Applications folder.

      - open **System Settings → Privacy & Security**, and click **Open Anyway**, or
      - run `xattr -dr com.apple.quarantine /Applications/Soundscape.app` in Terminal.

      SHA-256 of the zip: `8b0836d9`
      """)

    #expect(changes.map(\.headline) == ["Updates from inside the app", "Check for Updates…"])
    #expect(changes[0].detail == "Once a day, Soundscape asks GitHub whether there's a newer version. When there is, it shows what's new.")
    #expect(changes[0].hasLeadIn)
    #expect(changes[1].detail == "in the Soundscape menu checks right away.")
  }

  @Test
  func findsWhatsInAfterTheInstallSection() {
    let changes = ReleaseNotes.changes(in: """
      The first public release of NoteRepo.

      ## Install

      - open **System Settings → Privacy & Security**, or
      - run `xattr` in Terminal.

      ## What's in 1.0

      - Opens on today, with the earlier days that have notes above it
      - Search with ⌘K, and ⌘D to jump back to today

      SHA-256 of the zip: `47e4847d`
      """)

    #expect(changes.map(\.text) == [
      "Opens on today, with the earlier days that have notes above it",
      "Search with ⌘K, and ⌘D to jump back to today"
    ])
    #expect(!changes[0].hasLeadIn)
  }

  @Test
  func leavesOutCodeAndNestedItems() {
    let changes = ReleaseNotes.changes(in: """
      ## Changes

      - Faster startup
        - Measured on an M1
      - Smaller download

      ```sh
      - not a change
      ```
      """)

    #expect(changes.map(\.text) == ["Faster startup", "Smaller download"])
  }

  @Test
  func fallsBackToBulletsOutsideTheInstallSteps() {
    let changes = ReleaseNotes.changes(in: """
      - Fix the crash on launch
      * Better dark mode

      ## Install

      - Drag it to Applications
      """)

    #expect(changes.map(\.text) == ["Fix the crash on launch", "Better dark mode"])
  }

  @Test
  func fallsBackToTheFirstParagraph() {
    let changes = ReleaseNotes.changes(in: "The first public release of NoteRepo,\na daily notes app.\n\n## Install\n\nDownload the zip.")
    #expect(changes.map(\.text) == ["The first public release of NoteRepo, a daily notes app."])
    #expect(ReleaseNotes.changes(in: "").isEmpty)
  }

  @Test
  func splitsHeadlinesWithoutALeadIn() {
    let change = Change("Search with ⌘K. It also finds images.")
    #expect(change.headline == "Search with ⌘K")
    #expect(change.detail == "It also finds images.")
  }
}

struct ChangelogTests {
  @Test
  func readsNoteReposChangelog() {
    let changelog = Changelog.parse("""
      # Changelog

      Every NoteRepo release, newest first.

      ## 2.0.0 (September 30, 2026)

      NoteRepo is now a native Mac app written in Swift.

      - **A native app.** SwiftUI draws the window.
      - **Intel Macs.** The app is universal.

      A few things are different:

      - To move an image to another day, cut and paste it.

      ## 1.0.0 (September 29, 2026)

      The first public release.
      """)

    #expect(changelog["2.0.0"]?.map(\.headline) == ["A native app", "Intel Macs", "To move an image to another day, cut and paste it"])
    #expect(changelog["1.0.0"]?.map(\.text) == ["The first public release."])
  }

  @Test
  func readsKeepAChangelog() {
    let changelog = Changelog.parse("""
      # Changelog

      ## [Unreleased]

      - Work in progress

      ## [1.2.0] - 2026-09-30

      ### Added

      - YouTube titles

      ### Fixed

      - A crash when pasting images

      ## v1.1 - 2026-09-29

      - A CLI for agents
      """)

    #expect(changelog["1.2.0"]?.map(\.text) == ["YouTube titles", "A crash when pasting images"])
    #expect(changelog["1.1.0"]?.map(\.text) == ["A CLI for agents"])
    #expect(changelog.count == 2)
  }

  @Test
  func snapshotsPreferTheChangelog() {
    let release = Release(
      tag: "v1.2.0",
      url: URL(string: "https://github.com/flaviocopes/noterepo/releases/tag/v1.2.0")!,
      notes: "## What's new\n\n- From the notes"
    )
    var project = TrackedProject(path: "/Users/flavio/dev/noterepo")
    project.releases = [release]

    let withChangelog = ProjectSnapshot(project: project, local: LocalProject(name: "NoteRepo", changelog: ["1.2.0": [Change("From the changelog")]]))
    let withoutChangelog = ProjectSnapshot(project: project, local: LocalProject(name: "NoteRepo"))

    #expect(withChangelog.changes(in: release).map(\.text) == ["From the changelog"])
    #expect(withoutChangelog.changes(in: release).map(\.text) == ["From the notes"])
  }
}
