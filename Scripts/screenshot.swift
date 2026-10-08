// Captures the real app window for the README, in light and dark, into
// <folder>/screenshot-<light|dark>.png (Latest Releases) and
// <folder>/screenshot-project-<light|dark>.png (one project).
// Scripts/screenshot.sh compiles it with the app's views, in place of the @main file.
// The app names are real. Release notes, counts and dates are made up. The real project list is never read.

import AppKit
import ReleasesCore
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let title = "Releases Manager"
let width: CGFloat = 1180
let height: CGFloat = 760

@MainActor
enum Demo {
  static let model = AppModel()
  static let home = NSHomeDirectory()
  static let icons = FileManager.default.temporaryDirectory.appending(path: "releases-screenshot-icons")

  static func content() -> some View {
    ContentView().environment(model)
  }

  /// The pages to capture, by file name.
  static let pages: [(name: String, selection: SidebarItem)] = [
    ("screenshot", .home),
    ("screenshot-project", .project("\(home)/dev/note-repo"))
  ]

  static func prepare() async {
    try? FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
    model.snapshots = [
      project("Note Repo", folder: "note-repo", symbol: "pencil.line", colors: (0x5C9DFF, 0x2457D6), version: "2.5.0", releases: [
        release("Note Repo", "2.5.0", hoursAgo: 1.4, downloads: 38, notes: ["**Starred notes.** Keep the notes you want to return to in the sidebar.", "**Posts from X.** Save a post beside your own notes.", "**Search.** Find a note by its text."]),
        release("Note Repo", "2.4.0", hoursAgo: 96, downloads: 214, notes: ["**The editor.** Write and format notes without leaving the app.", "**Daily notes.** Scroll back through the days where you wrote something."]),
        release("Note Repo", "2.3.0", hoursAgo: 530, downloads: 167, notes: ["**Links.** Save a page to read later."]),
        release("Note Repo", "2.2.0", hoursAgo: 800, downloads: 96, notes: ["**Small fixes.** A smoother editing session."])
      ]),
      project("Tranquillity Maker", folder: "tranquillity-maker", symbol: "waveform", colors: (0xFFAE5C, 0xE8590C), version: "1.5.0", releases: [
        release("Tranquillity Maker", "1.5.0", hoursAgo: 4.2, downloads: 21, notes: ["**Your mix.** Layer background sounds and set each volume."]),
        release("Tranquillity Maker", "1.4.0", hoursAgo: 27, downloads: 64, notes: ["**Your last mix.** Sound choices and volumes are remembered between launches."])
      ]),
      project("VM Peek", folder: "vm-peek", symbol: "desktopcomputer", colors: (0xB79BFF, 0x6741D9), version: "1.2.0", releases: [
        release("VM Peek", "1.2.0", hoursAgo: 30, downloads: 112, notes: ["**The test VM.** See its screen and the agents using it."])
      ], commits: ["Keep the activity list beside the live screen", "Remember the window size"]),
      project("Work Tracebook", folder: "work-tracebook", symbol: "list.bullet.clipboard", colors: (0x7C95FF, 0x364FC7), version: "1.3.0", releases: [
        release("Work Tracebook", "1.3.0", hoursAgo: 75, downloads: 43, notes: ["**Work logs.** Follow tasks from the first report to completion."])
      ]),
      project("Skill Cabinet", folder: "skill-cabinet", symbol: "square.stack.3d.up", colors: (0xFF8FB8, 0xC2255C), version: "1.5.0", releases: [
        release("Skill Cabinet", "1.5.0", hoursAgo: 90, downloads: 390, notes: ["**Skills.** Browse the instructions your agents can use."])
      ]),
      project("Chip Pops", folder: "chip-pops", symbol: "speaker.wave.2", colors: (0x74C0FC, 0x1971C2), version: "1.2.0", releases: [
        release("Chip Pops", "1.2.0", hoursAgo: 110, downloads: 72, notes: ["**Sound effects.** Find a click, a chime or a game sound."])
      ]),
      project("Footage Ferry", folder: "footage-ferry", symbol: "camera", colors: (0x8CE99A, 0x2B8A3E), version: "1.3.0", releases: [
        release("Footage Ferry", "1.3.0", hoursAgo: 135, downloads: 29, notes: ["**Camera clips.** Bring footage from your phone to the Mac."])
      ]),
      project("Releases Manager", folder: "releases-manager", symbol: "shippingbox", colors: (0xFFD43B, 0xE67700), version: "1.6.0", releases: [
        release("Releases Manager", "1.6.0", hoursAgo: 160, downloads: 86, notes: ["**App releases.** See published versions and the commits waiting for the next one."])
      ]),
      project("CLI Tools Cabinet", folder: "cli-tools-cabinet", symbol: "terminal", colors: (0xFF8787, 0xC92A2A), version: "1.5.0", releases: [
        release("CLI Tools Cabinet", "1.5.0", hoursAgo: 180, downloads: 120, notes: ["**Your commands.** Find installed tools and ask what they can do."])
      ]),
      project("Number Pantry", folder: "number-pantry", symbol: "number", colors: (0x909AA5, 0x343A40), version: "1.2.0", releases: [
        release("Number Pantry", "1.2.0", hoursAgo: 205, downloads: 64, notes: ["**Calculators.** Find a formula, enter the values and keep the result."])
      ]),
      project("Architecture Dissector", folder: "architecture-dissector", symbol: "point.3.connected.trianglepath.dotted", colors: (0x5C9DFF, 0x2457D6), version: "1.2.0", releases: [
        release("Architecture Dissector", "1.2.0", hoursAgo: 230, downloads: 42, notes: ["**App maps.** Follow the components, stored data and workflows."])
      ]),
      project("Post Slide Deck", folder: "post-slide-deck", symbol: "rectangle.on.rectangle", colors: (0xB79BFF, 0x6741D9), version: "1.2.0", releases: [
        release("Post Slide Deck", "1.2.0", hoursAgo: 255, downloads: 91, notes: ["**Slides.** Present posts from X, text and images."])
      ]),
      project("Broadcast Keep", folder: "broadcast-keep", symbol: "record.circle", colors: (0xFFAE5C, 0xE8590C), version: "1.1.0", releases: [
        release("Broadcast Keep", "1.1.0", hoursAgo: 280, downloads: 37, notes: ["**Recordings.** Keep a livestream to watch later."])
      ])
    ].sortedByRelease()

    model.found = [
      found("Tab Reunion", folder: "tab-reunion", symbol: "rectangle.3.group", colors: (0x74C0FC, 0x1971C2), hoursAgo: 2, onGitHub: true),
      found("Slide Lookout", folder: "slide-lookout", symbol: "rectangle.inset.filled", colors: (0x8CE99A, 0x2B8A3E), hoursAgo: 26, onGitHub: true),
      found("Repo Foyer", folder: "repo-foyer", symbol: "folder", colors: (0x909AA5, 0x343A40), hoursAgo: 100, onGitHub: true),
      found("Couch Snake", folder: "couch-snake", symbol: "gamecontroller", colors: (0xFFD43B, 0xE67700), hoursAgo: 230, onGitHub: true)
    ]
    model.lastRefresh = .now.addingTimeInterval(-120)
    try? await Task.sleep(for: .seconds(1))
  }

  static func select(_ selection: SidebarItem) async {
    model.selection = selection
    try? await Task.sleep(for: .seconds(1))
  }

  // MARK: - Made-up data

  static func project(
    _ name: String,
    folder: String,
    symbol: String,
    colors: (UInt32, UInt32),
    version: String,
    releases: [Release],
    commits: [String]? = nil
  ) -> ProjectSnapshot {
    var project = TrackedProject(path: "\(home)/dev/\(folder)")
    project.releases = releases
    project.releasesFetchedAt = .now.addingTimeInterval(-120)
    let local = LocalProject(
      name: name,
      repository: GitHubRepository(owner: "orchard-apps", name: folder),
      version: VersionSource(version: version, file: "project.yml", key: "MARKETING_VERSION"),
      iconPath: icon(folder, symbol: symbol, colors: colors),
      branch: "main"
    )
    let unreleased = (commits ?? []).enumerated().map { index, subject in
      Commit(hash: String(format: "%07x", 0x3a1f9c0 + index * 0x1b7d3), subject: subject, date: .now.addingTimeInterval(-Double(index + 1) * 5_400))
    }
    return ProjectSnapshot(project: project, local: local, unreleasedCommits: unreleased)
  }

  static func found(_ name: String, folder: String, symbol: String, colors: (UInt32, UInt32), hoursAgo: Double, onGitHub: Bool) -> FoundProject {
    var project = TrackedProject(path: "\(home)/dev/\(folder)")
    project.releases = onGitHub ? [] : nil
    let local = LocalProject(
      name: name,
      repository: onGitHub ? GitHubRepository(owner: "orchard-apps", name: folder) : nil,
      version: VersionSource(version: "0.1.0", file: "project.yml", key: "MARKETING_VERSION"),
      iconPath: icon(folder, symbol: symbol, colors: colors),
      branch: "main"
    )
    return FoundProject(snapshot: ProjectSnapshot(project: project, local: local), lastActivity: .now.addingTimeInterval(-hoursAgo * 3_600))
  }

  static func release(_ name: String, _ version: String, hoursAgo: Double, downloads: Int, notes: [String]) -> Release {
    let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
    let asset = "\(slug)-\(version).zip"
    let base = "https://github.com/orchard-apps/\(slug)/releases"
    return Release(
      tag: "v\(version)",
      title: "\(name) \(version)",
      publishedAt: .now.addingTimeInterval(-hoursAgo * 3_600),
      url: URL(string: "\(base)/tag/v\(version)")!,
      notes: "## What's new\n\n" + notes.map { "- \($0)" }.joined(separator: "\n"),
      assets: [ReleaseAsset(
        name: asset,
        size: 3_400_000 + downloads * 1_000,
        downloadCount: downloads,
        downloadURL: URL(string: "\(base)/download/v\(version)/\(asset)")!
      )]
    )
  }

  /// An app icon drawn from an SF Symbol on a gradient, written to a temporary PNG.
  static func icon(_ folder: String, symbol: String, colors: (UInt32, UInt32)) -> String {
    let file = icons.appending(path: "\(folder).png")
    let view = RoundedRectangle(cornerRadius: 50, style: .continuous)
      .fill(LinearGradient(colors: [Color(hex: colors.0), Color(hex: colors.1)], startPoint: .top, endPoint: .bottom))
      .overlay {
        Image(systemName: symbol)
          .font(.system(size: 96, weight: .semibold))
          .foregroundStyle(.white)
      }
      .frame(width: 224, height: 224)
      .padding(16)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
      try? png.write(to: file)
    }
    return file.path
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

@main
enum Screenshot {
  @MainActor
  static func main() {
    // Points the app at an empty list, so nothing can read or change the real one.
    setenv("RELEASES_STORE", FileManager.default.temporaryDirectory.appending(path: "releases-screenshot/projects.json").path, 1)

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let host = NSHostingView(rootView: Demo.content().frame(width: width, height: height))
    host.sceneBridgingOptions = [.toolbars]
    let window = ActiveWindow(
      contentRect: CGRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unified
    window.contentView = host
    window.center()
    // Beside the pointer, so it can't hover a row while it captures. Fully off screen, the window can't become key.
    let mouse = NSEvent.mouseLocation
    if window.frame.insetBy(dx: -40, dy: -40).contains(mouse), let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
      let roomOnLeft = mouse.x - screen.frame.minX
      let roomOnRight = screen.frame.maxX - mouse.x
      window.setFrameOrigin(NSPoint(x: roomOnLeft > roomOnRight ? mouse.x - window.frame.width - 60 : mouse.x + 60, y: window.frame.minY))
    }
    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await capture(window) }
      }
    }
    app.run()
  }
}

/// Draws as the active window even when another app is frontmost, which is the case
/// when this runs from a terminal: macOS doesn't let it take focus.
final class ActiveWindow: NSWindow {
  override var isKeyWindow: Bool { true }
  override var isMainWindow: Bool { true }
  @objc(_hasActiveAppearance) func hasActiveAppearance() -> Bool { true }
  @objc(_hasActiveAppearanceIgnoringKeyFocus) func hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
  @objc(_hasKeyAppearance) func hasKeyAppearance() -> Bool { true }
  @objc(_hasMainAppearance) func hasMainAppearance() -> Bool { true }
}

/// The sidebar draws its selection in the accent color only while it has the focus.
@MainActor
func focusSidebar(_ window: NSWindow) {
  func table(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    return view.subviews.lazy.compactMap(table(in:)).first
  }
  if let root = window.contentView, let sidebar = table(in: root) {
    window.makeFirstResponder(sidebar)
  }
}

@MainActor
func capture(_ window: NSWindow) async {
  await Demo.prepare()
  for page in Demo.pages {
    await Demo.select(page.selection)
    focusSidebar(window)
    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
      NSApp.appearance = NSAppearance(named: appearance)
      try? await Task.sleep(for: .seconds(1))
      write(framed(snapshot(window)), to: output.appending(path: "\(page.name)-\(name).png"))
    }
  }
  NSApp.terminate(nil)
}

/// The whole window, title bar included, at the screen's scale.
@MainActor
func snapshot(_ window: NSWindow) -> CGImage {
  let view = window.contentView!.superview!
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  return rep.cgImage!
}

/// Rounds the corners like a window and adds a soft shadow on a transparent 48pt margin.
func framed(_ image: CGImage) -> CGImage {
  let scale: CGFloat = 2
  let margin = 48 * scale
  let radius = 10 * scale
  let size = CGSize(width: CGFloat(image.width) + 2 * margin, height: CGFloat(image.height) + 2 * margin)
  let context = CGContext(
    data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
  let window = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: CGColor(gray: 0, alpha: 0.32))
  context.addPath(window)
  context.setFillColor(CGColor(gray: 0.5, alpha: 1))
  context.fillPath()
  context.restoreGState()

  context.addPath(window)
  context.clip()
  context.draw(image, in: rect)
  context.resetClip()
  context.addPath(window)
  context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
  context.setLineWidth(1)
  context.strokePath()
  return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let rep = NSBitmapImageRep(cgImage: image)
  try! rep.representation(using: .png, properties: [:])!.write(to: url)
  print(url.path)
}
