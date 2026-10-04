import Charts
import ReleasesCore
import SwiftUI

/// The chart shows the downloads of each day, or the total so far.
private enum ChartMode {
  case perDay, total
}

/// How many times the releases were downloaded from GitHub: in total, over time, and for each app.
struct DownloadsView: View {
  @Environment(AppModel.self) private var model
  @State private var chartMode = ChartMode.perDay

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
    let series = released.downloadSeries()

    return Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Over time")
            .font(.headline)
          Spacer()
          PillPicker(selection: $chartMode, options: [
            PillOption(value: .perDay, title: "Per Day", symbol: "chart.bar.fill"),
            PillOption(value: .total, title: "Total", symbol: "chart.line.uptrend.xyaxis")
          ])
        }

        DownloadsChart(series: series, perDay: chartMode == .perDay)
          .frame(height: 260)

        Text(caption(released, series: series))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func caption(_ released: [ProjectSnapshot], series: [DownloadSeries]) -> String {
    var sentences: [String] = []
    if series.last?.name == "Other" {
      sentences.append("Other adds up the apps with fewer than 10 downloads.")
    }
    if series.total.contains(where: \.isEstimate) {
      let since = released.downloadsTrackedSince.map { ", since \($0.formatted(.dateTime.month(.wide).day()))" } ?? ""
      sentences.append("GitHub only keeps the total so far, so Releases saves it every day\(since). The faded bars before that are an estimate, spread evenly from each launch.")
    }
    return sentences.joined(separator: " ")
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

/// The downloads of each day, or the total so far, in bars stacked by app. Estimated days are faded,
/// and hovering a day shows its numbers.
private struct DownloadsChart: View {
  let series: [DownloadSeries]
  let perDay: Bool

  @State private var hoveredDay: Date?

  private static let palette: [Color] = [.orange, .blue, .green, .purple, .pink, .teal, .indigo, .yellow, .mint, .red, .cyan, .brown]

  var body: some View {
    let shown = series.map { DownloadSeries(name: $0.name, points: perDay ? $0.points.perDay() : $0.points) }
    let names = shown.map(\.name)
    let hoveredIndex = hoveredDay.flatMap { day in
      shown.first?.points.firstIndex { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    Chart {
      if let hoveredIndex, let day = shown.first?.points[hoveredIndex].day {
        RectangleMark(x: .value("Day", day, unit: .day))
          .foregroundStyle(Color.primary.opacity(0.07))
          .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
            DayBreakdown(day: day, perDay: perDay, rows: shown.compactMap { series in
              let point = series.points[hoveredIndex]
              guard point.downloads > 0 else { return nil }
              return DayBreakdown.Row(name: series.name, downloads: point.downloads, color: color(for: series.name, in: names), isEstimate: point.isEstimate)
            })
          }
      }

      ForEach(shown, id: \.name) { series in
        ForEach(series.points, id: \.day) { point in
          BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.downloads))
            .foregroundStyle(by: .value("App", series.name))
            .opacity(point.isEstimate ? 0.4 : 1)
        }
      }
    }
    .chartForegroundStyleScale(domain: names, range: names.map { color(for: $0, in: names) })
    .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
    .chartXSelection(value: $hoveredDay)
    .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 16))
    .chartYAxis {
      AxisMarks(position: .leading)
    }
  }

  private func color(for name: String, in names: [String]) -> Color {
    if name == "Other" { return .gray }
    return Self.palette[(names.firstIndex(of: name) ?? 0) % Self.palette.count]
  }
}

/// A day's downloads, app by app, the most first.
private struct DayBreakdown: View {
  struct Row: Identifiable {
    var name: String
    var downloads: Int
    var color: Color
    var isEstimate: Bool
    var id: String { name }
  }

  let day: Date
  let perDay: Bool
  let rows: [Row]

  var body: some View {
    let total = rows.reduce(0) { $0 + $1.downloads }

    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(perDay ? "+\(total.formatted())" : total.formatted())
          .font(.headline)
          .monospacedDigit()
        Text(day, format: .dateTime.month(.abbreviated).day())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(rows.sorted { $0.downloads > $1.downloads }) { row in
        HStack(spacing: 6) {
          Circle()
            .fill(row.color)
            .frame(width: 7, height: 7)
          Text(row.name)
            .lineLimit(1)
          Spacer(minLength: 12)
          Text(row.downloads, format: .number)
            .monospacedDigit()
        }
        .font(.caption)
      }
      if rows.contains(where: \.isEstimate) {
        Text("Estimate")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(8)
    .frame(width: 190)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
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
