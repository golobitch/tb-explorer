import SwiftUI

@main
struct TBExplorerApp: App {
    @State private var session = Session.shared

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserWindow()
                .environment(session)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        // Reopening yesterday's windows would make the debug screenshots non-deterministic,
        // and a restored window would point at a cluster the app is no longer connected to.
        .restorationBehavior(.disabled)
        .commands {
            GoCommands(session: session)
        }

        Settings {
            SettingsView()
                .environment(session)
        }
    }
}

/// One window onto the cluster. The connection is shared; this window's navigation is not.
struct BrowserWindow: View {
    @Environment(Session.self) private var session
    @State private var browser = Browser()
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        RootView()
            .environment(browser)
            // Publishes this window's browser to the menu commands while it is focused.
            .focusedSceneValue(browser)
            #if DEBUG
            .task {
                guard await session.applyDebugLaunchArguments(browser) else { return }
                for _ in 1..<max(1, UserDefaults.standard.integer(forKey: "TBWindows")) {
                    openWindow(id: "browser")
                }
                await session.applyDebugSnapshot()
            }
            #endif
    }
}

struct GoCommands: Commands {
    let session: Session
    /// The focused window's browser, or nil while Settings is frontmost or no window is open —
    /// which is exactly when the navigation items should be greyed out.
    @FocusedValue(Browser.self) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n")
        }
        CommandMenu("Go") {
            Button("Go to ID…") { browser?.isGoToPresented = true }
                .keyboardShortcut("k")
                .disabled(browser == nil || !session.isConnected)
            Divider()
            Button("Overview") { browser?.select(.overview) }
                .keyboardShortcut("1")
                .disabled(browser == nil || !session.isConnected)
            Button("Accounts") { browser?.select(.accounts) }
                .keyboardShortcut("2")
                .disabled(browser == nil || !session.isConnected)
            Button("Transfers") { browser?.select(.transfers) }
                .keyboardShortcut("3")
                .disabled(browser == nil || !session.isConnected)
            Button("Search") { browser?.select(.search) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(browser == nil || !session.isConnected)
            Divider()
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(browser?.canGoBack != true)
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(browser?.canGoForward != true)
            Divider()
            // Disconnect acts on the shared session, so it stays available with Settings frontmost.
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
