import Foundation
import Testing
@testable import ReleasesCore

struct ProjectInspectorTests {
  private func folder(_ files: [String: String]) throws -> URL {
    try makeFolder(files)
  }

  @Test
  func readsXcodeGenProjects() throws {
    let root = try folder([
      "project.yml": """
        name: Soundscape
        settings:
          base:
            MARKETING_VERSION: "1.0.2"
        """,
      "Soundscape.xcodeproj/project.pbxproj": "MARKETING_VERSION = 0.1;"
    ])

    let project = ProjectInspector().inspect(root)
    #expect(project.name == "Soundscape")
    #expect(project.version == VersionSource(version: "1.0.2", file: "project.yml", key: "MARKETING_VERSION"))
    #expect(project.version?.label == "MARKETING_VERSION in project.yml")
  }

  @Test
  func readsSwiftConstantsAndPrefersVersionFiles() throws {
    let root = try folder([
      "Sources/NoteRepoCore/Settings.swift": "let version = \"9.9.9\"",
      "Sources/NoteRepoCore/Version.swift": "public enum AppVersion {\n  public static let current = \"2.0.0\"\n}"
    ])

    let version = ProjectInspector().inspect(root).version
    #expect(version == VersionSource(version: "2.0.0", file: "Sources/NoteRepoCore/Version.swift", key: "current"))
  }

  @Test
  func readsPackageJSONAndItsProductName() throws {
    let root = try folder([
      "package.json": #"{"name": "port-pilot", "version": "1.0.0", "build": {"productName": "Port Pilot"}}"#
    ])

    let project = ProjectInspector().inspect(root)
    #expect(project.name == "Port Pilot")
    #expect(project.version?.version == "1.0.0")
  }

  @Test
  func readsXcodeProjects() throws {
    let root = try folder([
      "Shipyard.xcodeproj/project.pbxproj": "buildSettings = {\n MARKETING_VERSION = 1.0;\n};"
    ])

    #expect(ProjectInspector().inspect(root).version?.version == "1.0")
  }

  @Test
  func namesTheProjectAfterItsBuiltApp() throws {
    let root = try folder([
      "dist/CLI Tools.app": "",
      "build/screenshot/Screenshot.app": "",
      "Package.swift": "",
      "Sources/CliToolsCLI/Commands.swift": "enum Commands {\n  static let version = \"1.0.0\"\n}"
    ])

    let project = ProjectInspector().inspect(root)
    #expect(project.name == "CLI Tools")
    #expect(project.appPath?.hasSuffix("dist/CLI Tools.app") == true)
    #expect(project.version?.key == "version")
  }

  @Test
  func reportsMissingFolders() {
    let project = ProjectInspector().inspect(URL(filePath: "/Users/flavio/dev/gone-for-good"))
    #expect(!project.exists)
    #expect(project.name == "gone-for-good")
  }
}
