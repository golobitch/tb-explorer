#if DEBUG
import AppKit
import Foundation
import TBKit

/// Debug-only launch arguments for development and screenshots, e.g.
///
///     open "TigerBeetle Explorer.app" --args -TBConnect 127.0.0.1:3001 -TBOpen transfer:100011
///
/// - `-TBOpen`: `overview`, `search`, `accounts`, `transfers`, `ledger:<id>`, `account:<id>` or `transfer:<id>`
/// - `-TBTab`: account tab (`Transfers`, `Balance History`, `Raw`)
/// - `-TBSearch <id>` / `-TBFilterCode <code>`: prefill the account Transfers tab search or code filter
/// - `-TBSnapshot <name>`: after loading, draw the main window to `<name>.png` in the
///   app's temporary directory and quit. Needs no Screen Recording permission.
extension AppModel {
    func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "TBTab") {
            defaults.set(tab, forKey: "account.tab")
        }
        if let address = defaults.string(forKey: "TBConnect") {
            await debugConnect(address: address)
            if isConnected, let target = defaults.string(forKey: "TBOpen") {
                debugOpen(target)
            }
        }
        if let snapshot = defaults.string(forKey: "TBSnapshot") {
            try? await Task.sleep(for: .seconds(4))
            debugSnapshot(named: snapshot)
            NSApp.terminate(nil)
        }
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

    private func debugOpen(_ target: String) {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count == 2 ? parts[1] : nil) {
        case ("search", _): select(.search)
        case ("accounts", _): select(.accounts)
        case ("transfers", _): select(.transfers)
        case ("ledger", let id?): if let l = UInt32(id) { observe(ledger: l); select(.ledger(l)) }
        case ("account", let id?): if let v = UInt128(tbString: id) { open(.account(v)) }
        case ("transfer", let id?): if let v = UInt128(tbString: id) { open(.transfer(v)) }
        default: select(.overview)
        }
    }

    private func debugSnapshot(named name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frameView = window.contentView?.superview
        else {
            print("snapshot: no window")
            return
        }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        frameView.cacheDisplay(in: bounds, to: rep)
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(name).png")
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            print("snapshot: \(url.path)")
        } catch {
            print("snapshot failed: \(error)")
        }
    }
}
#endif
