import SwiftUI

@main
struct TBExplorerApp: App {
    @State private var session = Session.shared
    @State private var browser = Browser()

    var body: some Scene {
        Window("TigerBeetle Explorer", id: "main") {
            RootView()
                .environment(session)
                .environment(browser)
                .frame(minWidth: 900, minHeight: 560)
                #if DEBUG
                .task { await session.applyDebugLaunchArguments(browser) }
                #endif
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            GoCommands(session: session, browser: browser)
        }

        Settings {
            SettingsView()
                .environment(session)
        }
    }
}

struct GoCommands: Commands {
    let session: Session
    let browser: Browser

    var body: some Commands {
        CommandMenu("Go") {
            Button("Go to ID…") { browser.isGoToPresented = true }
                .keyboardShortcut("k")
                .disabled(!session.isConnected)
            Divider()
            Button("Overview") { browser.select(.overview) }
                .keyboardShortcut("1")
                .disabled(!session.isConnected)
            Button("Accounts") { browser.select(.accounts) }
                .keyboardShortcut("2")
                .disabled(!session.isConnected)
            Button("Transfers") { browser.select(.transfers) }
                .keyboardShortcut("3")
                .disabled(!session.isConnected)
            Button("Search") { browser.select(.search) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!session.isConnected)
            Divider()
            Button("Back") { browser.goBack() }
                .keyboardShortcut("[")
                .disabled(!browser.canGoBack)
            Button("Forward") { browser.goForward() }
                .keyboardShortcut("]")
                .disabled(!browser.canGoForward)
            Divider()
            Button("Disconnect") { session.disconnect() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!session.isConnected)
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        Group {
            if session.isConnected {
                ClusterView()
            } else {
                ConnectView()
            }
        }
        // Routes belong to the cluster they came from, so a new connection starts this window over.
        .onChange(of: session.connectionToken) { browser.connectionDidChange() }
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
