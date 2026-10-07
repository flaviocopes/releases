import ReleasesCore
import SwiftUI

struct CreateReleaseSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  let snapshot: ProjectSnapshot

  @State private var versionText: String
  @State private var notes = ""
  @State private var showsPrompt = false
  @State private var copied = false
  @State private var isStarting = false

  init(draft: ReleaseDraft) {
    snapshot = draft.snapshot
    _versionText = State(initialValue: (draft.version ?? draft.snapshot.suggestedVersion).description)
    _notes = State(initialValue: draft.notes)
  }

  private var subtitle: String {
    var text = "Codex opens the project with the prompt in the chat. Nothing runs until you send it."
    if !model.snapshots.contains(where: { $0.id == snapshot.id }) {
      text += " The project gets added to your list too."
    }
    return text
  }

  private var version: SemanticVersion? {
    SemanticVersion(versionText)
  }

  private var prompt: String {
    ReleasePrompt.make(for: snapshot, version: version ?? snapshot.suggestedVersion, notes: notes)
  }

  /// Why the version can't be released, if it can't.
  private var versionProblem: String? {
    guard let version else {
      return "Use a version like 1.2.0."
    }
    if snapshot.releases.contains(where: { $0.version == version }) {
      return "\(version.tag) is already on GitHub."
    }
    if let released = snapshot.latestRelease?.version, version < released {
      return "The latest release is \(released.tag). Pick a higher version."
    }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        ProjectIcon(snapshot: snapshot, size: 44)
        VStack(alignment: .leading, spacing: 2) {
          Text("Release \(snapshot.name)")
            .font(.title2.weight(.bold))
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Version")
          .font(.headline)

        HStack(spacing: 10) {
          TextField("1.2.0", text: $versionText)
            .font(.system(.title3, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)

          ForEach(SemanticVersion.Bump.allCases, id: \.self) { bump in
            let next = snapshot.bumpBase.bumped(bump)
            Button {
              versionText = next.description
            } label: {
              VStack(spacing: 0) {
                Text(bump.rawValue.capitalized)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(next.description)
                  .monospacedDigit()
              }
              .frame(minWidth: 56)
            }
            .buttonStyle(.bordered)
          }
        }

        Group {
          if let versionProblem {
            Label(versionProblem, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          } else if let latest = snapshot.latestRelease {
            Text("The latest release is \(latest.tag). The project says \(snapshot.local.version?.version ?? "nothing").")
              .foregroundStyle(.secondary)
          } else {
            Text("This is the first release.")
              .foregroundStyle(.secondary)
          }
        }
        .font(.callout)
      }

      if let commits = snapshot.unreleasedCommits, let latest = snapshot.latestRelease {
        VStack(alignment: .leading, spacing: 8) {
          Text(commits.isEmpty ? "No commits since \(latest.tag)" : "Changes since \(latest.tag)")
            .font(.headline)

          if !commits.isEmpty {
            ScrollView {
              VStack(alignment: .leading, spacing: 5) {
                ForEach(commits) { commit in
                  HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(commit.hash)
                      .font(.system(.caption, design: .monospaced))
                      .foregroundStyle(.tertiary)
                    Text(commit.subject)
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
            }
            .frame(maxHeight: 150)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.4))
            )
          }
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Anything else for the agent?")
          .font(.headline)
        TextField("Optional, like \"mention the new menu bar icon first\"", text: $notes, axis: .vertical)
          .lineLimit(2...4)
          .textFieldStyle(.roundedBorder)
      }

      DisclosureGroup("Prompt", isExpanded: $showsPrompt) {
        ScrollView {
          Text(prompt)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 180)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary.opacity(0.4))
        )
        .padding(.top, 6)
      }

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(prompt, forType: .string)
          copied = true
        } label: {
          Label(copied ? "Copied" : "Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .disabled(versionProblem != nil)

        Button {
          isStarting = true
          let prompt = prompt
          Task {
            await model.startRelease(snapshot, prompt: prompt)
            isStarting = false
            dismiss()
          }
        } label: {
          Label("Continue in Codex", systemImage: "arrow.up.forward.app")
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(versionProblem != nil || isStarting || !Codex.isInstalled)
        .help(Codex.isInstalled ? "Open the project in Codex with this prompt" : "Codex isn't installed")
      }
    }
    .padding(24)
    .frame(width: 580)
  }
}
