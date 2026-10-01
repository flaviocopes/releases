// Captures the real app window for the README, in light and dark, into
// <folder>/screenshot-<light|dark>.png (Latest Releases) and
// <folder>/screenshot-project-<light|dark>.png (one project).
// Scripts/screenshot.sh compiles it with the app's views, in place of the @main file.
// Every project is made up. The real project list is never read.

import AppKit
import ReleasesCore
import SwiftUI

let output = URL(filePath: CommandLine.arguments[1])
let title = "Releases"
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
    ("screenshot-project", .project("\(home)/dev/inkwell"))
  ]

  static func prepare() async {
    try? FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
    model.snapshots = [
      project("Inkwell", folder: "inkwell", symbol: "pencil.line", colors: (0x5C9DFF, 0x2457D6), version: "2.1.0", releases: [
        release("Inkwell", "2.1.0", hoursAgo: 1.4, downloads: 38, notes: ["**Tags.** Add #tags to any note and filter the sidebar by them.", "**Quick open.** ⌘P jumps to any note by its title.", "**Faster search.** Results show up while you type."]),
        release("Inkwell", "2.0.0", hoursAgo: 96, downloads: 214, notes: ["**Folders.** Group notes in folders, and drag them around.", "**iCloud sync.** Your notes on every Mac you use.", "**A new editor.** Markdown that formats while you type."]),
        release("Inkwell", "1.4.0", hoursAgo: 530, downloads: 167, notes: ["**Export to PDF.** With the same fonts as the app.", "**Word count.** In the status bar."]),
        release("Inkwell", "1.3.2", hoursAgo: 800, downloads: 96, notes: ["**Paste stays put.** The cursor no longer jumps to the end after pasting."])
      ]),
      project("Driftwood", folder: "driftwood", symbol: "timer", colors: (0xFFAE5C, 0xE8590C), version: "1.3.0", releases: [
        release("Driftwood", "1.3.0", hoursAgo: 4.2, downloads: 21, notes: ["**Menu bar timer.** The time left, always in sight.", "**Custom sounds.** Pick the chime at the end of a session."]),
        release("Driftwood", "1.2.1", hoursAgo: 27, downloads: 64, notes: ["**Sleep-proof sessions.** A session keeps going when the Mac goes to sleep."])
      ]),
      project("Lumen", folder: "lumen", symbol: "camera.aperture", colors: (0xB79BFF, 0x6741D9), version: "1.0.0", releases: [
        release("Lumen", "1.0.0", hoursAgo: 30, downloads: 112, notes: ["**Capture any window** with its shadow, or without.", "**Annotate** with arrows, boxes and text.", "**Copy or save** in one click."])
      ], commits: ["Add a timer before the capture", "Remember the last folder", "Fix blurry arrows on external displays"]),
      project("Portside", folder: "portside", symbol: "network", colors: (0x7C95FF, 0x364FC7), version: "1.1.0", releases: [
        release("Portside", "1.0.2", hoursAgo: 75, downloads: 43, notes: ["**Docker ports.** Ports used by Docker show up once."]),
        release("Portside", "1.0.0", hoursAgo: 260, downloads: 128, notes: ["**Every open port** on your Mac, with the app that opened it.", "**Kill a process** from the list."])
      ]),
      project("Stash", folder: "stash", symbol: "doc.on.clipboard", colors: (0xFF8FB8, 0xC2255C), version: "3.2.0", releases: [
        release("Stash", "3.2.0", hoursAgo: 340, downloads: 390, notes: ["**Pinned items** stay at the top of your clipboard history."])
      ])
    ].sortedByRelease()

    model.found = [
      found("Weather Bar", folder: "weather-bar", symbol: "cloud.sun.fill", colors: (0x74C0FC, 0x1971C2), hoursAgo: 2, onGitHub: false),
      found("Habit Grid", folder: "habit-grid", symbol: "square.grid.3x3.fill", colors: (0x8CE99A, 0x2B8A3E), hoursAgo: 26, onGitHub: true),
      found("Snippets", folder: "snippets", symbol: "curlybraces", colors: (0x909AA5, 0x343A40), hoursAgo: 100, onGitHub: false),
      found("Pixel Pad", folder: "pixel-pad", symbol: "paintbrush.pointed.fill", colors: (0xFFD43B, 0xE67700), hoursAgo: 230, onGitHub: true),
      found("Menu Clock", folder: "menu-clock", symbol: "clock.fill", colors: (0xFF8787, 0xC92A2A), hoursAgo: 400, onGitHub: false)
    ] + ["dotfiles-sync", "tiny-server", "markdown-preview", "color-picker", "rename-photos", "json-viewer", "dock-spacer"].enumerated().map { index, folder in
      found(folder, folder: folder, symbol: "hammer.fill", colors: (0xADB5BD, 0x495057), hoursAgo: 600 + Double(index) * 200, onGitHub: false)
    }
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
    let base = "https://github.com/orchard-apps/\(name.lowercased())/releases"
    return Release(
      tag: "v\(version)",
      title: "\(name) \(version)",
      publishedAt: .now.addingTimeInterval(-hoursAgo * 3_600),
      url: URL(string: "\(base)/tag/v\(version)")!,
      notes: "## What's new\n\n" + notes.map { "- \($0)" }.joined(separator: "\n"),
      assets: [ReleaseAsset(
        name: "\(name)-\(version).zip",
        size: 3_400_000 + downloads * 1_000,
        downloadCount: downloads,
        downloadURL: URL(string: "\(base)/download/v\(version)/\(name)-\(version).zip")!
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

@MainActor
func capture(_ window: NSWindow) async {
  await Demo.prepare()
  for page in Demo.pages {
    await Demo.select(page.selection)
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
