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

      Label {
        Text("Downloads")
      } icon: {
        Image(systemName: "arrow.down.circle")
          .foregroundStyle(.orange)
      }
      .tag(SidebarItem.downloads)

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
        AddMoreRow()
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      RefreshStatus()
    }
    .toolbar {
      ToolbarItem {
        Button {
          model.showsAddProjects = true
        } label: {
          Label("Add Projects", systemImage: "plus")
        }
        .help("Add projects from this Mac, or choose a folder")
      }
    }
  }
}

/// Project shortcuts used by the context menu and the detail toolbar.
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
      model.openInCodex(snapshot)
    } label: {
      Label("Open in Codex", systemImage: "terminal")
    }
    .help("Open the project in Codex")
    .disabled(!snapshot.local.exists || !Codex.isInstalled)
    Button {
      model.openInCursor(snapshot)
    } label: {
      Label("Open in Cursor", systemImage: "chevron.left.forwardslash.chevron.right")
    }
    .help("Open the project in Cursor")
    .disabled(!snapshot.local.exists)
    if GitHubDesktop.isInstalled {
      Button {
        model.openInGitHubDesktop(snapshot)
      } label: {
        Label("Open in GitHub Desktop", systemImage: "arrow.triangle.pull")
      }
      .help("Open the project in GitHub Desktop")
      .disabled(!snapshot.local.exists)
    }
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

        if snapshot.local.hasUncommittedChanges {
          Label("Waiting for commit", systemImage: "pencil.circle")
            .font(.caption)
            .foregroundStyle(.orange)
        }

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

/// Opens the Add Projects sheet. The badge counts the apps and tools on this Mac that aren't in the list.
private struct AddMoreRow: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 22))
        .foregroundStyle(.secondary)
        .frame(width: 34)
      Text("Add More…")
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .onTapGesture {
      model.showsAddProjects = true
    }
    .badge(model.foundProjects.count)
    .help("Add the apps and tools on this Mac that aren't in the list, or choose a folder")
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
