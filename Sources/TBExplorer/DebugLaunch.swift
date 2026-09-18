#if DEBUG
import AppKit
import Foundation
import TBKit

/// Debug-only launch arguments for development and screenshots, e.g.
///
///     open "TigerBeetle Explorer.app" --args -TBConnect 127.0.0.1:3001 -TBOpen transfer:100011
///
/// - `-TBOpen`: `overview`, `search`, `accounts`, `transfers`, `ledger:<id>`, `account:<id>` or
///   `transfer:<id>`; several separated by commas are opened in order, building a stack
/// - `-TBBack <n>` / `-TBForward <n>`: navigate the history after opening, so a snapshot can show
///   where Back and Forward land
/// - `-TBTab`: account tab (`Transfers`, `Balance History`, `Raw`)
/// - `-TBSearch <id>` / `-TBFilterCode <code>`: prefill the account Transfers tab search or code filter
/// - `-TBCurrency on|off`: sets the currency-format checkbox
/// - `-TBFormat "840:2:USD,700:2:EUR"`: ledger overrides for the debug connection, `id:decimals:name`
/// - `-TBConnectDelay <seconds>`: waits before connecting, leaving time to send a link to the
///   disconnected app and watch it be applied once the connection comes up
/// - `-TBWindows <n>`: opens `n` windows onto the same connection
/// - `-TBLink <url>`: delivers a `tb-explorer://` link as if it had been opened from outside,
///   and claims it here rather than waiting for the window to become key
/// - `-TBSettings YES`: opens the Settings window (snapshots then capture it)
/// - `-TBSnapshot <name>`: after loading, draw the main window to `<name>.png` in the
///   app's temporary directory and quit. Needs no Screen Recording permission.
extension Session {
    /// Returns true for the window that applied the arguments; later windows get false.
    @discardableResult
    func applyDebugLaunchArguments(_ browser: Browser) async -> Bool {
        guard !debugArgumentsApplied else { return false }
        debugArgumentsApplied = true
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "TBTab") {
            defaults.set(tab, forKey: "account.tab")
        }
        if let currency = defaults.string(forKey: "TBCurrency") {
            defaults.set(currency == "on" || currency == "true" || currency == "1", forKey: "format.currency")
        }
        if let address = defaults.string(forKey: "TBConnect") {
            let delay = defaults.integer(forKey: "TBConnectDelay")
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            await debugConnect(address: address)
            applyDebugFormats()
            if isConnected, let target = defaults.string(forKey: "TBOpen") {
                for step in target.split(separator: ",") { debugOpen(String(step), in: browser) }
                for _ in 0..<defaults.integer(forKey: "TBBack") { browser.goBack() }
                for _ in 0..<defaults.integer(forKey: "TBForward") { browser.goForward() }
            }
        }
        if let link = defaults.string(forKey: "TBLink").flatMap(URL.init(string:)) {
            receive(link)
            if let claimed = takePendingLink() { browser.apply(claimed) }
        }
        return true
    }

    /// Kept apart from `applyDebugLaunchArguments` because it ends the process: anything else the
    /// caller wants to set up, such as extra windows, has to happen first.
    func applyDebugSnapshot() async {
        guard let snapshot = UserDefaults.standard.string(forKey: "TBSnapshot") else { return }
        try? await Task.sleep(for: .seconds(4))
        debugSnapshot(named: snapshot)
        NSApp.terminate(nil)
    }

    private func debugConnect(address: String) async {
        let conn = SavedConnection(name: "Debug", clusterID: "0", addresses: [address])
        do {
            let (client, info) = try await TBClient.connect(clusterID: 0, addresses: conn.addresses)
            adoptDebugConnection(client: client, info: info, connection: conn)
        } catch {
            print("debug connect failed: \(error)")
        }
    }

    /// `-TBFormat "840:2:USD,700:2:EUR"`. Applied to the in-memory metadata only; the debug
    /// connection is never saved, so `metadata.json` is untouched.
    private func applyDebugFormats() {
        guard let spec = UserDefaults.standard.string(forKey: "TBFormat") else { return }
        var metadata = ClusterMetadata()
        for entry in spec.split(separator: ",") {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let ledger = UInt32(parts.first ?? "") else { continue }
            metadata[ledger: ledger] = LedgerFormat(
                name: parts.count > 2 ? parts[2] : nil,
                symbol: parts.count > 3 ? parts[3] : nil,
                exponent: parts.count > 1 ? UInt8(parts[1]) ?? 0 : 0)
            observe(ledger: ledger)
        }
        adoptDebugMetadata(metadata)
    }

    private func debugOpen(_ target: String, in browser: Browser) {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("search", _): browser.select(.search)
        case ("accounts", _): browser.select(.accounts)
        case ("transfers", _): browser.select(.transfers)
        case ("ledger", let id?): if let l = UInt32(id) { observe(ledger: l); browser.select(.ledger(l)) }
        case ("account", let id?): if let v = UInt128(tbString: id) { browser.open(.account(v)) }
        case ("transfer", let id?): if let v = UInt128(tbString: id) { browser.open(.transfer(v)) }
        default: browser.select(.overview)
        }
    }

    private func debugSnapshot(named name: String) {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        print("snapshot: windows " + candidates.map(\.title).joined(separator: " | "))
        // With `-TBSettings`, capture the Settings window rather than the main one. SwiftUI gives
        // it a known identifier; its title is the selected pane, so the title is no help.
        let wanted = UserDefaults.standard.bool(forKey: "TBSettings")
            ? candidates.first { ($0.identifier?.rawValue ?? "").contains("Settings") }
            : nil
        guard let window = wanted ?? NSApp.keyWindow.flatMap({ candidates.contains($0) ? $0 : nil }) ?? candidates.first,
              let frameView = window.contentView?.superview
        else {
            print("snapshot: no window")
            return
        }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        frameView.cacheDisplay(in: bounds, to: rep)
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(name).png")
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("snapshot: could not encode PNG")
            return
        }
        do {
            try png.write(to: url)
            print("snapshot: \(url.path)")
        } catch {
            print("snapshot failed: \(error)")
        }
        // The app is sandboxed and newer macOS blocks reading another app's container, so
        // `-TBSnapshotStdout` streams the image out instead: pipe it through `base64 -d`.
        // `SNAPSHOT:` is the chosen window; `SNAPSHOT<i>:` is every window, so a multi-window
        // run can be checked one window at a time.
        if UserDefaults.standard.bool(forKey: "TBSnapshotStdout") {
            print("SNAPSHOT:" + png.base64EncodedString())
            guard candidates.count > 1 else { return }
            for (i, other) in candidates.enumerated() {
                guard let view = other.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    print("SNAPSHOT\(i):" + data.base64EncodedString())
                }
            }
        }
    }
}
#endif
