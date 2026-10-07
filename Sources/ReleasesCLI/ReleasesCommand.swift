import Foundation
import ReleasesCore

@main
struct ReleasesCommand {
  /// Releases fetched more recently than this come from the cache.
  static let cacheAge: TimeInterval = 300

  static func main() async {
    do {
      try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      Output.error(error.localizedDescription)
      Foundation.exit(1)
    }
  }

  private static func run(_ arguments: [String]) async throws {
    guard let first = arguments.first else {
      try await run(["list"])
      return
    }

    switch first {
    case "--version", "-v", "version":
      print("releases \(Commands.version)")
      return
    case "--help", "-h":
      print(Commands.overview())
      return
    default:
      break
    }

    guard let spec = Commands.spec(for: first) else {
      throw CLIError.unknownCommand(first)
    }

    let rest = Array(arguments.dropFirst())
    if rest.contains("--help") || rest.contains("-h") {
      print(Commands.help(for: spec))
      return
    }

    let parsed = try ParsedArguments.parse(rest, for: spec)

    if spec.name == "capabilities" {
      try CapabilitiesManifest.current.print(json: parsed.has("--json"))
      return
    }

    let tracker = ReleaseTracker()

    switch spec.name {
    case "add":
      try await add(parsed, tracker)
    case "list":
      try await list(parsed, tracker)
    case "recent":
      try await recent(parsed, tracker)
    case "downloads":
      try await downloads(parsed, tracker)
    case "show":
      try await show(parsed, tracker)
    case "discover":
      try await discover(parsed, tracker)
    case "hide":
      try await hide(parsed, tracker)
    case "unhide":
      try await unhide(parsed, tracker)
    case "prompt":
      try await prompt(parsed, tracker)
    case "open":
      try await open(parsed, tracker)
    case "refresh":
      try await refresh(parsed, tracker)
    case "rename":
      try await rename(parsed, tracker)
    case "remove":
      try await remove(parsed, tracker)
    case "store-path":
      if parsed.has("--json") {
        try Output.json(["path": tracker.store.fileURL.path])
      } else {
        print(tracker.store.fileURL.path)
      }
    case "help":
      try help(parsed)
    default:
      throw CLIError.unknownCommand(spec.name)
    }
  }

  // MARK: - Commands

  private static func add(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    guard !options.positionals.isEmpty else {
      throw CLIError.missingFolder
    }

    var added: [ProjectSnapshot] = []
    var failures = 0

    for folder in options.positionals {
      let url = URL(filePath: (folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
      do {
        let (snapshot, isNew) = try await tracker.add(url)
        added.append(snapshot)
        guard !options.has("--json") else { continue }

        print("\(isNew ? "Added" : "Already tracked:") \(snapshot.name) (\(snapshot.project.path))")
        print("  GitHub:  \(snapshot.repository?.description ?? "no GitHub remote")")
        print("  Version: \(snapshot.local.version.map { "\($0.version) (\($0.label))" } ?? "not found")")
        print("  Status:  \(snapshot.statusText)")
      } catch {
        failures += 1
        Output.error(error.localizedDescription)
      }
    }

    if options.has("--json") {
      try Output.json(added.map { ProjectJSON($0, includeReleases: false) })
    }

    if failures > 0 {
      Foundation.exit(1)
    }
  }

  private static func list(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let all = try await tracker.refresh(maxAge: options.has("--refresh") ? nil : cacheAge)
    let waitingOnly = options.has("--waiting")
    let snapshots = waitingOnly ? all.waitingToShip() : all

    if options.has("--json") {
      try Output.json(snapshots.map { ProjectJSON($0, includeReleases: false) })
      return
    }

    if waitingOnly, snapshots.isEmpty, !all.isEmpty {
      print("Nothing is waiting to ship. Every project is up to date.")
    } else {
      Output.table(snapshots)
    }
    reportFetchErrors(all)
    if waitingOnly, snapshots.count > 1 {
      Output.hint("Run 'releases prompt --check --codex' to have an agent check which need a release, or 'releases prompt --waiting --codex' to release them all.")
    } else if !snapshots.isEmpty {
      Output.hint("Run 'releases show <project>' to see every release.")
    }
  }

  private static func recent(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let snapshots = try await tracker.refresh(maxAge: options.has("--refresh") ? nil : cacheAge)
    let firstOnly = options.has("--first")
    let timeline = firstOnly ? snapshots.timeline().filter(\.isFirstRelease) : snapshots.timeline()
    let entries = Array(timeline.prefix(try options.int("--limit") ?? 20))

    if options.has("--json") {
      try Output.json(entries.map(TimelineJSON.init))
      return
    }

    guard !entries.isEmpty else {
      print(snapshots.isEmpty ? "No projects yet. Add one with 'releases add <folder>'." : "No releases on GitHub yet.")
      return
    }

    Output.columns(entries.map { entry in
      [
        entry.date.formatted(date: .abbreviated, time: .shortened),
        entry.project.name,
        entry.release.tag + (entry.release.isPrerelease ? " [prerelease]" : "") + (entry.isFirstRelease && !firstOnly ? " [first release]" : ""),
        entry.release.downloadCount == 1 ? "1 download" : "\(entry.release.downloadCount) downloads"
      ]
    })
    reportFetchErrors(snapshots)
    if entries.count < timeline.count {
      Output.hint("Showing \(entries.count) of \(timeline.count) \(firstOnly ? "first releases" : "releases"). Use --limit to see more.")
    }
  }

  private static func downloads(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let snapshots = try await tracker.refresh(maxAge: options.has("--refresh") ? nil : cacheAge)
    let weekAgo = Date.now.addingTimeInterval(-7 * 86_400)
    let project = try options.positionals.first.map { try snapshots.project(matching: $0) }

    if options.has("--by-day") {
      let series = (project.map { [$0] } ?? snapshots).downloadSeries()
      if options.has("--json") {
        try Output.json(DayDownloadsJSON.days(series))
      } else if series.isEmpty {
        print("No releases on GitHub yet.")
      } else {
        Output.downloadsByDay(series)
      }
      return
    }

    if let snapshot = project {
      if options.has("--json") {
        try Output.json(ProjectDownloadsJSON(snapshot, weekAgo: weekAgo))
      } else {
        Output.downloads(of: snapshot, weekAgo: weekAgo)
        reportFetchErrors([snapshot])
      }
      return
    }

    let released = snapshots.filter { !$0.releases.isEmpty }.sorted { $0.totalDownloads > $1.totalDownloads }
    if options.has("--json") {
      try Output.json(DownloadsJSON(released, weekAgo: weekAgo))
      return
    }

    guard !released.isEmpty else {
      print(snapshots.isEmpty ? "No projects yet. Add one with 'releases add <folder>'." : "No releases on GitHub yet.")
      return
    }
    Output.downloads(released, weekAgo: weekAgo)
    reportFetchErrors(snapshots)
    if released.downloads(since: weekAgo) == nil, let since = released.downloadsTrackedSince {
      Output.hint("Releases saves the downloads every day it fetches them, since \(Output.date(since)). The last 7 days fill in a week after that.")
    } else {
      Output.hint("Run 'releases downloads <project>' to see each release.")
    }
  }

  private static func show(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let (snapshot, isTracked) = try await resolve(
      identifier(options, command: "show"),
      maxAge: options.has("--refresh") ? nil : cacheAge,
      tracker
    )

    if options.has("--json") {
      try Output.json(ProjectJSON(snapshot, includeReleases: true, isTracked: isTracked))
      return
    }

    Output.details(snapshot, isTracked: isTracked)
    if isTracked {
      reportFetchErrors([snapshot])
    }
  }

  private static func discover(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    if options.has("--hidden") {
      let hidden = try await tracker.hiddenPaths()
      if options.has("--json") {
        try Output.json(hidden)
      } else if hidden.isEmpty {
        print("Nothing is hidden.")
      } else {
        hidden.forEach { print($0) }
        Output.hint("Show one again with 'releases unhide <folder>'.")
      }
      return
    }

    let found = try await tracker.discover(fetchReleases: !options.has("--offline"))

    if options.has("--json") {
      try Output.json(found.map(FoundJSON.init))
      return
    }

    guard !found.isEmpty else {
      print("Every app and CLI on this Mac is in the list or hidden.")
      return
    }
    Output.found(found)
    Output.hint("Add one with 'releases add <folder>', or hide it with 'releases hide <folder>'.")
  }

  private static func hide(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    guard !options.positionals.isEmpty else {
      throw CLIError.missingProject(command: "hide")
    }

    var hidden: [NameJSON] = []
    var failures = 0
    for identifier in options.positionals {
      do {
        let (snapshot, isTracked) = try await tracker.lookup(identifier, fetchReleases: false)
        guard !isTracked else { throw CLIError.alreadyTracked(name: snapshot.name) }
        try await tracker.hide(snapshot.project.path)
        hidden.append(NameJSON(name: snapshot.name, path: snapshot.project.path))
        if !options.has("--json") {
          print("Hid \(snapshot.name) (\(snapshot.project.path)).")
        }
      } catch {
        failures += 1
        Output.error(error.localizedDescription)
      }
    }

    if options.has("--json") {
      try Output.json(hidden)
    }
    if failures > 0 {
      Foundation.exit(1)
    }
  }

  private static func unhide(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    guard !options.positionals.isEmpty else {
      throw CLIError.missingProject(command: "unhide")
    }

    var shown: [String] = []
    var failures = 0
    for identifier in options.positionals {
      do {
        let path = try await tracker.unhide(identifier)
        shown.append(path)
        if !options.has("--json") {
          print("\(path) shows up in 'releases discover' again.")
        }
      } catch {
        failures += 1
        Output.error(error.localizedDescription)
      }
    }

    if options.has("--json") {
      try Output.json(shown)
    }
    if failures > 0 {
      Foundation.exit(1)
    }
  }

  private static func prompt(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    if options.has("--check") {
      try await promptCheck(options, tracker)
      return
    }
    if options.has("--waiting") {
      try await promptWaiting(options, tracker)
      return
    }

    let (snapshot, isTracked) = try await resolve(identifier(options, command: "prompt"), maxAge: cacheAge, tracker)
    let version = try requestedVersion(options, for: snapshot) ?? snapshot.suggestedVersion
    let text = ReleasePrompt.make(for: snapshot, version: version, notes: options.value("--notes") ?? "")

    if options.has("--codex") {
      if !isTracked {
        _ = try await tracker.add(snapshot.project.url)
      }
      try Codex.start(prompt: text, in: snapshot.project.url)
    }

    if options.has("--json") {
      try Output.json(PromptJSON(
        project: snapshot.name,
        path: snapshot.project.path,
        version: version.description,
        tag: version.tag,
        prompt: text,
        openedInCodex: options.has("--codex")
      ))
    } else if options.has("--codex") {
      print("Opened \(snapshot.name) in Codex. Review the prompt in the chat and send it.")
    } else {
      print(text)
    }
  }

  private static func promptWaiting(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    if let project = options.positionals.first {
      throw CLIError.conflictingOptions(project, "--waiting")
    }
    if options.value("--version") != nil {
      throw CLIError.conflictingOptions("--version", "--waiting")
    }

    let waiting = try await tracker.refresh(maxAge: cacheAge).waitingToShip()
    let releases = try waiting.map { snapshot in
      let version = try requestedVersion(options, for: snapshot) ?? snapshot.suggestedVersion
      return (snapshot: snapshot, version: version, prompt: ReleasePrompt.make(for: snapshot, version: version, notes: options.value("--notes") ?? ""))
    }

    if options.has("--codex"), !releases.isEmpty {
      try Codex.start(releases.map { (prompt: $0.prompt, folder: $0.snapshot.project.url) })
    }

    if options.has("--json") {
      try Output.json(releases.map { release in
        PromptJSON(
          project: release.snapshot.name,
          path: release.snapshot.project.path,
          version: release.version.description,
          tag: release.version.tag,
          prompt: release.prompt,
          openedInCodex: options.has("--codex")
        )
      })
    } else if releases.isEmpty {
      print("Nothing is waiting to ship.")
    } else if options.has("--codex") {
      print("Opened \(releases.map(\.snapshot.name).joined(separator: ", ")) in Codex with their release prompts. Review the draft and send it.")
    } else {
      print(releases.map(\.prompt).joined(separator: "\n\n---\n\n"))
    }
  }

  private static func promptCheck(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    if let conflict = options.positionals.first ?? ["--waiting", "--version", "--bump"].first(where: { options.has($0) || options.value($0) != nil }) {
      throw CLIError.conflictingOptions(conflict, "--check")
    }

    let waiting = try await tracker.refresh(maxAge: cacheAge).waitingToShip()
    let text = waiting.isEmpty ? nil : ReleasePrompt.check(waiting, notes: options.value("--notes") ?? "")

    if options.has("--codex"), let text {
      try Codex.start(prompt: text)
    }

    if options.has("--json") {
      try Output.json(CheckPromptJSON(
        projects: waiting.map { NameJSON(name: $0.name, path: $0.project.path) },
        prompt: text,
        openedInCodex: options.has("--codex") && text != nil
      ))
    } else if let text {
      print(options.has("--codex") ? "Opened Codex with a prompt to check \(waiting.count == 1 ? "1 project" : "\(waiting.count) projects"). Review it and send it." : text)
    } else {
      print("Nothing is waiting to ship.")
    }
  }

  private static func open(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let targets = ["--github", "--codex", "--cursor", "--github-desktop", "--finder", "--release"].filter(options.has)
    let wantsRelease = options.has("--release") || options.value("--version") != nil
      || options.value("--bump") != nil || options.value("--notes") != nil
    if targets.count > 1 {
      throw CLIError.conflictingOptions(targets[0], targets[1])
    }
    if let target = targets.first, target != "--release", wantsRelease {
      throw CLIError.conflictingOptions(target, "--release")
    }

    guard let identifier = options.positionals.first else {
      guard targets.isEmpty, !wantsRelease else { throw CLIError.missingProject(command: "open") }
      try AppLink.home.open()
      try report(options, OpenJSON(opened: "app", project: nil, path: nil, url: AppLink.home.url), "Opened Releases.")
      return
    }

    let (snapshot, _) = try await tracker.lookup(identifier, fetchReleases: false)
    let path = snapshot.project.path

    switch targets.first {
    case "--github":
      guard let repository = snapshot.repository else { throw CLIError.notOnGitHub(name: snapshot.name) }
      try openURL(repository.url)
      try report(options, OpenJSON(opened: "github", project: snapshot.name, path: path, url: repository.url), "Opened \(repository.url.absoluteString).")
    case "--codex":
      try Codex.openProject(snapshot)
      try report(options, OpenJSON(opened: "codex", project: snapshot.name, path: path, url: nil), "Opened \(snapshot.name) in Codex.")
    case "--cursor":
      try Cursor.open(snapshot.project.url)
      try report(options, OpenJSON(opened: "cursor", project: snapshot.name, path: path, url: nil), "Opened \(snapshot.name) in Cursor.")
    case "--github-desktop":
      try GitHubDesktop.open(snapshot.project.url)
      try report(options, OpenJSON(opened: "github-desktop", project: snapshot.name, path: path, url: nil), "Opened \(snapshot.name) in GitHub Desktop.")
    case "--finder":
      try openURL(nil, arguments: ["-R", path])
      try report(options, OpenJSON(opened: "finder", project: snapshot.name, path: path, url: nil), "Showed \(snapshot.name) in the Finder.")
    default:
      let link: AppLink
      if wantsRelease {
        let fresh = try await resolve(path, maxAge: cacheAge, tracker).snapshot
        link = .release(path: path, version: try requestedVersion(options, for: fresh), notes: options.value("--notes"))
      } else {
        link = .project(path: path)
      }
      try link.open()
      let message = wantsRelease
        ? "Opened the Create Release sheet for \(snapshot.name) in the app. It's waiting for a human to review it."
        : "Showed \(snapshot.name) in the app."
      try report(options, OpenJSON(opened: wantsRelease ? "release" : "app", project: snapshot.name, path: path, url: link.url), message)
    }
  }

  private static func refresh(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let snapshots = try await tracker.refresh(maxAge: nil)
    if AppLink.isAppRunning {
      try? AppLink.refresh.open(inBackground: true)
    }

    if options.has("--json") {
      try Output.json(snapshots.map { ProjectJSON($0, includeReleases: false) })
      return
    }
    Output.table(snapshots)
    reportFetchErrors(snapshots)
  }

  private static func rename(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    let identifier = try identifier(options, command: "rename")
    let input = options.positionals.dropFirst().joined(separator: " ")
    guard options.has("--reset") || !options.positionals.dropFirst().isEmpty else {
      throw CLIError.missingName
    }
    let snapshot = try await tracker.snapshots().project(matching: identifier)
    let name = options.has("--reset") ? nil : snapshot.displayName(for: input)
    try await tracker.rename(snapshot.id, to: name)

    if options.has("--json") {
      try Output.json(RenameJSON(name: name ?? snapshot.local.name, detectedName: snapshot.local.name, path: snapshot.project.path))
    } else if let name {
      print("Renamed \(snapshot.name) to \(name). The app shows the new name right away.")
    } else {
      print("\(snapshot.local.name) is back to the name read from its folder.")
    }
  }

  private static func remove(_ options: ParsedArguments, _ tracker: ReleaseTracker) async throws {
    guard !options.positionals.isEmpty else {
      throw CLIError.missingProject(command: "remove")
    }

    let snapshots = try await tracker.snapshots()
    var removed: [NameJSON] = []
    var failures = 0

    for identifier in options.positionals {
      do {
        let snapshot = try snapshots.project(matching: identifier)
        try await tracker.remove(snapshot.project.path)
        removed.append(NameJSON(name: snapshot.name, path: snapshot.project.path))
        if !options.has("--json") {
          print("Removed \(snapshot.name).")
        }
      } catch {
        failures += 1
        Output.error(error.localizedDescription)
      }
    }

    if options.has("--json") {
      try Output.json(removed)
    }
    if failures > 0 {
      Foundation.exit(1)
    }
  }

  private static func help(_ options: ParsedArguments) throws {
    if let name = options.positionals.first {
      guard let target = Commands.spec(for: name) else {
        throw CLIError.unknownCommand(name)
      }
      if options.has("--json") {
        try Output.json(target)
      } else {
        print(Commands.help(for: target))
      }
    } else if options.has("--json") {
      try Output.json(HelpJSON(version: Commands.version, commands: Commands.all))
    } else {
      print(Commands.overview())
    }
  }

  // MARK: - Helpers

  private static func identifier(_ options: ParsedArguments, command: String) throws -> String {
    guard let value = options.positionals.first else {
      throw CLIError.missingProject(command: command)
    }
    return value
  }

  /// A tracked project with releases no older than `maxAge`, or a folder on disk with the releases GitHub has now.
  private static func resolve(_ identifier: String, maxAge: TimeInterval?, _ tracker: ReleaseTracker) async throws -> (snapshot: ProjectSnapshot, isTracked: Bool) {
    let (match, isTracked) = try await tracker.lookup(identifier, fetchReleases: false)
    guard isTracked else {
      return (await tracker.found(at: match.project.url).snapshot, false)
    }
    let snapshot = try await tracker
      .refresh(maxAge: maxAge, only: [match.id])
      .project(matching: match.project.path)
    return (snapshot, true)
  }

  /// The version from --version or --bump. Nil when neither is there.
  private static func requestedVersion(_ options: ParsedArguments, for snapshot: ProjectSnapshot) throws -> SemanticVersion? {
    switch (options.value("--version"), options.value("--bump")) {
    case (let raw?, nil):
      guard let parsed = SemanticVersion(raw) else {
        throw CLIError.invalidValue(option: "--version", value: raw)
      }
      return parsed
    case (nil, let raw?):
      guard let bump = SemanticVersion.Bump(rawValue: raw.lowercased()) else {
        throw CLIError.invalidValue(option: "--bump", value: raw)
      }
      return snapshot.bumpBase.bumped(bump)
    case (nil, nil):
      return nil
    case (_?, _?):
      throw CLIError.conflictingOptions("--version", "--bump")
    }
  }

  private static func openURL(_ url: URL?, arguments: [String] = []) throws {
    let result = Process()
    result.executableURL = URL(filePath: "/usr/bin/open")
    result.arguments = arguments + (url.map { [$0.absoluteString] } ?? [])
    try result.run()
    result.waitUntilExit()
    guard result.terminationStatus == 0 else {
      throw CLIError.couldNotOpen
    }
  }

  private static func report(_ options: ParsedArguments, _ value: OpenJSON, _ message: String) throws {
    if options.has("--json") {
      try Output.json(value)
    } else {
      print(message)
    }
  }

  private static func reportFetchErrors(_ snapshots: [ProjectSnapshot]) {
    for snapshot in snapshots where snapshot.project.releases != nil {
      if let error = snapshot.project.fetchError {
        Output.note("\(snapshot.name): \(error) Showing the releases fetched earlier.")
      }
    }
  }
}
