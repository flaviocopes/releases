import Charts
import ReleasesCore
import SwiftUI

/// How many times the releases were downloaded from GitHub: in total, over time, and for each app.
struct DownloadsView: View {
  @Environment(AppModel.self) private var model
  /// The app in the chart, or nil for every app together.
  @State private var chartedID: ProjectSnapshot.ID?

  var body: some View {
    let released = model.snapshots
      .filter { !$0.releases.isEmpty }
      .sorted { $0.totalDownloads > $1.totalDownloads }
    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now

    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Downloads")
            .font(.system(size: 28, weight: .bold))
          Text("How many times the files of your releases were downloaded from GitHub. In-app updates count too.")
            .foregroundStyle(.secondary)
        }

        if released.isEmpty {
          Card {
            Text("No releases yet. Their downloads show up here as soon as you publish one.")
              .foregroundStyle(.secondary)
          }
        } else {
          stats(released, weekAgo: weekAgo)
          chart(released)
          apps(released, weekAgo: weekAgo)
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.background)
    .navigationTitle("Downloads")
  }

  private func stats(_ released: [ProjectSnapshot], weekAgo: Date) -> some View {
    let total = released.totalDownloads
    let thisWeek = released.downloads(since: weekAgo)

    return HStack(spacing: 12) {
      Stat(value: total, label: total == 1 ? "download in total" : "downloads in total", symbol: "arrow.down.circle.fill", tint: .orange)
      Stat(value: thisWeek, label: "in the last 7 days", symbol: "calendar", tint: .green)
        .help(thisWeek == nil ? weekHelp(released) : "")
      if let top = released.first {
        Stat(value: top.totalDownloads, label: "\(top.name), the most downloaded", symbol: "trophy.fill", tint: .yellow)
      }
    }
  }

  private func weekHelp(_ released: [ProjectSnapshot]) -> String {
    guard let since = released.downloadsTrackedSince,
          let known = Calendar.current.date(byAdding: .day, value: 7, to: since) else {
      return "Releases saves the downloads every day, and knows the last 7 days after a week."
    }
    return "Releases started saving the downloads on \(since.formatted(.dateTime.month(.wide).day())), so it knows the last 7 days from \(known.formatted(.dateTime.month(.wide).day()))."
  }

  private func chart(_ released: [ProjectSnapshot]) -> some View {
    let charted = released.first { $0.id == chartedID }
    let points = charted?.downloadsByDay() ?? released.downloadsByDay()

    return Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Over time")
            .font(.headline)
          Spacer()
          Picker("App", selection: $chartedID) {
            Text("All Apps").tag(ProjectSnapshot.ID?.none)
            Divider()
            ForEach(released) { snapshot in
              Text(snapshot.name).tag(Optional(snapshot.id))
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .fixedSize()
        }

        DownloadsChart(points: points)
          .frame(height: 220)

        if points.contains(where: \.isEstimate) {
          Text(caption(released))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func caption(_ released: [ProjectSnapshot]) -> String {
    let estimate = "The dashed part is an estimate, a straight line from the launch to the first count."
    guard let since = released.downloadsTrackedSince else {
      return "GitHub only keeps the total so far, so Releases saves it every day. \(estimate)"
    }
    return "GitHub only keeps the total so far, so Releases saves it every day, since \(since.formatted(.dateTime.month(.wide).day())). \(estimate)"
  }

  private func apps(_ released: [ProjectSnapshot], weekAgo: Date) -> some View {
    let top = released.first?.totalDownloads ?? 0

    return VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "By app", detail: "\(released.count)")

      RowGroup {
        ForEach(released) { snapshot in
          RowButton {
            model.select(snapshot)
          } content: {
            AppDownloadsRow(snapshot: snapshot, share: top > 0 ? Double(snapshot.totalDownloads) / Double(top) : 0, weekAgo: weekAgo)
          }
          if snapshot.id != released.last?.id {
            Divider().padding(.leading, 62)
          }
        }
      }
    }
  }
}

/// The downloads so far, day by day. The line is dashed where it's an estimate, and hovering shows a day's count.
private struct DownloadsChart: View {
  let points: [DownloadPoint]

  @State private var hoveredDay: Date?

  var body: some View {
    let hovered = hoveredDay.flatMap { day in points.first { Calendar.current.isDate($0.day, inSameDayAs: day) } }

    Chart {
      ForEach(points, id: \.day) { point in
        AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.downloads))
          .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.3), .orange.opacity(0.02)], startPoint: .top, endPoint: .bottom))
      }

      ForEach(runs) { run in
        ForEach(run.points, id: \.day) { point in
          LineMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.downloads), series: .value("Part", run.id))
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: run.isEstimate ? [3, 4] : []))
        }
      }

      if let hovered {
        RuleMark(x: .value("Day", hovered.day, unit: .day))
          .foregroundStyle(Color.primary.opacity(0.18))
          .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
            VStack(spacing: 1) {
              Text(hovered.downloads, format: .number)
                .font(.headline)
                .monospacedDigit()
              Text(hovered.day, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
              if hovered.isEstimate {
                Text("estimate")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
          }
        PointMark(x: .value("Day", hovered.day, unit: .day), y: .value("Downloads", hovered.downloads))
          .foregroundStyle(.orange)
      } else if let last = points.last {
        PointMark(x: .value("Day", last.day, unit: .day), y: .value("Downloads", last.downloads))
          .foregroundStyle(.orange)
      }
    }
    .chartXSelection(value: $hoveredDay)
    .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 18))
    .chartYAxis {
      AxisMarks(position: .leading)
    }
  }

  private struct Run: Identifiable {
    var id: String
    var isEstimate: Bool
    var points: [DownloadPoint]
  }

  /// Days in a row that are all estimates, or all counted. Each run also takes the next run's first day, so the line has no gaps.
  private var runs: [Run] {
    var runs: [Run] = []
    for point in points {
      if let last = runs.last, last.isEstimate == point.isEstimate {
        runs[runs.count - 1].points.append(point)
      } else {
        if !runs.isEmpty {
          runs[runs.count - 1].points.append(point)
        }
        runs.append(Run(id: "\(runs.count)", isEstimate: point.isEstimate, points: [point]))
      }
    }
    return runs
  }
}

private struct AppDownloadsRow: View {
  let snapshot: ProjectSnapshot
  /// Its downloads next to the most downloaded app's, from 0 to 1.
  let share: Double
  let weekAgo: Date

  var body: some View {
    HStack(spacing: 12) {
      ProjectIcon(snapshot: snapshot, size: 36)

      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.name)
          .fontWeight(.semibold)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)

      Spacer(minLength: 12)

      if let week = snapshot.downloads(since: weekAgo), week > 0 {
        Text("+\(week.formatted()) this week")
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.green)
      }

      ShareBar(fraction: share)
        .frame(width: 120, height: 6)

      Text(snapshot.totalDownloads, format: .number)
        .fontWeight(.semibold)
        .monospacedDigit()
        .frame(minWidth: 44, alignment: .trailing)
    }
  }

  private var detail: String {
    let count = snapshot.releases.count { !$0.isDraft }
    let releases = count == 1 ? "1 release" : "\(count) releases"
    guard let start = snapshot.downloadsStart else { return releases }
    let thisYear = Calendar.current.isDate(start, equalTo: .now, toGranularity: .year)
    return "\(releases) · since \(start.formatted(thisYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year()))"
  }
}

private struct ShareBar: View {
  let fraction: Double

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.08))
        if fraction > 0 {
          Capsule()
            .fill(Color.orange.gradient)
            .frame(width: max(geometry.size.width * min(fraction, 1), geometry.size.height))
        }
      }
    }
  }
}
