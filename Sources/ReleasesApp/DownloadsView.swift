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
    let series = released.downloadSeries(top: Self.topCount)

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
      sentences.append("Other adds up the apps after the top \(Self.topCount), and the ones under 10 downloads.")
    }
    if series.total.contains(where: \.isEstimate) {
      let since = released.downloadsTrackedSince.map { ", since \($0.formatted(.dateTime.month(.wide).day()))" } ?? ""
      sentences.append("GitHub only keeps the total so far, so Releases saves it every day\(since). The shaded days before that are an estimate, spread evenly from each launch.")
    }
    return sentences.joined(separator: " ")
  }

  private func apps(_ released: [ProjectSnapshot], weekAgo: Date) -> some View {
    let (top, others) = released.splitByDownloads(top: Self.topCount)
    let most = Double(max(top.first?.totalDownloads ?? others.totalDownloads, 1))

    return VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "Top apps")

      RowGroup {
        ForEach(Array(top.enumerated()), id: \.element.id) { index, snapshot in
          if index > 0 {
            Divider().padding(.leading, 62)
          }
          RowButton {
            model.select(snapshot)
          } content: {
            AppDownloadsRow(snapshot: snapshot, color: DownloadColors.color(at: index), share: Double(snapshot.totalDownloads) / most, weekAgo: weekAgo)
          }
        }
        if !others.isEmpty {
          if !top.isEmpty {
            Divider().padding(.leading, 62)
          }
          OtherDownloadsRow(apps: others, share: Double(others.totalDownloads) / most, weekAgo: weekAgo)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
      }
    }
  }

  private static let topCount = 5
}

/// The chart's colors: one per top app, in order, and gray for Other.
private enum DownloadColors {
  static let palette: [Color] = [.orange, .blue, .green, .purple, .pink]
  static let other = Color.gray

  static func color(at index: Int) -> Color {
    palette[index % palette.count]
  }
}

/// The downloads of each day, or the total so far, in bars stacked by app, at least two weeks wide.
/// A shaded band marks the estimated days, and hovering a day shows its numbers.
private struct DownloadsChart: View {
  let series: [DownloadSeries]
  let perDay: Bool

  @State private var hoveredDay: Date?

  var body: some View {
    let calendar = Calendar.current
    let shown = series.map { DownloadSeries(name: $0.name, points: perDay ? $0.points.perDay() : $0.points) }
    let colors = shown.enumerated().map { index, series in series.name == "Other" ? DownloadColors.other : DownloadColors.color(at: index) }
    let totals = shown.total
    let lastDay = totals.last?.day ?? calendar.startOfDay(for: .now)
    let firstDay = min(totals.first?.day ?? lastDay, calendar.date(byAdding: .day, value: -13, to: lastDay) ?? lastDay)
    let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
    let dayCount = calendar.dateComponents([.day], from: firstDay, to: end).day ?? totals.count
    let estimateEnd = totals.last(where: \.isEstimate).flatMap { calendar.date(byAdding: .day, value: 1, to: $0.day) }
    let hoveredIndex = hoveredDay.flatMap { day in totals.firstIndex { calendar.isDate($0.day, inSameDayAs: day) } }

    Chart {
      if let estimateEnd, let start = totals.first?.day {
        RectangleMark(xStart: .value("Day", start), xEnd: .value("Day", estimateEnd))
          .foregroundStyle(Color.primary.opacity(0.045))
          .annotation(position: .overlay, alignment: .topLeading) {
            Text("Estimate")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.tertiary)
              .padding(6)
          }
      }

      if let hoveredIndex {
        RectangleMark(x: .value("Day", totals[hoveredIndex].day, unit: .day))
          .foregroundStyle(Color.primary.opacity(0.07))
      }

      ForEach(shown, id: \.name) { series in
        ForEach(series.points, id: \.day) { point in
          BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.downloads), width: .ratio(0.62))
            .foregroundStyle(by: .value("App", series.name))
        }
      }

      if dayCount <= 21 {
        ForEach(totals.filter { $0.downloads > 0 }, id: \.day) { point in
          PointMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.downloads))
            .symbolSize(0)
            .annotation(position: .top, spacing: 3) {
              Text(point.downloads, format: .number)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
      }

      if let hoveredIndex {
        RuleMark(x: .value("Day", totals[hoveredIndex].day, unit: .day))
          .foregroundStyle(.clear)
          .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
            DayBreakdown(day: totals[hoveredIndex].day, perDay: perDay, rows: shown.indices.compactMap { index in
              let point = shown[index].points[hoveredIndex]
              guard point.downloads > 0 else { return nil }
              return DayBreakdown.Row(name: shown[index].name, downloads: point.downloads, color: colors[index], isEstimate: point.isEstimate)
            })
          }
      }
    }
    .chartForegroundStyleScale(domain: shown.map(\.name), range: colors)
    .chartLegend(.hidden)
    .chartXSelection(value: $hoveredDay)
    .chartXScale(domain: firstDay...end, range: .plotDimension(startPadding: 0, endPadding: 14))
    .chartXAxis {
      AxisMarks(values: labelDays(from: firstDay, count: dayCount, calendar: calendar)) {
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading)
    }
  }

  /// About seven days to label, always ending with today, at the middle of each day so they sit under the bars.
  private func labelDays(from first: Date, count: Int, calendar: Calendar) -> [Date] {
    let step = max(1, Int((Double(count) / 7).rounded(.up)))
    return stride(from: count - 1, through: 0, by: -step).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: first).map { $0.addingTimeInterval(12 * 3_600) }
    }
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

/// An app in the top ones. Its bar has its color in the chart, so the list doubles as the legend.
private struct AppDownloadsRow: View {
  let snapshot: ProjectSnapshot
  let color: Color
  /// Its downloads next to the most downloaded app's, from 0 to 1.
  let share: Double
  let weekAgo: Date

  var body: some View {
    DownloadsRow(name: snapshot.name, detail: detail, week: snapshot.downloads(since: weekAgo), total: snapshot.totalDownloads, share: share, color: color) {
      ProjectIcon(snapshot: snapshot, size: 36)
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

/// The apps outside the top ones, added up like in the chart.
private struct OtherDownloadsRow: View {
  let apps: [ProjectSnapshot]
  let share: Double
  let weekAgo: Date

  var body: some View {
    let names = apps.map(\.name).joined(separator: ", ")
    DownloadsRow(name: "Other", detail: apps.count == 1 ? names : "\(apps.count) apps: \(names)", week: apps.downloads(since: weekAgo), total: apps.totalDownloads, share: share, color: DownloadColors.other) {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color.gray.opacity(0.25))
        .frame(width: 30, height: 30)
        .overlay {
          Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 36)
    }
    .help(names)
  }
}

private struct DownloadsRow<Icon: View>: View {
  let name: String
  let detail: String
  let week: Int?
  let total: Int
  let share: Double
  let color: Color
  @ViewBuilder let icon: Icon

  var body: some View {
    HStack(spacing: 12) {
      icon

      VStack(alignment: .leading, spacing: 3) {
        Text(name)
          .fontWeight(.semibold)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)

      Spacer(minLength: 12)

      if let week, week > 0 {
        Text("+\(week.formatted()) this week")
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.green)
      }

      ShareBar(fraction: share, color: color)
        .frame(width: 120, height: 6)

      Text(total, format: .number)
        .fontWeight(.semibold)
        .monospacedDigit()
        .frame(minWidth: 44, alignment: .trailing)
    }
  }
}

private struct ShareBar: View {
  let fraction: Double
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.08))
        if fraction > 0 {
          Capsule()
            .fill(color.gradient)
            .frame(width: max(geometry.size.width * min(fraction, 1), geometry.size.height))
        }
      }
    }
  }
}
