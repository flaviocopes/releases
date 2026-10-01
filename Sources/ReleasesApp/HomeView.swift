import ReleasesCore
import SwiftUI

/// Every release of every project, newest first and grouped by day.
struct HomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let entries = model.snapshots.timeline()

    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Latest Releases")
            .font(.system(size: 28, weight: .bold))
          Text("Every release of your \(model.snapshots.count == 1 ? "project" : "\(model.snapshots.count) projects"), newest first.")
            .foregroundStyle(.secondary)
        }

        Stats(entries: entries)

        if !waiting.isEmpty {
          WaitingSection(snapshots: waiting)
        }

        if entries.isEmpty {
          Card {
            Text("No releases on GitHub yet. They show up here as soon as you publish one.")
              .foregroundStyle(.secondary)
          }
        } else {
          ForEach(days(entries), id: \.day) { group in
            DaySection(day: group.day, entries: group.entries)
          }
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.background)
    .navigationTitle("Latest Releases")
  }

  /// Projects with work that isn't in a release yet.
  private var waiting: [ProjectSnapshot] {
    model.snapshots.filter { $0.status == .unreleasedChanges || $0.status == .readyToRelease }
  }

  private func days(_ entries: [TimelineEntry]) -> [(day: Date, entries: [TimelineEntry])] {
    let calendar = Calendar.current
    let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
  }
}

private struct Stats: View {
  @Environment(AppModel.self) private var model
  let entries: [TimelineEntry]

  var body: some View {
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    let thisWeek = entries.count { $0.date >= weekAgo }
    let released = model.snapshots.count { $0.latestRelease != nil }
    let downloads = model.snapshots.reduce(0) { $0 + $1.totalDownloads }

    HStack(spacing: 12) {
      Stat(value: thisWeek, label: thisWeek == 1 ? "release this week" : "releases this week", symbol: "calendar", tint: .green)
      Stat(value: released, label: released == 1 ? "app released" : "apps released", symbol: "shippingbox.fill", tint: .blue)
      Stat(value: downloads, label: downloads == 1 ? "download" : "downloads", symbol: "arrow.down.circle.fill", tint: .orange)
    }
  }
}

private struct Stat: View {
  let value: Int
  let label: String
  let symbol: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
      Text(value, format: .number)
        .font(.system(size: 26, weight: .bold))
        .monospacedDigit()
      Text(label)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.quaternary.opacity(0.4))
    )
  }
}

private struct WaitingSection: View {
  @Environment(AppModel.self) private var model
  let snapshots: [ProjectSnapshot]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "Waiting to ship", detail: "\(snapshots.count)")

      RowGroup {
        ForEach(snapshots) { snapshot in
          RowButton {
            model.select(snapshot)
          } content: {
            HStack(spacing: 12) {
              ProjectIcon(snapshot: snapshot, size: 32)
              Text(snapshot.name)
                .fontWeight(.semibold)
              Label(snapshot.statusText, systemImage: snapshot.status.symbol)
                .font(.callout)
                .foregroundStyle(snapshot.status.color)
                .lineLimit(1)
              Spacer(minLength: 8)
              Button("Create Release…") {
                model.createRelease(snapshot)
              }
              .controlSize(.small)
            }
          }
          if snapshot.id != snapshots.last?.id {
            Divider().padding(.leading, 58)
          }
        }
      }
    }
  }
}

private struct DaySection: View {
  @Environment(AppModel.self) private var model
  let day: Date
  let entries: [TimelineEntry]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: title, detail: entries.count == 1 ? "1 release" : "\(entries.count) releases")

      RowGroup {
        ForEach(entries) { entry in
          RowButton {
            model.select(entry.project)
          } content: {
            TimelineRow(entry: entry)
          }
          if entry.id != entries.last?.id {
            Divider().padding(.leading, 62)
          }
        }
      }
    }
  }

  private var title: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
      return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    return day.formatted(.dateTime.month(.wide).day().year())
  }
}

private struct TimelineRow: View {
  let entry: TimelineEntry

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

      Text(entry.date, format: .dateTime.hour().minute())
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

/// Rows stacked in one rounded box, like a grouped list.
private struct RowGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.quaternary.opacity(0.4))
    )
  }
}

/// A whole row that acts as a button and lights up on hover.
private struct RowButton<Content: View>: View {
  let action: () -> Void
  @ViewBuilder let content: Content

  @State private var isHovering = false

  var body: some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(isHovering ? 0.05 : 0))
      )
      .contentShape(Rectangle())
      .onTapGesture(perform: action)
      .onHover { isHovering = $0 }
  }
}
