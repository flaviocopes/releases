import ReleasesCore
import SwiftUI

struct ContentView: View {
  @Environment(AppModel.self) private var model
  @State private var isDropTargeted = false

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      ProjectListView()
        .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 380)
    } detail: {
      if let snapshot = model.selectedSnapshot {
        ProjectDetailView(snapshot: snapshot)
      } else if let found = model.selectedFound {
        ProjectDetailView(snapshot: found.snapshot, found: found)
      } else if model.snapshots.isEmpty {
        EmptyStateView()
      } else {
        HomeView()
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      let folders = urls.filter(\.hasDirectoryPath)
      guard !folders.isEmpty else { return false }
      Task { await model.add(folders) }
      return true
    } isTargeted: {
      isDropTargeted = $0
    }
    .overlay {
      if isDropTargeted {
        DropOverlay()
      }
    }
    .sheet(item: $model.releaseDraft) { draft in
      CreateReleaseSheet(draft: draft)
    }
    .alert(
      "Releases",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct DropOverlay: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.accentColor.opacity(0.08))
      )
      .overlay {
        Label("Drop to add the project", systemImage: "plus.circle.fill")
          .font(.title2.weight(.semibold))
          .foregroundStyle(Color.accentColor)
      }
      .padding(10)
      .allowsHitTesting(false)
  }
}

private struct EmptyStateView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ContentUnavailableView {
      Label("Drop a project folder here", systemImage: "shippingbox")
    } description: {
      Text(
        model.foundProjects.isEmpty
          ? "Releases finds the GitHub repo and the version, and lists every release.\nAgents can add projects with `releases add <folder>`."
          : "Releases finds the GitHub repo and the version, and lists every release.\nPick one of the apps it found on this Mac in the sidebar, or let an agent run `releases add <folder>`."
      )
    } actions: {
      Button("Add Project…") {
        model.chooseFolders()
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
