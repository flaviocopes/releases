import ReleasesCore
import SwiftUI

struct ProjectDetailView: View {
  @Environment(AppModel.self) private var model
  let snapshot: ProjectSnapshot
  /// Set for a project on disk that isn't in the list.
  var found: FoundProject?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let found {
          FoundBanner(project: found)
        }

        Header(snapshot: snapshot, lastActivity: found?.lastActivity, canRename: found == nil)

        if let commits = snapshot.unreleasedCommits, !commits.isEmpty, let latest = snapshot.latestRelease {
          UnreleasedSection(commits: commits, since: latest.tag)
        }

        ReleasesSection(snapshot: snapshot)
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.background)
    .navigationTitle(snapshot.name)
    .toolbar {
      ToolbarItemGroup {
        ProjectActions(snapshot: snapshot)
          .labelStyle(.iconOnly)
      }
    }
  }
}

/// Asks whether a project found on disk belongs in the list.
private struct FoundBanner: View {
  @Environment(AppModel.self) private var model
  let project: FoundProject

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "tray.and.arrow.down.fill")
        .font(.title2)
        .foregroundStyle(.blue)

      VStack(alignment: .leading, spacing: 2) {
        Text("Not in your list yet")
          .font(.headline)
        Text("Releases found it in \(folder). Add it to keep an eye on its releases, or hide it if you won't ship it.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button("Hide") {
        Task { await model.hide(project) }
      }
      .help("Leave it out of Add Projects. 'releases unhide' brings it back.")
      Button("Add to List") {
        Task { await model.add([project.snapshot.project.url]) }
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.blue.opacity(0.08))
    )
  }

  private var folder: String {
    project.snapshot.project.url.deletingLastPathComponent().path
      .replacingOccurrences(of: NSHomeDirectory(), with: "~")
  }
}

private struct Header: View {
  @Environment(AppModel.self) private var model
  let snapshot: ProjectSnapshot
  var lastActivity: Date?
  var canRename = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .center, spacing: 16) {
        ProjectIcon(snapshot: snapshot, size: 72)

        VStack(alignment: .leading, spacing: 4) {
          ProjectName(snapshot: snapshot, canRename: canRename)

          if let repository = snapshot.repository {
            Link(destination: repository.url) {
              HStack(spacing: 3) {
                Text(repository.description)
                Image(systemName: "arrow.up.right")
                  .font(.caption.weight(.semibold))
              }
            }
            .font(.callout)
          } else {
            Text(snapshot.project.path)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Button {
          model.createRelease(snapshot)
        } label: {
          Label("Create Release…", systemImage: "shippingbox")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!snapshot.local.exists)
        .help(snapshot.repository == nil
          ? "Pick the version, then continue in Cursor. The agent creates the GitHub repo too."
          : "Pick the version, then continue in Cursor")
      }

      HStack(spacing: 8) {
        StatusBadge(snapshot: snapshot)
        Spacer()
      }

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        if let source = snapshot.local.version {
          Fact(label: "Version") {
            Text(source.version).monospacedDigit().fontWeight(.medium)
            Text("in \(source.file)").foregroundStyle(.secondary)
          }
        } else {
          Fact(label: "Version") {
            Text("Not found in the project").foregroundStyle(.secondary)
          }
        }

        if let branch = snapshot.local.branch {
          Fact(label: "Branch") {
            Text(branch).fontWeight(.medium)
            if let unpushed = snapshot.local.unpushedCommitCount, unpushed > 0 {
              Tag(text: unpushed == 1 ? "1 not pushed" : "\(unpushed) not pushed", color: .orange)
            }
            if snapshot.local.hasUncommittedChanges {
              Tag(text: "uncommitted changes", color: .orange)
            }
          }
        }

        Fact(label: "Folder") {
          Text(snapshot.project.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        if let lastActivity {
          Fact(label: "Worked on") {
            Text(lastActivity, format: .relative(presentation: .named)).fontWeight(.medium)
            Text(lastActivity, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary)
          }
        }

        if !snapshot.releases.isEmpty {
          Fact(label: "Downloads") {
            Text(snapshot.totalDownloads, format: .number).monospacedDigit().fontWeight(.medium)
            Text("across \(snapshot.releases.count) releases").foregroundStyle(.secondary)
          }
        }
      }
      .font(.callout)
    }
  }
}

/// The project's name. Double-click it to give the project another name, in Releases only.
private struct ProjectName: View {
  @Environment(AppModel.self) private var model
  let snapshot: ProjectSnapshot
  let canRename: Bool

  @State private var isEditing = false
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    if isEditing {
      TextField(snapshot.local.name, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 28, weight: .bold))
        .focused($isFocused)
        .onSubmit(save)
        .onExitCommand { isEditing = false }
        .onChange(of: isFocused) { _, focused in
          if !focused, isEditing { save() }
        }
        .onAppear { isFocused = true }
    } else {
      Text(snapshot.name)
        .font(.system(size: 28, weight: .bold))
        .onTapGesture(count: 2) {
          guard canRename else { return }
          text = snapshot.name
          isEditing = true
        }
        .help(help)
    }
  }

  private var help: String {
    guard canRename else { return "" }
    guard snapshot.project.displayName != nil else { return "Double-click to rename it in Releases" }
    return "Double-click to rename it. Clear the name to go back to \"\(snapshot.local.name)\"."
  }

  private func save() {
    isEditing = false
    let name = snapshot.displayName(for: text)
    guard name != snapshot.project.displayName else { return }
    Task { await model.rename(snapshot, to: name) }
  }
}

private struct Fact<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
        .gridColumnAlignment(.trailing)
      HStack(spacing: 6) {
        content
      }
    }
  }
}

private struct UnreleasedSection: View {
  let commits: [Commit]
  let since: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(title: "Since \(since)", detail: commits.count == 1 ? "1 commit" : "\(commits.count) commits")

      Card {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(commits) { commit in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(commit.hash)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
              Text(commit.subject)
                .lineLimit(2)
              Spacer(minLength: 8)
              if let date = commit.date {
                Text(date, format: .relative(presentation: .named))
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
            }
          }
        }
      }
    }
  }
}

private struct ReleasesSection: View {
  let snapshot: ProjectSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(
        title: "Releases",
        detail: snapshot.releases.isEmpty ? nil : "\(snapshot.releases.count)"
      )

      if snapshot.releases.isEmpty {
        Card {
          Text(emptyMessage)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(spacing: 8) {
          ForEach(snapshot.releases) { release in
            ReleaseRow(
              release: release,
              isLatest: release.id == snapshot.latestRelease?.id,
              isFirst: release.id == snapshot.firstRelease?.id,
              changes: snapshot.changes(in: release)
            )
          }
        }
      }
    }
  }

  private var emptyMessage: String {
    switch snapshot.status {
    case .noRepository: "It isn't on GitHub yet. Create Release asks the agent to create the repo and publish the first release."
    case .missing: "The folder isn't there anymore. Remove the project, or move the folder back."
    case .notLoaded: snapshot.project.fetchError ?? "Loading the releases from GitHub…"
    default: "No releases yet. Create Release starts the first one."
    }
  }
}

struct SectionTitle: View {
  let title: String
  var detail: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .font(.title3.weight(.bold))
      if let detail {
        Text(detail)
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ReleaseRow: View {
  let release: Release
  let isLatest: Bool
  let isFirst: Bool
  let changes: [Change]

  @State private var showsDetails = false
  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(release.tag)
          .font(.system(.body, design: .monospaced, weight: .semibold))

        if let title = release.title, title != release.tag {
          Text(title)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if isLatest { Tag(text: "Latest", color: .green) }
        if isFirst { FirstReleaseTag() }
        if release.isDraft { Tag(text: "Draft", color: .orange) }
        if release.isPrerelease { Tag(text: "Prerelease", color: .purple) }

        Spacer(minLength: 8)

        if let date = release.publishedAt {
          Text(date, format: .dateTime.day().month(.abbreviated).year())
            .monospacedDigit()
          Text(date, format: .relative(presentation: .named))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(minWidth: 70, alignment: .trailing)
        }

        Link(destination: release.url) {
          Image(systemName: "arrow.up.right.square")
        }
        .help("Open the release on GitHub")
      }

      if !changes.isEmpty {
        ChangeList(changes: changes, showsDetails: showsDetails)
      }

      HStack(spacing: 12) {
        Label(release.downloadCount.downloads, systemImage: "arrow.down.circle")
          .monospacedDigit()

        ForEach(release.assets, id: \.name) { asset in
          Label {
            Text(asset.name)
            Text(asset.size.formatted(.byteCount(style: .file)))
              .foregroundStyle(.tertiary)
          } icon: {
            Image(systemName: asset.name.hasSuffix(".zip") ? "doc.zipper" : "doc")
          }
          .lineLimit(1)
        }

        Spacer(minLength: 0)

        if changes.contains(where: { !$0.detail.isEmpty }) {
          Button(showsDetails ? "Hide Details" : "Details") {
            withAnimation(.easeOut(duration: 0.15)) { showsDetails.toggle() }
          }
          .buttonStyle(.link)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(14)
    .background {
      if isFirst {
        LinearGradient(colors: [Color.firstRelease.opacity(0.14), Color.firstRelease.opacity(0.04)], startPoint: .leading, endPoint: .trailing)
      }
    }
    .background(.quaternary.opacity(isHovering ? 0.6 : 0.4))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onHover { isHovering = $0 }
  }
}
