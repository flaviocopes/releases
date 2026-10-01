import ReleasesCore
import SwiftUI

struct ProjectListView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    List(selection: $model.selection) {
      Label {
        Text("Latest Releases")
      } icon: {
        Image(systemName: "clock.arrow.circlepath")
          .foregroundStyle(.green)
      }
      .tag(SidebarItem.home)

      if !model.foundProjects.isEmpty {
        OnThisMacSection()
      }

      Section("Projects") {
        ForEach(model.snapshots) { snapshot in
          ProjectRow(snapshot: snapshot)
            .tag(SidebarItem.project(snapshot.id))
            .contextMenu {
              ProjectActions(snapshot: snapshot)
              Divider()
              Button("Remove from List") {
                Task { await model.remove(snapshot) }
              }
            }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      RefreshStatus()
    }
    .toolbar {
      ToolbarItem {
        Button {
          model.chooseFolders()
        } label: {
          Label("Add Project", systemImage: "plus")
        }
        .help("Add a project folder")
      }
    }
  }
}

/// Open on GitHub, in Cursor and in the Finder. Used by the context menu and the detail toolbar.
struct ProjectActions: View {
  @Environment(AppModel.self) private var model
  let snapshot: ProjectSnapshot

  var body: some View {
    if let repository = snapshot.repository {
      Button {
        NSWorkspace.shared.open(repository.url)
      } label: {
        Label("Open on GitHub", systemImage: "arrow.up.right.square")
      }
      .help("Open \(repository.description) on GitHub")
    }
    Button {
      model.openInCursor(snapshot)
    } label: {
      Label("Open in Cursor", systemImage: "chevron.left.forwardslash.chevron.right")
    }
    .help("Open the project in Cursor")
    .disabled(!snapshot.local.exists)
    Button {
      NSWorkspace.shared.activateFileViewerSelecting([snapshot.project.url])
    } label: {
      Label("Show in Finder", systemImage: "folder")
    }
    .help("Show the project folder in the Finder")
    .disabled(!snapshot.local.exists)
  }
}

private struct ProjectRow: View {
  let snapshot: ProjectSnapshot

  var body: some View {
    HStack(spacing: 10) {
      ProjectIcon(snapshot: snapshot, size: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text(snapshot.name)
          .font(.body.weight(.semibold))
          .lineLimit(1)

        if let latest = snapshot.latestRelease {
          HStack(spacing: 4) {
            Text(latest.tag)
              .monospacedDigit()
            if let date = latest.publishedAt {
              Text("·")
              Text(date, format: .relative(presentation: .named))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        } else {
          Text(snapshot.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 4)

      if snapshot.status != .upToDate {
        Image(systemName: snapshot.status.symbol)
          .font(.caption)
          .foregroundStyle(snapshot.status.color)
          .help(snapshot.statusText)
      }
    }
    .padding(.vertical, 3)
  }
}

/// Apps and CLIs on disk that aren't in the list, the most recently worked on first.
private struct OnThisMacSection: View {
  @Environment(AppModel.self) private var model
  @AppStorage("showsOnThisMac") private var isExpanded = true
  @State private var showsAll = false

  static let collapsedCount = 5

  var body: some View {
    let projects = model.foundProjects

    Section(isExpanded: $isExpanded) {
      ForEach(visible(projects)) { project in
        FoundRow(project: project)
          .tag(SidebarItem.found(project.id))
          .contextMenu {
            Button("Add to List") {
              Task { await model.add([project.snapshot.project.url]) }
            }
            Button("Create Release…") {
              model.createRelease(project.snapshot)
            }
            .disabled(!Cursor.isInstalled)
            Divider()
            ProjectActions(snapshot: project.snapshot)
            Divider()
            Button("Hide") {
              Task { await model.hide(project) }
            }
          }
      }

      if projects.count > Self.collapsedCount {
        Button(showsAll ? "Show Less" : "Show \(projects.count - Self.collapsedCount) More") {
          withAnimation(.easeOut(duration: 0.15)) { showsAll.toggle() }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 32)
      }
    } header: {
      Text("On This Mac")
        .help("Apps and CLIs in the folders around your projects that aren't in the list yet")
    }
  }

  /// The first few, plus the selected one when it's further down.
  private func visible(_ projects: [FoundProject]) -> [FoundProject] {
    guard !showsAll else { return projects }
    var visible = Array(projects.prefix(Self.collapsedCount))
    if let selected = model.selectedFound, !visible.contains(where: { $0.id == selected.id }) {
      visible.append(selected)
    }
    return visible
  }
}

private struct FoundRow: View {
  @Environment(AppModel.self) private var model
  let project: FoundProject

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 8) {
      ProjectIcon(snapshot: project.snapshot, size: 24)

      VStack(alignment: .leading, spacing: 1) {
        Text(project.name)
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      if isHovering {
        Button {
          Task { await model.add([project.snapshot.project.url]) }
        } label: {
          Image(systemName: "plus.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Add \(project.name) to the list")
      }
    }
    .padding(.vertical, 1)
    .onHover { isHovering = $0 }
  }

  private var subtitle: String {
    guard let date = project.lastActivity else { return project.statusText }
    return "\(project.statusText) · \(date.formatted(.relative(presentation: .named)))"
  }
}

private struct RefreshStatus: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack(spacing: 8) {
        if model.isRefreshing {
          ProgressView()
            .controlSize(.mini)
        } else {
          Button {
            Task { await model.refresh(force: true) }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.plain)
          .help("Fetch the releases from GitHub (⌘R)")
        }

        Text(status(at: context.date))
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }

  private func status(at date: Date) -> String {
    if model.isRefreshing {
      return "Checking GitHub…"
    }
    let count = model.snapshots.count
    let projects = count == 1 ? "1 project" : "\(count) projects"
    guard let lastRefresh = model.lastRefresh else {
      return projects
    }
    let relative = lastRefresh.formatted(.relative(presentation: .named))
    return "\(projects) · checked \(relative)"
  }
}
