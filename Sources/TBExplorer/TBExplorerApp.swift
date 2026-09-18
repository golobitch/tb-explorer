import SwiftUI
import TBKit

@main
struct TBExplorerApp: App {
    @State private var session = Session.shared

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserWindow()
                .environment(session)
                .frame(minWidth: 900, minHeight: 560)
                // An open window can service a link…
                .handlesExternalEvents(preferring: [DeepLink.scheme], allowing: [DeepLink.scheme])
        }
        // …so following one lands where you are looking instead of stacking up new windows.
        .handlesExternalEvents(matching: [])
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
    @Environment(\.controlActiveState) private var controlActive
    @State private var browser = Browser()
    /// Set when this window is handed a link it cannot act on yet, so the window the link was
    /// routed to is the one that opens it once a connection exists — whatever has focus by then.
    @State private var awaitingLink = false
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        RootView()
            .environment(browser)
            // Publishes this window's browser to the menu commands while it is focused.
            .focusedSceneValue(browser)
            // A link is parked on the session; the key window claims it, so exactly one window
            // acts on it, and a link that arrives while disconnected simply waits.
            .onOpenURL { url in
                session.receive(url)
                awaitingLink = true
                claimLink()
            }
            .onChange(of: session.pendingLinkToken) { claimLink() }
            .onChange(of: session.isConnected) { claimLink() }
            .onChange(of: controlActive) { claimLink() }
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

    private func claimLink() {
        guard awaitingLink || controlActive == .key else { return }
        guard session.isConnected, let link = session.takePendingLink() else { return }
        awaitingLink = false
        browser.apply(link)
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
        VStack(spacing: 0) {
            if let message = session.linkMessage {
                MessageBar(text: message, symbol: "link") { session.linkMessage = nil }
                Divider()
            }
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
