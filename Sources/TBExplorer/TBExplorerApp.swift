import SwiftUI

@main
struct TBExplorerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("TigerBeetle Explorer", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            GoCommands(model: model)
        }
    }
}

struct GoCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            Button("Overview") { model.select(.overview) }
                .keyboardShortcut("1")
                .disabled(!model.isConnected)
            Divider()
            Button("Back") { model.goBack() }
                .keyboardShortcut("[")
                .disabled(model.path.isEmpty)
            Divider()
            Button("Disconnect") { model.disconnect() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.isConnected)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isConnected {
            ClusterView()
        } else {
            ConnectView()
        }
    }
}
