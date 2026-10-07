import Foundation

enum Commands {
  static let version = "1.5.0"

  static let json = Option(name: "--json", help: "Print JSON instead of text.")
  static let refresh = Option(name: "--refresh", help: "Fetch the releases from GitHub even if they were fetched recently.")
  static let versionOption = Option(name: "--version", help: "The version to release.", takesValue: true)
  static let bump = Option(name: "--bump", help: "Bump the latest release: patch, minor or major.", takesValue: true)
  static let notes = Option(name: "--notes", help: "Extra instructions for the agent, added at the end of the prompt.", takesValue: true)

  static let all: [CommandSpec] = [
    CommandSpec(
      name: "add",
      summary: "Add project folders to the list.",
      usage: "releases add <folder>... [--json]",
      options: [json],
      details: """
        A folder inside a git repository adds the whole repository.
        The GitHub repo comes from the 'origin' remote, and the version from
        project.yml, package.json, a Swift constant, or the Xcode project.
        """
    ),
    CommandSpec(
      name: "list",
      summary: "List the projects, newest release first.",
      usage: "releases list [--waiting] [--refresh] [--json]",
      options: [
        Option(name: "--waiting", help: "Only the projects waiting to ship, with commits or a newer version since their last release."),
        refresh,
        json
      ],
      details: "Releases fetched in the last 5 minutes come from the cache.",
      aliases: ["ls"]
    ),
    CommandSpec(
      name: "recent",
      summary: "List the releases of every project, newest first.",
      usage: "releases recent [--first] [--limit <n>] [--refresh] [--json]",
      options: [
        Option(name: "--first", help: "Only the first release of each project, to see when each app launched."),
        Option(name: "--limit", help: "Show at most this many releases (default 20).", takesValue: true),
        refresh,
        json
      ],
      details: "Drafts are left out. Prereleases and each app's first release are marked."
    ),
    CommandSpec(
      name: "downloads",
      summary: "Show how many times each project's releases were downloaded from GitHub.",
      usage: "releases downloads [<project>] [--by-day] [--refresh] [--json]",
      options: [
        Option(name: "--by-day", help: "The downloads of each day, newest first, with the total so far. With --json, each app's too."),
        refresh,
        json
      ],
      details: """
        In-app updates download the same files, so they count too. GitHub only keeps the total
        so far, so the app and this command save it every day they fetch the releases. The last
        7 days show up once there's a count from a week ago, and the days before the first count
        are an estimate, spread evenly from each launch.
        With a project, it lists each release and the counts saved so far.
        """
    ),
    CommandSpec(
      name: "show",
      summary: "Show a project and all its releases.",
      usage: "releases show <project> [--refresh] [--json]",
      options: [refresh, json],
      details: """
        A project is its folder path, folder name, app name, or GitHub repo.
        It can also be a folder that isn't in the list, or a project 'discover' finds.
        """,
      aliases: ["info"]
    ),
    CommandSpec(
      name: "discover",
      summary: "List the apps and CLIs on this Mac that aren't in the list yet.",
      usage: "releases discover [--offline] [--hidden] [--json]",
      options: [
        Option(name: "--offline", help: "Don't ask GitHub whether each one was released. Faster."),
        Option(name: "--hidden", help: "List the hidden folders instead."),
        json
      ],
      details: """
        It looks in the folders that hold your projects, like ~/dev, for Xcode, SwiftPM,
        Electron and Tauri projects and npm packages with a command. Clones of other
        people's repos and hidden folders are left out. The most recently worked on come first.
        The app shows the same projects in its Add Projects sheet.
        """,
      aliases: ["found"]
    ),
    CommandSpec(
      name: "hide",
      summary: "Leave projects out of 'discover' and the app's Add Projects sheet.",
      usage: "releases hide <project>... [--json]",
      options: [json],
      details: "A project is its folder path, or the name 'discover' shows. Undo it with 'releases unhide'."
    ),
    CommandSpec(
      name: "unhide",
      summary: "Show hidden projects again.",
      usage: "releases unhide <folder>... [--json]",
      options: [json],
      details: "A folder is its path or its name. 'releases discover --hidden' lists them."
    ),
    CommandSpec(
      name: "prompt",
      summary: "Print the prompt that asks an agent to publish the next release, or to check which projects need one.",
      usage: "releases prompt (<project> | --waiting | --check) [--version <x.y.z> | --bump <patch|minor|major>] [--notes <text>] [--codex] [--json]",
      options: [
        Option(name: "--waiting", help: "A prompt for every project waiting to ship, like Create Releases in the app."),
        Option(name: "--check", help: "One prompt that asks an agent which projects waiting to ship need a release, like Check with Agent in the app."),
        versionOption,
        bump,
        notes,
        Option(name: "--codex", help: "Open the prompt in Codex. Adds a single project to the list too. --cursor is a legacy alias.", aliases: ["--cursor"]),
        json
      ],
      details: """
        Without --version or --bump, the version is the next minor release, or the project's own
        when it's higher than that.
        With --waiting, --bump and --notes apply to every project, and --codex opens
        one chat with all the prompts, to release them one at a time.
        With --check, the prompt lists the folders of every project waiting to ship, the
        most commits first. The agent picks the ones worth a release and their versions, and
        waits for your go-ahead. --codex opens it in a new Codex chat.
        """
    ),
    CommandSpec(
      name: "open",
      summary: "Show a project in the app, or open it on GitHub, in Cursor, in GitHub Desktop or in the Finder.",
      usage: "releases open [<project>] [--release [--version <x.y.z> | --bump <level>] [--notes <text>] | --github | --cursor | --github-desktop | --finder]",
      options: [
        Option(name: "--release", help: "Open the app's Create Release sheet, ready for you to review."),
        versionOption,
        bump,
        notes,
        Option(name: "--github", help: "Open the project on GitHub."),
        Option(name: "--cursor", help: "Open the project in Cursor."),
        Option(name: "--github-desktop", help: "Open the project in GitHub Desktop."),
        Option(name: "--finder", help: "Show the project folder in the Finder."),
        json
      ],
      details: """
        Without a project it opens the app on Latest Releases. The app opens through its
        releases:// links, which ./Scripts/build-app.sh registers.
        --version, --bump and --notes imply --release.
        """
    ),
    CommandSpec(
      name: "refresh",
      summary: "Fetch every project's releases from GitHub now, like ⌘R in the app.",
      usage: "releases refresh [--json]",
      options: [json],
      details: "When the app is running, it also looks for projects on disk again."
    ),
    CommandSpec(
      name: "rename",
      summary: "Give a project another name in Releases. The folder and the app stay as they are.",
      usage: "releases rename <project> <name> [--reset] [--json]",
      options: [
        Option(name: "--reset", help: "Go back to the name read from the folder."),
        json
      ],
      details: "An empty name works like --reset. The project is still found by its old name."
    ),
    CommandSpec(
      name: "remove",
      summary: "Remove projects from the list. The folders stay where they are.",
      usage: "releases remove <project>... [--json]",
      options: [json],
      aliases: ["rm"]
    ),
    CommandSpec(
      name: "store-path",
      summary: "Print the path of the file that keeps the project list.",
      usage: "releases store-path [--json]",
      options: [json]
    ),
    CommandSpec(
      name: "help",
      summary: "Show help for releases or one command.",
      usage: "releases help [command] [--json]",
      options: [json],
      details: "With --json it prints every command, its usage and its options, for agents."
    ),
    CommandSpec(
      name: "capabilities",
      summary: "What releases can do, and what changed in each version.",
      usage: "releases capabilities [--json]",
      options: [json],
      details: "Static summary for agents. No network and no user data."
    )
  ]

  static func spec(for name: String) -> CommandSpec? {
    all.first { $0.name == name || $0.aliases.contains(name) }
  }

  static func overview() -> String {
    let width = all.map(\.name.count).max() ?? 0
    let lines = all.map { spec in
      "  \(Output.pad(spec.name, to: width + 2))\(spec.summary)"
    }

    return """
      releases \(version)
      Track the versions and GitHub releases of your projects.

      Usage: releases <command> [options]

      Commands:
      \(lines.joined(separator: "\n"))

      Every command accepts --help and --json.

      Get started:
        releases add ~/dev/soundscape      Track a project.
        releases list                      See every project and its latest release.
        releases list --waiting            See the projects waiting to ship, the most commits first.
        releases prompt --check --codex   Have an agent check which of them need a release.
        releases recent                    See the latest releases across all projects.
        releases recent --first            See when each app launched.
        releases downloads                 See how many times each app was downloaded.
        releases discover                  See the apps on this Mac that aren't released yet.
        releases show soundscape           See all the releases of one project.
        releases prompt soundscape --bump minor --codex

      For agents:
        releases help --json               Every command and option, as JSON.
        releases capabilities --json       What releases can do, and what changed.
        releases open soundscape --release --bump minor
                                           Show the Create Release sheet in the app, for a human to review.
        Errors go to stderr and exit with 1. The app picks up every change to the list right away.
      """
  }

  static func help(for spec: CommandSpec) -> String {
    var text = """
      \(spec.summary)

      Usage: \(spec.usage)
      """

    if !spec.aliases.isEmpty {
      text += "\nAlias: \(spec.aliases.joined(separator: ", "))"
    }

    if !spec.options.isEmpty {
      let names = spec.options.map { ([$0.display] + $0.aliases).joined(separator: ", ") }
      let width = names.map(\.count).max() ?? 0
      let lines = zip(names, spec.options).map { name, option in
        "  \(Output.pad(name, to: width + 2))\(option.help)"
      }
      text += "\n\nOptions:\n\(lines.joined(separator: "\n"))"
    }

    if let details = spec.details {
      text += "\n\n\(details)"
    }

    return text
  }
}
