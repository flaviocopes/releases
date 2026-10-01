import ReleasesCore
import SwiftUI

/// The apps and tools on this Mac that aren't in the list, to add in one click, plus a folder picker for the rest.
struct AddProjectsSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Add Projects")
          .font(.title2.weight(.bold))
        Text("The apps and command-line tools next to your projects that aren't in the list yet, the ones you worked on last first.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(24)

      Divider()

      content
        .frame(height: 380)

      Divider()

      HStack {
        Button("Choose Folder…") {
          model.chooseFolders()
        }
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding(16)
    }
    .frame(width: 580)
    .task { await model.discoverIfNeeded() }
  }

  @ViewBuilder
  private var content: some View {
    let projects = model.foundProjects
    if !projects.isEmpty {
      List(projects) { project in
        FoundProjectRow(project: project)
      }
      .listStyle(.inset)
    } else if model.isDiscovering {
      ContentUnavailableView {
        ProgressView()
      } description: {
        Text("Looking in the folders that hold your projects…")
      }
    } else {
      ContentUnavailableView {
        Label("Nothing to add", systemImage: "checkmark.circle")
      } description: {
        Text("Every app and tool next to your projects is in the list. Choose a folder to add one from somewhere else.")
      }
    }
  }
}

private struct FoundProjectRow: View {
  @Environment(AppModel.self) private var model
  let project: FoundProject

  var body: some View {
    HStack(spacing: 12) {
      ProjectIcon(snapshot: project.snapshot, size: 34)

      VStack(alignment: .leading, spacing: 2) {
        Text(project.name)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Button {
        Task { await model.hide(project) }
      } label: {
        Image(systemName: "eye.slash")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help("Hide \(project.name). 'releases unhide' brings it back.")

      Button("Add") {
        Task { await model.add([project.snapshot.project.url]) }
      }
      .controlSize(.small)
    }
    .padding(.vertical, 4)
    .contextMenu {
      Button("Add to List") {
        Task { await model.add([project.snapshot.project.url]) }
      }
      Divider()
      ProjectActions(snapshot: project.snapshot)
      Divider()
      Button("Hide") {
        Task { await model.hide(project) }
      }
    }
  }

  private var subtitle: String {
    var parts = [project.statusText]
    if let date = project.lastActivity {
      parts.append(date.formatted(.relative(presentation: .named)))
    }
    parts.append(project.id.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    return parts.joined(separator: " · ")
  }
}
