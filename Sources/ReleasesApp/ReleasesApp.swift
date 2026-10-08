import ReleasesCore
import SwiftUI

@main
struct ReleasesDesktopApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    AppUpdater.shared.start(repository: "flaviocopes/releases-manager")
  }

  var body: some Scene {
    WindowGroup("Releases Manager") {
      ContentView()
        .environment(model)
        .frame(minWidth: 860, minHeight: 540)
        .task {
          model.watchStore()
          await model.reload()
          await model.refresh()

          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(600))
            await model.refresh()
          }
        }
        .onOpenURL { url in
          guard let link = AppLink(url: url) else { return }
          Task { await model.handle(link) }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
    .handlesExternalEvents(matching: ["*"])
    .defaultSize(width: 1180, height: 780)
    .windowToolbarStyle(.unified(showsTitle: false))
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") {
          AppUpdater.shared.checkForUpdates()
        }
      }
      CommandGroup(replacing: .newItem) {
        Button("Add Projects…") {
          model.showsAddProjects = true
        }
        .keyboardShortcut("o")
      }
      CommandGroup(before: .toolbar) {
        Button("Refresh") {
          Task { await model.refresh(force: true) }
        }
        .keyboardShortcut("r")
        Divider()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh() }
      }
    }
  }
}
