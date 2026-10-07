import Foundation

/// What `releases capabilities --json` prints. Add a changelog entry for every release, newest first.
struct CapabilitiesManifest: Encodable {
  struct Capability: Encodable {
    let description: String
    var command: String? = nil
  }

  struct Release: Encodable {
    let version: String
    let date: String
    let changes: [String]
  }

  let name: String
  let version: String
  let summary: String
  let capabilities: [Capability]
  let changelog: [Release]

  static let current = CapabilitiesManifest(
    name: "releases",
    version: Commands.version,
    summary: "Tracks the versions and GitHub releases of your Mac apps and tools, and helps you ship the next one.",
    capabilities: [
      Capability(
        description: "Track a project folder and list its GitHub releases",
        command: "releases add ~/dev/soundscape"
      ),
      Capability(
        description: "See which projects have commits or a newer version waiting to ship",
        command: "releases list --waiting --json"
      ),
      Capability(
        description: "Have an agent in Codex check which projects waiting to ship need a release",
        command: "releases prompt --check --codex"
      ),
      Capability(
        description: "List the latest releases across every tracked project",
        command: "releases recent --json"
      ),
      Capability(
        description: "See when each app launched with its first public release",
        command: "releases recent --first --json"
      ),
      Capability(
        description: "Show GitHub download counts for your projects and releases",
        command: "releases downloads --json"
      ),
      Capability(
        description: "Find Mac apps and CLIs on disk that are not in the list yet",
        command: "releases discover --json"
      ),
      Capability(
        description: "Print the release prompt for a project, or open it in Codex",
        command: "releases prompt soundscape --bump minor --codex"
      ),
      Capability(
        description: "Show a project in Releases, open it in Codex with --codex, or open its Create Release sheet",
        command: "releases open soundscape --release --bump minor"
      ),
      Capability(
        description: "Learn every command and option as JSON for agents",
        command: "releases help --json"
      )
    ],
    changelog: [
      Release(
        version: "1.5.0",
        date: "2026-10-07",
        changes: [
          "New releases downloads, with daily counts and --by-day output.",
          "releases list --waiting and releases recent --first filter projects and releases.",
          "releases prompt --waiting prepares batch releases; --check asks an agent which projects need one. Prompts open in Codex.",
          "New capabilities command for agents, with JSON output and release history."
        ]
      ),
      Release(
        version: "1.4.0",
        date: "2026-10-03",
        changes: ["Signed and notarized. The CLI did not change."]
      ),
      Release(
        version: "1.3.0",
        date: "2026-10-01",
        changes: [
          "New releases rename to give a project another name in Releases.",
          "releases open --github-desktop opens the folder in GitHub Desktop."
        ]
      ),
      Release(
        version: "1.2.0",
        date: "2026-10-01",
        changes: ["releases recent and releases show mark each app's first release in --json output."]
      ),
      Release(
        version: "1.1.0",
        date: "2026-10-01",
        changes: [
          "releases discover lists apps next to your projects that are not tracked yet.",
          "releases hide and releases unhide control what discover shows."
        ]
      ),
      Release(
        version: "1.0.0",
        date: "2026-10-01",
        changes: [
          "First release: add, list, recent, show, discover, prompt, open, refresh, and remove, all with --json.",
          "releases open drives the app through releases:// links."
        ]
      )
    ]
  )

  func print(json: Bool) throws {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      Swift.print(String(decoding: try encoder.encode(self), as: UTF8.self))
      return
    }

    Swift.print("\(name) \(version)\n\(summary)\n\nWhat it can do:")
    for capability in capabilities {
      Swift.print("  \(capability.description)")
      if let command = capability.command { Swift.print("    $ \(command)") }
    }
    Swift.print("\nChanges:")
    for release in changelog {
      Swift.print("  \(release.version) (\(release.date))")
      release.changes.forEach { Swift.print("    - \($0)") }
    }
  }
}
