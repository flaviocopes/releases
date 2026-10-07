import AppKit
import ReleasesCore
import SwiftUI

struct CodexIcon: View {
  private var image: Image {
    #if RELEASES_SCREENSHOT
    let bundle = Bundle.main
    #else
    let bundle = Bundle.module
    #endif
    return Image(nsImage: NSImage(contentsOf: bundle.url(forResource: "CodexLogo", withExtension: "png")!)!)
  }

  var body: some View {
    image
      .renderingMode(.original)
      .resizable()
      .frame(width: 18, height: 18)
      .accessibilityHidden(true)
  }
}

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

extension Color {
  /// Marks a project's first release, the one that launched it.
  static let firstRelease = Color.green
}

struct FirstReleaseTag: View {
  var body: some View {
    Label("First release", systemImage: "sparkles")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(Color.firstRelease)
      .background(Capsule().fill(Color.firstRelease.opacity(0.14)))
      .help("The release that launched this app")
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

/// A big number in a card, with a symbol above and a label below. Nil shows a dash.
struct Stat: View {
  let value: Int?
  let label: String
  let symbol: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
      Group {
        if let value {
          Text(value, format: .number)
        } else {
          Text("–").foregroundStyle(.tertiary)
        }
      }
      .font(.system(size: 26, weight: .bold))
      .monospacedDigit()
      Text(label)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.quaternary.opacity(0.4))
    )
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

struct PillOption<Value: Hashable> {
  var value: Value
  var title: String
  var symbol: String
  /// Nil for a neutral pill.
  var tint: Color?
  /// Shown in a badge when it's more than zero.
  var count = 0
}

/// Options as pills on one track, instead of a stock segmented control. The selection slides over.
struct PillPicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [PillOption<Value>]
  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        PillButton(title: option.title, symbol: option.symbol, tint: option.tint, count: option.count, isSelected: selection == option.value, namespace: namespace) {
          selection = option.value
        }
      }
    }
    .padding(3)
    .background(Capsule().fill(.quaternary.opacity(0.5)))
    .fixedSize()
    .animation(.snappy(duration: 0.25), value: selection)
  }
}

private struct PillButton: View {
  let title: String
  let symbol: String
  let tint: Color?
  let count: Int
  let isSelected: Bool
  let namespace: Namespace.ID
  let action: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Label {
          Text(title)
            .foregroundStyle(isSelected || isHovering ? Color.primary : .secondary)
        } icon: {
          Image(systemName: symbol)
            .foregroundStyle(isSelected ? tint ?? .primary : .secondary)
        }
        if count > 0 {
          Text(count, format: .number)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? tint ?? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
      }
      .font(.callout.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background {
        if isSelected {
          Capsule()
            .fill(pill)
            .shadow(color: .black.opacity(tint == nil && colorScheme == .light ? 0.12 : 0), radius: 1.5, y: 1)
            .matchedGeometryEffect(id: "selection", in: namespace)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var pill: Color {
    if let tint { return tint.opacity(colorScheme == .dark ? 0.24 : 0.18) }
    return colorScheme == .dark ? .white.opacity(0.14) : .white
  }
}

/// Rows stacked in one rounded box, like a grouped list.
struct RowGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(.quaternary.opacity(0.4))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

/// A whole row that acts as a button and lights up on hover. The group clips it to its rounded corners.
struct RowButton<Content: View>: View {
  var tint: Color?
  let action: () -> Void
  @ViewBuilder let content: Content

  @State private var isHovering = false

  var body: some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if let tint {
          LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .leading, endPoint: .trailing)
        }
      }
      .background(Color.primary.opacity(isHovering ? 0.05 : 0))
      .contentShape(Rectangle())
      .onTapGesture(perform: action)
      .onHover { isHovering = $0 }
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
