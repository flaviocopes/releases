import AppKit
import ReleasesCore
import SwiftUI

extension ReleaseStatus {
  var color: Color {
    switch self {
    case .upToDate: .green
    case .unreleasedChanges: .orange
    case .readyToRelease: .blue
    case .neverReleased: .purple
    case .versionBehind, .missing: .red
    case .notLoaded, .noRepository: .gray
    }
  }

  var symbol: String {
    switch self {
    case .upToDate: "checkmark.circle.fill"
    case .unreleasedChanges: "arrow.triangle.branch"
    case .readyToRelease: "shippingbox.fill"
    case .neverReleased: "sparkles"
    case .versionBehind: "exclamationmark.triangle.fill"
    case .missing: "questionmark.folder.fill"
    case .notLoaded: "clock"
    case .noRepository: "link.badge.plus"
    }
  }
}

/// App icons, loaded once per path.
@MainActor
enum IconCache {
  private static var images: [String: NSImage] = [:]

  static func image(for snapshot: ProjectSnapshot) -> NSImage? {
    if let appPath = snapshot.local.appPath {
      return cached(appPath) { NSWorkspace.shared.icon(forFile: appPath) }
    }
    if let iconPath = snapshot.local.iconPath {
      return cached(iconPath) { NSImage(contentsOfFile: iconPath) }
    }
    return nil
  }

  private static func cached(_ key: String, load: () -> NSImage?) -> NSImage? {
    if let image = images[key] { return image }
    let image = load()
    images[key] = image
    return image
  }
}

struct ProjectIcon: View {
  let snapshot: ProjectSnapshot
  var size: CGFloat = 32

  var body: some View {
    if let image = IconCache.image(for: snapshot) {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .frame(width: size, height: size)
    } else {
      RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .fill(tint.gradient)
        .frame(width: size * 0.82, height: size * 0.82)
        .overlay {
          Text(snapshot.name.prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
  }

  private var tint: Color {
    let colors: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
    let sum = snapshot.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return colors[sum % colors.count]
  }
}

struct StatusBadge: View {
  let snapshot: ProjectSnapshot

  var body: some View {
    Label(snapshot.statusText, systemImage: snapshot.status.symbol)
      .font(.callout.weight(.medium))
      .lineLimit(1)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .foregroundStyle(snapshot.status.color)
      .background(Capsule().fill(snapshot.status.color.opacity(0.13)))
  }
}

struct Tag: View {
  let text: String
  var color: Color = .secondary

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(color)
      .background(Capsule().fill(color.opacity(0.14)))
  }
}

struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(.quaternary.opacity(0.4))
      )
  }
}

extension Int {
  var downloads: String {
    self == 1 ? "1 download" : "\(formatted()) downloads"
  }
}

/// Inline Markdown, like **bold**, `code` and links.
func inlineMarkdown(_ text: String) -> AttributedString {
  (try? AttributedString(
    markdown: text,
    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
  )) ?? AttributedString(text)
}

/// A release's changes as bullets: just the headlines, or the whole text with the details.
struct ChangeList: View {
  let changes: [Change]
  var showsDetails = false

  var body: some View {
    VStack(alignment: .leading, spacing: showsDetails ? 7 : 4) {
      ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text("•")
            .foregroundStyle(.tertiary)
          Text(showsDetails ? fullText(change) : inlineMarkdown(change.headline))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .font(.callout)
    .textSelection(.enabled)
  }

  /// The bold lead-in stays in the primary color, the rest goes secondary.
  private func fullText(_ change: Change) -> AttributedString {
    var text = inlineMarkdown(change.text)
    guard change.hasLeadIn else { return text }
    let plainRanges = text.runs
      .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) != true }
      .map(\.range)
    for range in plainRanges {
      text[range].foregroundColor = .secondary
    }
    return text
  }
}
