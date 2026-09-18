import SwiftUI

@main
struct TBExplorerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("TigerBeetle Explorer", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                #if DEBUG
                .task { await model.applyDebugLaunchArguments() }
                #endif
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            GoCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct GoCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Go to ID…") { model.isGoToPresented = true }
                .keyboardShortcut("k")
                .disabled(!model.isConnected)
            Divider()
            Button("Overview") { model.select(.overview) }
                .keyboardShortcut("1")
                .disabled(!model.isConnected)
            Button("Accounts") { model.select(.accounts) }
                .keyboardShortcut("2")
                .disabled(!model.isConnected)
            Button("Transfers") { model.select(.transfers) }
                .keyboardShortcut("3")
                .disabled(!model.isConnected)
            Button("Search") { model.select(.search) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
            Divider()
            Button("Back") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(!model.canGoBack)
            Button("Forward") { model.goForward() }
                .keyboardShortcut("]")
                .disabled(!model.canGoForward)
            Divider()
            Button("Disconnect") { model.disconnect() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Group {
            if model.isConnected {
                ClusterView()
            } else {
                ConnectView()
            }
        }
        #if DEBUG
        // `-TBSettings YES` opens the Settings window for screenshots; `openSettings` only
        // exists in a view, so the debug launch path cannot do it itself.
        .task {
            guard UserDefaults.standard.bool(forKey: "TBSettings") else { return }
            try? await Task.sleep(for: .seconds(3))
            openSettings()
        }
        #endif
    }
}
