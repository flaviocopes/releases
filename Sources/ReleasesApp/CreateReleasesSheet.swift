import ReleasesCore
import SwiftUI

/// Releases every project waiting to ship, in one Codex chat.
struct CreateReleasesSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let snapshots: [ProjectSnapshot]

  @State private var versions: [ProjectSnapshot.ID: SemanticVersion] = [:]
  @State private var notes = ""

  private var selected: [ProjectSnapshot] {
    snapshots.filter { !model.skippedReleaseProjects.contains($0.id) }
  }

  private func version(of snapshot: ProjectSnapshot) -> SemanticVersion {
    versions[snapshot.id] ?? snapshot.suggestedVersion
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 2) {
        Text(selected.count == 1 ? "Release 1 app" : "Release \(selected.count) apps")
          .font(.title2.weight(.bold))
        Text("Codex opens one chat with the prompts for the checked projects. The agent releases them one at a time after you send it.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      ScrollView {
        VStack(spacing: 0) {
          ForEach(snapshots) { snapshot in
            row(snapshot)
            if snapshot.id != snapshots.last?.id {
              Divider().padding(.leading, 82)
            }
          }
        }
      }
      .frame(maxHeight: 340)
      .background(.quaternary.opacity(0.4))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 8) {
        Text("Anything else for the agents?")
          .font(.headline)
        TextField("Optional, added to every prompt", text: $notes, axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(.roundedBorder)
      }

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button {
          let releases = selected.map { snapshot in
            (snapshot: snapshot, prompt: ReleasePrompt.make(for: snapshot, version: version(of: snapshot), notes: notes))
          }
          Task { await model.startReleases(releases) }
          dismiss()
        } label: {
          Label("Continue in Codex", systemImage: "arrow.up.forward.app")
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(selected.isEmpty || !Codex.isInstalled)
        .help(Codex.isInstalled ? "Open the \(selected.count) checked projects in Codex, each with its prompt" : "Codex isn't installed")
      }
    }
    .padding(24)
    .frame(width: 580)
  }

  private func row(_ snapshot: ProjectSnapshot) -> some View {
    let isIncluded = Binding(
      get: { !model.skippedReleaseProjects.contains(snapshot.id) },
      set: { included in
        if included { model.skippedReleaseProjects.remove(snapshot.id) } else { model.skippedReleaseProjects.insert(snapshot.id) }
      }
    )
    let version = Binding(
      get: { self.version(of: snapshot) },
      set: { versions[snapshot.id] = $0 }
    )

    return HStack(spacing: 12) {
      Toggle("Release \(snapshot.name)", isOn: isIncluded)
        .toggleStyle(.checkbox)
        .labelsHidden()

      HStack(spacing: 12) {
        ProjectIcon(snapshot: snapshot, size: 32)
        VStack(alignment: .leading, spacing: 2) {
          Text(snapshot.name)
            .fontWeight(.semibold)
          Label(snapshot.statusText, systemImage: snapshot.status.symbol)
            .font(.caption)
            .foregroundStyle(snapshot.status.color)
            .lineLimit(1)
        }
      }
      .opacity(isIncluded.wrappedValue ? 1 : 0.45)

      Spacer(minLength: 8)

      Picker("Version", selection: version) {
        ForEach(choices(for: snapshot), id: \.version) { choice in
          Text("\(choice.version.description) · \(choice.label)").tag(choice.version)
        }
      }
      .labelsHidden()
      .fixedSize()
      .disabled(!isIncluded.wrappedValue)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  /// The three bumps of the latest release, plus the project's own version when it's none of them.
  private func choices(for snapshot: ProjectSnapshot) -> [(label: String, version: SemanticVersion)] {
    var choices = SemanticVersion.Bump.allCases.map { (label: $0.rawValue.capitalized, version: snapshot.bumpBase.bumped($0)) }
    if !choices.contains(where: { $0.version == snapshot.suggestedVersion }) {
      choices.append((label: "In the project", version: snapshot.suggestedVersion))
    }
    return choices.sorted { $0.version < $1.version }
  }
}
