import AppKit
import Observation
import ReleasesCore

enum SidebarItem: Hashable {
  case home
  case project(ProjectSnapshot.ID)
  /// A project on disk that isn't in the list.
  case found(FoundProject.ID)
}

/// What the Create Release sheet opens with.
struct ReleaseDraft: Identifiable {
  var snapshot: ProjectSnapshot
  var version: SemanticVersion?
  var notes = ""

  var id: String { snapshot.id }
}

@MainActor
@Observable
final class AppModel {
  var snapshots: [ProjectSnapshot] = []
  /// Apps and CLIs on disk that weren't in the list at the last look, the most recently worked on first.
  var found: [FoundProject] = []
  var selection: SidebarItem? = .home
  var isRefreshing = false
  var lastRefresh: Date?
  var errorMessage: String?
  var releaseDraft: ReleaseDraft?
  var showsAddProjects = false
  /// True while the app looks for projects on disk.
  private(set) var isDiscovering = false

  /// Releases fetched more recently than this are shown from the cache.
  static let cacheAge: TimeInterval = 300
  /// Looking for projects on disk asks GitHub about each one, so it happens at most this often without ⌘R.
  static let discoveryAge: TimeInterval = 3600

  @ObservationIgnored
  private let tracker = ReleaseTracker()

  @ObservationIgnored
  private var watcher: DispatchSourceFileSystemObject?

  @ObservationIgnored
  private var reloadTask: Task<Void, Never>?

  @ObservationIgnored
  private var lastDiscovery: Date?

  @ObservationIgnored
  private var hiddenPaths: Set<String> = []

  /// Found projects minus the ones added to the list since.
  var foundProjects: [FoundProject] {
    let tracked = Set(snapshots.map(\.id))
    return found.filter { !tracked.contains($0.id) }
  }

  var selectedSnapshot: ProjectSnapshot? {
    guard case .project(let id) = selection else { return nil }
    return snapshots.first { $0.id == id }
  }

  var selectedFound: FoundProject? {
    guard case .found(let id) = selection else { return nil }
    return foundProjects.first { $0.id == id }
  }

  func select(_ snapshot: ProjectSnapshot) {
    selection = .project(snapshot.id)
  }

  /// Goes back home when the selected project is gone.
  private func fixSelection() {
    if selection == nil || (selection != .home && selectedSnapshot == nil && selectedFound == nil) {
      selection = .home
    }
  }

  /// Reads the list from disk without going to GitHub.
  func reload() async {
    do {
      snapshots = try await tracker.snapshots()
      await syncHiddenPaths()
      fixSelection()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Fetches the releases from GitHub. Without `force`, recent fetches come from the cache.
  func refresh(force: Bool = false) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      snapshots = try await tracker.refresh(maxAge: force ? nil : Self.cacheAge)
      lastRefresh = .now
      fixSelection()
    } catch {
      errorMessage = error.localizedDescription
    }
    await discover(force: force)
  }

  /// Looks for apps and CLIs on disk that aren't in the list. A failed look keeps the last results.
  func discover(force: Bool = false) async {
    if !force, let lastDiscovery, Date.now.timeIntervalSince(lastDiscovery) < Self.discoveryAge { return }
    guard !isDiscovering else { return }
    isDiscovering = true
    defer { isDiscovering = false }

    guard var projects = try? await tracker.discover() else { return }
    if let selected = selectedFound, !projects.contains(where: { $0.id == selected.id }), !hiddenPaths.contains(selected.id) {
      projects.insert(selected, at: 0)
    }
    found = projects
    lastDiscovery = .now
    fixSelection()
  }

  /// The Add Projects sheet looks right away the first time, before the hourly look has run.
  func discoverIfNeeded() async {
    if lastDiscovery == nil {
      await discover(force: true)
    }
  }

  /// Drops found projects hidden from the CLI, and looks again when one is shown again.
  private func syncHiddenPaths() async {
    guard let hidden = try? await Set(tracker.hiddenPaths()), hidden != hiddenPaths else { return }
    let wasUnhidden = !hiddenPaths.subtracting(hidden).isEmpty
    hiddenPaths = hidden
    found.removeAll { hidden.contains($0.id) }
    if wasUnhidden {
      Task { await discover(force: true) }
    }
  }

  func add(_ urls: [URL]) async {
    var failures: [String] = []
    for url in urls {
      do {
        let (snapshot, _) = try await tracker.add(url)
        select(snapshot)
      } catch {
        failures.append(error.localizedDescription)
      }
    }
    await reload()
    if !failures.isEmpty {
      errorMessage = failures.joined(separator: "\n")
    }
  }

  func remove(_ snapshot: ProjectSnapshot) async {
    do {
      try await tracker.remove(snapshot.project.path)
      await reload()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func hide(_ project: FoundProject) async {
    found.removeAll { $0.id == project.id }
    hiddenPaths.insert(project.id)
    fixSelection()
    do {
      try await tracker.hide(project.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func chooseFolders() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    panel.message = "Choose the project folders to track."
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    Task { await add(urls) }
  }

  func openInCursor(_ snapshot: ProjectSnapshot) {
    do {
      try Cursor.open(snapshot.project.url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func createRelease(_ snapshot: ProjectSnapshot, version: SemanticVersion? = nil, notes: String = "") {
    releaseDraft = ReleaseDraft(snapshot: snapshot, version: version, notes: notes)
  }

  /// Opens Cursor with the prompt. A project that isn't in the list yet gets added first.
  func startRelease(_ snapshot: ProjectSnapshot, prompt: String) async {
    if !snapshots.contains(where: { $0.id == snapshot.id }) {
      await add([snapshot.project.url])
    }
    do {
      try await Cursor.start(prompt: prompt, in: snapshot.project.url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Links

  /// Shows what a `releases://` link asks for. The CLI sends them with `releases open`.
  func handle(_ link: AppLink) async {
    if snapshots.isEmpty {
      await reload()
    }

    switch link {
    case .home:
      selection = .home
    case .project(let path):
      await show(path: path)
    case .release(let path, let version, let notes):
      if let snapshot = await show(path: path) {
        createRelease(snapshot, version: version, notes: notes ?? "")
      }
    case .refresh:
      lastDiscovery = nil
      await refresh()
    }
  }

  /// Selects a project in the list or on disk. Folders outside the usual places get inspected on the spot.
  @discardableResult
  private func show(path: String) async -> ProjectSnapshot? {
    let path = URL(filePath: path).standardizedFileURL.path
    if let snapshot = snapshots.first(where: { $0.id == path }) {
      select(snapshot)
      return snapshot
    }

    var project = found.first { $0.id == path }
    if project == nil {
      guard FileManager.default.fileExists(atPath: path) else {
        errorMessage = "There's no folder at \(path)."
        return nil
      }
      let inspected = await tracker.found(at: URL(filePath: path, directoryHint: .isDirectory))
      found.insert(inspected, at: 0)
      project = inspected
    }
    selection = .found(path)
    return project?.snapshot
  }

  /// Reloads when another process, like the `releases` CLI, changes the project list.
  func watchStore() {
    guard watcher == nil else { return }
    let folder = tracker.store.fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let descriptor = open(folder.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: .write,
      queue: .main
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor in self?.scheduleReload() }
    }
    source.setCancelHandler {
      close(descriptor)
    }
    source.resume()
    watcher = source
  }

  /// Saves come in bursts, so wait for them to settle.
  private func scheduleReload() {
    reloadTask?.cancel()
    reloadTask = Task {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled, !isRefreshing else { return }
      await reload()
    }
  }
}
