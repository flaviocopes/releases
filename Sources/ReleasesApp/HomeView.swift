import ReleasesCore
import SwiftUI

/// The tabs of Latest Releases.
enum HomeTab: CaseIterable {
  case all, first, waiting

  var title: String {
    switch self {
    case .all: "All Releases"
    case .first: "First Releases"
    case .waiting: "Waiting to Ship"
    }
  }

  var symbol: String {
    switch self {
    case .all: "square.stack.3d.up.fill"
    case .first: "sparkles"
    case .waiting: "shippingbox.fill"
    }
  }

  /// Nil for a neutral pill.
  var tint: Color? {
    switch self {
    case .all: nil
    case .first: .firstRelease
    case .waiting: .orange
    }
  }
}

/// Every release of every project, newest first and grouped by day. Or only the first ones, grouped
/// into today, yesterday, the last 7 days, then months. Or the projects waiting to ship.
struct HomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    let timeline = model.snapshots.timeline()

    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack(spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Latest Releases")
              .font(.system(size: 28, weight: .bold))
            Text(subtitle(timeline))
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          HomeTabs(tab: $model.homeTab, waitingCount: waiting.count)
        }

        Stats(entries: timeline)

        switch model.homeTab {
        case .all: allReleases(timeline)
        case .first: firstReleases(timeline.filter(\.isFirstRelease))
        case .waiting: WaitingList(snapshots: waiting)
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.background)
    .navigationTitle("Latest Releases")
    .toolbar {
      ToolbarItemGroup {
        Spacer()
        if !waiting.isEmpty {
          Button {
            model.createReleasesForWaiting()
          } label: {
            Label(waiting.count == 1 ? "Create Release…" : "Create \(waiting.count) Releases…", systemImage: "shippingbox")
          }
          .labelStyle(.titleAndIcon)
          .help("Release every project waiting to ship, each in its own Cursor window")
        }
      }
    }
  }

  private var waiting: [ProjectSnapshot] {
    model.waitingToShip
  }

  @ViewBuilder
  private func allReleases(_ entries: [TimelineEntry]) -> some View {
    if entries.isEmpty {
      NoReleases()
    } else {
      ForEach(days(entries), id: \.start) { group in
        TimelineSection(
          title: dayTitle(group.start),
          detail: group.entries.count == 1 ? "1 release" : "\(group.entries.count) releases",
          entries: group.entries
        )
      }
    }
  }

  @ViewBuilder
  private func firstReleases(_ entries: [TimelineEntry]) -> some View {
    if entries.isEmpty {
      NoReleases()
    } else {
      ForEach(entries.groupedByPeriod(), id: \.period) { group in
        TimelineSection(
          title: title(group.period),
          detail: group.entries.count == 1 ? "1 app" : "\(group.entries.count) apps",
          entries: group.entries,
          firstReleasesOnly: true,
          showsDay: group.period != .today && group.period != .yesterday
        )
      }
    }
  }

  private func subtitle(_ timeline: [TimelineEntry]) -> String {
    switch model.homeTab {
    case .all:
      return "Every release of your \(model.snapshots.count == 1 ? "project" : "\(model.snapshots.count) projects"), newest first."
    case .first:
      let launches = timeline.count(where: \.isFirstRelease)
      return launches == 1 ? "When your app launched." : "When each of your \(launches) apps launched, newest first."
    case .waiting:
      switch waiting.count {
      case 0: return "Every project is up to date."
      case 1: return "1 project has something new since its last release."
      default: return "\(waiting.count) projects have something new since their last release."
      }
    }
  }

  private func days(_ entries: [TimelineEntry]) -> [(start: Date, entries: [TimelineEntry])] {
    let calendar = Calendar.current
    let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
  }

  private func title(_ period: TimelinePeriod) -> String {
    switch period {
    case .today: "Today"
    case .yesterday: "Yesterday"
    case .lastSevenDays: "Last 7 Days"
    case .month(let start): start.formatted(.dateTime.month(.wide).year())
    }
  }

  private func dayTitle(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
      return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    return day.formatted(.dateTime.month(.wide).day().year())
  }
}

/// The tabs as pills on one track. The selection slides over, green for first releases and orange for waiting to ship.
private struct HomeTabs: View {
  @Binding var tab: HomeTab
  let waitingCount: Int
  @Namespace private var selection

  var body: some View {
    HStack(spacing: 2) {
      ForEach(HomeTab.allCases, id: \.self) { option in
        TabPill(tab: option, count: option == .waiting ? waitingCount : 0, isSelected: tab == option, selection: selection) {
          tab = option
        }
      }
    }
    .padding(3)
    .background(Capsule().fill(.quaternary.opacity(0.5)))
    .fixedSize()
    .animation(.snappy(duration: 0.25), value: tab)
  }
}

private struct TabPill: View {
  let tab: HomeTab
  let count: Int
  let isSelected: Bool
  let selection: Namespace.ID
  let action: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Label {
          Text(tab.title)
            .foregroundStyle(isSelected || isHovering ? Color.primary : .secondary)
        } icon: {
          Image(systemName: tab.symbol)
            .foregroundStyle(isSelected ? tab.tint ?? .primary : .secondary)
        }
        if count > 0 {
          Text(count, format: .number)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? tab.tint ?? .primary : .secondary)
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
            .shadow(color: .black.opacity(tab.tint == nil && colorScheme == .light ? 0.12 : 0), radius: 1.5, y: 1)
            .matchedGeometryEffect(id: "selection", in: selection)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var pill: Color {
    if let tint = tab.tint { return tint.opacity(colorScheme == .dark ? 0.24 : 0.18) }
    return colorScheme == .dark ? .white.opacity(0.14) : .white
  }
}

private struct Stats: View {
  @Environment(AppModel.self) private var model
  let entries: [TimelineEntry]

  var body: some View {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    let thisWeek = entries.count { $0.date >= weekAgo }
    let released = model.snapshots.count { $0.latestRelease != nil }
    let downloads = model.snapshots.totalDownloads

    HStack(spacing: 12) {
      Stat(value: thisWeek, label: thisWeek == 1 ? "release this week" : "releases this week", symbol: "calendar", tint: .green)
      Stat(value: released, label: released == 1 ? "app released" : "apps released", symbol: "shippingbox.fill", tint: .blue)
      Button {
        model.selection = .downloads
      } label: {
        Stat(value: downloads, label: downloads == 1 ? "download from GitHub" : "downloads from GitHub", symbol: "arrow.down.circle.fill", tint: .orange)
      }
      .buttonStyle(.plain)
      .help("See the downloads of each app, and how they grew")
    }
  }
}

private struct NoReleases: View {
  var body: some View {
    Card {
      Text("No releases on GitHub yet. They show up here as soon as you publish one.")
        .foregroundStyle(.secondary)
    }
  }
}

/// The projects with commits or a newer version since their last release, each with what's waiting to go out.
private struct WaitingList: View {
  @Environment(AppModel.self) private var model
  let snapshots: [ProjectSnapshot]

  var body: some View {
    if snapshots.isEmpty {
      Card {
        Text("Nothing is waiting to ship. New commits and version bumps show up here.")
          .foregroundStyle(.secondary)
      }
    } else {
      RowGroup {
        ForEach(snapshots) { snapshot in
          RowButton {
            model.select(snapshot)
          } content: {
            HStack(spacing: 12) {
              ProjectIcon(snapshot: snapshot, size: 36)

              VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text(snapshot.name)
                    .fontWeight(.semibold)
                  Label(snapshot.statusText, systemImage: snapshot.status.symbol)
                    .font(.callout)
                    .foregroundStyle(snapshot.status.color)
                }
                .lineLimit(1)
                if let commits = snapshot.unreleasedCommits, !commits.isEmpty {
                  Text(commits.map(\.subject).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
              }

              Spacer(minLength: 8)

              Button("Create Release…") {
                model.createRelease(snapshot)
              }
              .controlSize(.small)
            }
          }
          if snapshot.id != snapshots.last?.id {
            Divider().padding(.leading, 62)
          }
        }
      }
    }
  }
}

private struct TimelineSection: View {
  @Environment(AppModel.self) private var model
  let title: String
  let detail: String
  let entries: [TimelineEntry]
  var firstReleasesOnly = false
  var showsDay = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: title, detail: detail)

      RowGroup {
        ForEach(entries) { entry in
          RowButton(tint: entry.isFirstRelease ? .firstRelease : nil) {
            model.select(entry.project)
          } content: {
            TimelineRow(entry: entry, firstReleasesOnly: firstReleasesOnly, showsDay: showsDay)
          }
          if entry.id != entries.last?.id {
            Divider().padding(.leading, 62)
          }
        }
      }
    }
  }
}

private struct TimelineRow: View {
  let entry: TimelineEntry
  /// Every row is a first release, so the tag would repeat on each one.
  var firstReleasesOnly = false
  /// The section spans more than one day, so the row shows the day instead of the time.
  var showsDay = false

  var body: some View {
    HStack(spacing: 12) {
      ProjectIcon(snapshot: entry.project, size: 36)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(entry.project.name)
            .fontWeight(.semibold)
          Text(entry.release.tag)
            .font(.system(.callout, design: .monospaced, weight: .medium))
            .foregroundStyle(.secondary)
          if entry.release.isPrerelease {
            Tag(text: "Prerelease", color: .purple)
          }
          if entry.isFirstRelease, !firstReleasesOnly {
            FirstReleaseTag()
          }
        }

        Text(summary)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Label(entry.release.downloadCount.formatted(), systemImage: "arrow.down.circle")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .help(entry.release.downloadCount.downloads)

      Text(entry.date, format: showsDay ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute())
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)

      Link(destination: entry.release.url) {
        Image(systemName: "arrow.up.right.square")
      }
      .help("Open the release on GitHub")
    }
  }

  /// The headlines of the changes on one line, or the release title when the notes have none.
  private var summary: AttributedString {
    let headlines = entry.project.changes(in: entry.release).map(\.headline)
    if !headlines.isEmpty {
      return inlineMarkdown(headlines.joined(separator: " · "))
    }
    return AttributedString(entry.release.title ?? entry.release.tag)
  }
}